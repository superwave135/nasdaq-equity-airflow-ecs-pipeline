"""
Build Stock Dimension Tables - reads JSONL format from Lambda
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.types import *
from datetime import datetime, timedelta

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'processing_date'])
processing_date = args['processing_date']

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)

job.init(args['JOB_NAME'], args)

print("="*80)
print("DIMENSION TABLES BUILD JOB")
print("="*80)
print(f"Processing date: {processing_date}")
print("="*80)

# READ RAW DATA - JSONL format
print("\n[1/4] Reading raw stock data from S3...")

s3_path = f"s3://nasdaq-airflow-ecs-data-dev/raw/stock_quotes/date={processing_date}/"
print(f"Reading from: {s3_path}")

try:
    raw_df = spark.read.json(s3_path)
    row_count = raw_df.count()
    print(f"Successfully read {row_count} rows")
    
    print("\nRaw data schema:")
    raw_df.printSchema()
    
except Exception as e:
    print(f"ERROR reading raw data: {str(e)}")
    raise

# DIM_STOCK
print("\n[2/4] Building dim_stock dimension table...")

dim_stock = raw_df.select(
    monotonically_increasing_id().alias("stock_key"),
    col("symbol"),
    col("name").alias("company_name"),
    col("exchange"),
    when(col("market_cap") > 1000000000000, "Large Cap")
     .when(col("market_cap") > 10000000000, "Mid Cap")
     .otherwise("Small Cap").alias("market_cap_tier"),
    lit("Technology").alias("sector"),
    lit("Software").alias("industry"),
    lit(processing_date).alias("first_seen_date"),
    lit(processing_date).alias("last_seen_date"),
    lit(True).alias("is_active")
).dropDuplicates(["symbol"])

print(f"dim_stock created with {dim_stock.count()} rows")

print("\nWriting dim_stock to Iceberg...")
try:
    dim_stock.writeTo("glue_catalog.nasdaq_airflow_warehouse_dev.dim_stock") \
        .tableProperty("format-version", "2") \
        .using("iceberg") \
        .createOrReplace()
    print("dim_stock written successfully")
except Exception as e:
    print(f"ERROR writing dim_stock: {str(e)}")
    raise

# DIM_DATE
print("\n[3/4] Building dim_date dimension table...")

start_date = datetime(2020, 1, 1)
end_date = datetime(2026, 12, 31)
date_range = [(start_date + timedelta(days=x)) for x in range((end_date - start_date).days + 1)]

dim_date_data = [
    (
        int(d.strftime('%Y%m%d')),
        d.date(),
        d.year,
        (d.month - 1) // 3 + 1,
        d.month,
        d.isocalendar()[1],
        d.strftime('%A'),
        d.weekday() < 5
    )
    for d in date_range
]

dim_date_schema = StructType([
    StructField("date_key", IntegerType(), False),
    StructField("date", DateType(), False),
    StructField("year", IntegerType(), False),
    StructField("quarter", IntegerType(), False),
    StructField("month", IntegerType(), False),
    StructField("week", IntegerType(), False),
    StructField("day_of_week", StringType(), False),
    StructField("is_trading_day", BooleanType(), False)
])

dim_date = spark.createDataFrame(dim_date_data, dim_date_schema)

print(f"dim_date created with {dim_date.count()} rows")

print("\nWriting dim_date to Iceberg...")
try:
    dim_date.writeTo("glue_catalog.nasdaq_airflow_warehouse_dev.dim_date") \
        .tableProperty("format-version", "2") \
        .using("iceberg") \
        .createOrReplace()
    print("dim_date written successfully")
except Exception as e:
    print(f"ERROR writing dim_date: {str(e)}")
    raise

# DIM_EXCHANGE
print("\n[4/4] Building dim_exchange dimension table...")

dim_exchange = spark.createDataFrame([
    (1, "NASDAQ", "NASDAQ Stock Market", "USA", "America/New_York"),
    (2, "NYSE", "New York Stock Exchange", "USA", "America/New_York"),
    (3, "AMEX", "American Stock Exchange", "USA", "America/New_York")
], ["exchange_key", "exchange_code", "exchange_name", "country", "timezone"])

print(f"dim_exchange created with {dim_exchange.count()} rows")

print("\nWriting dim_exchange to Iceberg...")
try:
    dim_exchange.writeTo("glue_catalog.nasdaq_airflow_warehouse_dev.dim_exchange") \
        .tableProperty("format-version", "2") \
        .using("iceberg") \
        .createOrReplace()
    print("dim_exchange written successfully")
except Exception as e:
    print(f"ERROR writing dim_exchange: {str(e)}")
    raise

# JOB SUMMARY
print("\n" + "="*80)
print("DIMENSION TABLES BUILD SUMMARY")
print("="*80)
print(f"Processing date: {processing_date}")
print(f"S3 source path: {s3_path}")
print(f"dim_stock: {dim_stock.count()} rows")
print(f"dim_date: {dim_date.count()} rows")
print(f"dim_exchange: {dim_exchange.count()} rows")
print("="*80)

job.commit()
print("\nJob completed successfully!")