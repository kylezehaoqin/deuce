{{ config(materialized='table') }}

-- ============================================================================
--  dim_charters -- one row per volunteer who charted matches.
--
--  This dataset is crowdsourced, and `charted_by` has been sitting in
--  raw.mcp_matches unused since Increment 0. It matters because the charting
--  spec makes direction, return depth and court position OPTIONAL, so different
--  charters produce systematically different completeness -- and every
--  direction-based rate in the warehouse silently inherits that.
--
--  Measured across 18 charters with >=20 matches in the 2020s:
--
--    share of points with shot direction:  min 0.623 | median 0.873 | max 0.906
--    share with court position:            0.068 -> 0.251   (a 4x spread)
--
--  So "Player A goes down the line 12% of the time" is partly a statement about
--  who watched Player A. This table makes that visible instead of latent.
--
--  It is a DIMENSION, not a mart: descriptive attributes of an entity, no
--  measures of the tennis itself. It feeds mart_data_coverage, which is the
--  table the agent should consult before answering.
--
--  NOT a quality ranking. A charter at 62% direction coverage did the hard part
--  -- charting a whole match by hand -- and the spec explicitly tells beginners
--  to skip direction. Rates describe depth of detail, not care.
-- ============================================================================

with matches as (

    select
        -- Some rows carry no charter. Label rather than drop: those matches are
        -- real data, and an unlabelled group is itself worth being able to see.
        coalesce(nullif(trim(charted_by), ''), '(unattributed)') as charter_name,
        match_id,
        match_date,
        tour
    from {{ ref('stg_matches') }}

),

flags as (

    select * from {{ ref('int_point_charting_flags') }}

),

per_charter as (

    select
        m.charter_name,

        count(distinct m.match_id)                          as matches_charted,
        count(f.point_number)                               as points_charted,
        min(m.match_date)                                   as first_charted_date,
        max(m.match_date)                                   as last_charted_date,

        count(distinct m.tour)                              as tours_covered,
        count(distinct m.match_id) filter (where m.tour = 'M') as matches_atp,
        count(distinct m.match_id) filter (where m.tour = 'W') as matches_wta,

        count(distinct m.match_id) filter (
            where extract(year from m.match_date) >= 2020)   as matches_2020s,
        count(distinct m.match_id) filter (
            where extract(year from m.match_date) between 2010 and 2019)
                                                            as matches_2010s,
        count(distinct m.match_id) filter (
            where extract(year from m.match_date) < 2010)    as matches_pre_2010,

        -- Completeness. Counts as well as rates, so a consumer can re-aggregate
        -- across charters without averaging averages.
        count(f.point_number) filter (where f.has_shot_direction)  as points_with_direction,
        count(f.point_number) filter (where f.has_return_depth)    as points_with_return_depth,
        count(f.point_number) filter (where f.has_court_position)  as points_with_court_position,
        count(f.point_number) filter (where f.has_unknown_shot
                                         or f.has_unknown_direction) as points_with_unknown_code,
        count(f.point_number) filter (where f.is_point_uncharted)  as points_uncharted

    from matches m
    left join flags f using (match_id)
    group by 1

)

select
    charter_name,
    matches_charted,
    points_charted,
    first_charted_date,
    last_charted_date,
    tours_covered > 1                                        as charts_both_tours,
    matches_atp,
    matches_wta,
    matches_2020s,
    matches_2010s,
    matches_pre_2010,

    points_with_direction,
    points_with_return_depth,
    points_with_court_position,
    points_with_unknown_code,
    points_uncharted,

    -- nullif guards a charter whose every match failed to join a point row.
    round(points_with_direction::numeric      / nullif(points_charted, 0), 4) as direction_charted_rate,
    round(points_with_return_depth::numeric   / nullif(points_charted, 0), 4) as return_depth_charted_rate,
    round(points_with_court_position::numeric / nullif(points_charted, 0), 4) as court_position_charted_rate,
    round(points_uncharted::numeric           / nullif(points_charted, 0), 4) as uncharted_point_rate

from per_charter
