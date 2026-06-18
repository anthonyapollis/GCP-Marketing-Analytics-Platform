{{
    config(
        materialized = 'incremental',
        unique_key   = ['date', 'campaign_id', 'ad_group_id', 'keyword_text', 'device', 'network'],
        partition_by = {'field': 'date', 'data_type': 'date'},
        cluster_by   = ['campaign_id'],
        tags = ['silver', 'google_ads', 'daily']
    )
}}

/*
  SILVER LAYER — stg_google_ads
  Source: marketing_bronze.google_ads_raw (via BQ Data Transfer: Google Ads connector)

  Cleaning performed:
    1. Deduplicate on natural key
    2. Parse cost_micros → cost in ZAR (divide by 1,000,000)
    3. Clamp negative impressions/clicks → NULL (data integrity errors from source)
    4. Normalise currency: ZAR variants → 'ZAR', USD variants → 'USD'
    5. Normalise device & network values to canonical set
    6. Calculate derived metrics: CTR, CPC, ROAS
    7. Normalise campaign status
*/

with

source as (
    select * from {{ source('bronze', 'google_ads_raw') }}
    {% if is_incremental() %}
        where _pipeline_date >= (select max(date) - interval 3 day from {{ this }})
    {% endif %}
),

deduped as (
    select *,
        row_number() over (
            partition by date, campaign_id, coalesce(ad_group_id,''), coalesce(keyword_text,''), coalesce(device,''), coalesce(network,'')
            order by _processed_at asc
        ) as _row_num
    from source
    where campaign_id is not null
),

cleaned as (
    select
        -- Date
        coalesce(
            safe.parse_date('%Y-%m-%d', date),
            safe.parse_date('%d/%m/%Y', date),
            safe.parse_date('%Y%m%d',   date)
        )                                                       as date,

        nullif(trim(customer_id), '')                          as customer_id,
        nullif(trim(campaign_id), '')                          as campaign_id,
        initcap(regexp_replace(nullif(trim(campaign_name),''), r'[_\-]+', ' '))
                                                               as campaign_name,

        -- Status
        case upper(trim(campaign_status))
            when 'ENABLED'  then 'ENABLED'
            when 'PAUSED'   then 'PAUSED'
            when 'REMOVED'  then 'REMOVED'
            else null
        end                                                     as campaign_status,

        nullif(trim(ad_group_id), '')                          as ad_group_id,
        nullif(trim(ad_group_name), '')                        as ad_group_name,
        lower(nullif(trim(keyword_text), ''))                  as keyword_text,

        case upper(trim(match_type))
            when 'EXACT'  then 'EXACT'
            when 'BROAD'  then 'BROAD'
            when 'PHRASE' then 'PHRASE'
            else null
        end                                                     as match_type,

        -- Metrics: clamp negatives → NULL
        case when safe_cast(impressions as int64) < 0 then null
             else safe_cast(impressions as int64) end           as impressions,
        case when safe_cast(clicks as int64) < 0 then null
             else safe_cast(clicks as int64) end                as clicks,

        -- cost_micros → ZAR (divide 1M)
        safe_cast(cost_micros as int64) / 1000000.0            as cost_zar,

        -- Normalise conversions
        safe_cast(conversions as float64)                      as conversions,
        case when safe_cast(conversion_value as float64) < 0 then null
             else safe_cast(conversion_value as float64) end    as conversion_value_zar,

        -- Currency normalise
        case
            when upper(trim(currency_code)) in ('ZAR','R','RSA') then 'ZAR'
            when upper(trim(currency_code)) = 'USD' then 'USD'
            else null
        end                                                     as currency_code,

        case lower(trim(device))
            when 'desktop' then 'desktop'
            when 'mobile'  then 'mobile'
            when 'tablet'  then 'tablet'
            else null
        end                                                     as device,

        case upper(trim(network))
            when 'SEARCH'  then 'SEARCH'
            when 'DISPLAY' then 'DISPLAY'
            when 'YOUTUBE' then 'YOUTUBE'
            else null
        end                                                     as network,

        nullif(trim(geo_target), '')                           as geo_target,

        -- Derived metrics
        safe_divide(safe_cast(clicks as int64), safe_cast(impressions as int64))
                                                               as ctr,
        safe_divide(safe_cast(cost_micros as int64)/1000000.0, safe_cast(clicks as int64))
                                                               as cpc_zar,
        safe_divide(safe_cast(conversion_value as float64), safe_cast(cost_micros as int64)/1000000.0)
                                                               as roas,

        _source, _pipeline_date, _processed_at,
        current_timestamp()                                     as _silver_loaded_at

    from deduped
    where _row_num = 1
)

select * from cleaned
where date is not null
  and campaign_id is not null
