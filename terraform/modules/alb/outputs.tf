# terraform/modules/alb/outputs.tf

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.airflow.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.airflow.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.airflow.zone_id
}

output "webserver_target_group_arn" {
  description = "ARN of the webserver target group"
  value       = aws_lb_target_group.webserver.arn
}

output "webserver_target_group_name" {
  description = "Name of the webserver target group"
  value       = aws_lb_target_group.webserver.name
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (if certificate provided)"
  value       = var.certificate_arn != null ? aws_lb_listener.https[0].arn : null
}
