# terraform/modules/security-groups/main.tf
terraform {
	required_version = ">= 1.5.0"
	required_providers {
	aws = {
		source  = "hashicorp/aws"
		version = "~> 5.0"
		}
	}
}

# ECS Tasks Security Group
resource "aws_security_group" "ecs_tasks" {
	name        = "${var.project_name}-ecs-tasks"
	description = "Security group for ECS tasks (Airflow)"
	vpc_id      = var.vpc_id
	egress {
	description = "Allow all outbound traffic"
	from_port   = 0
	to_port     = 0
	protocol    = "-1"
	cidr_blocks = ["0.0.0.0/0"]
	}
	tags = {
	Name        = "${var.project_name}-ecs-tasks"
	Environment = var.environment
	}
}

# RDS Security Group
resource "aws_security_group" "rds" {
	name        = "${var.project_name}-rds"
	description = "Security group for RDS PostgreSQL"
	vpc_id      = var.vpc_id
	ingress {
	description     = "PostgreSQL from ECS tasks"
	from_port       = 5432
	to_port         = 5432
	protocol        = "tcp"
	security_groups = [aws_security_group.ecs_tasks.id]
	}
	egress {
	description = "Allow all outbound traffic"
	from_port   = 0
	to_port     = 0
	protocol    = "-1"
	cidr_blocks = ["0.0.0.0/0"]
	}
	tags = {
	Name        = "${var.project_name}-rds"
	Environment = var.environment
	}
}

# EFS Security Group
resource "aws_security_group" "efs" {
	name        = "${var.project_name}-efs"
	description = "Security group for EFS"
	vpc_id      = var.vpc_id
	ingress {
	description     = "NFS from ECS tasks"
	from_port       = 2049
	to_port         = 2049
	protocol        = "tcp"
	security_groups = [aws_security_group.ecs_tasks.id]
	}
	egress {
	description = "Allow all outbound traffic"
	from_port   = 0
	to_port     = 0
	protocol    = "-1"
	cidr_blocks = ["0.0.0.0/0"]
	}
	tags = {
	Name        = "${var.project_name}-efs"
	Environment = var.environment
	}
}

# ALB Security Group (optional, for production)
resource "aws_security_group" "alb" {
	name        = "${var.project_name}-alb"
	description = "Security group for Application Load Balancer"
	vpc_id      = var.vpc_id
	ingress {
	description = "HTTP from internet"
	from_port   = 80
	to_port     = 80
	protocol    = "tcp"
	cidr_blocks = var.allowed_cidr_blocks
	}
	ingress {
	description = "HTTPS from internet"
	from_port   = 443
	to_port     = 443
	protocol    = "tcp"
	cidr_blocks = var.allowed_cidr_blocks
	}
	egress {
	description = "Allow all outbound traffic"
	from_port   = 0
	to_port     = 0
	protocol    = "-1"
	cidr_blocks = ["0.0.0.0/0"]
	}
	tags = {
	Name        = "${var.project_name}-alb"
	Environment = var.environment
	}
}

# Lambda Security Group (if Lambda needs VPC access)
resource "aws_security_group" "lambda" {
	count = var.create_lambda_sg ? 1 : 0
	name        = "${var.project_name}-lambda"
	description = "Security group for Lambda functions"
	vpc_id      = var.vpc_id
	egress {
	description = "Allow all outbound traffic"
	from_port   = 0
	to_port     = 0
	protocol    = "-1"
	cidr_blocks = ["0.0.0.0/0"]
	}
	tags = {
	Name        = "${var.project_name}-lambda"
	Environment = var.environment
	}
}

# Allow ALB to communicate with ECS tasks
resource "aws_security_group_rule" "ecs_from_alb" {
type                     = "ingress"
description              = "Allow ALB to ECS tasks on port 8080"
from_port                = 8080
to_port                  = 8080
protocol                 = "tcp"
source_security_group_id = aws_security_group.alb.id
security_group_id        = aws_security_group.ecs_tasks.id
}
