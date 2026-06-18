{{
    config(
        materialized = 'table',
        partition_by = {'field': 'report_date', 'data_type': 'date'},
        cluster_by   = ['channel', 'campaign_name'],
        tags = ['gold', 'marketing', 'daily']
    )
}}

/*
  GOLD LAYER — fct_cross_channel_performance
  Unified cross-channel marketing performance fact table.
  Joins GA4 session data with paid media spend & impression data.

  Grain: one row per date × channel × campaign × device

  Use cases:
    - Campaign ROI dashboard
    - Channel attribution analysis
    - Media mix modelling input
    - Executive weekly briefing
*/

with

-- Silver: GA4 sessions aggregated to campaign grain
ga4 as (
    select
        event_date                                      as report_date,
        channel_medium                                  as channel,
        campaign_name,
        device_category                                 as device,
        country_code,

        -- Session & engagement metrics
        count(distinct case when event_name = 'session_start' then session_id end)
                                                        as sessions,
        count(distinct user_pseudo_id)                  as unique_users,
        count(distinct case when is_first_session then user_pseudo_id end)
                                                        as new_users,
        countif(event_name = 'page_view')               as page_views,
        countif(event_name = 'purchase')                as purchases,
        sum(case when event_name = 'purchase' then event_value_usd end)
                                                        as revenue_usd,
        countif(event_name = 'add_to_cart')             as add_to_carts,
        countif(event_name = 'begin_checkout')          as checkouts

    from {{ ref('stg_ga4_events') }}
    where event_date >= date_sub(current_date(), interval 90 day)
    group by 1,2,3,4,5
),

-- Silver: Paid search spend (Google Ads)
ads as (
    select
        date                                            as report_date,
        'Paid Search'                                   as channel,
        campaign_name,
        device,
        null                                            as country_code,

        -- Paid metrics
        sum(impressions)                                as paid_impressions,
        sum(clicks)                                     as paid_clicks,
        sum(cost_zar)                                   as spend_zar,
        sum(conversions)                                as paid_conversions,
        sum(conversion_value_zar)                       as paid_conversion_value_zar,
        avg(ctr)                                        as avg_ctr,
        avg(cpc_zar)                                    as avg_cpc_zar,
        avg(roas)                                       as avg_roas

    from {{ ref('stg_google_ads') }}
    where date >= date_sub(current_date(), interval 90 day)
      and campaign_status = 'ENABLED'
    group by 1,2,3,4,5
),

-- Silver: Display (CM360)
cm360 as (
    select
        date                                            as report_date,
        'Display'                                       as channel,
        campaign_name,
        null                                            as device,
        null                                            as country_code,

        sum(impressions)                                as paid_impressions,
        sum(clicks)                                     as paid_clicks,
        null                                            as spend_zar,
        sum(click_through_conversions + view_through_conversions)
                                                        as paid_conversions,
        null                                            as paid_conversion_value_zar,
        safe_divide(sum(clicks), sum(impressions))      as avg_ctr,
        null                                            as avg_cpc_zar,
        null                                            as avg_roas

    from {{ ref('stg_cm360') }}
    where date >= date_sub(current_date(), interval 90 day)
    group by 1,2,3,4,5
),

-- Union all paid channels
all_paid as (
    select * from ads
    union all
    select * from cm360
),

-- Join GA4 (sessions/revenue) with paid media (spend/impressions)
joined as (
    select
        coalesce(g.report_date, p.report_date)          as report_date,
        coalesce(g.channel, p.channel)                  as channel,
        coalesce(g.campaign_name, p.campaign_name)      as campaign_name,
        coalesce(g.device, p.device)                    as device,
        g.country_code,

        -- GA4 metrics
        coalesce(g.sessions, 0)                         as sessions,
        coalesce(g.unique_users, 0)                     as unique_users,
        coalesce(g.new_users, 0)                        as new_users,
        coalesce(g.page_views, 0)                       as page_views,
        coalesce(g.purchases, 0)                        as purchases,
        coalesce(g.revenue_usd, 0)                      as revenue_usd,
        coalesce(g.add_to_carts, 0)                     as add_to_carts,
        coalesce(g.checkouts, 0)                        as checkouts,

        -- Paid media metrics
        coalesce(p.paid_impressions, 0)                 as paid_impressions,
        coalesce(p.paid_clicks, 0)                      as paid_clicks,
        p.spend_zar,
        coalesce(p.paid_conversions, 0)                 as paid_conversions,
        p.paid_conversion_value_zar,
        p.avg_ctr,
        p.avg_cpc_zar,
        p.avg_roas,

        -- Derived KPIs
        safe_divide(g.purchases, g.sessions)            as session_conversion_rate,
        safe_divide(g.revenue_usd, g.sessions)          as revenue_per_session,
        safe_divide(p.spend_zar, g.purchases)           as cost_per_purchase_zar,
        safe_divide(g.checkouts, g.add_to_carts)        as cart_to_checkout_rate,
        safe_divide(g.purchases, g.checkouts)           as checkout_to_purchase_rate,

        -- Metadata
        current_timestamp()                             as _gold_loaded_at

    from ga4 g
    full outer join all_paid p
        on  g.report_date   = p.report_date
        and g.channel       = p.channel
        and coalesce(g.campaign_name,'') = coalesce(p.campaign_name,'')
        and coalesce(g.device,'')        = coalesce(p.device,'')
)

select * from joined
where report_date is not null
