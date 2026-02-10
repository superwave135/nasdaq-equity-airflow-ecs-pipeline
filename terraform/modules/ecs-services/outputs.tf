# terraform/modules/ecs-services/outputs.tf

# ============================================================================
# ECS SERVICE OUTPUTS
# ============================================================================

output "webserver_service_name" {
  description = "Name of the Airflow webserver ECS service"
  value       = aws_ecs_service.webserver.name
}

output "webserver_service_arn" {
  description = "ARN of the Airflow webserver ECS service"
  value       = aws_ecs_service.webserver.id
}

output "scheduler_service_name" {
  description = "Name of the Airflow scheduler ECS service"
  value       = aws_ecs_service.scheduler.name
}

output "scheduler_service_arn" {
  description = "ARN of the Airflow scheduler ECS service"
  value       = aws_ecs_service.scheduler.id
}

output "worker_service_name" {
  description = "Name of the Airflow worker ECS service (if CeleryExecutor)"
  value       = var.airflow_executor == "CeleryExecutor" ? aws_ecs_service.worker[0].name : null
}

output "worker_service_arn" {
  description = "ARN of the Airflow worker ECS service (if CeleryExecutor)"
  value       = var.airflow_executor == "CeleryExecutor" ? aws_ecs_service.worker[0].id : null
}

# ============================================================================
# TASK DEFINITION OUTPUTS
# ============================================================================

output "webserver_task_definition_arn" {
  description = "ARN of the webserver task definition"
  value       = aws_ecs_task_definition.webserver.arn
}

output "scheduler_task_definition_arn" {
  description = "ARN of the scheduler task definition"
  value       = aws_ecs_task_definition.scheduler.arn
}

output "worker_task_definition_arn" {
  description = "ARN of the worker task definition (if CeleryExecutor)"
  value       = var.airflow_executor == "CeleryExecutor" ? aws_ecs_task_definition.worker[0].arn : null
}

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

output "webserver_log_group" {
  description = "CloudWatch log group for webserver"
  value       = aws_cloudwatch_log_group.webserver.name
}

output "scheduler_log_group" {
  description = "CloudWatch log group for scheduler"
  value       = aws_cloudwatch_log_group.scheduler.name
}

output "worker_log_group" {
  description = "CloudWatch log group for worker (if CeleryExecutor)"
  value       = var.airflow_executor == "CeleryExecutor" ? aws_cloudwatch_log_group.worker[0].name : null
}

# ============================================================================
# REDIS OUTPUTS (IF CELERY EXECUTOR)
# ============================================================================

output "redis_endpoint" {
  description = "Redis cluster endpoint (if CeleryExecutor)"
  value       = var.airflow_executor == "CeleryExecutor" ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : null
}

output "redis_port" {
  description = "Redis cluster port (if CeleryExecutor)"
  value       = var.airflow_executor == "CeleryExecutor" ? aws_elasticache_cluster.redis[0].cache_nodes[0].port : null
}

# ============================================================================
# AUTO-SCALING POLICY OUTPUTS
# ============================================================================

output "worker_scale_up_policy_arn" {
  description = "ARN of the worker scale-up policy"
  value       = var.airflow_executor == "CeleryExecutor" ? aws_appautoscaling_policy.worker_scale_up[0].arn : null
}

output "worker_scale_down_policy_arn" {
  description = "ARN of the worker scale-down policy (SQS-based)"
  value       = var.airflow_executor == "CeleryExecutor" ? aws_appautoscaling_policy.worker_scale_sqs[0].arn : null
}
