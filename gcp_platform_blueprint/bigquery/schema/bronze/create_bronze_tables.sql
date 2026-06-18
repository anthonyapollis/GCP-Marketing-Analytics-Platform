-- ============================================================
-- BigQuery Bronze Layer DDL
-- Raw tables as-is from BQ Data Transfer Service
-- Schema is permissive (STRING everywhere) to accept all source data
-- No constraints — data quality enforced in Dataflow + dbt Silver
-- ============================================================

-- ── GA4 Events Raw ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `{project}.marketing_bronze.ga4_events_raw`
(
    event_date                  STRING,
    event_timestamp             STRING,
    event_name                  STRING,
    user_pseudo_id              STRING,
    session_id                  STRING,
    geo_country                 STRING,
    geo_city                    STRING,
    device_category             STRING,
    traffic_source_medium       STRING,
    traffic_source_source       STRING,
    traffic_source_name         STRING,
    page_location               STRING,
    page_title                  STRING,
    event_value_in_usd          STRING,
    ga_session_number           STRING,
    user_first_touch_timestamp  STRING,
    is_active_user              STRING,
    platform                    STRING,
    stream_id                   STRING,
    -- Pipeline metadata (added by Dataflow)
    _source                     STRING,
    _pipeline_date              DATE,
    _processed_at               TIMESTAMP,
    _validation_pass            BOOL,
    _quarantine_reason          STRING
)
PARTITION BY _pipeline_date
CLUSTER BY event_name, device_category
OPTIONS (
    description = "Bronze: raw GA4 events from BQ Data Transfer Service. Intentionally permissive schema — all fields as STRING to preserve raw source fidelity.",
    require_partition_filter = false,
    partition_expiration_days = 365
);

-- ── Google Ads Raw ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `{project}.marketing_bronze.google_ads_raw`
(
    date                    STRING,
    customer_id             STRING,
    campaign_id             STRING,
    campaign_name           STRING,
    campaign_status         STRING,
    ad_group_id             STRING,
    ad_group_name           STRING,
    keyword_text            STRING,
    match_type              STRING,
    impressions             STRING,
    clicks                  STRING,
    cost_micros             STRING,
    conversions             STRING,
    conversion_value        STRING,
    currency_code           STRING,
    device                  STRING,
    network                 STRING,
    geo_target              STRING,
    _source                 STRING,
    _pipeline_date          DATE,
    _processed_at           TIMESTAMP,
    _validation_pass        BOOL,
    _quarantine_reason      STRING
)
PARTITION BY _pipeline_date
CLUSTER BY campaign_id
OPTIONS (description = "Bronze: raw Google Ads data from BQ Data Transfer Service.");

-- ── CM360 Raw ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `{project}.marketing_bronze.cm360_raw`
(
    date                            STRING,
    advertiser_id                   STRING,
    advertiser_name                 STRING,
    campaign_id                     STRING,
    campaign_name                   STRING,
    placement_id                    STRING,
    placement_name                  STRING,
    ad_id                           STRING,
    ad_name                         STRING,
    creative_type                   STRING,
    impressions                     STRING,
    clicks                          STRING,
    click_through_conversions       STRING,
    view_through_conversions        STRING,
    total_conversions               STRING,
    revenue                         STRING,
    dma_region                      STRING,
    country                         STRING,
    _source                         STRING,
    _pipeline_date                  DATE,
    _processed_at                   TIMESTAMP,
    _validation_pass                BOOL,
    _quarantine_reason              STRING
)
PARTITION BY _pipeline_date
OPTIONS (description = "Bronze: raw Campaign Manager 360 impression & conversion data.");

-- ── DV360 Raw ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `{project}.marketing_bronze.dv360_raw`
(
    date                            STRING,
    partner_id                      STRING,
    advertiser_id                   STRING,
    campaign_id                     STRING,
    insertion_order_id              STRING,
    insertion_order_name            STRING,
    line_item_id                    STRING,
    line_item_name                  STRING,
    line_item_type                  STRING,
    targeting_type                  STRING,
    audience_segment                STRING,
    impressions                     STRING,
    clicks                          STRING,
    revenue_usd                     STRING,
    total_conversions               STRING,
    view_rate                       STRING,
    average_cpm                     STRING,
    exchange                        STRING,
    _source                         STRING,
    _pipeline_date                  DATE,
    _processed_at                   TIMESTAMP,
    _validation_pass                BOOL,
    _quarantine_reason              STRING
)
PARTITION BY _pipeline_date
OPTIONS (description = "Bronze: raw Display & Video 360 line-item performance data.");

-- ── YouTube Raw ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `{project}.marketing_bronze.youtube_raw`
(
    date                                    STRING,
    channel_id                              STRING,
    video_id                                STRING,
    video_title                             STRING,
    country                                 STRING,
    device_type                             STRING,
    traffic_source_type                     STRING,
    views                                   STRING,
    watch_time_minutes                      STRING,
    average_view_duration                   STRING,
    impressions                             STRING,
    impressions_click_through_rate          STRING,
    likes                                   STRING,
    comments                                STRING,
    shares                                  STRING,
    subscribers_gained                      STRING,
    estimated_revenue_usd                   STRING,
    _source                                 STRING,
    _pipeline_date                          DATE,
    _processed_at                           TIMESTAMP,
    _validation_pass                        BOOL,
    _quarantine_reason                      STRING
)
PARTITION BY _pipeline_date
OPTIONS (description = "Bronze: raw YouTube Channel Analytics from BQ Data Transfer.");
