######### AIRFLOW UI URL #########
http://nasdaq-airflow-ecs-alb-dev-xxxxxxxxxx.ap-southeast-1.elb.amazonaws.com/
##################################

# 0. Package and deploy Lambda
cd lambda/stock_extractor
zip -r ../../terraform/lambda_deployment_package.zip . -x "*.pyc" -x "__pycache__/*"
cd ../../terraform
terraform apply -auto-approve

###############################################################

# 1. Navigate to the project root directory
cd ~/Documents/dev/data_engineering_projects/AWS/nasdaq-airflow-ecs-pipeline/

# Build new image w Dockerfile in the docker folder (specify Dockerfile location with -f flag) 
# Build from docker/ directory (this sets the build context correctly)
docker build -t nasdaq-airflow-ecs:v$(date +%Y%m%d-%H%M%S) docker/

# 3. Get the latest tag
LATEST_TAG=$(docker images nasdaq-airflow-ecs --format "{{.Tag}}" | grep -v latest | head -1)
echo "Latest tag: $LATEST_TAG"

# 4. Define ECR repository
ECR_REPO="XXXXXXXXXXXX.dkr.ecr.ap-southeast-1.amazonaws.com/nasdaq-airflow"

# 5. Tag the image for ECR
docker tag nasdaq-airflow-ecs:$LATEST_TAG $ECR_REPO:$LATEST_TAG
docker tag nasdaq-airflow-ecs:$LATEST_TAG $ECR_REPO:latest

# Re-authenticate to ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin \
  XXXXXXXXXXXX.dkr.ecr.ap-southeast-1.amazonaws.com

# Push to ECR
docker push $ECR_REPO:$LATEST_TAG
docker push $ECR_REPO:latest

echo "Image pushed: $ECR_REPO:$LATEST_TAG"

# Update ECS services
aws ecs update-service \
  --cluster nasdaq-airflow-ecs-cluster \
  --service nasdaq-airflow-ecs-scheduler \
  --force-new-deployment \
  --region ap-southeast-1

aws ecs update-service \
  --cluster nasdaq-airflow-ecs-cluster \
  --service nasdaq-airflow-ecs-webserver \
  --force-new-deployment \
  --region ap-southeast-1

#################################################################
# Verification:
# After running, you can verify the build worked correctly:

# Check that the image was built
docker images nasdaq-airflow-ecs

# Inspect the image to see copied files
docker run --rm nasdaq-airflow-ecs:$LATEST_TAG ls -la /opt/airflow/dags
docker run --rm nasdaq-airflow-ecs:$LATEST_TAG ls -la /opt/airflow/glue/jobs

#################################################################
# Monitor deployment
watch -n 5 "aws ecs describe-services \
  --cluster nasdaq-airflow-ecs-cluster \
  --services nasdaq-airflow-ecs-scheduler nasdaq-airflow-ecs-webserver \
  --region ap-southeast-1 \
  --query 'services[*].[serviceName,deployments[0].rolloutState,runningCount,desiredCount]' \
  --output table"


## Key Changes Made:

1. **requirements.txt**: `docker/requirements.txt` → `requirements.txt` (relative to Dockerfile location)
2. **dags/**: `docker/dags/` → `../dags/` (go up one level from docker/ folder)
3. **glue/jobs/**: `glue/jobs/` → `../glue/jobs/` (go up one level from docker/ folder)
4. **airflow.cfg**: `docker/airflow.cfg` → `airflow.cfg` (relative to Dockerfile location)

## Expected Directory Structure:
```
nasdaq-airflow-ecs-pipeline/
├── docker/
│   ├── Dockerfile          ← Your Dockerfile here
│   ├── requirements.txt    ← Must be here
│   └── airflow.cfg        ← Must be here
├── dags/                   ← Referenced as ../dags/ in Dockerfile
│   └── stock_data_pipeline.py
├── glue/
│   └── jobs/              ← Referenced as ../glue/jobs/ in Dockerfile
│       ├── build_fact_table.py
│       └── build_dimensions.py
└── terraform/

############################################################################################
################# Docker deploy with GX integration into the main pipeline #################
############################################################################################

Step 1: Build & Push New Image

    cd ~/Documents/dev/data_engineering_projects/AWS/nasdaq-airflow-ecs-pipeline

    # Build with descriptive tag
    ./build_and_push.sh "gx-main-pipeline-integrated"
    ```

    **Output will be something like:**
    ```
    Version Tag: v20260205-152030-schema-fixed-gx-pipeline
    Full URI: XXXXXXXXXXXX.dkr.ecr.ap-southeast-1.amazonaws.com/nasdaq-airflow:v20260205-152030-schema-fixed-gx-pipeline

Step 2: Update Terraform

    cd terraform

    # Edit terraform.tfvars
    nano terraform.tfvars

    # Update the FULL IMAGE URI (not just the tag):
    airflow_docker_image = "XXXXXXXXXXXX.dkr.ecr.ap-southeast-1.amazonaws.com/nasdaq-airflow:v20260205-152030-schema-fixed-gx-pipeline"

    # Save and apply
    terraform apply

Step 3: (if no terraform apply)
    geekytan@geeky:~/Documents/dev/data_engineering_projects/AWS/nasdaq-airflow-ecs-pipeline$
    ./deploy_versioned_image.sh

#######################################################
# To verify that nasdaq-airflow-ecs-scheduler and nasdaq-airflow-ecs-webserver come from image 
# v20260206-171057-gx-main-pipeline-integrated, latest

# Get running tasks
WEBSERVER_TASKS=$(aws ecs list-tasks \
  --cluster nasdaq-airflow-ecs-cluster \
  --service-name nasdaq-airflow-ecs-webserver \
  --region ap-southeast-1 \
  --query 'taskArns[0]' \
  --output text)

SCHEDULER_TASKS=$(aws ecs list-tasks \
  --cluster nasdaq-airflow-ecs-cluster \
  --service-name nasdaq-airflow-ecs-scheduler \
  --region ap-southeast-1 \
  --query 'taskArns[0]' \
  --output text)

# Check webserver image
echo "=========================================="
echo "WEBSERVER TASK IMAGE:"
echo "=========================================="
aws ecs describe-tasks \
  --cluster nasdaq-airflow-ecs-cluster \
  --tasks $WEBSERVER_TASKS \
  --region ap-southeast-1 \
  --query 'tasks[0].containers[0].[name,image]' \
  --output table

# Check scheduler image
echo ""
echo "=========================================="
echo "SCHEDULER TASK IMAGE:"
echo "=========================================="
aws ecs describe-tasks \
  --cluster nasdaq-airflow-ecs-cluster \
  --tasks $SCHEDULER_TASKS \
  --region ap-southeast-1 \
  --query 'tasks[0].containers[0].[name,image]' \
  --output table
```

**You should see:**
```
| airflow-webserver  | XXXXXXXXXXXX.dkr.ecr.ap-southeast-1.amazonaws.com/nasdaq-airflow:v20260206-171057-gx-main-pipeline-integrated |

| airflow-scheduler  | XXXXXXXXXXXX.dkr.ecr.ap-southeast-1.amazonaws.com/nasdaq-airflow:v20260206-171057-gx-main-pipeline-integrated |