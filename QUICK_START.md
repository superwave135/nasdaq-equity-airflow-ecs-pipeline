# Quick Start — NASDAQ Stock Pipeline on ECS Fargate

Deploy the full pipeline from scratch in approximately 2 hours.

---

## Prerequisites

```bash
aws --version       # AWS CLI 2.x
terraform --version # >= 1.5.0
docker --version    # >= 20.x
python3 --version   # >= 3.11
```

You also need an AWS account with programmatic access configured (`aws configure`).

---

## Step 1 — Generate Required Secrets (5 min)

Before editing any configuration, generate the three secret values you will need.

### Database credentials

Choose a username and a strong password for the Airflow RDS database. These are values you create — there is no default you should reuse.

```bash
# Example — use your own values
AIRFLOW_DB_USERNAME="airflow_admin"
AIRFLOW_DB_PASSWORD="$(openssl rand -base64 24)"
echo "Username: $AIRFLOW_DB_USERNAME"
echo "Password: $AIRFLOW_DB_PASSWORD"
```

Keep these values — you will add them to `terraform.tfvars` in Step 3.

### Fernet key

Airflow uses a Fernet key to encrypt sensitive data (connection passwords, Variables) stored in its metadata database. Generate one with:

```bash
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Example output (yours will differ):

```
xK3mP9qR2vL8nW5jY7uH4bC1tA6eD0sF=
```

> ⚠️ Store this value securely. If you lose it, Airflow cannot decrypt existing connection passwords. Never commit it to version control.

---

## Step 2 — Build and Push Docker Image (15 min)

```bash
# From the project root
./build_and_push.sh "<descriptive-tag>"

# Example
./build_and_push.sh "initial-deployment"
```

The script will output the full ECR image URI — copy it for use in Step 3.

To test the image locally before pushing:

```bash
# Build locally
docker build -t nasdaq-airflow:local docker/

# Verify DAGs and scripts are present
docker run --rm nasdaq-airflow:local ls /opt/airflow/dags
docker run --rm nasdaq-airflow:local ls /opt/airflow/scripts
```

---

## Step 3 — Configure terraform.tfvars (10 min)

```bash
cd terraform
```

Create `terraform.tfvars` (this file is gitignored and must never be committed):

```hcl
# terraform/terraform.tfvars

# General
project_name = "nasdaq-airflow-ecs"
environment  = "dev"
aws_region   = "ap-southeast-1"

# Docker image — use the ECR URI from Step 2
airflow_docker_image = "<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/nasdaq-airflow:<tag>"

# Database credentials — values you created in Step 1
airflow_db_username = "<your-db-username>"
airflow_db_password = "<your-db-password>"

# Fernet key — generated in Step 1
airflow_fernet_key = "<your-fernet-key>"

# ECS sizing
webserver_cpu    = 1024
webserver_memory = 2048
scheduler_cpu    = 1024
scheduler_memory = 2048

# Stock API
fmp_api_key_secret_name = "nasdaq-airflow-ecs-fmp-api-key"
```

> **Why these three secrets?**
> - `airflow_db_username` / `airflow_db_password`: Terraform creates the RDS instance with these credentials. The Airflow connection string is assembled from these variables so nothing is hardcoded.
> - `airflow_fernet_key`: Injected into ECS tasks as `AIRFLOW__CORE__FERNET_KEY`. Required for Airflow to start.

---

## Step 4 — Deploy Infrastructure (20 min)

```bash
cd terraform

# Initialise (downloads providers, sets up local state)
terraform init

# Preview what will be created
terraform plan

# Deploy (~15–20 minutes on first run)
terraform apply
```

Resources created: ECS cluster, RDS PostgreSQL, EFS, ALB, Lambda, Glue jobs, S3 buckets, IAM roles, security groups, CloudWatch log groups.

After apply completes, get the Airflow UI URL:

```bash
terraform output alb_dns_name
```

---

## Step 5 — Initialise the Airflow Database (5 min)

This only needs to be done once, before the scheduler and webserver start.

```bash
# Run db-init as a one-shot ECS task
aws ecs run-task \
  --cluster nasdaq-airflow-ecs-cluster \
  --task-definition nasdaq-airflow-ecs-db-init \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<private-subnet-id>],securityGroups=[<ecs-sg-id>],assignPublicIp=DISABLED}" \
  --region ap-southeast-1
```

Subnet and security group IDs are available in `terraform output`.

Wait for the task to reach `STOPPED` status before proceeding:

```bash
# Monitor task status
aws ecs list-tasks --cluster nasdaq-airflow-ecs-cluster --region ap-southeast-1
```

---

## Step 6 — Start Airflow Services (5 min)

```bash
# Start webserver
aws ecs update-service \
  --cluster nasdaq-airflow-ecs-cluster \
  --service nasdaq-airflow-ecs-webserver \
  --desired-count 1 \
  --region ap-southeast-1

# Start scheduler
aws ecs update-service \
  --cluster nasdaq-airflow-ecs-cluster \
  --service nasdaq-airflow-ecs-scheduler \
  --desired-count 1 \
  --region ap-southeast-1
```

Allow 2–3 minutes for tasks to reach `RUNNING` state:

```bash
watch -n 10 "aws ecs describe-services \
  --cluster nasdaq-airflow-ecs-cluster \
  --services nasdaq-airflow-ecs-webserver nasdaq-airflow-ecs-scheduler \
  --region ap-southeast-1 \
  --query 'services[*].[serviceName,deployments[0].rolloutState,runningCount]' \
  --output table"
```

---

## Step 7 — Access Airflow UI and Trigger the DAG (10 min)

Open `http://<alb_dns_name>` in your browser. Default credentials are `admin` / `admin` — change the password immediately.

In the DAG list, locate `nasdaq_stock_pipeline_with_gx` and:

1. Toggle the DAG on (unpause)
2. Click **Trigger DAG** to run manually
3. Monitor task progress in the **Graph** view

Expected run time: 15–20 minutes end-to-end.

---

## Step 8 — Verify Results (5 min)

```bash
# Raw extracted data
aws s3 ls s3://nasdaq-airflow-ecs-data-dev/raw/stock_quotes/ --recursive | tail -20

# Iceberg warehouse tables
aws s3 ls s3://nasdaq-airflow-ecs-data-dev/warehouse/ --recursive | head -30

# Query via Athena
aws athena start-query-execution \
  --query-string "SELECT symbol, trade_date, close_price FROM nasdaq_airflow_warehouse_dev.fact_stock_daily_price ORDER BY trade_date DESC LIMIT 10" \
  --result-configuration "OutputLocation=s3://nasdaq-airflow-ecs-data-dev/athena-results/" \
  --region ap-southeast-1
```

---

## Upload Glue Scripts (if not automated by Terraform)

```bash
aws s3 cp glue/jobs/ s3://nasdaq-airflow-ecs-scripts-dev/glue-scripts/ --recursive
```

---

## Troubleshooting

### DAG not appearing in UI

```bash
# Check DAG file is present in the running container
aws ecs execute-command \
  --cluster nasdaq-airflow-ecs-cluster \
  --task <webserver-task-id> \
  --container airflow-webserver \
  --interactive \
  --command "ls /opt/airflow/dags"

# Check CloudWatch logs for import errors
aws logs tail /ecs/nasdaq-airflow-ecs/webserver --follow
```

### Database connection failed

Verify the connection string is assembled correctly from your `terraform.tfvars` values. The format should be:

```
postgresql+psycopg2://<username>:<password>@<rds-endpoint>:5432/airflow?sslmode=require
```

The `?sslmode=require` suffix is mandatory — RDS enforces TLS.

### ECS task keeps restarting

```bash
# Check CloudWatch logs for the failing task
aws logs tail /ecs/nasdaq-airflow-ecs/scheduler --follow
```

Common causes: insufficient memory (increase to 2048 MB), missing Fernet key, or wrong DB credentials.

---

## Cost Optimisation

To stop all services when not in use:

```bash
aws ecs update-service --cluster nasdaq-airflow-ecs-cluster --service nasdaq-airflow-ecs-webserver --desired-count 0 --region ap-southeast-1
aws ecs update-service --cluster nasdaq-airflow-ecs-cluster --service nasdaq-airflow-ecs-scheduler --desired-count 0 --region ap-southeast-1
```

Consider using AWS Scheduler to automate start/stop around your daily pipeline window.

---

## Checklist

- [ ] Docker image built and pushed to ECR
- [ ] `terraform.tfvars` created with all three secrets
- [ ] `terraform apply` completed successfully
- [ ] `airflow db migrate` run via db-init task
- [ ] Webserver and scheduler services running
- [ ] Airflow UI accessible
- [ ] Admin password changed
- [ ] DAG triggered successfully
- [ ] S3 output data verified

---

*Last updated: February 2026*
