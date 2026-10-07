{{ config(materialized='table') }}

-- ============================================================================
--  int_player_match_style -- style COUNTS per (match, player). No rates.
--
--  Two marts read this: mart_player_style sums it to (player, season,
--  surface), and mart_matchup sums it to (player, opponent) and to the matched
--  baseline. One definition of every count, so the two marts cannot drift.
--
--  A table, not a view: both marts read it, and the fct_serves aggregation is
--  the expensive part of the build.
--
--  Grain: one row per (match_id, player_name) present in ShotTypes. ShotTypes
--  defines which player-matches exist. The parsed sources LEFT JOIN on, so a
--  match with shot types but no usable serves still contributes its shot mix.
--
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
--  SOURCES, and the oracle rule (docs/marts.md §6)
--
--  Shot mix and error profile come from stg_stats_shot_types -- Sackmann's
--  ShotTypes ORACLE. Allowed today because no mart parses shot types yet. The
--  moment fct_shots exists and is validated against ShotTypes, the marts reading this must
--  switch to reading fct_shots, or the validation becomes circular. That
--  decision is written into the model description so it cannot be forgotten.
--
--  Direction comes from stg_stats_shot_direction (also an oracle; same rule).
--  Serve placement and rally length come from OUR parse (fct_serves, fct_points).
--
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
-- ============================================================================

with matches as (

    select
        match_id,
        extract(year from match_date)::int          as season,
        coalesce(surface, 'Unknown')                as surface,
        tour,
        player_1_name,
        player_2_name,
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

)

select
    st.match_id,
    st.player_name,
    case when st.player_name = m.player_1_name then m.player_2_name
         when st.player_name = m.player_2_name then m.player_1_name
    end                                                         as opponent_name,
    m.season,
    m.surface,
    m.tour,
    m.parse_confidence,

    st.shots, st.fh_drives, st.bh_drives, st.fh_slices, st.bh_slices,
    st.volleys, st.overheads, st.drop_shots, st.lobs, st.half_volleys,
    st.swinging_volleys, st.net_shots, st.fh_side_shots, st.bh_side_shots,
    st.winners, st.unforced_errors, st.induced_forced_errors, st.point_ending_shots,
    st.fh_winners, st.fh_unforced_errors, st.bh_winners, st.bh_unforced_errors,

    d.fh_directed, d.fh_crosscourt, d.fh_down_middle, d.fh_down_the_line,
    d.fh_inside_out, d.fh_inside_in,
    d.bh_directed, d.bh_crosscourt, d.bh_down_middle, d.bh_down_the_line,
    d.bh_inside_out, d.bh_inside_in,

    s.first_serves, s.first_serves_in, s.first_serves_directed,
    s.deuce_wide, s.deuce_body, s.deuce_t, s.ad_wide, s.ad_body, s.ad_t,

    p.points, p.points_won, p.serve_points, p.serve_points_won,
    p.return_points, p.return_points_won,
    p.points_rally_scoreable, p.rally_length_sum

from shot_types st
join matches m           using (match_id)
left join directions d   on d.match_id = st.match_id and d.player_name = st.player_name
left join serves s       on s.match_id = st.match_id and s.player_name = st.player_name
left join point_counts p on p.match_id = st.match_id and p.player_name = st.player_name
