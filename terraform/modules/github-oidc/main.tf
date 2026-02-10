# GitHub OIDC Provider for AWS Authentication
# This allows GitHub Actions to assume an AWS IAM role without storing credentials

# OIDC Provider - Trust GitHub's identity service
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
  
  client_id_list = [
    "sts.amazonaws.com"
  ]
  
  # GitHub's thumbprint (this is constant and doesn't change)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
  
  tags = {
    Name        = "GitHub Actions OIDC Provider"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  
  tags = {
    Name        = "GitHub Actions Role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Trust policy - Who can assume this role
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    # Verify it's GitHub
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    
    # Restrict to specific repo and branch
    # Format: repo:ORG/REPO:ref:refs/heads/BRANCH
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
      ]
    }
  }
}

# Permissions Policy - What this role can do
data "aws_iam_policy_document" "github_actions_permissions" {
  # ECR - Push/Pull Docker images
  statement {
    sid    = "ECRAccess"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    resources = ["*"]
  }
  
  # ECS - Update services
  statement {
    sid    = "ECSAccess"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "ecs:ExecuteCommand"
    ]
    resources = ["*"]
  }
  
  # S3 - Terraform state
  statement {
    sid    = "S3TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::*-terraform-state",
      "arn:aws:s3:::*-terraform-state/*"
    ]
  }
  
  # DynamoDB - Terraform state lock
  statement {
    sid    = "DynamoDBTerraformLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = ["arn:aws:dynamodb:*:*:table/*-terraform-lock"]
  }
  
  # CloudWatch Logs - View logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
  
  # SNS - Send notifications
  statement {
    sid    = "SNSPublish"
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = ["*"]
  }
  
  # EFS - For DAG uploads
  statement {
    sid    = "EFSAccess"
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:DescribeFileSystems"
    ]
    resources = ["*"]
  }
}

# Attach the permissions policy
resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project_name}-github-actions-policy-${var.environment}"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}