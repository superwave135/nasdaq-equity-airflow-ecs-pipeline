# terraform/modules/efs/main.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_efs_file_system" "main" {
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode
  
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null
  
  encrypted = true
  
  tags = {
    Name        = "${var.project_name}-efs"
    Environment = var.environment
  }
}

resource "aws_efs_mount_target" "main" {
  count = length(var.subnet_ids)
  
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = var.security_group_ids
}

# ============================================================================
# SEPARATE ACCESS POINTS - One for each Airflow directory
# ============================================================================

# Access Point for Logs
resource "aws_efs_access_point" "logs" {
  file_system_id = aws_efs_file_system.main.id
  
  posix_user {
    gid = 50000
    uid = 50000
  }
  
  root_directory {
    path = "/airflow/logs"
    creation_info {
      owner_gid   = 50000
      owner_uid   = 50000
      permissions = "755"
    }
  }
  
  tags = {
    Name        = "${var.project_name}-logs-access-point"
    Environment = var.environment
  }
}

# Access Point for Plugins
resource "aws_efs_access_point" "plugins" {
  file_system_id = aws_efs_file_system.main.id
  
  posix_user {
    gid = 50000
    uid = 50000
  }
  
  root_directory {
    path = "/airflow/plugins"
    creation_info {
      owner_gid   = 50000
      owner_uid   = 50000
      permissions = "755"
    }
  }
  
  tags = {
    Name        = "${var.project_name}-plugins-access-point"
    Environment = var.environment
  }
}
