# terraform/modules/efs/outputs.tf

output "file_system_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.main.id
}

output "file_system_arn" {
  description = "EFS file system ARN"
  value       = aws_efs_file_system.main.arn
}

output "logs_access_point_id" {
  description = "Access Point ID for Logs"
  value       = aws_efs_access_point.logs.id
}

output "plugins_access_point_id" {
  description = "Access Point ID for Plugins"
  value       = aws_efs_access_point.plugins.id
}

