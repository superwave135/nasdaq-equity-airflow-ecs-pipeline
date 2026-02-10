
# ECR Repository
output "ecr_repository_url" {
  description = "ECR repository URL for Airflow Docker images"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = module.ecr.repository_name
}

output "data_docs_url" {
  description = "URL to access Great Expectations Data Docs"
  value       = "http://nasdaq-airflow-ecs-data-dev.s3-website-ap-southeast-1.amazonaws.com/great_expectations/data_docs/s3_site/index.html"
}