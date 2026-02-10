# ============================================================================
# PROJECT CONFIGURATION
# ============================================================================
project_name = "nasdaq-airflow-ecs"
environment  = "dev"
aws_region   = "ap-southeast-1"

# ============================================================================
# DOCKER IMAGE CONFIGURATION
# ============================================================================
# Using custom ECR image for initial deployment

# image (below) with GX integrated into the main pipeline DAG flow (need to check vYYYYMMDD-hhmmss from the newly pushed image in ECR)
# Update with the new fixed version
airflow_docker_image = "881786084229.dkr.ecr.ap-southeast-1.amazonaws.com/nasdaq-airflow:vYYYYMMDD-hhmmss-gx-main-pipeline-integrated"

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================

# Generate a strong random password
# airflow_db_password="$(openssl rand -base64 24)"
# echo $airflow_db_password   # copy this value and paste into airflow_db_password

airflow_db_password       = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
airflow_db_username       = "airflow_admin"
rds_instance_class        = "db.t3.small"
rds_allocated_storage     = 20
rds_multi_az              = false
rds_backup_retention_days = 7
rds_backup_window         = "03:00-04:00"
rds_maintenance_window    = "sun:04:00-sun:05:00"

# ============================================================================
# AIRFLOW CONFIGURATION
# ============================================================================

# Airflow uses airflow_fernet_key to encrypt sensitive values in its metadata DB. 
# Generate one with: python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
# Store the output in terraform.tfvars as airflow_fernet_key. 
# Keep it secret and consistent — rotating it requires re-encrypting all stored connections.

airflow_fernet_key = "Hs_56gk3xt17fF3eWO4UV_5Q5hOGIkV20_h2oKW6lM0="
airflow_executor   = "LocalExecutor"

# ============================================================================
# ECS RESOURCE SIZING
# ============================================================================
# Increase these (REQUIRED):
webserver_cpu    = 1024
webserver_memory = 2048
scheduler_cpu    = 1024
scheduler_memory = 2048
worker_cpu       = 1024
worker_memory    = 2048

# Worker auto-scaling (only used if airflow_executor = "CeleryExecutor")
worker_min_capacity = 1
worker_max_capacity = 5
enable_fargate_spot = false

# ============================================================================
# GLUE CONFIGURATION
# ============================================================================
glue_database_name     = "nasdaq_airflow_warehouse_dev"
glue_number_of_workers = 2

# ============================================================================
# LAMBDA CONFIGURATION
# ============================================================================
lambda_vpc_enabled = false

# ============================================================================
# Stock API CONFIGURATION
# ============================================================================
stock_api_endpoint = "https://financialmodelingprep.com/stable/quote"

# ============================================================================
# S3 LIFECYCLE POLICIES
# ============================================================================
s3_raw_data_retention_days        = 90
s3_processed_data_transition_days = 30

# ============================================================================
# EFS CONFIGURATION
# ============================================================================
efs_performance_mode = "generalPurpose"
efs_throughput_mode  = "bursting"

# ============================================================================
# OPTIONAL: HTTPS CONFIGURATION
# ============================================================================
acm_certificate_arn = null

# Optional: Explicitly set bucket name instead of auto-generating
# data_bucket_name = "nasdaq-airflow-ecs-data-dev"
