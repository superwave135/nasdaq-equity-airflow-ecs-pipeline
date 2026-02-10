output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github_actions.arn
  description = "ARN of the GitHub OIDC provider"
}

output "role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "ARN of the IAM role for GitHub Actions - ADD THIS TO GITHUB SECRETS AS 'AWS_ROLE_ARN'"
}

output "role_name" {
  value       = aws_iam_role.github_actions.name
  description = "Name of the IAM role"
}

output "role_unique_id" {
  value       = aws_iam_role.github_actions.unique_id
  description = "Unique ID of the IAM role"
}