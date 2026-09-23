{{ config(
    materialized='table',
    indexes=[
      {'columns': ['player_name']},
      {'columns': ['player_name', 'coverage_grain']},
    ]
) }}

-- ============================================================================
--  mart_data_coverage -- "can I answer this, and how confidently?"
--
--  The table the agent consults BEFORE it answers, not after.
--
--  questions.yml says, repeatedly, "if N < 20 say the sample is thin". That is
--  only enforceable if sample size is a fact the agent can LOOK UP. If it has to
--  remember to compute a COUNT(*) alongside every rate, it will sometimes not,
--  and the failure is silent and confident -- the worst combination.
--
--  It answers four different questions, and they fail independently:
--
--    1. Is there enough data?          matches, points, opponents
--    2. Is the field I need charted?   direction / return depth / court position
--    3. Can I trust the parse?         confidence mix (charting era)
--    4. Is this one person's view?     charters_involved, dominant_charter
--
--  (4) is the non-obvious one. Charting completeness varies from 0.00 to 0.93
--  across 196 volunteers (dim_charters), so a player whose record comes from a
--  single low-detail charter has thin direction data for a reason that has
--  nothing to do with the player.
--
-- ----------------------------------------------------------------------------
--  WHY GROUPING SETS
--
--  The agent needs coverage at whatever level the question is at: "Alcaraz"
--  (player), "Alcaraz on clay" (player x surface), "Alcaraz in 2024"
--  (player x season), "Alcaraz on clay in 2024" (all three).
--
--  Four separate models would drift. One model at the finest grain would force
--  the agent to re-aggregate -- and re-aggregating RATES is exactly the error we
--  are trying to prevent, because you cannot average averages without weighting.
--
--  GROUPING SETS emits all four levels from one pass. `coverage_grain` labels
--  which level each row is, derived from GROUPING() -- a bitmask saying which
--  grouping columns were collapsed to NULL for that row. So a NULL in `surface`
--  means "all surfaces", never "surface unknown", and the label makes that
--  unambiguous.
--
--  Counts are exposed alongside every rate so a consumer that DOES need to
--  re-aggregate can do it correctly.
-- ============================================================================

with match_players as (

    -- One row per (match, player). `player_1`/`player_2` upstream is a repeating
    -- group; unpivoting to rows is the 1NF fix and makes "every match this
    -- player appeared in" a simple filter.
    select
        match_id, match_date, surface, tour, charted_by,
        player_1_name as player_name,
        player_2_name as opponent_name
    from {{ ref('stg_matches') }}
    where player_1_name is not null

    union all

    select
        match_id, match_date, surface, tour, charted_by,
        player_2_name as player_name,
        player_1_name as opponent_name
    from {{ ref('stg_matches') }}
    where player_2_name is not null

),

point_level as (

    -- Each point joins to BOTH players: a point is jointly produced, and
    -- "coverage for Alcaraz" means coverage of points he was involved in.
    select
        mp.player_name,
        mp.match_id,
        mp.opponent_name,
        mp.match_date,
        coalesce(mp.surface, 'Unknown')                as surface,
        extract(year from mp.match_date)::int          as season,
        mp.charted_by,
        {{ mcp_parse_confidence('mp.match_date') }}    as parse_confidence,
        f.point_number,
        f.has_shot_direction,
        f.has_return_depth,
        f.has_court_position,
        f.is_point_uncharted
    from match_players mp
    left join {{ ref('int_point_charting_flags') }} f using (match_id)

),

aggregated as (

    select
        player_name,
        surface,
        season,

        -- GROUPING() returns a bitmask of which columns were rolled up.
        -- 0 = neither, 1 = season only, 2 = surface only, 3 = both.
        grouping(surface, season)                                  as _grouping_bits,

        count(distinct match_id)                                   as matches,
        count(distinct opponent_name)                              as opponents_faced,
        count(point_number)                                        as points,
        min(match_date)                                            as first_match_date,
        max(match_date)                                            as last_match_date,

        count(distinct charted_by)                                 as charters_involved,
        mode() within group (order by charted_by)                  as dominant_charter,

        count(point_number) filter (where parse_confidence = 'high')   as points_high_confidence,
        count(point_number) filter (where parse_confidence = 'medium') as points_medium_confidence,
        count(point_number) filter (where parse_confidence = 'low')    as points_low_confidence,

        count(point_number) filter (where has_shot_direction)      as points_with_direction,
        count(point_number) filter (where has_return_depth)        as points_with_return_depth,
        count(point_number) filter (where has_court_position)      as points_with_court_position,
        count(point_number) filter (where is_point_uncharted)      as points_uncharted

    from point_level
    group by grouping sets (
        (player_name, surface, season),
        (player_name, surface),
        (player_name, season),
        (player_name)
    )

)

select
    player_name,
    surface,
    season,

    case _grouping_bits
        when 0 then 'player_surface_season'
        when 1 then 'player_surface'
        when 2 then 'player_season'
        when 3 then 'player'
    end                                                            as coverage_grain,

    matches,
    opponents_faced,
    points,
    first_match_date,
    last_match_date,

    charters_involved,
    dominant_charter,

    points_high_confidence,
    points_medium_confidence,
    points_low_confidence,

    points_with_direction,
    points_with_return_depth,
    points_with_court_position,
    points_uncharted,

    round(points_with_direction::numeric      / nullif(points, 0), 4) as direction_charted_rate,
    round(points_with_return_depth::numeric   / nullif(points, 0), 4) as return_depth_charted_rate,
    round(points_with_court_position::numeric / nullif(points, 0), 4) as court_position_charted_rate,
    round(points_high_confidence::numeric     / nullif(points, 0), 4) as high_confidence_rate

from aggregated
