-- ============================================================
-- Silver: Campaign Manager 360 cleaned staging model
-- Source: marketing_bronze.cm360_raw
-- Grain: date × campaign × placement × ad × creative_type
-- ============================================================
{{
  config(
    materialized      = 'incremental',
    unique_key        = ['report_date','campaign_id','placement_id','ad_id'],
    incremental_strategy = 'merge',
    partition_by      = {'field': 'report_date', 'data_type': 'date'},
    cluster_by        = ['campaign_id'],
    tags              = ['silver','cm360']
  )
}}

WITH

-- Step 1: Deduplicate (pipeline replays can re-deliver rows)
deduped AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY date, campaign_id, placement_id, ad_id
               ORDER BY _processed_at DESC
           ) AS rn
    FROM {{ source('bronze', 'cm360_raw') }}
    {% if is_incremental() %}
    WHERE _pipeline_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {{ var('lookback_days') }} DAY)
    {% endif %}
),

raw AS (SELECT * FROM deduped WHERE rn = 1),

-- Step 2: Parse date (multiple formats observed in bronze)
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

-- Step 3: Normalise string fields and IDs
cleaned AS (
    SELECT
        report_date,

        -- Identifiers
        NULLIF(TRIM(advertiser_id), '')                                     AS advertiser_id,
        NULLIF(TRIM(advertiser_name), '')                                   AS advertiser_name,
        NULLIF(TRIM(campaign_id), '')                                       AS campaign_id,
        NULLIF(TRIM(campaign_name), '')                                     AS campaign_name,
        NULLIF(TRIM(placement_id), '')                                      AS placement_id,
        NULLIF(TRIM(placement_name), '')                                    AS placement_name,
        NULLIF(TRIM(ad_id), '')                                             AS ad_id,
        NULLIF(TRIM(ad_name), '')                                           AS ad_name,
        UPPER(TRIM(NULLIF(creative_type, '')))                              AS creative_type,
        UPPER(TRIM(NULLIF(country, '')))                                    AS country_code,
        NULLIF(TRIM(dma_region), '')                                        AS dma_region,

        -- Metrics: nullify negatives (data quality rule)
        CASE
            WHEN SAFE_CAST(impressions AS INT64) < 0 THEN NULL
            ELSE SAFE_CAST(impressions AS INT64)
        END AS impressions,

        CASE
            WHEN SAFE_CAST(clicks AS INT64) < 0 THEN NULL
            ELSE SAFE_CAST(clicks AS INT64)
        END AS clicks,

        GREATEST(SAFE_CAST(click_through_conversions AS FLOAT64), 0)       AS click_through_conversions,
        GREATEST(SAFE_CAST(view_through_conversions AS FLOAT64), 0)        AS view_through_conversions,
        GREATEST(SAFE_CAST(total_conversions AS FLOAT64), 0)               AS total_conversions,
        GREATEST(SAFE_CAST(revenue AS FLOAT64), 0)                         AS revenue_usd,

        -- Derived CTR
        SAFE_DIVIDE(
            GREATEST(SAFE_CAST(clicks AS FLOAT64), 0),
            GREATEST(SAFE_CAST(impressions AS FLOAT64), 1)
        )                                                                   AS ctr,

        -- Pipeline metadata
        _source,
        _pipeline_date,
        _processed_at,
        _validation_pass

    FROM parsed_date
    WHERE report_date IS NOT NULL
),

-- Step 4: Reject rows missing required business keys
valid AS (
    SELECT *
    FROM cleaned
    WHERE campaign_id IS NOT NULL
)

SELECT * FROM valid
