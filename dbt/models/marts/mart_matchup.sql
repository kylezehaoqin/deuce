{{ config(
    materialized='table',
    indexes=[
      {'columns': ['player_name']},
      {'columns': ['player_name', 'opponent_name']},
    ]
) }}

-- ============================================================================
--  mart_matchup -- how a player's style shifts against ONE opponent.
--
--  One row per (player, opponent). Each pair appears twice, once from each
--  side. For every style rate: the rate in the pair's matches, the player's
--  own baseline, and the delta. This is the table analogical scouting queries:
--  "how does A deviate against players like B".
--
-- ----------------------------------------------------------------------------
--  THE BASELINE IS MATCHED ON SURFACE. Read this before using a delta.
--
--  A pooled baseline compares the pair's surface mix with the player's own mix.
--  For 470 pairs with 5+ matches, the median total variation distance between
--  the two mixes is 0.115, and 88 pairs (19%) are at 0.2 or more. Federer v
--  Nadal is 45.7% clay against 18.0% in all Federer matches. Federer slices
--  less on clay (.260 v .351 hard), so a pooled baseline puts about -2.6 pp of
--  "clay" into his slice delta against Nadal.
--
--  So the baseline is the player's rate on each surface, weighted by the
--  PAIR's surface mix. If 46% of the pair's matches were on clay, 46% of the
--  baseline is the player's clay rate.
--
--  Three rules, decided with Kyle:
--    1. Surface only. Not season: seasons are too thin, and the baseline gets
--       noisy. So a delta still includes career change -- Federer v Nadal runs
--       2004-2019. first_season / last_season are on the row.
--    2. LEAVE THE PAIR OUT of its own baseline. Otherwise a long rivalry pulls
--       the baseline toward itself and the delta toward zero.
--    3. Keep one-match pairs. 77% of pairs have one charted match. They stay,
--       with `matches`, so the consumer filters and the gap is visible.
--
--  A baseline rate is NULL if any surface the pair played on has no other
--  matches for that player, or no data for that rate there. A partial
--  baseline would bring the surface-mix bias back.
--
--  The delta still includes opponent QUALITY. "Federer against Nadal" also
--  means "Federer against a top-2 player". Nothing here controls for that.
-- ============================================================================

{%- set rates = style_rate_names() %}
{%- set count_cols = [
    'shots', 'fh_drives', 'bh_drives', 'fh_slices', 'bh_slices', 'net_shots',
    'drop_shots', 'bh_side_shots', 'point_ending_shots',
    'fh_directed', 'fh_inside_out', 'fh_down_the_line',
    'bh_directed', 'bh_down_the_line',
    'first_serves', 'first_serves_in', 'first_serves_directed',
    'deuce_wide', 'deuce_body', 'deuce_t', 'ad_wide', 'ad_body', 'ad_t',
    'points', 'points_won', 'points_rally_scoreable', 'rally_length_sum'
] %}

with player_matches as (

    select * from {{ ref('int_player_match_style') }}
    where opponent_name is not null

),

pair_surface as (

    select
        player_name, opponent_name, surface,
        count(*)                                                    as matches,
        {%- for c in count_cols %}
        sum({{ c }})                                                as {{ c }}{{ "," if not loop.last }}
        {%- endfor %}
    from player_matches
    group by 1, 2, 3

),

player_surface as (

    select
        player_name, surface,
        count(*)                                                    as matches,
        {%- for c in count_cols %}
        sum({{ c }})                                                as {{ c }}{{ "," if not loop.last }}
        {%- endfor %}
    from player_matches
    group by 1, 2

),

baseline_surface as (

    -- The player's matches on this surface, MINUS the matches against this
    -- opponent (rule 2). Subtracting sums is exact here, because both sums
    -- come from the same rows of int_player_match_style.
    select
        ps.player_name,
        ps.opponent_name,
        ps.surface,
        ps.matches                                                  as pair_matches,
        pl.matches - ps.matches                                     as matches,
        {%- for c in count_cols %}
        pl.{{ c }} - coalesce(ps.{{ c }}, 0)                        as {{ c }}{{ "," if not loop.last }}
        {%- endfor %}
    from pair_surface ps
    join player_surface pl using (player_name, surface)

),

baseline_surface_rates as (

    select
        player_name, opponent_name, surface, pair_matches, matches,
        {{ style_rates(rounded=false) }}
    from baseline_surface

),

baseline as (

    -- Weight each surface's rate by the pair's matches on that surface. If any
    -- surface has no rate, the whole baseline is NULL: dropping that surface
    -- would bring back the mix bias this table exists to remove.
    select
        player_name,
        opponent_name,
        sum(matches)                                                as baseline_matches,
        count(*) filter (where matches = 0)                         as surfaces_without_baseline,
        {%- for r in rates %}
        case when count({{ r }}) = count(*)
             then sum({{ r }} * pair_matches) / sum(pair_matches)
        end                                                         as {{ r }}{{ "," if not loop.last }}
        {%- endfor %}
    from baseline_surface_rates
    group by 1, 2

),

pair as (

    select
        player_name,
        opponent_name,
        count(*)                                                    as matches,
        min(season)                                                 as first_season,
        max(season)                                                 as last_season,
        min(tour)                                                   as tour,
        string_agg(distinct surface, ', ' order by surface)         as surfaces,
        {%- for c in count_cols %}
        sum({{ c }})                                                as {{ c }}{{ "," if not loop.last }}
        {%- endfor %}
    from player_matches
    group by 1, 2

),

pair_rates as (

    select
        player_name, opponent_name, matches, first_season, last_season, tour, surfaces,
        shots, fh_directed, bh_directed, first_serves, points, points_rally_scoreable,
        deuce_wide + deuce_body + deuce_t + ad_wide + ad_body + ad_t as serves_sided,
        -- Outcome, NOT style: the head-to-head. Points rather than matches,
        -- because retirements make match winners unreliable (fct_games).
        points_won::numeric / nullif(points, 0)                     as h2h_points_won_rate,
        {{ style_rates(rounded=false) }}
    from pair

)

select
    p.player_name,
    p.opponent_name,
    p.tour,
    p.matches,
    p.first_season,
    p.last_season,
    p.surfaces,
    b.baseline_matches,
    b.surfaces_without_baseline,

    -- n for the pair's rates. The baseline's n is baseline_matches.
    p.shots,
    p.fh_directed,
    p.bh_directed,
    p.first_serves,
    p.serves_sided,
    p.points,
    p.points_rally_scoreable,

    round(p.h2h_points_won_rate, 4)                                 as h2h_points_won_rate,

    {%- for r in rates %}

    round(p.{{ r }}, 4)                                             as {{ r }},
    round(b.{{ r }}, 4)                                             as {{ r }}_baseline,
    round(p.{{ r }} - b.{{ r }}, 4)                                 as {{ r }}_delta{{ "," if not loop.last }}
    {%- endfor %}

from pair_rates p
join baseline b using (player_name, opponent_name)
