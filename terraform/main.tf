provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ============================================================================
# VPC (Use existing or create new)
# ============================================================================

# Option 1: Use existing VPC
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  id    = var.vpc_id
}

data "aws_subnets" "private" {
  count = var.use_existing_vpc ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    Tier = "private"
  }
}

data "aws_subnets" "public" {
  count = var.use_existing_vpc ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    Tier = "public"
  }
}

# Option 2: Create new VPC (simplified - use AWS VPC module in production)
resource "aws_vpc" "main" {
  count = var.use_existing_vpc ? 0 : 1

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "private" {
  count = var.use_existing_vpc ? 0 : length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "private"
  }
}

resource "aws_subnet" "public" {
  count = var.use_existing_vpc ? 0 : length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# NAT Gateway (for private subnets to access internet)
resource "aws_eip" "nat" {
  count  = var.use_existing_vpc ? 0 : (var.enable_nat_gateway ? 1 : 0)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  count = var.use_existing_vpc ? 0 : (var.enable_nat_gateway ? 1 : 0)

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = aws_vpc.main[0].id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = var.use_existing_vpc ? 0 : length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private" {
  count = var.use_existing_vpc ? 0 : length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

# ============================================================================
# LOCAL VARIABLES
# ============================================================================

locals {
  vpc_id = var.use_existing_vpc ? var.vpc_id : aws_vpc.main[0].id

  private_subnet_ids = var.use_existing_vpc ? data.aws_subnets.private[0].ids : aws_subnet.private[*].id
  public_subnet_ids  = var.use_existing_vpc ? data.aws_subnets.public[0].ids : aws_subnet.public[*].id

  account_id = data.aws_caller_identity.current.account_id
  region     = var.aws_region
}

# ============================================================================
# GITHUB OICD
# ============================================================================
module "github_oidc" {
  source = "./modules/github-oidc"

  # These are ALREADY defined in your terraform.tfvars:
  environment  = var.environment
  project_name = var.project_name

  # YOU NEED TO ADD THESE:
  github_org    = "superwave135"
  github_repo   = "nasdaq-airflow-ecs-pipeline"
  github_branch = "main" # Usually "main"
}

# ============================================================================
# SECURITY GROUPS
# ============================================================================

module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = local.vpc_id

  # CIDR blocks for access control
  allowed_cidr_blocks = var.allowed_cidr_blocks
}

# ============================================================================
# IAM ROLES
# ============================================================================

module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment

  # S3 buckets for access
  data_bucket_arn    = module.s3.data_bucket_arn
  scripts_bucket_arn = module.s3.scripts_bucket_arn

  # Glue job names
  glue_job_names = [
    "${var.project_name}-dimensions",
    "${var.project_name}-fact",
    "${var.project_name}-aggregations"
  ]

  # Legacy compatibility
  database_name = var.glue_database_name
  s3_bucket     = module.s3.bucket_name

  # Region
  aws_region = var.aws_region
}

# ============================================================================
# RDS POSTGRESQL (AIRFLOW METADATA DATABASE)
# ============================================================================

module "rds" {
  source = "./modules/rds"

  project_name = var.project_name
  environment  = var.environment

  # Database configuration
  db_name     = var.airflow_db_name
  db_username = var.airflow_db_username
  db_password = var.airflow_db_password # Use AWS Secrets Manager in production

  # Instance configuration
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  multi_az          = var.rds_multi_az

  # Network configuration
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [module.security_groups.rds_security_group_id]

  # Backup configuration
  backup_retention_period = var.rds_backup_retention_days
  backup_window           = var.rds_backup_window
  maintenance_window      = var.rds_maintenance_window
}

# ============================================================================
# EFS (SHARED FILE SYSTEM FOR DAGS, LOGS, PLUGINS)
# ============================================================================

module "efs" {
  source = "./modules/efs"

  project_name = var.project_name
  environment  = var.environment

  # Network configuration
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [module.security_groups.efs_security_group_id]

  # Performance configuration
  performance_mode                = var.efs_performance_mode
  throughput_mode                 = var.efs_throughput_mode
  provisioned_throughput_in_mibps = var.efs_provisioned_throughput
}

# ============================================================================
# APPLICATION LOAD BALANCER (FOR AIRFLOW UI)
# ============================================================================

module "alb" {
  source = "./modules/alb"

  project_name = var.project_name
  environment  = var.environment

  # Network configuration
  vpc_id             = local.vpc_id
  subnet_ids         = local.public_subnet_ids
  security_group_ids = [module.security_groups.alb_security_group_id]

  # Health check configuration
  health_check_path     = "/health"
  health_check_interval = 30

  # Certificate ARN for HTTPS (optional)
  certificate_arn = var.acm_certificate_arn
}

# ============================================================================
# ECS CLUSTER
# ============================================================================

module "ecs_cluster" {
  source = "./modules/ecs-cluster"

  project_name = var.project_name
  environment  = var.environment

  # Enable Container Insights for monitoring
  enable_container_insights = var.enable_container_insights
}

# ============================================================================
# ECS SERVICES (WEBSERVER, SCHEDULER, WORKER)
# ============================================================================

module "ecs_services" {
  source = "./modules/ecs-services"

  project_name = var.project_name
  environment  = var.environment

  # ECS cluster
  ecs_cluster_id   = module.ecs_cluster.cluster_id
  ecs_cluster_name = module.ecs_cluster.cluster_name

  # Network configuration
  vpc_id             = local.vpc_id
  private_subnet_ids = local.private_subnet_ids

  # Security groups
  ecs_tasks_security_group_id = module.security_groups.ecs_tasks_security_group_id

  # IAM roles
  ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  ecs_task_role_arn           = module.iam.ecs_task_role_arn

  # Database connection
  db_host     = module.rds.db_address
  db_port     = module.rds.db_port
  db_name     = module.rds.db_name
  db_username = var.airflow_db_username
  db_password = var.airflow_db_password

  # EFS configuration
  efs_file_system_id  = module.efs.file_system_id
  efs_logs_access_point_id    = module.efs.logs_access_point_id
  efs_plugins_access_point_id = module.efs.plugins_access_point_id

  # ALB target group
  webserver_target_group_arn = module.alb.webserver_target_group_arn

  # Docker image
  airflow_image = var.airflow_docker_image

  # Service configuration
  webserver_cpu    = var.webserver_cpu
  webserver_memory = var.webserver_memory
  scheduler_cpu    = var.scheduler_cpu
  scheduler_memory = var.scheduler_memory
  worker_cpu       = var.worker_cpu
  worker_memory    = var.worker_memory

  # Auto-scaling configuration
  worker_min_capacity = var.worker_min_capacity
  worker_max_capacity = var.worker_max_capacity

  # Fargate Spot
  enable_fargate_spot_for_workers = var.enable_fargate_spot

  # Airflow configuration
  airflow_executor = var.airflow_executor
  fernet_key       = var.airflow_fernet_key

  # AWS region for operators
  aws_region = var.aws_region
}

# ============================================================================
# S3 BUCKETS
# ============================================================================

module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  bucket_name  = "${var.project_name}-data-${var.environment}"
  environment  = var.environment

  # Lifecycle policies
  enable_lifecycle_rules         = true
  raw_data_expiration_days       = var.s3_raw_data_retention_days
  processed_data_transition_days = var.s3_processed_data_transition_days
}

# ============================================================================
# LAMBDA FUNCTION (STOCK EXTRACTOR)
# ============================================================================

module "lambda" {
  source = "./modules/lambda"

  project_name = var.project_name
  environment  = var.environment

  # Lambda configuration
  function_name = "${var.project_name}-stock-extractor"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  # Source code
  source_dir = "${path.root}/../lambda/stock_extractor"

  # IAM role
  lambda_role_arn = module.iam.lambda_execution_role_arn

  # S3 bucket - ADD THIS LINE!
  s3_bucket = module.s3.data_bucket_name

  # Environment variables
  environment_variables = {
    AWS_REGION       = var.aws_region
    S3_BUCKET        = module.s3.data_bucket_name
    API_SECRET_NAME  = "nasdaq-pipeline/stock-api-key"
    API_PROVIDER     = "fmp"
    USE_MOCK_DATA    = "false"
    RATE_LIMIT_DELAY = "1"
  }

  # VPC configuration (optional)
  vpc_config = var.lambda_vpc_enabled ? {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [module.security_groups.lambda_security_group_id]
  } : null
}

# ============================================================================
# AWS GLUE JOBS
# ============================================================================

module "glue" {
  source = "./modules/glue"

  project_name = var.project_name
  environment  = var.environment

  # S3 bucket
  s3_bucket = module.s3.bucket_name

  # Glue configuration
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.glue_number_of_workers

  # IAM role
  glue_role_arn = module.iam.glue_execution_role_arn

  # Script locations
  scripts_bucket = module.s3.scripts_bucket_name

  # Database
  database_name = var.glue_database_name

  # Job definitions
  jobs = {
    dimensions = {
      name        = "${var.project_name}-dimensions"
      script_path = "glue/jobs/build_stock_dimensions.py"
      timeout     = 60
    }
    fact = {
      name        = "${var.project_name}-fact"
      script_path = "glue/jobs/build_stock_fact_table.py"
      timeout     = 60
    }
    aggregations = {
      name        = "${var.project_name}-aggregations"
      script_path = "glue/jobs/build_stock_aggregations.py"
      timeout     = 60
    }
  }
}

# ============================================================================
# CLOUDWATCH MONITORING
# ============================================================================

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ecs_tasks" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "${var.project_name}-ecs-logs"
  }
}

# CloudWatch Alarms for auto-scaling
resource "aws_cloudwatch_metric_alarm" "worker_cpu_high" {
  count = var.airflow_executor == "CeleryExecutor" && var.enable_worker_autoscaling ? 1 : 0

  alarm_name          = "${var.project_name}-worker-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    ClusterName = module.ecs_cluster.cluster_name
    ServiceName = module.ecs_services.worker_service_name
  }

  alarm_description = "Worker CPU utilization is too high"
  alarm_actions     = [module.ecs_services.worker_scale_up_policy_arn]
}

resource "aws_cloudwatch_metric_alarm" "worker_cpu_low" {
  count = var.airflow_executor == "CeleryExecutor" && var.enable_worker_autoscaling ? 1 : 0

  alarm_name          = "${var.project_name}-worker-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 20

  dimensions = {
    ClusterName = module.ecs_cluster.cluster_name
    ServiceName = module.ecs_services.worker_service_name
  }

  alarm_description = "Worker CPU utilization is too low"
  alarm_actions     = [module.ecs_services.worker_scale_down_policy_arn]
}

# ============================================================================
# ECR REPOSITORY
# ============================================================================

module "ecr" {
  source = "./modules/ecr"

  repository_name      = "nasdaq-airflow"
  environment          = var.environment
  project_name         = var.project_name
  image_tag_mutability = "MUTABLE"
  scan_on_push         = true
  max_image_count      = 10
}
