# terraform/modules/efs/variables.tf
variable "project_name" {
description = "Project name"
type        = string
}
variable "environment" {
description = "Environment (dev/prod)"
type        = string
}
variable "subnet_ids" {
description = "List of subnet IDs for mount targets"
type        = list(string)
}
variable "security_group_ids" {
description = "List of security group IDs"
type        = list(string)
}
variable "performance_mode" {
description = "EFS performance mode (generalPurpose or maxIO)"
type        = string
default     = "generalPurpose"
}
variable "throughput_mode" {
description = "EFS throughput mode (bursting or provisioned)"
type        = string
default     = "bursting"
}
variable "provisioned_throughput_in_mibps" {
description = "Provisioned throughput in MiB/s (required if throughput_mode is provisioned)"
type        = number
default     = null
}
