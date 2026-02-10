# terraform/modules/ecs-services/variables.tf

# ============================================================================
# PROJECT VARIABLES
# ============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

# ============================================================================
# NETWORKING VARIABLES
# ============================================================================

variable "vpc_id" {
  description = "VPC ID where ECS services will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

# ============================================================================
# ECS CLUSTER VARIABLES
# ============================================================================

variable "ecs_cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

# ============================================================================
# IAM ROLE VARIABLES
# ============================================================================

variable "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
}

# ============================================================================
# DATABASE VARIABLES
# ============================================================================

variable "db_host" {
  description = "RDS PostgreSQL database host"
  type        = string
}

variable "db_port" {
  description = "RDS PostgreSQL database port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "RDS PostgreSQL database name"
  type        = string
}

variable "db_username" {
  description = "RDS PostgreSQL database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS PostgreSQL database password"
  type        = string
  sensitive   = true
}

# ============================================================================
# EFS VARIABLES
# ============================================================================

variable "efs_file_system_id" {
  description = "EFS file system ID for shared DAGs/logs/plugins"
  type        = string
}


# ============================================================================
# LOAD BALANCER VARIABLES
# ============================================================================

variable "webserver_target_group_arn" {
  description = "Target group ARN for Airflow webserver"
  type        = string
}

# ============================================================================
# AIRFLOW CONFIGURATION VARIABLES
# ============================================================================

variable "airflow_image" {
  description = "Docker image for Airflow (ECR repository URL)"
  type        = string
  default     = "881786084229.dkr.ecr.ap-southeast-1.amazonaws.com/nasdaq-airflow:v20260204-143022-with-gx"
}

variable "airflow_executor" {
  description = "Airflow executor type (LocalExecutor, CeleryExecutor, etc.)"
  type        = string
  default     = "LocalExecutor"
  
  validation {
    condition     = contains(["LocalExecutor", "CeleryExecutor", "SequentialExecutor"], var.airflow_executor)
    error_message = "airflow_executor must be one of: LocalExecutor, CeleryExecutor, SequentialExecutor"
  }
}

variable "fernet_key" {
  description = "Fernet key for Airflow encryption"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

# ============================================================================
# RESOURCE SIZING VARIABLES
# ============================================================================

variable "webserver_cpu" {
  description = "CPU units for webserver task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "webserver_memory" {
  description = "Memory (MiB) for webserver task"
  type        = number
  default     = 1024
}

variable "scheduler_cpu" {
  description = "CPU units for scheduler task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "scheduler_memory" {
  description = "Memory (MiB) for scheduler task"
  type        = number
  default     = 1024
}

variable "worker_cpu" {
  description = "CPU units for worker task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "worker_memory" {
  description = "Memory (MiB) for worker task"
  type        = number
  default     = 2048
}

# ============================================================================
# SCALING VARIABLES
# ============================================================================

variable "worker_min_capacity" {
  description = "Minimum number of worker tasks"
  type        = number
  default     = 1
}

variable "worker_max_capacity" {
  description = "Maximum number of worker tasks"
  type        = number
  default     = 5
}

variable "enable_fargate_spot_for_workers" {
  description = "Enable Fargate Spot for worker tasks (cost savings)"
  type        = bool
  default     = false
}

variable "efs_logs_access_point_id" {
  description = "EFS Access Point ID for Logs"
  type        = string
}

variable "efs_plugins_access_point_id" {
  description = "EFS Access Point ID for Plugins"
  type        = string
}
