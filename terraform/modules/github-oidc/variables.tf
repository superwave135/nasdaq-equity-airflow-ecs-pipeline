variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  
  validation {
    condition     = length(var.github_org) > 0
    error_message = "GitHub organization cannot be empty"
  }
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  
  validation {
    condition     = length(var.github_repo) > 0
    error_message = "GitHub repository name cannot be empty"
  }
}

variable "github_branch" {
  description = "GitHub branch to allow (e.g., main, develop)"
  type        = string
  default     = "main"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "nasdaq-airflow"
}