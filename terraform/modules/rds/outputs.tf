output "db_instance_id" {
description = "RDS instance ID"
value       = aws_db_instance.main.id
}
output "db_endpoint" {
description = "RDS endpoint"
value       = aws_db_instance.main.endpoint
}
output "db_port" {
description = "RDS port"
value       = aws_db_instance.main.port
}
output "db_name" {
description = "Database name"
value       = aws_db_instance.main.db_name
}
output "db_arn" {
description = "RDS instance ARN"
value       = aws_db_instance.main.arn
}

output "db_address" {
  description = "RDS address (without port)"
  value       = aws_db_instance.main.address
}
