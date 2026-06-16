{{
    config(
        materialized = 'incremental',
        unique_key   = ['session_id', 'event_timestamp', 'event_name'],
        partition_by = {'field': 'event_date', 'data_type': 'date'},
        cluster_by   = ['channel_medium', 'device_category'],
        on_schema_change = 'sync_all_columns',
        tags = ['silver', 'ga4', 'daily']
    )
}}

/*
  SILVER LAYER — stg_ga4_events
  Source: marketing_bronze.ga4_events_raw (loaded via BQ Data Transfer Service)

  Cleaning performed:
    1. Deduplicate rows on (session_id, event_timestamp, event_name)
    2. Parse & standardise date from mixed formats → DATE type
    3. Normalise geo_country to ISO 3166-1 alpha-2
    4. Normalise device_category to lowercase canonical set
    5. Normalise traffic channel values (remove caps/underscores/variants)
    6. Cast event_value_in_usd to FLOAT; negative values → NULL
    7. Filter out rows with NULL event_date or NULL user_pseudo_id
    8. Cast ga_session_number to INT; negative → NULL (data error)
    9. Derive is_first_session flag from ga_session_number
   10. Incremental load: only process new dates
*/

with

source as (
    select * from {{ source('bronze', 'ga4_events_raw') }}
    {% if is_incremental() %}
        where _pipeline_date >= (select max(event_date) - interval 3 day from {{ this }})
    {% endif %}
),

-- Step 1: Remove exact duplicates, keep first occurrence
deduped as (
    select *,
        row_number() over (
            partition by session_id, event_timestamp, event_name
            order by _processed_at asc
        ) as _row_num
    from source
    where session_id is not null
      and event_name is not null
),

-- Step 2–9: Clean, type, and standardise
cleaned as (
    select
        -- Keys
        user_pseudo_id,
        safe_cast(session_id as int64)                          as session_id,
        event_name,

        -- Date: try all known source formats, default to NULL
        coalesce(
            safe.parse_date('%Y-%m-%d',  event_date),
            safe.parse_date('%d/%m/%Y',  event_date),
            safe.parse_date('%d-%m-%Y',  event_date),
            safe.parse_date('%Y%m%d',    event_date),
            safe.parse_date('%B %d, %Y', event_date)
        )                                                       as event_date,

        -- Timestamp: valid 16-digit micros only
        case when length(trim(event_timestamp)) = 16
             then safe_cast(event_timestamp as int64)
             else null end                                      as event_timestamp_micros,

        -- Geo: normalise country to ISO code
        case
            when lower(trim(geo_country)) in ('south africa','rsa','za') then 'ZA'
            when lower(trim(geo_country)) in ('united states','us','usa')  then 'US'
            when lower(trim(geo_country)) in ('united kingdom','uk','gb')  then 'GB'
            when trim(geo_country) = ''  then null
            else upper(trim(geo_country))
        end                                                     as country_code,

        initcap(nullif(trim(geo_city), ''))                    as city,

        -- Device: canonical lowercase
        case
            when lower(trim(device_category)) in ('desktop','desk') then 'desktop'
            when lower(trim(device_category)) in ('mobile','mob')   then 'mobile'
            when lower(trim(device_category)) in ('tablet','tab')   then 'tablet'
            else null
        end                                                     as device_category,

        -- Channel: normalise medium
        case
            when regexp_contains(lower(trim(traffic_source_medium)), r'organic|natural') then 'Organic Search'
            when regexp_contains(lower(trim(traffic_source_medium)), r'cpc|paid|ppc')    then 'Paid Search'
            when regexp_contains(lower(trim(traffic_source_medium)), r'display|banner')  then 'Display'
            when regexp_contains(lower(trim(traffic_source_medium)), r'social|soc')      then 'Social'
            when regexp_contains(lower(trim(traffic_source_medium)), r'email|newsletter') then 'Email'
            when lower(trim(coalesce(traffic_source_medium,''))) in ('(none)','','direct') then 'Direct'
            else nullif(initcap(trim(traffic_source_medium)), '')
        end                                                     as channel_medium,

        lower(nullif(trim(traffic_source_source), ''))         as traffic_source,
        nullif(trim(traffic_source_name), '')                  as campaign_name,

        -- Page
        nullif(trim(page_location), '')                        as page_path,
        nullif(trim(page_title), '')                           as page_title,

        -- Value: negative = data error → NULL
        case
            when safe_cast(event_value_in_usd as float64) < 0 then null
            else safe_cast(event_value_in_usd as float64)
        end                                                     as event_value_usd,

        -- Session number: negative = error → NULL
        case
            when safe_cast(ga_session_number as int64) <= 0 then null
            else safe_cast(ga_session_number as int64)
        end                                                     as ga_session_number,

        -- First session flag derived from session number
        case when safe_cast(ga_session_number as int64) = 1 then true else false
        end                                                     as is_first_session,

        -- Boolean: normalise text booleans
        case
            when lower(trim(is_active_user)) in ('true','1','yes') then true
            when lower(trim(is_active_user)) in ('false','0','no')  then false
            else null
        end                                                     as is_active_user,

        upper(nullif(trim(platform), ''))                      as platform,
        nullif(trim(stream_id), '')                            as stream_id,

        -- Metadata
        _source,
        _pipeline_date,
        _processed_at,
        current_timestamp()                                     as _silver_loaded_at

    from deduped
    where _row_num = 1
      and user_pseudo_id is not null
),

-- Step 10: Drop rows where cleaned date is still NULL
final as (
    select * from cleaned
    where event_date is not null
)

select * from final
