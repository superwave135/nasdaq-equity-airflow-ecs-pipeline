# terraform/modules/alb/main.tf
# Application Load Balancer for Airflow Webserver

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# APPLICATION LOAD BALANCER
# ============================================================================

resource "aws_lb" "airflow" {
  name               = "${var.project_name}-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.subnet_ids

  enable_deletion_protection = false
  enable_http2              = true
  
  tags = {
    Name        = "${var.project_name}-alb-${var.environment}"
    Environment = var.environment
    Purpose     = "Airflow Webserver Load Balancer"
  }
}

# ============================================================================
# TARGET GROUP FOR AIRFLOW WEBSERVER
# ============================================================================

resource "aws_lb_target_group" "webserver" {
  name        = "${var.project_name}-webserver-${var.environment}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200,302"
  }
  
  deregistration_delay = 30
  
  tags = {
    Name        = "${var.project_name}-webserver-tg-${var.environment}"
    Environment = var.environment
  }
}

# ============================================================================
# LISTENERS
# ============================================================================

# HTTP Listener - redirect to HTTPS if certificate provided, otherwise serve
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.airflow.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn != null ? "redirect" : "forward"
    
    dynamic "redirect" {
      for_each = var.certificate_arn != null ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    
    target_group_arn = var.certificate_arn == null ? aws_lb_target_group.webserver.arn : null
  }
}

# HTTPS Listener (only if certificate provided)
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != null && var.certificate_arn != "" ? 1 : 0
  
  load_balancer_arn = aws_lb.airflow.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webserver.arn
  }
}
