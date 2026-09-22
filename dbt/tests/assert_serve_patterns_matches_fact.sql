-- DRIFT TEST for the option-C pair.
--
-- Keeping a fact table AND a pre-aggregate beside it buys convenience and costs
-- the risk they silently disagree -- someone edits a filter in one and not the
-- other, and the agent gives two different answers to the same question
-- depending on which table it reached for. This recomputes the aggregate from
-- the fact table and fails on any difference.
--
-- WHY `EXCEPT` AND NOT A JOIN
--
-- The obvious implementation is a FULL OUTER JOIN on the grain columns. Two
-- problems, both hit on the way here:
--
--   1. `=` is not NULL-safe. NULL = NULL is never true, so a matched pair with
--      a NULL key is reported as two unmatched rows. This test failed that way
--      on its first run (server_name is NULL for orphan points).
--   2. `IS NOT DISTINCT FROM` fixes that but Postgres refuses it in a FULL
--      JOIN: "only supported with merge-joinable or hash-joinable conditions".
--
-- `EXCEPT` sidesteps both. It compares entire rows, treats NULLs as equal, and
-- asks the question directly: is either side holding a row the other isn't?
--
-- dbt singular test: any returned row fails the build.

with mart as (

    select
        server_name, court_side, pressure, serve_number, parse_confidence,
        serves, serves_with_direction, wide_serves, body_serves, t_serves, faults
    from {{ ref('mart_serve_patterns') }}

),

recomputed as (

    select
        server_name, court_side, pressure, serve_number, parse_confidence,
        count(*)                                         as serves,
        count(serve_direction)                           as serves_with_direction,
        count(*) filter (where serve_direction = 'wide') as wide_serves,
        count(*) filter (where serve_direction = 'body') as body_serves,
        count(*) filter (where serve_direction = 'T')    as t_serves,
        count(*) filter (where not landed)               as faults
    from {{ ref('fct_serves') }}
    where court_side is not null
      and server_name is not null
    group by 1, 2, 3, 4, 5

),

in_mart_only as (
    select 'in_mart_not_fact' as side, * from (
        select * from mart except select * from recomputed
    ) a
),

in_fact_only as (
    select 'in_fact_not_mart' as side, * from (
        select * from recomputed except select * from mart
    ) b
)

select * from in_mart_only
union all
select * from in_fact_only
