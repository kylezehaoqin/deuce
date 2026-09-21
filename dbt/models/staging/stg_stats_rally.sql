-- ORACLE model -- Sackmann's own rally-length aggregation.
--
-- Not for analysis. It exists so our parser can be diffed against an independent
-- implementation of the same spec, on every `dbt build`.
-- See dbt/tests/assert_rally_length_matches_oracle.sql and lessons/004.
--
-- Upstream `row` packs two dimensions into one string: the rally-length bucket
-- and (optionally) the serve number. '7-9-2' = rallies of 7-9 shots on second
-- serve. Splitting them here is exactly the staging layer's job -- every
-- consumer would otherwise re-derive the same string surgery.

with source as (

    select * from {{ source('raw', 'mcp_stats_rally') }}

),

renamed as (

    select
        match_id,
        server                     as server_name,
        returner                   as returner_name,
        row_label,

        case
            when row_label = 'Total'              then 'total'
            when row_label ~ '^(1-3|4-6|7-9|10)$' then 'all_serves'
            when row_label ~ '-1$'                then 'first_serve'
            when row_label ~ '-2$'                then 'second_serve'
        end                        as serve_split,

        case
            when row_label = 'Total'   then null
            when row_label like '1-3%' then '1-3'
            when row_label like '4-6%' then '4-6'
            when row_label like '7-9%' then '7-9'
            when row_label like '10%'  then '10+'
        end                        as rally_bucket,

        nullif(pts, '')::int       as points,
        _source_file,
        _loaded_at

    from source

)

select * from renamed
