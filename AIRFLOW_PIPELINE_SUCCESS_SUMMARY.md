# NASDAQ Airflow ECS Pipeline — Operational Runbook

**Status:** ✅ Production Ready | **Region:** ap-southeast-1 (Singapore)

---

## System Status

| Component | Status | Details |
|-----------|--------|---------|
| Scheduler | ✅ Healthy | ECS task: `nasdaq-airflow-ecs-scheduler` |
| Webserver | ✅ Healthy | ECS task: `nasdaq-airflow-ecs-webserver` |
| Database | ✅ Available | RDS PostgreSQL with SSL enforced |
| Airflow UI | ✅ Accessible | Via ALB (see Terraform outputs) |
| DAG Execution | ✅ Running | `nasdaq_stock_pipeline_with_gx` |

---

## Issues Resolved During Initial Setup

### 1. IAM Role Naming Mismatch
- **Error:** `ECS was unable to assume the role`
- **Cause:** Task definition referenced non-existent role names
- **Fix:** Updated to correct role ARNs from Terraform outputs (`nasdaq-airflow-ecs-ecs-task`, `nasdaq-airflow-ecs-ecs-task-execution`)

### 2. Missing Airflow Command in Task Definition
- **Error:** `airflow command error: GROUP_OR_COMMAND required`
- **Cause:** Task definition `command` field was null
- **Fix:** Set `["airflow", "scheduler"]` and `["webserver"]` explicitly

### 3. Wrong Database Username
- **Error:** `password authentication failed for user "airflow"`
- **Cause:** Connection string used default username instead of the master username set in `terraform.tfvars`
- **Fix:** Updated `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN` to use `var.airflow_db_username`

### 4. Missing SSL on RDS Connection
- **Error:** `no pg_hba.conf entry for host ... no encryption`
- **Cause:** RDS enforces encrypted connections
- **Fix:** Appended `?sslmode=require` to the connection string

### 5. Database Not Initialized
- **Error:** `You need to initialize the database`
- **Cause:** `airflow db migrate` was never run
- **Fix:** Created a one-shot `db-init` ECS task definition; run once before starting services

### 6. Insufficient Webserver Resources
- **Error:** `gunicorn workers died and were not restarted`
- **Cause:** Webserver allocated only 512 CPU / 1024 MB
- **Fix:** Increased to 1024 CPU / 2048 MB

---

## Final ECS Task Configuration

```
Scheduler:
  CPU:     1024
  Memory:  2048 MB
  Command: ["airflow", "scheduler"]

Webserver:
  CPU:     1024
  Memory:  2048 MB
  Command: ["webserver"]
```

### Key Environment Variables (set via Terraform)

```bash
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://<db_user>:<db_pass>@<rds_endpoint>:5432/airflow?sslmode=require
AIRFLOW__CORE__LOAD_EXAMPLES=False
AIRFLOW__CORE__FERNET_KEY=<generated — see terraform.tfvars>
AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags
AIRFLOW__SCHEDULER__MIN_FILE_PROCESS_INTERVAL=60
```

> ⚠️ Never hardcode credentials. All sensitive values are managed in `terraform.tfvars` (gitignored) and injected as ECS environment variables.

---

## Accessing the Airflow UI

```bash
# Retrieve the ALB DNS name from Terraform
terraform output alb_dns_name
```

Navigate to `http://<alb_dns_name>/home`.

Default login (change immediately after first login):

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | `admin` |

**AWS Resources:**

| Resource | Name |
|----------|------|
| ECS Cluster | `nasdaq-airflow-ecs-cluster` |
| RDS Instance | `nasdaq-airflow-ecs-db` |
| Region | `ap-southeast-1` |

---

## Cost Estimate

| Scenario | ECS Tasks | RDS | ALB | Total |
|----------|-----------|-----|-----|-------|
| 24/7 (always-on) | ~$35/mo | ~$25/mo | ~$20/mo | **~$85/mo** |
| Optimised (1 hr/day pipeline) | ~$2/mo | ~$10/mo | ~$20/mo | **~$32/mo** |

---

## Key Learnings

1. **Resource allocation matters** — webserver requires ≥ 1024 CPU / 2048 MB; scheduler is stable at the same spec.
2. **Always specify the Airflow command** — Docker images without `ENTRYPOINT` require an explicit `command` in the ECS task definition.
3. **RDS always needs `?sslmode=require`** — verify the master username from Terraform state, never assume it matches the Airflow default.
4. **Manual AWS console changes break Terraform state** — always sync fixes back to Terraform before the next `apply`.
5. **Database initialisation is a prerequisite** — run `airflow db migrate` once via a dedicated `db-init` task before starting the scheduler or webserver.

---

## Recommended Next Steps

- [ ] Rotate the Airflow admin password
- [ ] Verify `nasdaq_stock_pipeline_with_gx` DAG execution end-to-end
- [ ] Confirm S3 output data is partitioned correctly
- [ ] Set up CloudWatch alarms for ECS task failures
- [ ] Implement CI/CD for automated Docker image builds
- [ ] Configure log retention policies
- [ ] Set up scheduled start/stop for cost optimisation

---

*Last updated: February 2026*
