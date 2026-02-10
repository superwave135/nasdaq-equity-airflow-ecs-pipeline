terraform {
	required_version = ">= 1.5.0"
	required_providers {
		aws = {
		source  = "hashicorp/aws"
		version = "~> 5.0"
		}
	}
}

resource "aws_db_subnet_group" "main" {
	name       = "${var.project_name}-db-subnet"
	subnet_ids = var.subnet_ids
	tags = {
		Name        = "${var.project_name}-db-subnet"
		Environment = var.environment
	}
}

resource "aws_db_instance" "main" {
	identifier     = "${var.project_name}-db"
	engine         = "postgres"
	engine_version = "15.15"
	instance_class = var.instance_class
	allocated_storage     = var.allocated_storage
	storage_type          = "gp3"
	storage_encrypted     = true
	db_name  = var.db_name
	username = var.db_username
	password = var.db_password
	db_subnet_group_name   = aws_db_subnet_group.main.name
	vpc_security_group_ids = var.security_group_ids
	multi_az               = var.multi_az
	backup_retention_period = var.backup_retention_period
	backup_window          = var.backup_window
	maintenance_window     = var.maintenance_window
	skip_final_snapshot       = true
	final_snapshot_identifier = "${var.project_name}-final-snapshot"
	tags = {
		Name        = "${var.project_name}-db"
		Environment = var.environment
	}
}
