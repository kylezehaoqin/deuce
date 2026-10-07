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
--  SOURCES, and the oracle rule (docs/marts.md §6)
--
--  Shot mix and error profile come from stg_stats_shot_types -- Sackmann's
--  ShotTypes ORACLE. Allowed today because no mart parses shot types yet. The
--  moment fct_shots exists and is validated against ShotTypes, this mart must
--  switch to reading fct_shots, or the validation becomes circular. That
--  decision is written into the model description so it cannot be forgotten.
--
--  Direction comes from stg_stats_shot_direction (also an oracle; same rule).
--  Serve placement and rally length come from OUR parse (fct_serves, fct_points).
--
-- ----------------------------------------------------------------------------
--  SHOTTYPES ROLL-UP ROWS LIE. Use leaf rows only.
--
--  Measured over 23,604 player-matches:
--
--    Fgs = F + R      99.97%    Vo = V + Z    99.97%    Hv = H + I   100%
--    Bgs = B + S      99.97%    Dr = U + Y    99.98%    Sw = J + K   100%
--    Net = V Z O P H I J K  99.99%           Lo = L + M    99.99%
--
--    Gs  = F + B      99.96%   <- NOT Fgs + Bgs (0.3%). "Groundstroke" means
--                                 drives only; slices are excluded. Name trap.
--    Sl  = R + S      91.7%    <- short in 8.3% of matches, reason unknown
--    Total = sum(leaves) 95.1%, mean gap 0.13 shots -- usable, but we sum the
--                                 leaves ourselves so every denominator is ours.
--
--  So every family below is summed from the 17 leaf codes, and the roll-up rows
--  are never read. A definition we derived is one we can state.
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

with matches as (

    select
        match_id,
        extract(year from match_date)::int          as season,
        coalesce(surface, 'Unknown')                as surface,
        tour,
        {{ mcp_parse_confidence('match_date') }}    as parse_confidence
    from {{ ref('stg_matches') }}
    where match_date is not null

),

-- ----------------------------------------------------------------------------
--  Shot mix and error profile, from ShotTypes LEAF rows.
-- ----------------------------------------------------------------------------

shot_types as (

    select
        match_id,
        player_name,
        sum(shots) filter (where row_label in
            ('F','B','R','S','V','Z','O','P','U','Y','L','M','H','I','J','K','T'))
                                                                    as shots,
        sum(shots) filter (where row_label = 'F')                    as fh_drives,
        sum(shots) filter (where row_label = 'B')                    as bh_drives,
        sum(shots) filter (where row_label = 'R')                    as fh_slices,
        sum(shots) filter (where row_label = 'S')                    as bh_slices,
        sum(shots) filter (where row_label in ('V','Z'))             as volleys,
        sum(shots) filter (where row_label in ('O','P'))             as overheads,
        sum(shots) filter (where row_label in ('U','Y'))             as drop_shots,
        sum(shots) filter (where row_label in ('L','M'))             as lobs,
        sum(shots) filter (where row_label in ('H','I'))             as half_volleys,
        sum(shots) filter (where row_label in ('J','K'))             as swinging_volleys,
        -- Net = the volley family, verified 99.99% against his Net row.
        sum(shots) filter (where row_label in ('V','Z','O','P','H','I','J','K'))
                                                                    as net_shots,
        -- Backhand SIDE = everything hit off the backhand, for T9's one-hander
        -- proxy (bh_slices / bh_side_shots).
        sum(shots) filter (where row_label in ('B','S','Z','P','Y','M','I','K'))
                                                                    as bh_side_shots,
        sum(shots) filter (where row_label in ('F','R','V','O','U','L','H','J'))
                                                                    as fh_side_shots,

        sum(winners) filter (where row_label in
            ('F','B','R','S','V','Z','O','P','U','Y','L','M','H','I','J','K','T'))
                                                                    as winners,
        sum(unforced_errors) filter (where row_label in
            ('F','B','R','S','V','Z','O','P','U','Y','L','M','H','I','J','K','T'))
                                                                    as unforced_errors,
        sum(induced_forced_errors) filter (where row_label in
            ('F','B','R','S','V','Z','O','P','U','Y','L','M','H','I','J','K','T'))
                                                                    as induced_forced_errors,
        sum(point_ending_shots) filter (where row_label in
            ('F','B','R','S','V','Z','O','P','U','Y','L','M','H','I','J','K','T'))
                                                                    as point_ending_shots,
        sum(winners)         filter (where row_label = 'F')          as fh_winners,
        sum(unforced_errors) filter (where row_label = 'F')          as fh_unforced_errors,
        sum(winners)         filter (where row_label = 'B')          as bh_winners,
        sum(unforced_errors) filter (where row_label = 'B')          as bh_unforced_errors
    from {{ ref('stg_stats_shot_types') }}
    group by 1, 2

),

-- ----------------------------------------------------------------------------
--  Direction, from ShotDirection. F and B rows (drives); see lesson 005 for
--  what Sackmann's scope counts. Denominator is DIRECTED shots.
-- ----------------------------------------------------------------------------

directions as (

    select
        match_id,
        player_name,
        sum(directed_shots)  filter (where row_label = 'F')          as fh_directed,
        sum(crosscourt)      filter (where row_label = 'F')          as fh_crosscourt,
        sum(down_middle)     filter (where row_label = 'F')          as fh_down_middle,
        sum(down_the_line)   filter (where row_label = 'F')          as fh_down_the_line,
        sum(inside_out)      filter (where row_label = 'F')          as fh_inside_out,
        sum(inside_in)       filter (where row_label = 'F')          as fh_inside_in,
        sum(directed_shots)  filter (where row_label = 'B')          as bh_directed,
        sum(crosscourt)      filter (where row_label = 'B')          as bh_crosscourt,
        sum(down_middle)     filter (where row_label = 'B')          as bh_down_middle,
        sum(down_the_line)   filter (where row_label = 'B')          as bh_down_the_line,
        sum(inside_out)      filter (where row_label = 'B')          as bh_inside_out,
        sum(inside_in)       filter (where row_label = 'B')          as bh_inside_in
    from {{ ref('stg_stats_shot_direction') }}
    group by 1, 2

),

-- ----------------------------------------------------------------------------
--  Serve placement, from our own parse. FIRST serves only: second-serve
--  placement is mostly "get it in", so pooling the two dilutes intent.
--  Faulted first serves are INCLUDED -- direction is where he aimed, which is
--  the style question. Split by court side because wide/T mean different
--  tactics on each. Direction values are 'wide' | 'body' | 'T' -- uppercase T;
--  a lowercase 't' matches nothing and silently zeroes every T count.
-- ----------------------------------------------------------------------------

serves as (

    select
        match_id,
        server_name                                                 as player_name,
        count(*)                                                    as first_serves,
        count(*) filter (where landed)                              as first_serves_in,
        count(*) filter (where serve_direction is not null)         as first_serves_directed,
        count(*) filter (where court_side = 'deuce' and serve_direction = 'wide') as deuce_wide,
        count(*) filter (where court_side = 'deuce' and serve_direction = 'body') as deuce_body,
        count(*) filter (where court_side = 'deuce' and serve_direction = 'T')    as deuce_t,
        count(*) filter (where court_side = 'ad'    and serve_direction = 'wide') as ad_wide,
        count(*) filter (where court_side = 'ad'    and serve_direction = 'body') as ad_body,
        count(*) filter (where court_side = 'ad'    and serve_direction = 'T')    as ad_t
    from {{ ref('fct_serves') }}
    where serve_number = 1
    group by 1, 2

),

-- ----------------------------------------------------------------------------
--  Points and rally length, from our own parse. Rally length is scoped to
--  high+medium confidence (lesson 004) -- points_rally_scoreable is its n.
-- ----------------------------------------------------------------------------

points as (

    select match_id, server_name as player_name,
           true as on_serve, server_won_point as won, rally_length, parse_confidence
    from {{ ref('fct_points') }}
    union all
    select match_id, returner_name, false, not server_won_point, rally_length, parse_confidence
    from {{ ref('fct_points') }}

),

point_counts as (

    select
        match_id,
        player_name,
        count(*)                                                    as points,
        count(*) filter (where won)                                 as points_won,
        count(*) filter (where on_serve)                            as serve_points,
        count(*) filter (where on_serve and won)                    as serve_points_won,
        count(*) filter (where not on_serve)                        as return_points,
        count(*) filter (where not on_serve and won)                as return_points_won,
        count(*) filter (where parse_confidence in ('high','medium')
                           and rally_length is not null)            as points_rally_scoreable,
        sum(rally_length) filter (where parse_confidence in ('high','medium'))
                                                                    as rally_length_sum
    from points
    where player_name is not null
    group by 1, 2

),

-- ----------------------------------------------------------------------------
--  Roll every source up to the grain. ShotTypes defines which player-matches
--  exist; the parsed sources LEFT JOIN on, so a match with shot types but no
--  usable serves still contributes its shot mix.
-- ----------------------------------------------------------------------------

counts as (

    select
        st.player_name,
        m.season,
        m.surface,
        min(m.tour)                                                 as tour,
        min(m.parse_confidence)                                     as parse_confidence,
        count(distinct st.match_id)                                 as matches,

        sum(st.shots) as shots, sum(st.fh_drives) as fh_drives, sum(st.bh_drives) as bh_drives,
        sum(st.fh_slices) as fh_slices, sum(st.bh_slices) as bh_slices,
        sum(st.volleys) as volleys, sum(st.overheads) as overheads,
        sum(st.drop_shots) as drop_shots, sum(st.lobs) as lobs,
        sum(st.half_volleys) as half_volleys, sum(st.swinging_volleys) as swinging_volleys,
        sum(st.net_shots) as net_shots,
        sum(st.fh_side_shots) as fh_side_shots, sum(st.bh_side_shots) as bh_side_shots,
        sum(st.winners) as winners, sum(st.unforced_errors) as unforced_errors,
        sum(st.induced_forced_errors) as induced_forced_errors,
        sum(st.point_ending_shots) as point_ending_shots,
        sum(st.fh_winners) as fh_winners, sum(st.fh_unforced_errors) as fh_unforced_errors,
        sum(st.bh_winners) as bh_winners, sum(st.bh_unforced_errors) as bh_unforced_errors,

        sum(d.fh_directed) as fh_directed, sum(d.fh_crosscourt) as fh_crosscourt,
        sum(d.fh_down_middle) as fh_down_middle, sum(d.fh_down_the_line) as fh_down_the_line,
        sum(d.fh_inside_out) as fh_inside_out, sum(d.fh_inside_in) as fh_inside_in,
        sum(d.bh_directed) as bh_directed, sum(d.bh_crosscourt) as bh_crosscourt,
        sum(d.bh_down_middle) as bh_down_middle, sum(d.bh_down_the_line) as bh_down_the_line,
        sum(d.bh_inside_out) as bh_inside_out, sum(d.bh_inside_in) as bh_inside_in,

        sum(s.first_serves) as first_serves, sum(s.first_serves_in) as first_serves_in,
        sum(s.first_serves_directed) as first_serves_directed,
        sum(s.deuce_wide) as deuce_wide, sum(s.deuce_body) as deuce_body, sum(s.deuce_t) as deuce_t,
        sum(s.ad_wide) as ad_wide, sum(s.ad_body) as ad_body, sum(s.ad_t) as ad_t,

        sum(p.points) as points, sum(p.points_won) as points_won,
        sum(p.serve_points) as serve_points, sum(p.serve_points_won) as serve_points_won,
        sum(p.return_points) as return_points, sum(p.return_points_won) as return_points_won,
        sum(p.points_rally_scoreable) as points_rally_scoreable,
        sum(p.rally_length_sum) as rally_length_sum

    from shot_types st
    join matches m          using (match_id)
    left join directions d  on d.match_id = st.match_id and d.player_name = st.player_name
    left join serves s      on s.match_id = st.match_id and s.player_name = st.player_name
    left join point_counts p on p.match_id = st.match_id and p.player_name = st.player_name
    group by 1, 2, 3

),

coverage as (

    select player_name, surface, season,
           dominant_charter, charters_involved, direction_charted_rate
    from {{ ref('mart_data_coverage') }}
    where coverage_grain = 'player_surface_season'

),

serve_shares as (

    -- Serve placement shares per court side. The denominator is the serves
    -- with BOTH a direction and a court side. first_serves_directed also counts
    -- 59,048 first serves with a direction but no court side. All of them are
    -- tiebreak points, where court side is NULL by design (E19).
    select
        *,
        deuce_wide + deuce_body + deuce_t                           as deuce_sided,
        ad_wide + ad_body + ad_t                                    as ad_sided,
        deuce_wide::numeric / nullif(deuce_wide + deuce_body + deuce_t, 0) as p_dw,
        deuce_body::numeric / nullif(deuce_wide + deuce_body + deuce_t, 0) as p_db,
        deuce_t::numeric    / nullif(deuce_wide + deuce_body + deuce_t, 0) as p_dt,
        ad_wide::numeric    / nullif(ad_wide + ad_body + ad_t, 0)          as p_aw,
        ad_body::numeric    / nullif(ad_wide + ad_body + ad_t, 0)          as p_ab,
        ad_t::numeric       / nullif(ad_wide + ad_body + ad_t, 0)          as p_at
    from counts

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
    select
        player_name, season, surface, tour, parse_confidence,
        matches,

        -- Shot mix. n = shots (or drives, or backhand-side shots).
        shots,
        fh_drives + bh_drives                                       as drives,
        bh_side_shots,
        round(fh_drives::numeric / nullif(fh_drives + bh_drives, 0), 4)
                                                                    as fh_dominance,
        round(bh_slices::numeric / nullif(bh_side_shots, 0), 4)     as bh_slice_rate,
        round(net_shots::numeric / nullif(shots, 0), 4)             as net_rate,
        round(drop_shots::numeric / nullif(shots, 0), 4)            as drop_shot_rate,
        round(point_ending_shots::numeric / nullif(shots, 0), 4)    as point_ending_rate,

        -- Direction. Two denominators, never summed. `+` would also turn NULL
        -- when one wing has no rows -- 3 cells measured.
        fh_directed,
        bh_directed,
        round(fh_inside_out::numeric / nullif(fh_directed, 0), 4)    as fh_inside_out_rate,
        round(fh_down_the_line::numeric / nullif(fh_directed, 0), 4) as fh_down_the_line_rate,
        round(bh_down_the_line::numeric / nullif(bh_directed, 0), 4) as bh_down_the_line_rate,

        -- Serve. Location (T share) and predictability (entropy) are different
        -- questions, so both go in -- one per court side for entropy, because
        -- wide and T mean different tactics on each side.
        first_serves,
        first_serves_directed,
        deuce_sided,
        ad_sided,
        round((deuce_t + ad_t)::numeric / nullif(deuce_sided + ad_sided, 0), 4)
                                                                    as first_serve_t_rate,
        round(-(  coalesce(p_dw * ln(nullif(p_dw, 0)), 0)
                + coalesce(p_db * ln(nullif(p_db, 0)), 0)
                + coalesce(p_dt * ln(nullif(p_dt, 0)), 0)) / ln(3::numeric), 4)
                                                                    as deuce_serve_entropy,
        round(-(  coalesce(p_aw * ln(nullif(p_aw, 0)), 0)
                + coalesce(p_ab * ln(nullif(p_ab, 0)), 0)
                + coalesce(p_at * ln(nullif(p_at, 0)), 0)) / ln(3::numeric), 4)
                                                                    as ad_serve_entropy,
        round(first_serves_in::numeric / nullif(first_serves, 0), 4) as first_serve_in_rate,

        -- Rally length. Our parse, high + medium confidence only (lesson 004).
        points_rally_scoreable,
        round(rally_length_sum::numeric / nullif(points_rally_scoreable, 0), 2)
                                                                    as avg_rally_length
    from serve_shares

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
