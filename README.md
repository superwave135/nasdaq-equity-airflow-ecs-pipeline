# NASDAQ Stock Pipeline — Airflow on ECS Fargate

[![AWS](https://img.shields.io/badge/AWS-Cloud-orange?logo=amazon-aws)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-purple?logo=terraform)](https://www.terraform.io/)
[![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python)](https://www.python.org/)
[![Apache Airflow](https://img.shields.io/badge/Apache%20Airflow-2.8-017CEE?logo=apache-airflow)](https://airflow.apache.org/)
[![Apache Iceberg](https://img.shields.io/badge/Apache%20Iceberg-table%20format-00ADD8?logo=apache)](https://iceberg.apache.org/)
[![Great Expectations](https://img.shields.io/badge/Great%20Expectations-data%20quality-FF6B35)](https://greatexpectations.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A production-ready daily data pipeline that extracts stock quotes for NASDAQ-listed symbols, transforms them into a star schema using Apache Iceberg, and makes them queryable via Athena. Orchestrated by Apache Airflow on AWS ECS Fargate with data quality validation via Great Expectations.

**Current scope:** 5 symbols (AAPL, MSFT, GOOGL, AMZN, NVDA) | **Scalable to:** 100+ symbols

---

## Architecture

```
Airflow Scheduler (cron: 0 2 * * * — daily 2 AM UTC / 10 AM SGT)
        │
        ▼
  Airflow DAG (ECS Fargate — LocalExecutor)
  ┌──────────────────────────────────────────────┐
  │  1. Extract     Lambda → FMP API → S3 (raw)  │
  │  2. Validate    Great Expectations (raw)     │
  │  3. Transform   Glue: dim_stock              │
  │  4. Transform   Glue: fact_daily_price       │
  │  5. Transform   Glue: weekly/monthly aggs    │
  │  6. Validate    Great Expectations (tables)  │
  └──────────────────────────────────────────────┘
        │
        ▼
  S3 Data Lake (Apache Iceberg tables)
        │
        ▼
  Athena (ad-hoc queries)
```

### Infrastructure

| Component | AWS Service | Role |
|-----------|-------------|------|
| Orchestration | ECS Fargate (Airflow 2.8) | DAG scheduling and execution |
| Extraction | Lambda | Calls FMP API; writes raw JSON to S3 |
| Transformation | Glue (PySpark) | Builds Iceberg star schema |
| Metadata DB | RDS PostgreSQL | Airflow state storage |
| Shared storage | EFS | DAGs and logs shared across ECS tasks |
| Load balancer | ALB | Airflow UI access |
| Monitoring | CloudWatch | Logs, metrics, alarms |
| IaC | Terraform | All infrastructure managed as code |

---

## Data Model

Star schema stored as Apache Iceberg tables, partitioned by `year/month/day`:

| Table | Type | Description |
|-------|------|-------------|
| `dim_stock` | Dimension | Symbol, company name, sector, exchange |
| `fact_stock_daily_price` | Fact | OHLCV + derived metrics per symbol per day |
| `agg_stock_weekly_metrics` | Aggregate | Weekly OHLCV summary |
| `agg_stock_monthly_metrics` | Aggregate | Monthly OHLCV summary |

---

## Quick Start

See **[QUICK_START.md](QUICK_START.md)** for the full step-by-step deployment guide (~2 hours).

### Prerequisites

```bash
aws --version       # AWS CLI 2.x
terraform --version # >= 1.5.0
docker --version    # >= 20.x
python3 --version   # >= 3.11
```

### Deployment in brief

```bash
# 1. Generate secrets (DB credentials + Fernet key) — see QUICK_START.md Step 1
# 2. Build and push Docker image
./build_and_push.sh "initial-deployment"

# 3. Create terraform/terraform.tfvars with your secrets (gitignored)
# 4. Deploy infrastructure
cd terraform
terraform init && terraform apply

# 5. Initialise Airflow DB (one-time)
aws ecs run-task --cluster nasdaq-airflow-ecs-cluster \
  --task-definition nasdaq-airflow-ecs-db-init --launch-type FARGATE ...

# 6. Start services
aws ecs update-service --cluster nasdaq-airflow-ecs-cluster \
  --service nasdaq-airflow-ecs-webserver --desired-count 1 ...
aws ecs update-service --cluster nasdaq-airflow-ecs-cluster \
  --service nasdaq-airflow-ecs-scheduler --desired-count 1 ...
```

---

## Project Structure

```
nasdaq-equity-airflow-ecs-pipeline/
│
├── README.md                              # This file
├── QUICK_START.md                         # Full deployment guide
├── IMPLEMENTATION_SUMMARY.md             # Architecture and design decisions
├── AIRFLOW_PIPELINE_SUCCESS_SUMMARY.md   # Operational runbook
├── PROJECT_STRUCTURE.md                  # File-by-file reference
│
├── backend.tf                            # Terraform provider config
├── build_and_push.sh                     # Build Docker image and push to ECR
│
├── config/
│   ├── dev.yaml                          # Environment settings
│   └── symbols.yaml                      # Stock symbols to process
│
├── docker/
│   ├── Dockerfile                        # Airflow image (2.8.1 base)
│   ├── requirements.txt                  # Python dependencies
│   ├── airflow.cfg                       # Airflow runtime config
│   ├── dags/
│   │   ├── nasdaq_stock_pipeline_with_gx.py   # Active DAG (with GX validation)
│   │   └── nasdaq_stock_pipeline.py           # Reference DAG (no GX)
│   ├── great_expectations/                    # GX config and checkpoints
│   └── scripts/
│       └── create_expectations.py             # Auto-generates expectation suites
│
├── glue/jobs/
│   ├── build_stock_dimensions.py
│   ├── build_stock_fact_table.py
│   └── build_stock_aggregations.py
│
├── lambda/stock_extractor/                    # Lambda deployment package source
│
└── terraform/                                 # All infrastructure as code
    ├── main.tf / variables.tf / outputs.tf
    ├── terraform.tfvars                        # ⚠️ gitignored — your secrets here
    └── modules/
        ├── alb/ ecr/ ecs-cluster/ ecs-services/
        ├── efs/ glue/ iam/ lambda/ rds/ s3/ security-groups/
```

---

## Cost

| Mode | Est. Monthly Cost |
|------|------------------|
| 24/7 always-on | ~$85 |
| Optimised (1 hr/day pipeline) | ~$27–32 |

Main fixed cost is the ALB (~$20/mo). Stop ECS tasks and RDS when not in use to minimise spend.

---

## Scaling

The pipeline is designed to scale from 5 to 100+ symbols with minimal changes:

1. Add symbols to `config/symbols.yaml`
2. The DAG uses dynamic task mapping — no code changes needed
3. Increase Glue DPU allocation if processing time grows

---

## Security

- No credentials are hardcoded — all secrets managed via `terraform.tfvars` (gitignored) and injected as ECS environment variables
- IAM roles follow least-privilege; Lambda and Glue use scoped policies
- RDS enforces TLS (`?sslmode=require`)
- S3, RDS, and EFS are encrypted at rest
- FMP API key stored in AWS Secrets Manager

---

## Documentation

| Document | Purpose |
|----------|---------|
| [QUICK_START.md](QUICK_START.md) | Step-by-step deployment from zero |
| [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) | Architecture decisions and component detail |
| [AIRFLOW_PIPELINE_SUCCESS_SUMMARY.md](AIRFLOW_PIPELINE_SUCCESS_SUMMARY.md) | Operational runbook; issues resolved during setup |
| [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) | File-by-file repository reference |

---

*Last updated: February 2026*