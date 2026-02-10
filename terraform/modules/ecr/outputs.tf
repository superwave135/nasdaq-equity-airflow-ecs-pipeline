# terraform/modules/ecr/outputs.tf

output "repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.airflow.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.airflow.arn
}

output "repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.airflow.name
}

output "registry_id" {
  description = "ECR registry ID"
  value       = aws_ecr_repository.airflow.registry_id
}
