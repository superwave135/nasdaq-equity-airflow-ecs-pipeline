import sys
from datetime import datetime
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.types import *
from pyspark.sql.window import Window

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'processing_date'])
processing_date = args['processing_date']

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

print("="*80)
print("FACT TABLE BUILD JOB")
print("="*80)
print(f"Processing date: {processing_date}")
print("="*80)

# Read from raw stock data (JSONL format from Lambda)
input_path = f"s3://nasdaq-airflow-ecs-data-dev/raw/stock_quotes/date={processing_date}/"
print(f"\nReading from: {input_path}")

try:
    raw_df = spark.read.json(input_path)
    row_count_before = raw_df.count()
    print(f"Successfully read {row_count_before} rows (before deduplication)")
    
    print("\nRaw data schema:")
    raw_df.printSchema()
    
    # DEDUPLICATION: Keep only the latest record per symbol based on extraction_time
    print("\nDeduplicating records...")
    window_spec = Window.partitionBy("symbol").orderBy(desc("extraction_time"))
    raw_df = raw_df.withColumn("row_num", row_number().over(window_spec)) \
                   .filter(col("row_num") == 1) \
                   .drop("row_num")
    
    row_count_after = raw_df.count()
    duplicates_removed = row_count_before - row_count_after
    print(f"After deduplication: {row_count_after} rows (removed {duplicates_removed} duplicates)")
    
except Exception as e:
    print(f"ERROR reading raw data: {str(e)}")
    raise

# Transform to fact table structure - matching original schema exactly
fact_df = raw_df.select(
    monotonically_increasing_id().alias("fact_key"),
    col("symbol").alias("stock_symbol"),
    to_date(lit(processing_date)).alias("trade_date"),
    from_unixtime(col("timestamp")).cast("timestamp").alias("trade_timestamp"),
    col("price").cast("decimal(18,4)").alias("close_price"),
    col("open").cast("decimal(18,4)").alias("open_price"),
    col("day_high").cast("decimal(18,4)").alias("high_price"),
    col("day_low").cast("decimal(18,4)").alias("low_price"),
    col("previous_close").cast("decimal(18,4)").alias("previous_close"),
    col("volume").cast("bigint").alias("volume"),
    col("market_cap").cast("bigint").alias("market_cap"),
    col("change").cast("decimal(18,4)").alias("price_change"),
    col("change_percent").cast("decimal(18,4)").alias("change_percentage"),
    col("year_high").cast("decimal(18,4)").alias("year_high_52w"),
    col("year_low").cast("decimal(18,4)").alias("year_low_52w"),
    col("price_avg_50").cast("decimal(18,4)").alias("price_avg_50d"),
    col("price_avg_200").cast("decimal(18,4)").alias("price_avg_200d"),
    ((col("day_high") - col("day_low")) / col("day_low") * 100).cast("decimal(18,4)").alias("daily_volatility"),
    lit(processing_date).alias("processing_date"),
    current_timestamp().alias("created_at")
)

print(f"\nTransformed records: {fact_df.count()}")

print("\nSample transformed data:")
fact_df.show(3, truncate=False)

# Write to Iceberg table using the correct database
table_name = "glue_catalog.nasdaq_airflow_warehouse_dev.fact_stock_daily_price"
print(f"\nWriting to table: {table_name}")

try:
    fact_df.writeTo(table_name).using("iceberg").tableProperty(
        "format-version", "2"
    ).createOrReplace()
    
    print("Fact table build completed successfully")
    
except Exception as e:
    print(f"ERROR writing to Iceberg table: {str(e)}")
    raise

print("\n" + "="*80)
print("FACT TABLE BUILD SUMMARY")
print("="*80)
print(f"Processing date: {processing_date}")
print(f"S3 source path: {input_path}")
print(f"Records written: {fact_df.count()}")
print(f"Table: {table_name}")
print("="*80)

job.commit()
print("\nJob completed successfully!")