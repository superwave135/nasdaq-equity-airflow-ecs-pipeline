# terraform/modules/glue/variables.tf

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "database_name" {
  description = "Name of the Glue catalog database"
  type        = string
}

variable "s3_bucket" {
  description = "S3 bucket name for Glue scripts and data"
  type        = string
}

variable "glue_version" {
  description = "Glue version to use"
  type        = string
  default     = "4.0"
}

variable "worker_type" {
  description = "Glue worker type (G.1X, G.2X, etc.)"
  type        = string
  default     = "G.1X"
}

variable "number_of_workers" {
  description = "Number of Glue workers"
  type        = number
  default     = 2
}

variable "glue_role_arn" {
  description = "IAM role ARN for Glue jobs (from IAM module)"
  type        = string
}

variable "scripts_bucket" {
  description = "S3 bucket name where Glue scripts are stored"
  type        = string
}

variable "jobs" {
  description = "Map of Glue job configurations"
  type = map(object({
    name        = string
    script_path = string
    timeout     = number
  }))
  default = {}
}
