{{ config(
    materialized='table',
    indexes=[
        {'columns': ['server_name']},
        {'columns': ['match_id']},
    ],
    post_hook=[
        "drop index if exists analytics_analytics.ix_fct_serves_server_bp",
        "create index ix_fct_serves_server_bp on {{ this }} (server_name) where is_break_point",
    ]
) }}

-- ============================================================================
--  INDEXES -- measured, not guessed.
--
--  A typical agent query (one player, first serves, break points) seq-scanned
--  the whole 706 MB table: 90,482 buffers, 402 rows kept out of 2.58M.
--
--    no index                                     384 ms   90,482 buffers
--    btree (server_name)                          290 ms    3,163 buffers
--    partial (server_name) where is_break_point   1.9 ms    1,035 buffers
--
--  The partial index wins by 200x, and the reason is heap fetches rather than
--  column selectivity. server_name is the more selective column (0.9% vs 9.2%),
--  but a plain index on it still pulls all 23,821 of that player's serves into
--  the heap before filtering. The partial index only CONTAINS break-point rows,
--  so it touches 1,663. Pre-filtering the index beats narrowing the lookup.
--
--  Partial indexes need a post_hook: dbt's `indexes` config has no WHERE
--  clause. Both kinds are asserted by tests/assert_indexes_exist.sql, because
--  an index is state dbt does not consider part of the model's contract -- it
--  can vanish and the build stays green. (lesson 010)
-- ============================================================================

-- ============================================================================
--  fct_serves -- TRUE SERVE GRAIN. One row per serve struck, faults included.
--
--  fct_points is one row per POINT and holds both serves side by side.
--  This model unpivots that into one row per SERVE, which is the grain every
--  serve question actually has:
--
--    "what is his first-serve percentage"        -> a filter, not a ratio of ratios
--    "where does he miss his first serve"        -> impossible at point grain
--    "does he change placement on the second"    -> a GROUP BY serve_number
--
--  A point contributes one row if the first serve landed, two if it faulted.
--  Double faults contribute two rows, both with landed = false.
--
--  Coverage (2020s): 99.78% of faulted first serves yield a direction and
--  99.75% a fault type. The remainder are charted as a bare error letter
--  ('n' with no direction) -- real data, left as NULL.
-- ============================================================================

with points as (

    select * from {{ ref('fct_points') }}

),

first_serves as (

    select
        point_key,
        match_id, point_number, game_number,
        server_name, returner_name, server_hand, returner_hand,
        court_side, pressure, is_break_point, is_game_point, is_deuce,
        is_tiebreak_set, point_score,
        server_won_point, rally_length, rally_bucket,
        tournament, round, match_date, tour, surface, parse_confidence,

        1                           as serve_number,
        first_serve_direction       as serve_direction,
        is_first_serve_in           as landed,
        first_serve_fault_type      as fault_type
    from points

),

second_serves as (

    select
        point_key,
        match_id, point_number, game_number,
        server_name, returner_name, server_hand, returner_hand,
        court_side, pressure, is_break_point, is_game_point, is_deuce,
        is_tiebreak_set, point_score,
        server_won_point, rally_length, rally_bucket,
        tournament, round, match_date, tour, surface, parse_confidence,

        2                           as serve_number,
        second_serve_direction      as serve_direction,
        -- A second serve landed unless it carries a fault letter. Note this is
        -- NOT "second_serve_notation is null" -- the notation is present either
        -- way; what distinguishes a double fault is the error code.
        second_serve_fault_type is null AS landed,
        second_serve_fault_type     as fault_type
    from points
    where not is_first_serve_in     -- a second serve exists only after a fault

)

select
    {{ dbt_utils.generate_surrogate_key(['point_key', 'serve_number']) }}
        as serve_key,
    *
from (
    select * from first_serves
    union all
    select * from second_serves
) s
