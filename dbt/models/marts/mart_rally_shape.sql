{{ config(
    materialized='table',
    indexes=[
      {'columns': ['player_name']},
      {'columns': ['player_name', 'surface']},
    ]
) }}

-- ============================================================================
--  mart_rally_shape -- how a player's win rate moves with rally length.
--
--  Reference data for T1 (Federer is a first-striker, Nadal is a grinder) and
--  questions.yml #3 and #4.
--
-- ----------------------------------------------------------------------------
--  THE ONE THING THIS MART EXISTS TO PREVENT
--
--  T1's finding was NOT "Federer wins 54% of short points". It was that his win
--  rate FALLS as rallies lengthen while Nadal's RISES. The level is mostly
--  opponent quality -- these players beat people, so everyone sits near .53.
--  Only the within-player slope is interpretable.
--
--  An LLM handed bucket win rates will compare levels across players, confidently
--  and wrongly. So `win_rate_slope` is computed here, in tested SQL, and the
--  column description says what it means. Precomputing it is the only reliable
--  way to stop the comparison that doesn't work.
--
--  The slope uses regr_slope(win_rate, bucket_ordinal) -- Postgres's
--  least-squares aggregate -- over the player's bucket rows. Negative = wins more
--  on short points (first-striker). Positive = wins more on long ones (grinder).
--  A simple last-minus-first difference would throw away the middle buckets and
--  is noisier on thin samples.
--
-- ----------------------------------------------------------------------------
--  TRAPS HANDLED HERE
--
--  1. RALLY LENGTH IS PARSED, so it inherits the parser's accuracy: ~90% on
--     2020s matches, ~55% pre-2010 (lesson 004). Rates are computed over
--     high+medium confidence ONLY, and `points_low_confidence` reports what was
--     excluded so the omission is visible rather than silent.
--
--  2. SURFACE MATTERS ENORMOUSLY for exactly this metric -- it is what dissolved
--     two of six apparent Alcaraz trends (T10). Emitted per-surface AND pooled,
--     via GROUPING SETS, so the agent never re-aggregates a rate.
--
--  3. BOTH PLAYERS PLAY EVERY POINT. fct_points is server-oriented, so each
--     point is unpivoted to two rows -- a point is jointly produced, and "rally
--     shape for Nadal" means points he was in, serving or returning.
-- ============================================================================

with per_player_point as (

    -- One row per (point, player). Upstream is server-oriented; rally shape is a
    -- property of the player, not of the serve.
    select
        server_name   as player_name,
        returner_name as opponent_name,
        server_won_point as won_point,
        rally_length, rally_bucket, surface, parse_confidence, match_id
    from {{ ref('fct_points') }}
    where rally_bucket is not null

    union all

    select
        returner_name as player_name,
        server_name   as opponent_name,
        not server_won_point as won_point,
        rally_length, rally_bucket, surface, parse_confidence, match_id
    from {{ ref('fct_points') }}
    where rally_bucket is not null

),

scoped as (

    -- 305 points reference a match_id absent from the matches file (the upstream
    -- points/matches split is not perfectly in sync, plus the 11 rows the loader
    -- rejects on field count). fct_points LEFT JOINs to matches, so those arrive
    -- with a NULL player. A rally-shape row for an unknown player is meaningless,
    -- and the not_null test on player_name is what surfaced it.
    select
        player_name,
        coalesce(surface, 'Unknown') as surface,
        rally_bucket,
        -- Ordinal for the regression. rally_bucket is a label, and regr_slope
        -- needs a number; the 1..4 spacing treats the buckets as evenly spaced,
        -- which is an approximation (they are 3/3/3/open) but a monotone one.
        case rally_bucket when '1-3' then 1 when '4-6' then 2
                          when '7-9' then 3 when '10+' then 4 end as bucket_ordinal,
        won_point,
        rally_length,
        opponent_name,
        match_id,
        parse_confidence in ('high', 'medium') as is_scoreable
    from per_player_point
    where player_name is not null

),

bucketed as (

    select
        player_name,
        surface,
        rally_bucket,
        min(bucket_ordinal)                                        as bucket_ordinal,
        grouping(surface)                                          as _surface_rolled,

        count(*)                                                   as points_total,
        count(*) filter (where is_scoreable)                        as points,
        count(*) filter (where not is_scoreable)                    as points_low_confidence,
        count(distinct opponent_name) filter (where is_scoreable)   as opponents_faced,
        count(distinct match_id) filter (where is_scoreable)        as matches,

        count(*) filter (where is_scoreable and won_point)          as points_won,
        avg(rally_length) filter (where is_scoreable)               as avg_rally_length

    from scoped
    group by grouping sets ((player_name, surface, rally_bucket), (player_name, rally_bucket))

),

rated as (

    select
        *,
        points_won::numeric / nullif(points, 0)                     as win_rate,
        -- Share of this player's points (at this surface level) in this bucket.
        -- The window partition must match the grouping-set level, or a pooled row
        -- would divide by a per-surface total.
        points::numeric
          / nullif(sum(points) over (partition by player_name, surface, _surface_rolled), 0)
                                                                    as share_of_points
    from bucketed

),

-- regr_slope is an aggregate over the bucket ROWS, so it needs its own pass at
-- the player level, then joins back.
slopes as (

    select
        player_name,
        surface,
        _surface_rolled,
        -- regr_* return double precision, and Postgres has no two-argument
        -- round() for double -- only for numeric. Cast here rather than at the
        -- call site so every consumer gets the same type. (errors E1, third
        -- time this class has bitten.)
        regr_slope(win_rate, bucket_ordinal)::numeric                as win_rate_slope,
        regr_r2(win_rate, bucket_ordinal)::numeric                   as slope_r2,
        sum(points)                                                 as player_points,
        count(*) filter (where points >= 20)                        as buckets_with_20_plus
    from rated
    where win_rate is not null
    group by 1, 2, 3

)

select
    r.player_name,
    case when r._surface_rolled = 1 then null else r.surface end    as surface,
    case when r._surface_rolled = 1 then 'player' else 'player_surface' end
                                                                    as shape_grain,
    r.rally_bucket,
    r.bucket_ordinal,

    r.matches,
    r.opponents_faced,
    r.points,
    r.points_low_confidence,
    r.points_won,
    round(r.win_rate, 4)                                            as win_rate,
    round(r.share_of_points, 4)                                     as share_of_points,
    round(r.avg_rally_length, 2)                                    as avg_rally_length,

    s.player_points,
    round(s.win_rate_slope, 5)                                      as win_rate_slope,
    round(s.slope_r2, 4)                                            as slope_r2,
    s.buckets_with_20_plus

from rated r
left join slopes s
       on  r.player_name = s.player_name
       -- `is not distinct from`, NOT `=`. GROUPING SETS sets `surface` to NULL on
       -- rolled-up rows, and NULL = NULL evaluates to NULL, not true -- so `=`
       -- silently matches nothing and every pooled row gets a NULL slope. The
       -- build still succeeds. Same three-valued-logic trap as errors E6, wearing
       -- a join key instead of a CASE branch.
       and r.surface is not distinct from s.surface
       and r._surface_rolled = s._surface_rolled
