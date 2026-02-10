# NASDAQ Stock Pipeline — Implementation Summary

## What Was Built

A production-ready NASDAQ stock data pipeline that processes daily stock quotes for 5+ symbols (scalable to 100+) using Apache Airflow on AWS ECS Fargate. The pipeline extracts data via a Lambda function, transforms it through AWS Glue into a star schema using Apache Iceberg, and makes results queryable via Athena.

---

## Architecture

```
Airflow Scheduler (cron: 0 2 * * * — daily 2 AM UTC / 10 AM SGT)
        │
        ▼
  Airflow DAG (ECS Fargate — LocalExecutor)
   ┌─────────────────────────────────────────┐
   │  1. Extract   → Lambda (FMP API → S3)   │
   │  2. Validate  → Great Expectations      │
   │  3. Transform → Glue: dim_stock         │
   │  4. Transform → Glue: fact_daily_price  │
   │  5. Transform → Glue: aggregations      │
   │  6. Validate  → Great Expectations      │
   └─────────────────────────────────────────┘
        │
        ▼
   S3 Data Lake (Iceberg tables)
        │
        ▼
   Athena (ad-hoc queries)
```

**Infrastructure components:**

| Component | Service | Purpose |
|-----------|---------|---------|
| Orchestration | ECS Fargate (Airflow) | DAG scheduling and task execution |
| Extraction | Lambda | Calls FMP API; writes raw JSON to S3 |
| Transformation | Glue (PySpark) | Builds star schema Iceberg tables |
| Metadata DB | RDS PostgreSQL | Airflow state and DAG metadata |
| Shared storage | EFS | DAGs and logs shared across ECS tasks |
| Load balancer | ALB | Airflow UI access |
| Monitoring | CloudWatch | Logs, metrics, and alarms |

---

## Project Structure

```
nasdaq-equity-airflow-ecs-pipeline/
├── README.md
├── QUICK_START.md
├── IMPLEMENTATION_SUMMARY.md
├── AIRFLOW_PIPELINE_SUCCESS_SUMMARY.md
├── PROJECT_STRUCTURE.md
│
├── backend.tf                         # Terraform backend config
├── build_and_push.sh                  # Build & push Docker image to ECR
│
├── config/
│   ├── dev.yaml                       # Environment config (region, S3 bucket, DB)
│   └── symbols.yaml                   # Stock symbols to process
│
├── docker/
│   ├── Dockerfile                     # Airflow image (apache/airflow:2.8.1 base)
│   ├── requirements.txt               # Python dependencies (GX, AWS providers)
│   ├── airflow.cfg                    # Airflow configuration
│   ├── build-and-push.sh              # Docker build helper
│   ├── dags/
│   │   ├── nasdaq_stock_pipeline.py            # Core pipeline DAG
│   │   └── nasdaq_stock_pipeline_with_gx.py    # Pipeline + GX validation (active)
│   ├── great_expectations/
│   │   ├── great_expectations.yml              # GX context config
│   │   └── checkpoints/                        # Validation checkpoints
│   └── scripts/
│       └── create_expectations.py              # Auto-generates expectation suites
│
├── glue/jobs/
│   ├── build_stock_dimensions.py      # Builds dim_stock table
│   ├── build_stock_fact_table.py      # Builds fact_stock_daily_price
│   └── build_stock_aggregations.py    # Builds weekly/monthly aggregates
│
├── lambda/stock_extractor/
│   └── (deployment package — see Lambda Deployment below)
│
└── terraform/                         # Infrastructure-as-Code (separate directory)
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars               # ⚠️ gitignored — contains secrets
    └── modules/
        ├── alb/
        ├── ecr/
        ├── ecs-cluster/
        ├── ecs-services/
        ├── efs/
        ├── glue/
        ├── iam/
        ├── lambda/
        ├── rds/
        ├── s3/
        └── security-groups/
```

---

## Data Model

**Star schema** stored as Apache Iceberg tables in S3, queryable via Athena:

| Table | Type | Description |
|-------|------|-------------|
| `dim_stock` | Dimension | Symbol, company name, sector, exchange |
| `fact_stock_daily_price` | Fact | OHLCV + derived metrics per symbol per day |
| `agg_stock_weekly_metrics` | Aggregate | Weekly OHLCV summary |
| `agg_stock_monthly_metrics` | Aggregate | Monthly OHLCV summary |

**Partitioning:** fact and aggregate tables are partitioned by `year/month/day` for efficient Athena queries.

---

## Great Expectations Integration

Data quality validation runs at two stages:

1. **After extraction** — validates raw S3 data (row counts, schema, nulls)
2. **After transformation** — validates each Iceberg table (business rules, referential integrity)

Key implementation decisions:
- Expectation suites are auto-generated on first run by `create_expectations.py`
- Suites stored on local filesystem inside the Docker image (simpler than S3-backed for dev)
- Validation tasks run **sequentially** (not in parallel) to avoid resource contention
- 38 lightweight table-level checks (reduced from 125 to avoid memory pressure)

---

## Performance

| Metric | Value |
|--------|-------|
| Current symbols | 5 (AAPL, MSFT, GOOGL, AMZN, NVDA) |
| Daily pipeline runtime | ~15–20 minutes |
| ECS task memory (scheduler/webserver) | 2048 MB each |
| Glue DPU per job | 2 |
| Data cadence | T-1 (previous trading day) |
| Scalability target | 100+ symbols |

---

## Cost (ap-southeast-1)

| Mode | Monthly Estimate |
|------|-----------------|
| 24/7 always-on | ~$85 |
| Optimised (1 hr/day) | ~$27–32 |

Main cost drivers: ALB (~$20/mo fixed) + RDS (~$10–25 depending on instance and uptime).

---

## Skills Demonstrated

- Apache Airflow 2.8 DAG authoring (dynamic task mapping, branching, sensors)
- AWS ECS Fargate container orchestration
- Infrastructure-as-Code with Terraform (modular, environment-aware)
- Apache Iceberg table format on S3
- Great Expectations data quality framework
- PySpark ETL on AWS Glue
- Docker image build and ECR deployment
- Cost-conscious architecture design

---

## Future Enhancements

- Scale to 100+ symbols (dynamic task mapping already supports this)
- CI/CD pipeline for automated Docker image builds on DAG changes
- Snowflake external table integration over the Iceberg data lake
- Prometheus/Grafana monitoring dashboard
- Scheduled ECS start/stop for further cost reduction

---

*Last updated: February 2026*
