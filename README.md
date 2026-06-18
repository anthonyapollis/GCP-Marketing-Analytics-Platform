# GCP Marketing Analytics Platform

![Architecture](https://img.shields.io/badge/Architecture-Medallion_(Bronze%2FSilver%2FGold)-FFB300?style=flat-square)
![BigQuery](https://img.shields.io/badge/BigQuery-4285F4?style=flat-square&logo=googlebigquery&logoColor=white)
![dbt](https://img.shields.io/badge/dbt-FF694B?style=flat-square&logo=dbt&logoColor=white)
![Apache Airflow](https://img.shields.io/badge/Apache_Airflow-017CEE?style=flat-square&logo=apacheairflow&logoColor=white)
![Cloud Dataflow](https://img.shields.io/badge/Cloud_Dataflow-4285F4?style=flat-square&logo=googlecloud&logoColor=white)
![Apache Beam](https://img.shields.io/badge/Apache_Beam-00A86B?style=flat-square&logo=apache&logoColor=white)
![Python](https://img.shields.io/badge/Python_3.11-3776AB?style=flat-square&logo=python&logoColor=white)

> **Production-grade GCP marketing data platform.** Ingests 5 advertising sources (GA4, Google Ads, CM360, DV360, YouTube) through a Bronze → Silver → Gold medallion pipeline. Dataflow validates raw data; dbt transforms and models it; Airflow orchestrates the daily DAG.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SOURCES  (BQ Data Transfer Service)                  │
│   GA4 · Google Ads · Campaign Manager 360 · DV360 · YouTube Analytics  │
└───────────────────────────┬─────────────────────────────────────────────┘
                            │  Managed connectors — daily scheduled load
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  BRONZE  (marketing_bronze.*)                                           │
│  All columns STRING — permissive schema preserves raw source fidelity   │
│  Partitioned by _pipeline_date                                          │
└───────────────────────────┬─────────────────────────────────────────────┘
                            │  Apache Beam / Cloud Dataflow
                            │  ValidateAndTagRow → valid vs quarantine
                            │  EmitQualityMetric → Cloud Monitoring
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  SILVER  (marketing_silver.*)  ←── dbt staging models                  │
│  Typed, deduped, date-parsed, negatives clamped, strings normalised     │
│  Incremental materialization (merge on unique_key)                      │
└───────────────────────────┬─────────────────────────────────────────────┘
                            │  dbt mart models
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  GOLD  (marketing_gold.*)                                               │
│  fct_cross_channel_performance — unified GA4 + Ads + CM360 fact        │
│  rpt_channel_attribution       — exec-ready channel ROAS summary        │
└─────────────────────────────────────────────────────────────────────────┘
                            │  Looker Studio / Tableau
                            ▼
                    Executive Dashboards
```

### Orchestration (Apache Airflow)

```
marketing_pipeline_dag  (schedule: 04:00 UTC daily)
│
├── TaskGroup: bq_data_transfer
│   ├── trigger_ga4_transfer
│   ├── trigger_google_ads_transfer
│   ├── trigger_cm360_transfer
│   ├── trigger_dv360_transfer
│   └── trigger_youtube_transfer
│
├── TaskGroup: dataflow_validation
│   └── run_bronze_validation_dataflow     ← Apache Beam pipeline
│
├── TaskGroup: dbt_silver
│   ├── dbt_run_staging                    ← 5 staging models
│   └── dbt_test_staging                   ← dbt tests + freshness checks
│
├── TaskGroup: dbt_gold
│   └── dbt_run_marts                      ← fct + rpt models
│
└── notify_slack_on_success / notify_slack_on_failure
```

---

## Platform Framing

This portfolio is presented as a **GCP Marketing Analytics Platform** first:

- BigQuery stores Bronze, Silver, and Gold layers.
- Dataflow / Apache Beam validates dirty rows and writes quarantine outputs.
- dbt builds typed Silver models and Gold reporting facts.
- Airflow orchestrates the daily pipeline.
- The dashboard, ebook, and workbook tell the GCP business story.

Snowflake is included as a **validation and portability extension**. The curated data was replicated into `CAPE_CART_H1_GROWTH` with `RAW`, `SILVER`, `GOLD`, `ANALYTICS`, and `ML` schemas to prove that the model is warehouse-portable and to run a second ML workbench. ML metrics may not be numerically identical across GCP and Snowflake unless the feature store, labels, split window, algorithm, and thresholds are identical; the business conclusions should remain consistent.

## Project Structure

```
GCP-Marketing-Analytics-Platform/
│
├── airflow/
│   └── dags/
│       └── marketing_pipeline_dag.py      Airflow 2.x DAG with TaskGroups
│
├── bigquery/
│   └── schema/
│       ├── bronze/create_bronze_tables.sql  Permissive STRING schemas
│       └── gold/create_gold_tables.sql      Typed + partitioned gold tables
│
├── bq_transfer/
│   └── configs/                            BQ Data Transfer JSON configs
│       ├── ga4_transfer_config.json
│       ├── google_ads_transfer_config.json
│       ├── cm360_transfer_config.json
│       ├── dv360_transfer_config.json
│       └── youtube_transfer_config.json
│
├── data/
│   └── bronze/
│       ├── generate_bronze_data.py         Generates dirty test data
│       ├── ga4_events_raw.csv              5 150 rows (3% dupes, 8-20% nulls)
│       ├── google_ads_raw.csv              2 080 rows
│       └── youtube_raw.csv                 1 545 rows
│
├── dataflow/
│   └── pipelines/
│       └── bronze_validation_pipeline.py   Apache Beam DoFn validation
│
└── dbt/
    ├── dbt_project.yml                     Vars: bronze/silver/gold datasets
    └── models/
        ├── staging/                        SILVER models
        │   ├── stg_ga4_events.sql
        │   ├── stg_google_ads.sql
        │   ├── stg_cm360.sql
        │   ├── stg_dv360.sql
        │   └── stg_youtube.sql
        └── marts/
            └── marketing/
                └── fct_cross_channel_performance.sql   GOLD unified fact
```

---

## Data Quality — What We Catch

The Bronze layer intentionally stores dirty data exactly as received. The Dataflow pipeline and dbt models clean the following:

| Issue | How Detected | Resolution |
|-------|-------------|------------|
| Mixed date formats | 5 regex patterns | `PARSE_DATE` with fallback → NULL |
| Negative impressions / clicks | Numeric check < 0 | → NULL (flagged quarantine) |
| Negative costs / revenue | Numeric check < 0 | → 0 via `GREATEST()` |
| Duplicate rows (3–5%) | `ROW_NUMBER()` PARTITION | Keep latest by `_processed_at` |
| Null key fields (8–20%) | IS NULL check | Row excluded from Silver |
| Mixed-case strings (`ZAR`/`zar`/`Zar`) | `UPPER(TRIM())` | Normalised to UPPER |
| CTR > 1 (impossible) | Range check | → NULL (implausible metric) |
| Empty strings as nulls | `NULLIF(TRIM(x),'')` | Unified to SQL NULL |
| Wrong data types | `SAFE_CAST` | NULL on failure, not error |

---

## Key Design Decisions

| Decision | Why |
|----------|-----|
| **BigQuery Data Transfer Service** over custom ETL | Managed, SLA-backed connectors for each Google platform — eliminates auth headaches and connector maintenance |
| **Permissive STRING schema in Bronze** | Accept data as-is; never reject at ingestion — quarantine and clean downstream |
| **Apache Beam / Cloud Dataflow for validation** | Serverless, autoscaling, handles peak daily loads without provisioning — also emits quality metrics to Cloud Monitoring |
| **dbt incremental + merge** | Idempotent reruns without full table scans; partition pruning keeps BigQuery costs low |
| **Airflow TaskGroups** | Clear DAG structure, partial retries per group, isolated failure domains |
| **Gold grain: date × channel × campaign × device** | Fine enough for optimisation decisions, coarse enough to avoid fan-out in dashboards |

---

## Quick Start

```bash
# 1. Generate dirty bronze test data
cd data/bronze
python generate_bronze_data.py

# 2. Deploy Bronze DDL to BigQuery
bq query --use_legacy_sql=false < bigquery/schema/bronze/create_bronze_tables.sql

# 3. Deploy Gold DDL
bq query --use_legacy_sql=false < bigquery/schema/gold/create_gold_tables.sql

# 4. Install dbt dependencies
cd dbt && pip install dbt-bigquery && dbt deps

# 5. Run Silver staging models
dbt run --select staging

# 6. Run dbt tests
dbt test --select staging

# 7. Run Gold marts
dbt run --select marts
```

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Ingestion | BigQuery Data Transfer Service | Managed connectors for GA4, Ads, CM360, DV360, YouTube |
| Validation | Apache Beam + Cloud Dataflow | Row-level quality tagging, quarantine routing, monitoring metrics |
| Transformation | dbt (BigQuery adapter) | Deduplication, type casting, normalisation, incremental loads |
| Orchestration | Apache Airflow 2.x | DAG scheduling, TaskGroups, Slack alerting |
| Storage | Google BigQuery | Bronze / Silver / Gold datasets |
| Language | Python 3.11 | Beam pipeline DoFns, Airflow operators, data generation |
