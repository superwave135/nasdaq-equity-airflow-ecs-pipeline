# terraform/modules/iam/outputs.tf
# ============================================================================
# OUTPUTS (Add to your existing outputs.tf)
# ============================================================================
output "ecs_task_execution_role_arn" {
description = "ECS task execution role ARN"
value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
description = "ECS task role ARN"
value       = aws_iam_role.ecs_task.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "glue_execution_role_arn" {
  description = "ARN of the Glue execution role"
  value       = aws_iam_role.glue_service_role.arn
}