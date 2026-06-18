"""
Cloud Dataflow Pipeline — Bronze Layer Validation & Routing
Google's managed Apache Beam service running on Dataflow.

What this pipeline does:
  1. Reads raw data from BigQuery (Bronze layer — as-is from BQ Data Transfer)
  2. Validates each row against schema rules (type checks, range checks, null checks)
  3. Routes VALID rows to the validated Bronze partition
  4. Routes INVALID rows to a quarantine table for review
  5. Emits row-level quality metrics to BigQuery for monitoring

Run locally:
  python bronze_validation_pipeline.py \
    --source ga4_events \
    --bq_project my-project \
    --bq_dataset marketing_bronze \
    --date 2024-06-01 \
    --runner DirectRunner

Run on Dataflow:
  python bronze_validation_pipeline.py \
    --source ga4_events \
    --bq_project my-project \
    --bq_dataset marketing_bronze \
    --date 2024-06-01 \
    --runner DataflowRunner \
    --project my-project \
    --region europe-west1 \
    --temp_location gs://my-bucket/temp \
    --staging_location gs://my-bucket/staging
"""

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions, GoogleCloudOptions
from apache_beam.io.gcp.bigquery import WriteToBigQuery, ReadFromBigQuery, BigQueryDisposition
import argparse, logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

# ─── Validation rules per source ───────────────────────────────────────────────
RULES = {
    "ga4_events": {
        "required":  ["event_date","event_name","user_pseudo_id","session_id"],
        "int_fields": ["ga_session_number"],
        "positive":  [],
        "date_fields":["event_date"],
        "valid_sets": {
            "device_category": {"desktop","mobile","tablet",""},
            "platform":        {"WEB","ANDROID","IOS",""},
        },
    },
    "google_ads": {
        "required":  ["date","campaign_id","impressions","clicks"],
        "int_fields": ["impressions","clicks"],
        "positive":  ["impressions","clicks"],
        "date_fields":["date"],
        "valid_sets": {},
    },
    "cm360": {
        "required":  ["date","campaign_id","impressions"],
        "int_fields": ["impressions","clicks"],
        "positive":  ["impressions"],
        "date_fields":["date"],
        "valid_sets": {},
    },
    "dv360": {
        "required":  ["date","campaign_id","impressions"],
        "int_fields": ["impressions","clicks"],
        "positive":  ["impressions"],
        "date_fields":["date"],
        "valid_sets": {},
    },
    "youtube": {
        "required":  ["date","video_id","views"],
        "int_fields": ["views"],
        "positive":  ["views"],
        "date_fields":["date"],
        "valid_sets": {},
    },
}

DATE_FORMATS = ["%Y-%m-%d","%d/%m/%Y","%d-%m-%Y","%Y%m%d","%B %d, %Y"]

def parse_date(s):
    for fmt in DATE_FORMATS:
        try: return datetime.strptime(str(s).strip(), fmt).strftime("%Y-%m-%d")
        except: pass
    return None

def normalise_text(s):
    if s is None: return ""
    return str(s).strip().lower().replace(" ","_").replace("-","_")

# ─── Beam DoFns ────────────────────────────────────────────────────────────────
class ValidateAndTagRow(beam.DoFn):
    """
    Tags each row as VALID or INVALID based on source-specific rules.
    Outputs:
      - 'valid'     : passes all checks
      - 'quarantine': fails at least one check (with reason column)
    """
    VALID = "valid"
    QUARANTINE = "quarantine"

    def __init__(self, source, date_partition):
        self.source = source
        self.date_partition = date_partition

    def process(self, row):
        rules = RULES.get(self.source, {})
        errors = []
        out = dict(row)

        # 1. Required field null check
        for field in rules.get("required", []):
            val = out.get(field, "")
            if val is None or str(val).strip() == "":
                errors.append(f"NULL:{field}")

        # 2. Date normalisation & validity
        for field in rules.get("date_fields", []):
            raw = out.get(field, "")
            parsed = parse_date(raw)
            if parsed:
                out[field] = parsed
            elif raw not in (None, ""):
                errors.append(f"BAD_DATE:{field}={raw}")

        # 3. Integer type coercion
        for field in rules.get("int_fields", []):
            raw = out.get(field, "")
            try:
                out[field] = int(float(str(raw).strip()))
            except (ValueError, TypeError):
                if raw not in (None, ""):
                    errors.append(f"NOT_INT:{field}={raw}")

        # 4. Positive value check
        for field in rules.get("positive", []):
            val = out.get(field)
            try:
                if float(str(val)) < 0:
                    errors.append(f"NEGATIVE:{field}={val}")
            except (ValueError, TypeError): pass

        # 5. Valid set membership
        for field, valid_set in rules.get("valid_sets", {}).items():
            val = str(out.get(field,"")).strip().lower()
            if val not in valid_set and val != "":
                errors.append(f"INVALID_VALUE:{field}={val}")

        # 6. Metadata
        out["_pipeline_date"]   = self.date_partition
        out["_source"]          = self.source
        out["_processed_at"]    = datetime.utcnow().isoformat()
        out["_validation_pass"] = len(errors) == 0

        if errors:
            out["_quarantine_reason"] = " | ".join(errors)
            yield beam.pvalue.TaggedOutput(self.QUARANTINE, out)
        else:
            yield beam.pvalue.TaggedOutput(self.VALID, out)


class EmitQualityMetric(beam.DoFn):
    """Counts valid vs quarantine rows and emits a quality summary row."""
    def __init__(self, source, date_partition):
        self.source = source
        self.date_partition = date_partition

    def process(self, element):
        tag, rows = element
        yield {
            "source":         self.source,
            "pipeline_date":  self.date_partition,
            "status":         tag,
            "row_count":      len(rows),
            "measured_at":    datetime.utcnow().isoformat(),
        }


# ─── Pipeline entry ────────────────────────────────────────────────────────────
def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--source",     required=True)
    parser.add_argument("--bq_project", required=True)
    parser.add_argument("--bq_dataset", required=True)
    parser.add_argument("--date",       required=True)
    known, pipeline_args = parser.parse_known_args(argv)

    source          = known.source
    project         = known.bq_project
    dataset         = known.bq_dataset
    date_partition  = known.date

    src_table       = f"{project}:{dataset}.{source}_raw"
    valid_table     = f"{project}:{dataset}.{source}_validated"
    quarantine_tbl  = f"{project}:{dataset}.{source}_quarantine"
    quality_tbl     = f"{project}:marketing_monitoring.pipeline_quality_metrics"

    opts = PipelineOptions(pipeline_args)
    opts.view_as(GoogleCloudOptions).project = project

    log.info(f"Starting Dataflow pipeline | source={source} | date={date_partition}")

    with beam.Pipeline(options=opts) as p:
        raw = (
            p
            | "ReadBronze" >> ReadFromBigQuery(
                table=src_table,
                use_standard_sql=True,
            )
        )

        tagged = (
            raw
            | "ValidateRows" >> beam.ParDo(
                ValidateAndTagRow(source, date_partition)
            ).with_outputs(
                ValidateAndTagRow.VALID,
                ValidateAndTagRow.QUARANTINE,
            )
        )

        # Write valid rows back to Bronze validated partition
        (
            tagged[ValidateAndTagRow.VALID]
            | "WriteValid" >> WriteToBigQuery(
                table=valid_table,
                write_disposition=BigQueryDisposition.WRITE_APPEND,
                create_disposition=BigQueryDisposition.CREATE_IF_NEEDED,
            )
        )

        # Write quarantine rows for remediation review
        (
            tagged[ValidateAndTagRow.QUARANTINE]
            | "WriteQuarantine" >> WriteToBigQuery(
                table=quarantine_tbl,
                write_disposition=BigQueryDisposition.WRITE_APPEND,
                create_disposition=BigQueryDisposition.CREATE_IF_NEEDED,
            )
        )

        # Emit quality metrics
        (
            {
                ValidateAndTagRow.VALID:      tagged[ValidateAndTagRow.VALID],
                ValidateAndTagRow.QUARANTINE: tagged[ValidateAndTagRow.QUARANTINE],
            }
            | "GroupByTag"     >> beam.GroupByKey()
            | "EmitMetrics"    >> beam.ParDo(EmitQualityMetric(source, date_partition))
            | "WriteMetrics"   >> WriteToBigQuery(
                table=quality_tbl,
                write_disposition=BigQueryDisposition.WRITE_APPEND,
                create_disposition=BigQueryDisposition.CREATE_IF_NEEDED,
            )
        )

    log.info("Pipeline complete.")

if __name__ == "__main__":
    run()
