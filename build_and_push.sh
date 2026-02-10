#!/bin/bash
# Build and push Docker image with descriptive timestamp tag
# Usage: ./build_and_push.sh [description]
# Example: ./build_and_push.sh "gx-integrated-pipeline"

set -e  # Exit on error

# Configuration
REGION="ap-southeast-1"
REPO_NAME="nasdaq-airflow"
DEFAULT_DESCRIPTION="gx-integrated-pipeline"

# Get description from argument or use default
DESCRIPTION="${1:-$DEFAULT_DESCRIPTION}"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Build version tag
VERSION_TAG="v${TIMESTAMP}-${DESCRIPTION}"

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

echo "=========================================="
echo "Building and Pushing Airflow Docker Image"
echo "=========================================="
echo "Repository: ${REPO_NAME}"
echo "Version Tag: ${VERSION_TAG}"
echo "Description: ${DESCRIPTION}"
echo "Timestamp: ${TIMESTAMP}"
echo "Full URI: ${REPO_URI}:${VERSION_TAG}"
echo ""

# Confirm before proceeding
read -p "Continue with this build? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 1
fi

echo ""
echo "=========================================="
echo "Step 1: Building Docker Image"
echo "=========================================="
cd ~/Documents/dev/data_engineering_projects/AWS/nasdaq-airflow-ecs-pipeline/docker

docker build -t nasdaq-airflow:${VERSION_TAG} -t nasdaq-airflow:latest .

if [ $? -eq 0 ]; then
  echo "Docker image built successfully"
else
  echo "Docker build failed"
  exit 1
fi

echo ""
echo "=========================================="
echo "Step 2: Tagging for ECR"
echo "=========================================="
# Tag with version
docker tag nasdaq-airflow:${VERSION_TAG} ${REPO_URI}:${VERSION_TAG}
# Also tag as latest
docker tag nasdaq-airflow:${VERSION_TAG} ${REPO_URI}:latest

echo "Tagged:"
echo "   - ${REPO_URI}:${VERSION_TAG}"
echo "   - ${REPO_URI}:latest"

echo ""
echo "=========================================="
echo "Step 3: Login to ECR"
echo "=========================================="
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

if [ $? -eq 0 ]; then
  echo "Logged in to ECR"
else
  echo "ECR login failed"
  exit 1
fi

echo ""
echo "=========================================="
echo "Step 4: Pushing Images to ECR"
echo "=========================================="
echo "Pushing version tag..."
docker push ${REPO_URI}:${VERSION_TAG}

echo ""
echo "Pushing latest tag..."
docker push ${REPO_URI}:latest

if [ $? -eq 0 ]; then
  echo ""
  echo "=========================================="
  echo "SUCCESS! Images pushed to ECR"
  echo "=========================================="
  echo ""
  echo "Available tags in ECR:"
  echo "  1. ${VERSION_TAG} (immutable, recommended for production)"
  echo "  2. latest (mutable, for development)"
  echo ""
  echo "Next Steps:"
  echo "=========================================="
  echo ""
  echo " Update Terraform to use versioned tag:"
  echo "  1. Edit terraform/terraform.tfvars"
  echo "  2. Set: airflow_image_tag = \"${VERSION_TAG}\""
  echo "  3. Run: cd terraform && terraform plan"
  echo "  4. terraform apply"
  echo ""
  echo "Force deployment with current config (latest tag):"
  echo "  for service in scheduler webserver worker; do"
  echo "    aws ecs update-service \\"
  echo "      --cluster nasdaq-airflow-ecs-cluster \\"
  echo "      --service nasdaq-airflow-ecs-\${service} \\"
  echo "      --force-new-deployment \\"
  echo "      --region ap-southeast-1"
  echo "  done"
  echo ""

  echo "  - Updating scheduler service..."
  echo " aws ecs update-service \\"
  echo "   --cluster $CLUSTER_NAME \\"
  echo "  --service nasdaq-airflow-ecs-scheduler \\"
  echo "  --force-new-deployment \\"
  echo "  --region $AWS_REGION \\"
  echo "  --no-cli-pager > /dev/null"

  echo "  - Updating webserver service..."
  echo " aws ecs update-service \\"
  echo "   --cluster $CLUSTER_NAME \\"
  echo "   --service nasdaq-airflow-ecs-webserver \\"
  echo "   --force-new-deployment \\"
  echo "   --region $AWS_REGION \\"
  echo "   --no-cli-pager > /dev/null"

  echo "=========================================="
  echo "For Your Records:"
  echo "=========================================="
  echo "Version: ${VERSION_TAG}"
  echo "Built: $(date)"
  echo "Image URI: ${REPO_URI}:${VERSION_TAG}"
  echo ""
  
  # Save to version file
  VERSION_FILE="~/Documents/dev/data_engineering_projects/AWS/nasdaq-airflow-ecs-pipeline/VERSIONS.txt"
  echo "$(date +%Y-%m-%d\ %H:%M:%S) - ${VERSION_TAG} - ${DESCRIPTION}" >> ${VERSION_FILE}
  echo "Version logged to: ${VERSION_FILE}"
  
else
  echo "Failed to push images"
  exit 1
fi