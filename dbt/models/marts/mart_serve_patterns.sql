{{ config(materialized='table') }}

-- NOT INDEXED, deliberately. 29,294 rows in 6.7 MB -- a sequential scan reads
-- the whole thing in about a millisecond, and the planner would ignore an index
-- anyway (same reason dim_players' trigram index goes unused at 1,739 rows).
-- An index here would cost rebuild time and storage to buy nothing. Revisit if
-- the grain gets finer.

-- ============================================================================
--  mart_serve_patterns -- PRE-AGGREGATED. The other half of the option-C pair.
--
--    fct_serves           one row per serve  -- slice it any way a question needs
--    mart_serve_patterns  (this)             -- statistics computed once, tested
--
--  Grain: (server, court_side, pressure, serve_number, parse_confidence).
--
--  Everything an LLM gets subtly wrong lives here: shares, denominators, and
--  serve_direction_entropy. Drift between the two is caught by
--  assert_serve_patterns_matches_fact -- that test is why keeping both is safe.
--
--  Answers questions.yml #1 and #9 with a filter instead of an aggregation.
--  Reference data for T3, T4, T5 in lessons/hypotheses-tennis.md.
--
-- ----------------------------------------------------------------------------
--  HOW THE AGGREGATION WORKS -- two different GROUP BYs, on purpose.
--
--  Entropy needs each direction's SHARE of its group, so it takes three passes:
--
--    by_direction  GROUP BY (server, court, pressure, serve#, conf, DIRECTION)
--                  -> one row per direction: how many serves went there
--
--    with_shares   SUM(...) OVER (PARTITION BY everything-except-direction)
--                  -> staple the group total onto each row WITHOUT collapsing.
--                     This step is a window function, not a GROUP BY. GROUP BY
--                     reduces; OVER annotates.
--
--    entropy       GROUP BY (server, court, pressure, serve#, conf)
--                  -> collapse the 1-3 direction rows into one, summing
--                     -p*ln(p) across them
--
--  As a single conditional aggregate, entropy would be three hand-written terms
--  with three zero-guards. This generalises to k buckets.
--
--  DENOMINATORS (spec: direction is optional): shares divide by
--  serves_with_direction, never by serves. Both are exposed.
-- ============================================================================

with serves as (

    select * from {{ ref('fct_serves') }}
    where court_side is not null      -- tiebreak points have no deuce/ad side
      -- ~500 serves belong to points whose match row is missing upstream (the
      -- same gap the stg_points relationships test warns about). A serve with
      -- no resolvable server cannot answer any question, so it is dropped here
      -- rather than aggregated into a NULL-named bucket. The fact table keeps
      -- them; the curated view does not.
      and server_name is not null

),

-- Every serve struck, including those with no direction charted. Computed
-- BEFORE the direction filter below, or the denominator is not honest.
totals as (

    select
        server_name, court_side, pressure, serve_number, parse_confidence,
        count(*)                                    as serves,
        count(serve_direction)                      as serves_with_direction,
        count(distinct match_id)                    as matches,
        avg(landed::int)                            as landed_rate,
        avg(server_won_point::int)                  as server_win_rate,

        -- How he misses. Only meaningful on the rows where a serve faulted,
        -- which is why these are counts, not rates -- the agent divides by
        -- faults, and faults is right here.
        count(*) filter (where not landed)                             as faults,
        count(*) filter (where fault_type = 'net')                     as faults_net,
        count(*) filter (where fault_type = 'deep')                    as faults_deep,
        count(*) filter (where fault_type = 'wide')                    as faults_wide,
        count(*) filter (where fault_type = 'wide_and_deep')           as faults_wide_deep
    from serves
    group by 1, 2, 3, 4, 5

),

-- PASS 1: one row per direction within each group.
by_direction as (

    select
        server_name, court_side, pressure, serve_number, parse_confidence,
        serve_direction,
        count(*) as serves
    from serves
    where serve_direction is not null
    group by 1, 2, 3, 4, 5, 6

),

-- PASS 2: annotate with the group total. Rows survive, so each can compute its
-- own share against it.
with_shares as (

    select
        *,
        serves::numeric / sum(serves) over (
            partition by server_name, court_side, pressure,
                         serve_number, parse_confidence
        ) as p
    from by_direction

),

-- PASS 3: collapse directions into one row per group.
entropy as (

    select
        server_name, court_side, pressure, serve_number, parse_confidence,

        max(serves) filter (where serve_direction = 'wide') as wide_serves,
        max(serves) filter (where serve_direction = 'body') as body_serves,
        max(serves) filter (where serve_direction = 'T')    as t_serves,

        max(p) filter (where serve_direction = 'wide')      as wide_share,
        max(p) filter (where serve_direction = 'body')      as body_share,
        max(p) filter (where serve_direction = 'T')         as t_share,

        -- -SUM(p ln p) normalised by ln(3), so it lands in [0, 1].
        --   1.00 = evenly split across wide/body/T -- unreadable
        --   0.00 = every serve to the same spot
        -- ln(3::numeric) because ln(3) is double precision and Postgres has no
        -- two-argument round() for double (errors E1).
        (-sum(p * ln(p))) / ln(3::numeric)                  as entropy_raw,

        -- An entropy of 0 from one direction means something different from an
        -- entropy of 0 across three. Carry the count so the caveat is possible.
        count(*)                                            as directions_used

    from with_shares
    group by 1, 2, 3, 4, 5

)

select
    t.server_name,
    t.court_side,
    t.pressure,
    t.serve_number,
    t.parse_confidence,

    t.matches,
    t.serves,
    t.serves_with_direction,
    round(t.serves_with_direction::numeric / nullif(t.serves, 0), 4)
                                                    as direction_charted_rate,

    coalesce(e.wide_serves, 0)                      as wide_serves,
    coalesce(e.body_serves, 0)                      as body_serves,
    coalesce(e.t_serves, 0)                         as t_serves,

    round(e.wide_share, 4)                          as wide_share,
    round(e.body_share, 4)                          as body_share,
    round(e.t_share, 4)                             as t_share,

    round(e.entropy_raw, 4)                         as serve_direction_entropy,
    e.directions_used,

    round(t.landed_rate::numeric, 4)                as landed_rate,
    round(t.server_win_rate::numeric, 4)            as server_win_rate,

    t.faults,
    t.faults_net,
    t.faults_deep,
    t.faults_wide,
    t.faults_wide_deep

from totals t
left join entropy e
       on  t.server_name      = e.server_name
       and t.court_side       = e.court_side
       and t.pressure         = e.pressure
       and t.serve_number     = e.serve_number
       and t.parse_confidence = e.parse_confidence
