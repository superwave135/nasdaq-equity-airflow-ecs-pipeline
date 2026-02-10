# terraform/modules/security-groups/outputs.tf

output "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}

output "efs_security_group_id" {
  description = "Security group ID for EFS"
  value       = aws_security_group.efs.id
}

output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "lambda_security_group_id" {
  description = "Security group ID for Lambda (if created)"
  value       = var.create_lambda_sg ? aws_security_group.lambda[0].id : null
}
