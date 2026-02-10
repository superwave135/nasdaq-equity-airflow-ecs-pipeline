"""
Build Stock Aggregation Tables

This Glue job creates aggregation tables for analytics:
- agg_stock_weekly_metrics: Weekly performance metrics
- agg_stock_monthly_metrics: Monthly performance metrics
- agg_sector_performance: Sector-level aggregations

NOTE: This job reads from Iceberg tables (fact and dimensions), not from S3.
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.window import Window

# Get job parameters
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'processing_date'])
processing_date = args['processing_date']

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)

job.init(args['JOB_NAME'], args)

print("="*80)
print("AGGREGATION TABLES BUILD JOB")
print("="*80)
print(f"Processing date: {processing_date}")
print("="*80)

# =============================================================================
# READ DATA FROM ICEBERG TABLES
# =============================================================================
print("\n[1/4] Reading fact and dimension tables from Iceberg...")

try:
    print("Reading fact_stock_daily_price...")
    fact_df = spark.table("glue_catalog.nasdaq_airflow_warehouse_dev.fact_stock_daily_price")
    fact_count = fact_df.count()
    print(f"Fact table loaded: {fact_count} rows")
    
    print("Reading dim_stock...")
    dim_stock = spark.table("glue_catalog.nasdaq_airflow_warehouse_dev.dim_stock")
    print(f"dim_stock loaded: {dim_stock.count()} rows")
    
    print("Reading dim_date...")
    dim_date = spark.table("glue_catalog.nasdaq_airflow_warehouse_dev.dim_date")
    print(f"dim_date loaded: {dim_date.count()} rows")
    
except Exception as e:
    print(f"ERROR reading Iceberg tables: {str(e)}")
    print("Make sure fact and dimension tables exist before running aggregations!")
    raise

# Verify fact table has data
if fact_count == 0:
    print("WARNING: Fact table is empty! Cannot build aggregations.")
    print("Exiting gracefully...")
    job.commit()
    sys.exit(0)

# =============================================================================
# AGG_STOCK_WEEKLY_METRICS
# =============================================================================
print("\n[2/4] Building agg_stock_weekly_metrics...")

# Join fact with dimensions - using correct column names from fact table
fact_with_dims = fact_df \
    .join(dim_date, fact_df.trade_date == dim_date.date, "left") \
    .join(dim_stock, fact_df.stock_symbol == dim_stock.symbol, "left")

# Create weekly aggregation
weekly_agg = fact_with_dims \
    .groupBy(
        col("year"),
        col("week"),
        col("symbol"),
        col("company_name")
    ) \
    .agg(
        first("open_price").alias("week_open"),
        last("close_price").alias("week_close"),
        max("high_price").alias("week_high"),
        min("low_price").alias("week_low"),
        sum("volume").alias("total_volume"),
        avg("close_price").alias("avg_price"),
        stddev("close_price").alias("price_std_dev"),
        avg("daily_volatility").alias("avg_volatility"),
        ((last("close_price") - first("open_price")) / first("open_price") * 100).alias("weekly_return_pct")
    )

weekly_count = weekly_agg.count()
print(f"Weekly aggregation created: {weekly_count} rows")

print("\nSample weekly aggregation:")
weekly_agg.show(3, truncate=False)

print("\nWriting agg_stock_weekly_metrics to Iceberg...")
try:
    weekly_agg.writeTo("glue_catalog.nasdaq_airflow_warehouse_dev.agg_stock_weekly_metrics") \
        .tableProperty("format-version", "2") \
        .partitionedBy("year", "week") \
        .using("iceberg") \
        .createOrReplace()
    print("agg_stock_weekly_metrics written successfully")
except Exception as e:
    print(f"ERROR writing weekly metrics: {str(e)}")
    raise

# =============================================================================
# AGG_STOCK_MONTHLY_METRICS
# =============================================================================
print("\n[3/4] Building agg_stock_monthly_metrics...")

monthly_agg = fact_with_dims \
    .groupBy(
        col("year"),
        col("month"),
        col("symbol"),
        col("company_name"),
        col("sector")
    ) \
    .agg(
        first("open_price").alias("month_open"),
        last("close_price").alias("month_close"),
        max("high_price").alias("month_high"),
        min("low_price").alias("month_low"),
        sum("volume").alias("total_volume"),
        avg("close_price").alias("avg_price"),
        avg("market_cap").alias("avg_market_cap"),
        stddev("close_price").alias("price_volatility"),
        ((last("close_price") - first("open_price")) / first("open_price") * 100).alias("monthly_return_pct"),
        avg("daily_volatility").alias("avg_daily_volatility")
    )

monthly_count = monthly_agg.count()
print(f"Monthly aggregation created: {monthly_count} rows")

print("\nSample monthly aggregation:")
monthly_agg.show(3, truncate=False)

print("\nWriting agg_stock_monthly_metrics to Iceberg...")
try:
    monthly_agg.writeTo("glue_catalog.nasdaq_airflow_warehouse_dev.agg_stock_monthly_metrics") \
        .tableProperty("format-version", "2") \
        .partitionedBy("year", "month") \
        .using("iceberg") \
        .createOrReplace()
    print("agg_stock_monthly_metrics written successfully")
except Exception as e:
    print(f"ERROR writing monthly metrics: {str(e)}")
    raise

# =============================================================================
# AGG_SECTOR_PERFORMANCE
# =============================================================================
print("\n[4/4] Building agg_sector_performance...")

sector_performance = fact_with_dims \
    .groupBy(
        col("trade_date").alias("date"),
        col("sector")
    ) \
    .agg(
        avg("change_percentage").alias("avg_sector_change_pct"),
        sum("volume").alias("total_sector_volume"),
        avg("market_cap").alias("avg_sector_market_cap"),
        count("*").alias("num_stocks"),
        stddev("change_percentage").alias("sector_volatility")
    )

sector_count = sector_performance.count()
print(f"Sector performance created: {sector_count} rows")

print("\nSample sector performance:")
sector_performance.show(3, truncate=False)

print("\nWriting agg_sector_performance to Iceberg...")
try:
    sector_performance.writeTo("glue_catalog.nasdaq_airflow_warehouse_dev.agg_sector_performance") \
        .tableProperty("format-version", "2") \
        .partitionedBy("date") \
        .using("iceberg") \
        .createOrReplace()
    print("agg_sector_performance written successfully")
except Exception as e:
    print(f"ERROR writing sector performance: {str(e)}")
    raise

# =============================================================================
# JOB SUMMARY
# =============================================================================
print("\n" + "="*80)
print("AGGREGATION TABLES BUILD SUMMARY")
print("="*80)
print(f"Processing date: {processing_date}")
print(f"Source fact table rows: {fact_count}")
print(f"agg_stock_weekly_metrics: {weekly_count} rows")
print(f"agg_stock_monthly_metrics: {monthly_count} rows")
print(f"agg_sector_performance: {sector_count} rows")
print("="*80)

job.commit()
print("\nJob completed successfully!")