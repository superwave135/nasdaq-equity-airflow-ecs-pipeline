# Project Structure Reference

This document describes every file and directory in the repository.

---

## Repository Layout

```
nasdaq-equity-airflow-ecs-pipeline/
│
├── README.md                              # Project overview
├── QUICK_START.md                         # Step-by-step deployment guide
├── IMPLEMENTATION_SUMMARY.md             # Architecture and design decisions
├── AIRFLOW_PIPELINE_SUCCESS_SUMMARY.md   # Operational runbook and resolved issues
├── PROJECT_STRUCTURE.md                  # This file
│
├── backend.tf                            # Terraform provider and backend config
├── build_and_push.sh                     # Build Docker image and push to ECR
│
├── config/
│   ├── dev.yaml                          # Dev environment settings (region, S3, DB name)
│   └── symbols.yaml                      # Stock symbols processed by the pipeline
│
├── docker/                               # Everything baked into the Airflow Docker image
│   ├── Dockerfile                        # Image definition (apache/airflow:2.8.1 base)
│   ├── requirements.txt                  # Python packages (great-expectations, AWS providers)
│   ├── airflow.cfg                       # Airflow runtime configuration
│   ├── build-and-push.sh                 # Helper script for building and pushing
│   │
│   ├── dags/
│   │   ├── nasdaq_stock_pipeline.py              # Core pipeline (no GX) — reference only
│   │   ├── nasdaq_stock_pipeline_with_gx.py      # Active DAG with GX validation
│   │   └── test_gx_production.py                 # One-off GX connectivity test DAG
│   │
│   ├── great_expectations/
│   │   ├── great_expectations.yml                # GX datasource and store config
│   │   ├── gx-config-check.yml                   # Config validation helper
│   │   └── checkpoints/
│   │       ├── daily_fact_validation.yml
│   │       ├── dim_stock_validation.yml
│   │       ├── monthly_agg_validation.yml
│   │       └── weekly_agg_validation.yml
│   │
│   └── scripts/
│       ├── create_expectations.py                # Auto-generates expectation suites on first run
│       └── test_gx_setup.py                      # Validates GX/Athena connectivity locally
│
├── glue/jobs/
│   ├── build_stock_dimensions.py         # Builds dim_stock Iceberg table
│   ├── build_stock_fact_table.py         # Builds fact_stock_daily_price Iceberg table
│   └── build_stock_aggregations.py       # Builds weekly and monthly aggregate tables
│
├── lambda/stock_extractor/
│   └── (deployment package contents)    # Lambda zip is built from this directory
│       # Key source files (not shown — in terraform/lambda_deployment_package.zip):
│       #   lambda_function.py            # Handler: calls FMP API, writes raw JSON to S3
│       #   config.py                     # Lambda configuration constants
│       #   requirements.txt              # Lambda dependencies
│
└── terraform/                           # Infrastructure-as-Code (managed separately)
    ├── main.tf                          # Root module — wires all sub-modules
    ├── variables.tf                     # All input variable declarations
    ├── outputs.tf                       # Exported values (ALB DNS, RDS endpoint, etc.)
    ├── terraform.tfvars                 # ⚠️ GITIGNORED — your actual values go here
    ├── backend.tf                       # State backend configuration
    │
    └── modules/
        ├── alb/                         # Application Load Balancer for Airflow UI
        ├── ecr/                         # ECR repository for Docker images
        ├── ecs-cluster/                 # ECS Fargate cluster
        ├── ecs-services/                # Scheduler, webserver ECS services
        ├── efs/                         # EFS for shared DAGs and logs
        ├── glue/                        # Glue job definitions and IAM
        ├── iam/                         # IAM roles and policies
        ├── lambda/                      # Lambda function deployment
        ├── rds/                         # RDS PostgreSQL (Airflow metadata DB)
        ├── s3/                          # S3 buckets (data lake + scripts)
        └── security-groups/             # VPC security group rules
```

---

## Active vs Reference Files

| File | Status | Notes |
|------|--------|-------|
| `docker/dags/nasdaq_stock_pipeline_with_gx.py` | **Active** | Primary DAG deployed in production |
| `docker/dags/nasdaq_stock_pipeline.py` | Reference | GX-free version kept for comparison |
| `docker/dags/test_gx_production.py` | Utility | Run once to verify GX/Athena connectivity |
| `docker/scripts/create_expectations.py` | Active | Called automatically on first GX run |
| `docker/scripts/test_gx_setup.py` | Utility | Local debugging helper |

---

## Configuration Files

### `config/dev.yaml`
Environment-level settings used by Glue jobs and the DAG at runtime. Override with environment-specific files for staging or production.

### `config/symbols.yaml`
List of stock symbols processed by the pipeline. Add or remove symbols here to change pipeline scope — no code changes needed.

### `docker/airflow.cfg`
Minimal Airflow configuration baked into the Docker image. Sensitive settings (Fernet key, DB connection string) are injected as environment variables via Terraform/ECS task definitions — never stored in this file.

### `docker/great_expectations/great_expectations.yml`
GX datasource and store configuration. The active version uses local filesystem stores (embedded in the Docker image). The file also contains commented-out S3-backed configuration ready for production use.

---

## Secrets and Sensitive Data

All secrets are managed through `terraform/terraform.tfvars` (gitignored) and injected into ECS tasks at runtime. No secrets should ever appear in committed files.

**Files that must remain gitignored:**

```
terraform/terraform.tfvars
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/.terraform/
```

See `QUICK_START.md` for instructions on generating and storing the required secrets.

---

## Lambda Deployment Package

The `lambda/stock_extractor/` directory serves as the source for the Lambda deployment zip. The actual `lambda_function.py` and its dependencies are packaged via:

```bash
cd lambda/stock_extractor
pip install -r requirements.txt -t .
zip -r ../../terraform/lambda_deployment_package.zip . -x "*.pyc" -x "__pycache__/*"
```

> **Note on `six.py`:** This file is a transitive dependency of `python-dateutil`, which is required by `botocore`. It is included automatically when running `pip install -r requirements.txt -t .` and does not need to be managed manually.

---

*Last updated: February 2026*
