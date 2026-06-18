# Cape & Cart H1 Growth Campaign Analytics

![Case Study](https://img.shields.io/badge/Case_Study-Cape_%26_Cart_H1_Growth-0099B8?style=flat-square)
![Currency](https://img.shields.io/badge/Currency-ZAR%20%2F%20Rand-00A86B?style=flat-square)
![GCP](https://img.shields.io/badge/Primary_Platform-GCP%20%2B%20BigQuery-4285F4?style=flat-square&logo=googlecloud&logoColor=white)
![dbt](https://img.shields.io/badge/Transform-dbt-FF694B?style=flat-square&logo=dbt&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-GCP%20primary%20%7C%20Snowflake%20validation-29B5E8?style=flat-square)
![Python](https://img.shields.io/badge/Python_3.11-3776AB?style=flat-square&logo=python&logoColor=white)

> **One project:** this repository is the **Cape & Cart H1 Growth Campaign Analytics Platform**. It contains the business case study, the data, the dashboards, the workbook, the ML outputs, and the platform implementation needed to reproduce the story.

## What This Project Is

Cape & Cart needed to understand whether its H1 growth campaign was creating profitable local growth. This single project follows the data from dirty ecommerce transactions through Bronze, Silver, and Gold layers, then into BI dashboards, Excel reporting, Snowflake validation, and machine learning outputs.

All commercial values are in **South African Rand (ZAR / R)** so revenue, ad spend, average order value, margin, and return on ad spend can be compared on the same business basis.

## Open These First

| Priority | File / Folder | Why it matters |
|---|---|---|
| 1 | `dashboard/bi_dashboard.html` | Main BI report with chart explanations, abbreviation guide, ZAR/Rand context, and action recommendations. |
| 2 | `dashboard/gcp_dashboard.html` | Interactive GCP-style campaign dashboard. |
| 3 | `ebook/gcp_ebook.html` | Narrative technical case study. |
| 4 | `excel/GCP_Marketing_Analytics_Platform_v2.xlsx` | Excel workbook for stakeholder review. |
| 5 | `data/` | Bronze, Silver, Gold, transactional, and ML-ready data used by the reports. |
| 6 | `platform/` | GCP implementation plus Snowflake validation scripts used to reproduce the platform. |

## Folder Map

| Folder | Role |
|---|---|
| `dashboard/` | Final BI and campaign dashboards. |
| `data/` | Raw dirty transactions, cleaned Silver tables, Gold product performance, and ML outputs. |
| `ebook/` | Case-study document for readers who want the story and architecture. |
| `excel/` | Generated workbook and workbook builder. |
| `platform/gcp/` | GCP implementation: Airflow, BigQuery schemas, Dataflow, BigQuery Transfer configs, and dbt. |
| `platform/snowflake/` | Snowflake setup pack, warehouse DDL, and load manifest for validation/portability. |

## Control Totals

These are the figures the reports reconcile to:

| Metric | Value |
|---|---:|
| Data period | January 1, 2024 to June 30, 2024 |
| H1 revenue | R5,038,057.79 |
| Orders | 12,100 |
| Average Order Value (AOV) | R416.37 |
| Customers | 10,350 |
| Products | 30 |
| Clean order items | 16,218 |
| Clean campaign touchpoints | 1,886 |
| Quarantined dirty rows | 964 |
| ML customer scores | 10,350 |
| ROAS forecast rows | 28 |

## Platform Framing

This is one integrated analytics platform project:

- **GCP / BigQuery** is the primary warehouse and orchestration implementation.
- **dbt** models the Silver and Gold business layers.
- **Airflow / Dataflow / BigQuery Transfer Service** live under `platform/gcp/` as the reproducible platform code.
- **Snowflake** lives under `platform/snowflake/` as a validation implementation, proving the same curated data and ML-ready outputs can be loaded into another warehouse without changing the business story.

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
├── platform/gcp/bigquery/
│   └── schema/
│       ├── bronze/create_bronze_tables.sql  Permissive STRING schemas
│       └── gold/create_gold_tables.sql      Typed + partitioned gold tables
│
├── platform/gcp/bq_transfer/
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
├── platform/gcp/dataflow/
│   └── pipelines/
│       └── bronze_validation_pipeline.py   Apache Beam DoFn validation
│
└── platform/gcp/dbt/
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
bq query --use_legacy_sql=false < platform/gcp/bigquery/schema/bronze/create_bronze_tables.sql

# 3. Deploy Gold DDL
bq query --use_legacy_sql=false < platform/gcp/bigquery/schema/gold/create_gold_tables.sql

# 4. Install dbt dependencies
cd platform/gcp/dbt && pip install dbt-bigquery && dbt deps

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
