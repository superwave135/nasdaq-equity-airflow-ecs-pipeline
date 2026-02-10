# terraform/modules/iam/variables.tf

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "data_bucket_arn" {
  description = "ARN of the data S3 bucket"
  type        = string
}

variable "scripts_bucket_arn" {
  description = "ARN of the scripts S3 bucket"
  type        = string
}

variable "glue_job_names" {
  description = "List of Glue job names for IAM permissions"
  type        = list(string)
  default     = []
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

# Legacy variables for compatibility (can be removed if not needed)
variable "database_name" {
  description = "Name of the Glue catalog database"
  type        = string
  default     = ""
}

variable "s3_bucket" {
  description = "S3 bucket name for Glue scripts and data"
  type        = string
  default     = ""
}