{{ config(
    materialized='table',
    indexes=[
      {'columns': ['player_name']},
      {'columns': ['player_name', 'surface']},
    ]
) }}

-- ============================================================================
--  mart_player_style -- one style vector per (player, season, surface).
--
--  The shared substrate under three features: player evolution (T10), style
--  similarity (T9) and analogical scouting (mart_matchup). Build the grain once,
--  project it three ways. Feeds pgvector via emb_player_style.
--
-- ----------------------------------------------------------------------------
--  WHAT THIS MART IS NOT
--
--  Not z-scored. Standardisation depends on the comparison population, and T9's
--  first attempt returned Ana Ivanovic as Federer's nearest neighbour because
--  ATP and WTA were standardised together. The population is a property of the
--  QUESTION, so z-scoring belongs to the consumer (emb_player_style), never here.
--  This mart emits rates and the counts behind them.
--
-- ----------------------------------------------------------------------------
--  SOURCES: every count comes from int_player_match_style, which also holds
--  the oracle rule and the ShotTypes leaf-row findings. Read it first.
--
-- ----------------------------------------------------------------------------
--  TRAPS THE PLUMBING HANDLES
--
--  1. SURFACE IS PART OF THE GRAIN, not a filter. Controlling for it dissolved
--     two of six apparent Alcaraz trends (T10). No pooled-surface rows: a pooled
--     rate silently averages over a surface MIX that changes season to season.
--  2. CHARTING COVERAGE RIDES ALONG. T10's inside-out "decline" sat exactly
--     inside a window where direction coverage fell .943 -> .797 as the dominant
--     charter changed. The observation process has its own time series, so
--     dominant_charter and direction_charted_rate are on every row.
--  3. EVERY RATE HAS ITS DENOMINATOR. Direction is optional in the spec, so the
--     direction denominator is directed shots, not shots (CLAUDE.md landmines).
--  4. PARSE CONFIDENCE is a function of season (charting era), so it needs no
--     extra grouping key -- it is carried as a column, never averaged away.
-- ============================================================================

with counts as (

    -- Sum the per-(match, player) counts to the grain. Every count is defined
    -- once, in int_player_match_style, and mart_matchup sums the same rows.
    select
        player_name,
        season,
        surface,
        min(tour)                                                   as tour,
        min(parse_confidence)                                       as parse_confidence,
        count(distinct match_id)                                    as matches,

        sum(shots) as shots, sum(fh_drives) as fh_drives, sum(bh_drives) as bh_drives,
        sum(fh_slices) as fh_slices, sum(bh_slices) as bh_slices,
        sum(volleys) as volleys, sum(overheads) as overheads,
        sum(drop_shots) as drop_shots, sum(lobs) as lobs,
        sum(half_volleys) as half_volleys, sum(swinging_volleys) as swinging_volleys,
        sum(net_shots) as net_shots,
        sum(fh_side_shots) as fh_side_shots, sum(bh_side_shots) as bh_side_shots,
        sum(winners) as winners, sum(unforced_errors) as unforced_errors,
        sum(induced_forced_errors) as induced_forced_errors,
        sum(point_ending_shots) as point_ending_shots,
        sum(fh_winners) as fh_winners, sum(fh_unforced_errors) as fh_unforced_errors,
        sum(bh_winners) as bh_winners, sum(bh_unforced_errors) as bh_unforced_errors,

        sum(fh_directed) as fh_directed, sum(fh_crosscourt) as fh_crosscourt,
        sum(fh_down_middle) as fh_down_middle, sum(fh_down_the_line) as fh_down_the_line,
        sum(fh_inside_out) as fh_inside_out, sum(fh_inside_in) as fh_inside_in,
        sum(bh_directed) as bh_directed, sum(bh_crosscourt) as bh_crosscourt,
        sum(bh_down_middle) as bh_down_middle, sum(bh_down_the_line) as bh_down_the_line,
        sum(bh_inside_out) as bh_inside_out, sum(bh_inside_in) as bh_inside_in,

        sum(first_serves) as first_serves, sum(first_serves_in) as first_serves_in,
        sum(first_serves_directed) as first_serves_directed,
        sum(deuce_wide) as deuce_wide, sum(deuce_body) as deuce_body, sum(deuce_t) as deuce_t,
        sum(ad_wide) as ad_wide, sum(ad_body) as ad_body, sum(ad_t) as ad_t,

        sum(points) as points, sum(points_won) as points_won,
        sum(serve_points) as serve_points, sum(serve_points_won) as serve_points_won,
        sum(return_points) as return_points, sum(return_points_won) as return_points_won,
        sum(points_rally_scoreable) as points_rally_scoreable,
        sum(rally_length_sum) as rally_length_sum

    from {{ ref('int_player_match_style') }}
    group by 1, 2, 3

),

coverage as (

    select player_name, surface, season,
           dominant_charter, charters_involved, direction_charted_rate
    from {{ ref('mart_data_coverage') }}
    where coverage_grain = 'player_surface_season'

),

features as (

    -- The style vector. Written by Claude at Kyle's request; the reasons are
    -- below so they can be reviewed, not just read.
    --
    -- RULE 1, STYLE NOT OUTCOME. No points won, no serve or return points won,
    -- no winner/error ratio. Those measure how GOOD a player is. With them in,
    -- "plays like Federer" means "is as good as Federer".
    -- One exception, on purpose: point_ending_rate. Good players end more
    -- points, so it carries some quality. It stays because it is the
    -- first-strike signal from T1. Remove it if similarity results say so.
    --
    -- RULE 2, ONE CONCEPT, ONE FEATURE. T9's vector was mostly reading slice,
    -- because it had two slice features. Here slice appears once, as the
    -- one-hander proxy. The five direction categories sum to 1, so only two
    -- per wing go in -- the rest are implied.
    --
    -- RULE 3, EVERY RATE OVER ITS OWN DENOMINATOR, and that n is a column.
    -- Forehand direction over fh_directed, backhand over bh_directed, never
    -- the sum (T10 made that mistake).
    --
    -- Serve entropy uses the SAME formula as mart_serve_patterns:
    -- -sum(p * ln p) / ln 3, so 0 = one direction always, 1 = uniform. Two
    -- marts with two entropy definitions would disagree without any error.
    --
    -- Thin cells are NOT filtered. `matches` and the n columns let the
    -- consumer filter. questions.yml calls N < 20 thin.
    --
    -- The rate FORMULAS live in macros/style_rates.sql, shared with
    -- mart_matchup. This CTE chooses the n columns that go beside them.
    select
        player_name, season, surface, tour, parse_confidence,
        matches,

        -- Denominators. Each rate's n is named in its yml description.
        shots,
        fh_drives + bh_drives                                       as drives,
        bh_side_shots,
        -- Two direction denominators, never summed. `+` would also turn NULL
        -- when one wing has no rows -- 3 cells measured.
        fh_directed,
        bh_directed,
        first_serves,
        first_serves_directed,
        -- Serves with a direction AND a court side. first_serves_directed also
        -- counts 59,048 tiebreak first serves, where court side is NULL by
        -- design (E19), and those cannot go into a per-side rate.
        deuce_wide + deuce_body + deuce_t                           as deuce_sided,
        ad_wide + ad_body + ad_t                                    as ad_sided,
        -- Rally length is our parse, high + medium confidence only (lesson 004).
        points_rally_scoreable,

{{ style_rates() }}
    from counts

)

select
    f.*,

    -- The observation process, beside the observations (T10).
    cov.dominant_charter,
    cov.charters_involved,
    cov.direction_charted_rate

from features f
left join coverage cov
     on  cov.player_name = f.player_name
     and cov.surface = f.surface
     and cov.season = f.season
