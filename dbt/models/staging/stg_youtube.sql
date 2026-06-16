-- ============================================================
-- Silver: YouTube Channel Analytics cleaned staging model
-- Source: marketing_bronze.youtube_raw
-- Grain: date × channel × video × country × device × traffic_source
-- ============================================================
{{
  config(
    materialized      = 'incremental',
    unique_key        = ['report_date','channel_id','video_id','country','device_type','traffic_source_type'],
    incremental_strategy = 'merge',
    partition_by      = {'field': 'report_date', 'data_type': 'date'},
    cluster_by        = ['channel_id','country'],
    tags              = ['silver','youtube']
  )
}}

WITH

-- Step 1: Deduplicate
deduped AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY date, channel_id, video_id, country, device_type, traffic_source_type
               ORDER BY _processed_at DESC
           ) AS rn
    FROM {{ source('bronze', 'youtube_raw') }}
    {% if is_incremental() %}
    WHERE _pipeline_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {{ var('lookback_days') }} DAY)
    {% endif %}
),

raw AS (SELECT * FROM deduped WHERE rn = 1),

-- Step 2: Parse date
parsed_date AS (
    SELECT
        *,
        CASE
            WHEN REGEXP_CONTAINS(date, r'^\d{4}-\d{2}-\d{2}$')       THEN PARSE_DATE('%Y-%m-%d', date)
            WHEN REGEXP_CONTAINS(date, r'^\d{2}/\d{2}/\d{4}$')       THEN PARSE_DATE('%d/%m/%Y', date)
            WHEN REGEXP_CONTAINS(date, r'^\d{2}-\d{2}-\d{4}$')       THEN PARSE_DATE('%d-%m-%Y', date)
            WHEN REGEXP_CONTAINS(date, r'^\d{8}$')                    THEN PARSE_DATE('%Y%m%d', date)
            WHEN REGEXP_CONTAINS(date, r'^[A-Za-z]+ \d{2}, \d{4}$')  THEN PARSE_DATE('%B %d, %Y', date)
            ELSE NULL
        END AS report_date
    FROM raw
),

-- Step 3: Clean, cast, clamp negatives
cleaned AS (
    SELECT
        report_date,

        -- Identifiers
        NULLIF(TRIM(channel_id), '')                                        AS channel_id,
        NULLIF(TRIM(video_id), '')                                          AS video_id,
        NULLIF(TRIM(video_title), '')                                       AS video_title,
        UPPER(TRIM(NULLIF(country, '')))                                    AS country,
        UPPER(TRIM(NULLIF(device_type, '')))                                AS device_type,
        UPPER(TRIM(NULLIF(traffic_source_type, '')))                        AS traffic_source_type,

        -- Core metrics: clamp negatives to 0
        GREATEST(SAFE_CAST(views AS INT64), 0)                             AS views,
        GREATEST(SAFE_CAST(watch_time_minutes AS FLOAT64), 0)              AS watch_time_minutes,
        GREATEST(SAFE_CAST(impressions AS INT64), 0)                       AS impressions,
        GREATEST(SAFE_CAST(likes AS INT64), 0)                             AS likes,
        GREATEST(SAFE_CAST(comments AS INT64), 0)                          AS comments,
        GREATEST(SAFE_CAST(estimated_revenue_usd AS FLOAT64), 0)           AS estimated_revenue_usd,

        -- Click-through rate: must be in [0, 1]
        CASE
            WHEN SAFE_CAST(impressions_click_through_rate AS FLOAT64) < 0  THEN 0
            WHEN SAFE_CAST(impressions_click_through_rate AS FLOAT64) > 1  THEN NULL
            ELSE SAFE_CAST(impressions_click_through_rate AS FLOAT64)
        END AS impressions_ctr,

        -- Derived: average view duration in minutes
        SAFE_DIVIDE(
            GREATEST(SAFE_CAST(watch_time_minutes AS FLOAT64), 0),
            NULLIF(GREATEST(SAFE_CAST(views AS INT64), 0), 0)
        )                                                                   AS avg_view_duration_minutes,

        -- Derived: revenue per 1000 views (RPM)
        SAFE_DIVIDE(
            GREATEST(SAFE_CAST(estimated_revenue_usd AS FLOAT64), 0) * 1000,
            NULLIF(GREATEST(SAFE_CAST(views AS INT64), 0), 0)
        )                                                                   AS rpm_usd,

        -- Pipeline metadata
        _source,
        _pipeline_date,
        _processed_at,
        _validation_pass

    FROM parsed_date
    WHERE report_date IS NOT NULL
),

valid AS (
    SELECT * FROM cleaned
    WHERE channel_id IS NOT NULL
      AND video_id IS NOT NULL
)

SELECT * FROM valid
