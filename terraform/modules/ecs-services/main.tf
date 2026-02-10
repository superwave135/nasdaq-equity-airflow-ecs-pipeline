# terraform/modules/ecs-services/main.tf
# ECS Services for Airflow: Webserver, Scheduler, Worker

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
# LOCALS
# ============================================================================

locals {
  container_name_webserver = "airflow-webserver"
  container_name_scheduler = "airflow-scheduler"
  container_name_worker    = "airflow-worker"
  
  common_environment = [
    {
      name  = "AIRFLOW__CORE__EXECUTOR"
      value = var.airflow_executor
    },
    {
      name  = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN"
      value = "postgresql+psycopg2://${var.db_username}:${var.db_password}@${var.db_host}:${var.db_port}/${var.db_name}"
    },
    {
      name  = "AIRFLOW__CORE__FERNET_KEY"
      value = var.fernet_key
    },
    {
      name  = "AIRFLOW__CORE__LOAD_EXAMPLES"
      value = "False"
    },
    {
      name  = "AIRFLOW__CORE__PLUGINS_FOLDER"
      value = "/opt/airflow/plugins"
    },
    {
      name  = "AIRFLOW__CORE__DAGS_FOLDER"
      value = "/opt/airflow/dags"
    },
    {
      name  = "AIRFLOW__WEBSERVER__EXPOSE_CONFIG"
      value = "True"
    },
    {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    },
    {
      name  = "AIRFLOW__LOGGING__REMOTE_LOGGING"
      value = "False"
    }
  ]
  
  # For CeleryExecutor, need Redis backend
  celery_environment = var.airflow_executor == "CeleryExecutor" ? [
    {
      name  = "AIRFLOW__CELERY__BROKER_URL"
      value = "redis://${aws_elasticache_cluster.redis[0].cache_nodes[0].address}:6379/0"
    },
    {
      name  = "AIRFLOW__CELERY__RESULT_BACKEND"
      value = "db+postgresql://${var.db_username}:${var.db_password}@${var.db_host}:${var.db_port}/${var.db_name}"
    }
  ] : []
}

# ============================================================================
# REDIS FOR CELERY (IF CELERY EXECUTOR)
# ============================================================================

resource "aws_elasticache_subnet_group" "redis" {
  count = var.airflow_executor == "CeleryExecutor" ? 1 : 0
  
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids
  
  tags = {
    Name = "${var.project_name}-redis-subnet-group"
  }
}

resource "aws_elasticache_cluster" "redis" {
  count = var.airflow_executor == "CeleryExecutor" ? 1 : 0
  
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  
  subnet_group_name  = aws_elasticache_subnet_group.redis[0].name
  security_group_ids = [aws_security_group.redis[0].id]
  
  tags = {
    Name = "${var.project_name}-redis"
  }
}

resource "aws_security_group" "redis" {
  count = var.airflow_executor == "CeleryExecutor" ? 1 : 0
  
  name        = "${var.project_name}-redis-sg"
  description = "Security group for Redis (Celery broker)"
  vpc_id      = var.vpc_id
  
  ingress {
    description     = "Redis from ECS tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.ecs_tasks_security_group_id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.project_name}-redis-sg"
  }
}

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

resource "aws_cloudwatch_log_group" "airflow" {
  name              = "/ecs/${var.project_name}/airflow"
  retention_in_days = 7
  
  tags = {
    Name = "${var.project_name}-airflow-logs"
  }
}

resource "aws_cloudwatch_log_group" "webserver" {
  name              = "/ecs/${var.project_name}/webserver"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-webserver-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "scheduler" {
  name              = "/ecs/${var.project_name}/scheduler"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-scheduler-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "worker" {
  count = var.airflow_executor == "CeleryExecutor" ? 1 : 0
  
  name              = "/ecs/${var.project_name}/worker"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-worker-logs"
    Environment = var.environment
  }
}

# ============================================================================
# TASK DEFINITION: WEBSERVER
# ============================================================================

resource "aws_ecs_task_definition" "webserver" {
  family                   = "${var.project_name}-webserver"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.webserver_cpu
  memory                   = var.webserver_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn
  
  container_definitions = jsonencode([
    {
      name      = local.container_name_webserver
      image     = var.airflow_image
      essential = true
      command   = ["webserver"]
      
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      
      environment = concat(local.common_environment, local.celery_environment)
      
      mountPoints = [
        {
          sourceVolume  = "efs-logs"
          containerPath = "/opt/airflow/logs"
          readOnly      = false
        },
        {
          sourceVolume  = "efs-plugins"
          containerPath = "/opt/airflow/plugins"
          readOnly      = false
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.webserver.name  # or scheduler/worker
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "webserver"
        }
      }
      
      healthCheck = {
        command = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval = 30
        timeout  = 5
        retries  = 3
      }
    }
  ])
  
  volume {
    name = "efs-logs"
    
    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.efs_logs_access_point_id
      }
    }
  }
  
  volume {
    name = "efs-plugins"
    
    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.efs_plugins_access_point_id
      }
    }
  }
  
  tags = {
    Name = "${var.project_name}-webserver-task"
  }
}

# ============================================================================
# TASK DEFINITION: SCHEDULER
# ============================================================================

resource "aws_ecs_task_definition" "scheduler" {
  family                   = "${var.project_name}-scheduler"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.scheduler_cpu
  memory                   = var.scheduler_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn
  
  container_definitions = jsonencode([
    {
      name      = local.container_name_scheduler
      image     = var.airflow_image
      essential = true
      command   = ["scheduler"]
      
      environment = concat(local.common_environment, local.celery_environment)
      
      mountPoints = [
        {
          sourceVolume  = "efs-logs"
          containerPath = "/opt/airflow/logs"
          readOnly      = false
        },
        {
          sourceVolume  = "efs-plugins"
          containerPath = "/opt/airflow/plugins"
          readOnly      = false
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.scheduler.name  # scheduler
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "scheduler"
        }
      }
      
      # healthCheck = {
      #   command = ["CMD-SHELL", "airflow jobs check --job-type SchedulerJob --local || exit 1"]
      #   interval = 30
      #   timeout  = 10
      #   retries  = 5
      #   startPeriod = 120
      # }
    }
  ])
  
  volume {
    name = "efs-logs"
    
    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.efs_logs_access_point_id
      }
    }
  }
  
  volume {
    name = "efs-plugins"
    
    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.efs_plugins_access_point_id
      }
    }
  }
  
  tags = {
    Name = "${var.project_name}-scheduler-task"
  }
}

# ============================================================================
# TASK DEFINITION: WORKER
# ============================================================================

resource "aws_ecs_task_definition" "worker" {
  count = var.airflow_executor == "CeleryExecutor" ? 1 : 0  # Add this line
  family                   = "${var.project_name}-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn
  
  container_definitions = jsonencode([
    {
      name      = local.container_name_worker
      image     = var.airflow_image
      essential = true
      command   = var.airflow_executor == "CeleryExecutor" ? ["celery", "worker"] : ["worker"]
      
      environment = concat(local.common_environment, local.celery_environment)
      
      mountPoints = [
        {
          sourceVolume  = "efs-logs"
          containerPath = "/opt/airflow/logs"
          readOnly      = false
        },
        {
          sourceVolume  = "efs-plugins"
          containerPath = "/opt/airflow/plugins"
          readOnly      = false
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.webserver.name  # or scheduler/worker
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "worker"
        }
      }
    }
  ])
  
  volume {
    name = "efs-logs"
    
    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.efs_logs_access_point_id
      }
    }
  }
  
  volume {
    name = "efs-plugins"
    
    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.efs_plugins_access_point_id
      }
    }
  }
  
  tags = {
    Name = "${var.project_name}-worker-task"
  }
}

# ============================================================================
# ECS SERVICE: WEBSERVER
# ============================================================================

resource "aws_ecs_service" "webserver" {
  name            = "${var.project_name}-webserver"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.webserver.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_tasks_security_group_id]
    assign_public_ip = false
  }
  
  load_balancer {
    target_group_arn = var.webserver_target_group_arn
    container_name   = local.container_name_webserver
    container_port   = 8080
  }
  
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  
  depends_on = [var.webserver_target_group_arn]
  
  tags = {
    Name = "${var.project_name}-webserver-service"
  }
}

# ============================================================================
# ECS SERVICE: SCHEDULER
# ============================================================================

resource "aws_ecs_service" "scheduler" {
  name            = "${var.project_name}-scheduler"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.scheduler.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_tasks_security_group_id]
    assign_public_ip = false
  }
  
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0
  
  tags = {
    Name = "${var.project_name}-scheduler-service"
  }
}

# ============================================================================
# ECS SERVICE: WORKER (WITH AUTO-SCALING)
# ============================================================================

resource "aws_ecs_service" "worker" {
  count = var.airflow_executor == "CeleryExecutor" ? 1 : 0  # Add this line
  name            = "${var.project_name}-worker"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.worker[0].arn
  desired_count   = var.worker_min_capacity
  
  # Use Fargate Spot for workers to save 70% cost
  capacity_provider_strategy {
    capacity_provider = var.enable_fargate_spot_for_workers ? "FARGATE_SPOT" : "FARGATE"
    weight            = var.enable_fargate_spot_for_workers ? 100 : 0
    base              = 0
  }
  
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = var.enable_fargate_spot_for_workers ? 0 : 100
    base              = var.enable_fargate_spot_for_workers ? 0 : 1
  }
  
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_tasks_security_group_id]
    assign_public_ip = false
  }
  
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50
  
  tags = {
    Name = "${var.project_name}-worker-service"
  }
}

# ============================================================================
# AUTO-SCALING: WORKER SERVICE
# ============================================================================

resource "aws_appautoscaling_target" "worker" {
  count = var.airflow_executor == "CeleryExecutor" ? 1 : 0
  max_capacity       = var.worker_max_capacity
  min_capacity       = var.worker_min_capacity
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.worker[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale UP policy - based on CPU utilization
resource "aws_appautoscaling_policy" "worker_scale_up" {
  count = var.airflow_executor == "CeleryExecutor" ? 1 : 0
  name               = "${var.project_name}-worker-scale-up"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# Alternative: Scale based on SQS queue depth (for CeleryExecutor)
resource "aws_appautoscaling_policy" "worker_scale_sqs" {
  count = var.airflow_executor == "CeleryExecutor" ? 1 : 0
  
  name               = "${var.project_name}-worker-scale-sqs"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    target_value       = 5  # 5 messages per worker
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    
    customized_metric_specification {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      statistic   = "Average"
      unit        = "Count"
      
      dimensions {
        name  = "QueueName"
        value = "celery"
      }
    }
  }
}