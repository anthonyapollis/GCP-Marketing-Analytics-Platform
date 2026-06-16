-- ============================================================
-- BigQuery Gold Layer DDL
-- Business-ready tables, fully typed and documented
-- Populated by dbt mart models
-- ============================================================

-- ── Cross-Channel Performance Fact ──────────────────────────
CREATE TABLE IF NOT EXISTS `{project}.marketing_gold.fct_cross_channel_performance`
(
    -- Dimensions
    report_date             DATE        NOT NULL,
    channel                 STRING      NOT NULL,
    campaign_name           STRING,
    device                  STRING,
    country_code            STRING,

    -- GA4 Session metrics
    sessions                INT64,
    unique_users            INT64,
    new_users               INT64,
    page_views              INT64,
    purchases               INT64,
    revenue_usd             FLOAT64,
    add_to_carts            INT64,
    checkouts               INT64,

    -- Paid media metrics
    paid_impressions        INT64,
    paid_clicks             INT64,
    spend_zar               FLOAT64,
    paid_conversions        FLOAT64,
    paid_conversion_value_zar FLOAT64,
    avg_ctr                 FLOAT64,
    avg_cpc_zar             FLOAT64,
    avg_roas                FLOAT64,

    -- Derived KPIs
    session_conversion_rate     FLOAT64,
    revenue_per_session         FLOAT64,
    cost_per_purchase_zar       FLOAT64,
    cart_to_checkout_rate       FLOAT64,
    checkout_to_purchase_rate   FLOAT64,

    -- Metadata
    _gold_loaded_at         TIMESTAMP
)
PARTITION BY report_date
CLUSTER BY channel, campaign_name
OPTIONS (
    description = "Gold: unified cross-channel marketing performance. Joins GA4 sessions + Google Ads + CM360. Grain: date × channel × campaign × device.",
    require_partition_filter = false
);

-- ── Channel Attribution Summary ─────────────────────────────
CREATE TABLE IF NOT EXISTS `{project}.marketing_gold.rpt_channel_attribution`
(
    report_date             DATE,
    channel                 STRING,
    total_sessions          INT64,
    total_purchases         INT64,
    total_revenue_usd       FLOAT64,
    total_spend_zar         FLOAT64,
    overall_roas            FLOAT64,
    cpa_zar                 FLOAT64,
    session_share_pct       FLOAT64,
    revenue_share_pct       FLOAT64,
    spend_share_pct         FLOAT64,
    _gold_loaded_at         TIMESTAMP
)
PARTITION BY report_date
OPTIONS (description = "Gold: weekly/monthly channel attribution summary. Source of truth for exec dashboards.");
