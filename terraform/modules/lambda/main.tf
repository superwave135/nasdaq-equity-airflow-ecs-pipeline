# terraform/modules/lambda/main.tf
# Lambda Function for Stock Data Extraction

# Get current AWS account ID
data "aws_caller_identity" "current" {}


# ============================================================================
# LAMBDA FUNCTION
# ============================================================================

resource "aws_lambda_function" "stock_extractor" {
  function_name = "nasdaq-airflow-stock-extractor-${var.environment}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  
  # Code deployment - Using placeholder zip for now
  # NOTE: You need to create lambda_deployment_package.zip containing your Lambda code
  # Or use S3 deployment (see commented section below)
  filename         = "${path.root}/lambda_deployment_package.zip"
  source_code_hash = filebase64sha256("${path.root}/lambda_deployment_package.zip")
  
  # Alternative: S3 deployment (uncomment if using S3)
  # s3_bucket = var.s3_bucket
  # s3_key    = "lambda-code/stock_extractor.zip"
  # s3_object_version = var.lambda_code_version  # Optional: for versioning
  
  timeout     = 300  # 5 minutes
  memory_size = 512  # 512 MB
  
  environment {
    variables = {
    ENVIRONMENT  = var.environment
    S3_BUCKET    = var.s3_bucket
    SNS_TOPIC    = var.sns_topic_arn
    }
  }
  
  tags = {
    Name        = "stock_extractor_${var.environment}"
    Environment = var.environment
    Purpose     = "Extract stock data from financial APIs"
  }
}

# ============================================================================
# IAM ROLE FOR LAMBDA
# ============================================================================

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
  
  tags = {
    Name        = "stock_extractor_role_${var.environment}"
    Environment = var.environment
  }
}

# ============================================================================
# IAM POLICIES
# ============================================================================

# Basic execution policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 access policy
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda_s3_access_${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket}",
          "arn:aws:s3:::${var.s3_bucket}/*"
        ]
      }
    ]
  })
}

# Secrets Manager access policy (for API keys)
resource "aws_iam_role_policy" "lambda_secrets_policy" {
  name = "lambda_secrets_access_${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:nasdaq-pipeline/*"
        ]
      }
    ]
  })
}

# SNS publish policy (for notifications)
resource "aws_iam_role_policy" "lambda_sns_policy" {
  name = "lambda_sns_publish_${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "sns:Publish",
          "sns:ListTopics"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# OUTPUTS - CRITICAL!
# ============================================================================

output "function_name" {
  value       = aws_lambda_function.stock_extractor.function_name
  description = "Lambda function name"
}

output "function_arn" {
  value       = aws_lambda_function.stock_extractor.arn
  description = "Lambda function ARN"
}

output "function_invoke_arn" {
  value       = aws_lambda_function.stock_extractor.invoke_arn
  description = "Lambda function invoke ARN"
}

output "role_arn" {
  value       = aws_iam_role.lambda_role.arn
  description = "Lambda IAM role ARN"
}
