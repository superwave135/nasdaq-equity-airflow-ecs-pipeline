# terraform/modules/s3/variables.tf

variable "project_name" {
  description = "Name of the project (used for tagging)"
  type        = string
  default     = ""
}

variable "bucket_name" {
  description = "Name of the S3 bucket (must be globally unique)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "enable_lifecycle_rules" {
  description = "Enable lifecycle rules for data retention"
  type        = bool
  default     = true
}

variable "raw_data_expiration_days" {
  description = "Days to retain raw data before deletion"
  type        = number
  default     = 90
}

variable "processed_data_transition_days" {
  description = "Days before transitioning processed data to cheaper storage"
  type        = number
  default     = 30
}
