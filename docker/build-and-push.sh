#!/bin/bash

set -e

# Configuration
AWS_REGION="ap-southeast-1"
ECR_REPO_NAME="nasdaq-airflow"

echo "Getting ECR repository URL..."
ECR_REPO=$(aws ecr describe-repositories \
  --repository-names $ECR_REPO_NAME \
  --region $AWS_REGION \
  --query 'repositories[0].repositoryUri' \
  --output text)

if [ -z "$ECR_REPO" ]; then
    echo "Error: ECR repository not found"
    exit 1
fi

echo "ECR Repository: $ECR_REPO"

echo ""
echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REPO

echo ""
echo "Building Docker image..."
docker build -t nasdaq-airflow-ecs:latest -f Dockerfile .

echo ""
echo "Tagging image..."
VERSION="v$(date +%Y%m%d-%H%M%S)-with-gx"
docker tag nasdaq-airflow-ecs:latest $ECR_REPO:latest
docker tag nasdaq-airflow-ecs:latest $ECR_REPO:$VERSION

echo ""
echo "Pushing to ECR..."
docker push $ECR_REPO:latest
docker push $ECR_REPO:$VERSION

echo ""
echo "Image pushed successfully!"
echo "Latest: $ECR_REPO:latest"
echo "Version: $ECR_REPO:$VERSION"
echo ""
echo "Next steps:"
echo "1. Update terraform/modules/ecs-services/variables.tf with image tag: $VERSION"
echo "2. Run 'terraform plan' to review changes"
echo "3. Run 'terraform apply' to deploy the updated image"










### ####################################

# #!/bin/bash

# set -e

# # Configuration
# AWS_REGION="ap-southeast-1"
# ECR_REPO_NAME="nasdaq-airflow"

# echo "🔍 Getting ECR repository URL..."
# ECR_REPO=$(aws ecr describe-repositories \
#   --repository-names $ECR_REPO_NAME \
#   --region $AWS_REGION \
#   --query 'repositories[0].repositoryUri' \
#   --output text)

# if [ -z "$ECR_REPO" ]; then
#     echo "❌ Error: ECR repository not found"
#     exit 1
# fi

# echo "✅ ECR Repository: $ECR_REPO"

# echo ""
# echo "🔐 Logging into ECR..."
# aws ecr get-login-password --region $AWS_REGION | \
#   docker login --username AWS --password-stdin $ECR_REPO

# echo ""
# echo "🐳 Building Docker image..."
# docker build -t nasdaq-airflow-ecs:latest .

# echo ""
# echo "🏷️  Tagging image..."
# VERSION="v$(date +%Y%m%d-%H%M%S)"
# docker tag nasdaq-airflow-ecs:latest $ECR_REPO:latest
# docker tag nasdaq-airflow-ecs:latest $ECR_REPO:$VERSION

# echo ""
# echo "📤 Pushing to ECR..."
# docker push $ECR_REPO:latest
# docker push $ECR_REPO:$VERSION

# echo ""
# echo "✅ Image pushed successfully!"
# echo "   Latest: $ECR_REPO:latest"
# echo "   Version: $ECR_REPO:$VERSION"