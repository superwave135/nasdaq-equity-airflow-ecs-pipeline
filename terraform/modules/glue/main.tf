# terraform/modules/glue/main.tf
# Complete AWS Glue Module - Database, Jobs, Crawler

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# GLUE DATA CATALOG DATABASE
# ============================================================================

resource "aws_glue_catalog_database" "nasdaq_warehouse" {
  name        = var.database_name
  description = "NASDAQ stock data warehouse - Iceberg tables"

  tags = {
    Name        = var.database_name
    Environment = var.environment
    Project     = "nasdaq-stock-pipeline"
  }
}

# ============================================================================
# S3 BUCKET FOR GLUE SCRIPTS
# ============================================================================

resource "aws_s3_object" "glue_script_dimensions" {
  bucket = var.s3_bucket
  key    = "glue-scripts/build_stock_dimensions.py"
  source = "${path.root}/../glue/jobs/build_stock_dimensions.py"
  etag   = filemd5("${path.root}/../glue/jobs/build_stock_dimensions.py")
}

resource "aws_s3_object" "glue_script_fact" {
  bucket = var.s3_bucket
  key    = "glue-scripts/build_stock_fact_table.py"
  source = "${path.root}/../glue/jobs/build_stock_fact_table.py"
  etag   = filemd5("${path.root}/../glue/jobs/build_stock_fact_table.py")
}

resource "aws_s3_object" "glue_script_aggregations" {
  bucket = var.s3_bucket
  key    = "glue-scripts/build_stock_aggregations.py"
  source = "${path.root}/../glue/jobs/build_stock_aggregations.py"
  etag   = filemd5("${path.root}/../glue/jobs/build_stock_aggregations.py")
}

# ============================================================================
# GLUE JOB 1: Build Dimensions
# ============================================================================

resource "aws_glue_job" "build_dimensions" {
  name         = "nasdaq-airflow-dimensions-${var.environment}"
  role_arn     = var.glue_role_arn  # Changed from aws_iam_role.glue_service_role.arn
  glue_version = "4.0"
  
  command {
    name            = "glueetl"
    script_location = "s3://${var.s3_bucket}/glue-scripts/build_stock_dimensions.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${var.s3_bucket}/logs/glue-spark-logs/"
    "--enable-job-insights"              = "true"
    "--enable-glue-datacatalog"          = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                          = "s3://${var.s3_bucket}/temp/glue/"
    "--datalake-formats"                 = "iceberg"
    "--conf" = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=s3://${var.s3_bucket}/warehouse/ --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
  }

  execution_property {
    max_concurrent_runs = 2
  }

  max_retries = 1
  timeout     = 60  # 60 minutes

  number_of_workers = 2
  worker_type       = "G.1X"  # 1X = 4 vCPU, 16 GB memory

  tags = {
    Name        = "build_stock_dimensions_${var.environment}"
    Environment = var.environment
    Purpose     = "Build dimension tables"
  }

  depends_on = [
    aws_s3_object.glue_script_dimensions
  ]
}

# ============================================================================
# GLUE JOB 2: Build Fact Table
# ============================================================================

resource "aws_glue_job" "build_fact_table" {
  name         = "nasdaq-airflow-fact-${var.environment}"
  role_arn     = var.glue_role_arn  # Changed from aws_iam_role.glue_service_role.arn
  glue_version = "4.0"
  
  command {
    name            = "glueetl"
    script_location = "s3://${var.s3_bucket}/glue-scripts/build_stock_fact_table.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${var.s3_bucket}/logs/glue-spark-logs/"
    "--enable-job-insights"              = "true"
    "--enable-glue-datacatalog"          = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                          = "s3://${var.s3_bucket}/temp/glue/"
    "--processing_date"                  = ""  # Will be set when job is run
    "--datalake-formats"                 = "iceberg"
    "--conf"                             = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=s3://${var.s3_bucket}/warehouse/ --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
  }

  execution_property {
    max_concurrent_runs = 2
  }

  max_retries = 1
  timeout     = 60

  number_of_workers = 5
  worker_type       = "G.1X"

  tags = {
    Name        = "build_stock_fact_table_${var.environment}"
    Environment = var.environment
    Purpose     = "Build fact table with derived metrics"
  }

  depends_on = [
    aws_s3_object.glue_script_fact
  ]
}

# ============================================================================
# GLUE JOB 3: Build Aggregations
# ============================================================================

resource "aws_glue_job" "build_aggregations" {
  name         = "nasdaq-airflow-aggregations-${var.environment}"
  role_arn     = var.glue_role_arn  # Changed from aws_iam_role.glue_service_role.arn
  glue_version = "4.0"
  
  command {
    name            = "glueetl"
    script_location = "s3://${var.s3_bucket}/glue-scripts/build_stock_aggregations.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${var.s3_bucket}/logs/glue-spark-logs/"
    "--enable-job-insights"              = "true"
    "--enable-glue-datacatalog"          = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                          = "s3://${var.s3_bucket}/temp/glue/"
    "--datalake-formats"                 = "iceberg"
    "--conf"                             = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=s3://${var.s3_bucket}/warehouse/ --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
  }

  execution_property {
    max_concurrent_runs = 2
  }

  max_retries = 1
  timeout     = 60

  number_of_workers = 3
  worker_type       = "G.1X"

  tags = {
    Name        = "build_stock_aggregations_${var.environment}"
    Environment = var.environment
    Purpose     = "Build aggregation tables"
  }

  depends_on = [
    aws_s3_object.glue_script_aggregations
  ]
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "database_name" {
  value       = aws_glue_catalog_database.nasdaq_warehouse.name
  description = "Glue catalog database name"
}

output "job_names" {
  value = {
    dimensions   = aws_glue_job.build_dimensions.name
    fact_table   = aws_glue_job.build_fact_table.name
    aggregations = aws_glue_job.build_aggregations.name
  }
  description = "Glue job names"
}