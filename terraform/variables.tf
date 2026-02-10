# terraform/variables.tf
# Variables for NASDAQ Stock Pipeline on ECS Fargate

# ============================================================================
# GENERAL CONFIGURATION
# ============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "nasdaq-stock-pipeline"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "GeekyTan"
}

# ============================================================================
# NETWORK CONFIGURATION
# ============================================================================

variable "use_existing_vpc" {
  description = "Whether to use an existing VPC"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "Existing VPC ID (if use_existing_vpc is true)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (if creating new)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Airflow UI"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this in production
}

# ============================================================================
# RDS CONFIGURATION (AIRFLOW METADATA DATABASE)
# ============================================================================

variable "airflow_db_name" {
  description = "Airflow database name"
  type        = string
  default     = "airflow"
}

variable "airflow_db_username" {
  description = "Airflow database username"
  type        = string
  default     = "airflow"
  sensitive   = true
}

variable "airflow_db_password" {
  description = "Airflow database password"
  type        = string
  sensitive   = true
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = false
}

variable "rds_backup_retention_days" {
  description = "Number of days to retain RDS backups"
  type        = number
  default     = 7
}

variable "rds_backup_window" {
  description = "RDS backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "rds_maintenance_window" {
  description = "RDS maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# ============================================================================
# EFS CONFIGURATION
# ============================================================================

variable "efs_performance_mode" {
  description = "EFS performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode (bursting or provisioned)"
  type        = string
  default     = "bursting"
}

variable "efs_provisioned_throughput" {
  description = "EFS provisioned throughput in MiB/s (only if throughput_mode is provisioned)"
  type        = number
  default     = null
}

# ============================================================================
# ECS CONFIGURATION
# ============================================================================

variable "enable_container_insights" {
  description = "Enable Container Insights for ECS cluster"
  type        = bool
  default     = true
}

variable "airflow_docker_image" {
  description = "Docker image for Airflow"
  type        = string
  default     = "nasdaq-airflow:latest"
}

# Webserver configuration
variable "webserver_cpu" {
  description = "CPU units for webserver task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "webserver_memory" {
  description = "Memory for webserver task in MB"
  type        = number
  default     = 2048
}

# Scheduler configuration
variable "scheduler_cpu" {
  description = "CPU units for scheduler task (1024 = 1 vCPU)"
  type        = number
  default     = 2048
}

variable "scheduler_memory" {
  description = "Memory for scheduler task in MB"
  type        = number
  default     = 4096
}

# Worker configuration
variable "worker_cpu" {
  description = "CPU units for worker task (1024 = 1 vCPU)"
  type        = number
  default     = 2048
}

variable "worker_memory" {
  description = "Memory for worker task in MB"
  type        = number
  default     = 4096
}

variable "worker_min_capacity" {
  description = "Minimum number of worker tasks"
  type        = number
  default     = 0
}

variable "worker_max_capacity" {
  description = "Maximum number of worker tasks"
  type        = number
  default     = 20
}

variable "enable_fargate_spot" {
  description = "Enable Fargate Spot for workers (70% cost savings)"
  type        = bool
  default     = true
}

variable "enable_worker_autoscaling" {
  description = "Enable auto-scaling for workers"
  type        = bool
  default     = true
}

# ============================================================================
# AIRFLOW CONFIGURATION
# ============================================================================

variable "airflow_executor" {
  description = "Airflow executor type (CeleryExecutor for distributed, LocalExecutor for single instance)"
  type        = string
  default     = "CeleryExecutor"
}

variable "airflow_fernet_key" {
  description = "Fernet key for Airflow (generate with: python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')"
  type        = string
  sensitive   = true
}

# ============================================================================
# ALB CONFIGURATION
# ============================================================================

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional)"
  type        = string
  default     = ""
}

# ============================================================================
# S3 CONFIGURATION
# ============================================================================

variable "s3_raw_data_retention_days" {
  description = "Number of days to retain raw data in S3"
  type        = number
  default     = 90
}

variable "s3_processed_data_transition_days" {
  description = "Number of days before transitioning processed data to Glacier"
  type        = number
  default     = 180
}

# ============================================================================
# LAMBDA CONFIGURATION
# ============================================================================

variable "stock_api_endpoint" {
  description = "Stock API endpoint URL"
  type        = string
}

variable "lambda_vpc_enabled" {
  description = "Enable VPC configuration for Lambda"
  type        = bool
  default     = false
}

# ============================================================================
# GLUE CONFIGURATION
# ============================================================================

variable "glue_database_name" {
  description = "Glue database name"
  type        = string
  default     = "nasdaq_airflow_warehouse_dev"
}

variable "glue_number_of_workers" {
  description = "Number of workers for Glue jobs"
  type        = number
  default     = 2
}

# ============================================================================
# MONITORING CONFIGURATION
# ============================================================================

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

# Add Explicit S3 Bucket Variable
variable "data_bucket_name" {
  description = "Name of the S3 data lake bucket (auto-generated if not provided)"
  type        = string
  default     = ""  # Empty means auto-generate from project_name-data-environment
}