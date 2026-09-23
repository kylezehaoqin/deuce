{{ config(materialized='table') }}

-- ============================================================================
--  fct_games -- one row per game. The missing rung on the grain ladder.
--
--  A game is the natural unit of a PRESSURE EPISODE, and almost nothing models
--  it. Points are too granular for "he got broken"; matches are too coarse.
--
--  Unlocks:
--    * The let-down game (questions.yml #11, T8) -- needs game SEQUENCE, which
--      is exactly what T2's within-game control had to discard.
--    * 0-40 recovery: who saves triple break point?
--    * Hold rate under conditions rather than in aggregate.
--    * Game-level momentum -- where the folk belief actually lives. People say
--      "he lost the momentum" about games, not points.
--
-- ----------------------------------------------------------------------------
--  TIEBREAKS ARE NOT GAMES, STRUCTURALLY
--
--  In a tiebreak the server rotates every two points, so "who held" has no
--  meaning. Measured, the split is exact:
--
--    291,358 regular games  -- one server throughout (2 exceptions, noise)
--      4,928 tiebreaks      -- server changes in ALL of them, ~12 points each
--
--  Detection is free: tiebreak points score numerically ('5-4'), so they fail
--  the standard-score parse upstream and arrive with server_points NULL.
--
--  Consequently `server_name`, `held` and `broken` are NULL on tiebreak rows
--  rather than wrong. Filter with `not is_tiebreak` for hold/break questions --
--  the column exists so you cannot forget.
-- ============================================================================

with points as (

    select * from {{ ref('fct_points') }}
    where game_number is not null

),

agg as (

    select
        match_id,
        game_number,

        count(*)                                    as points_played,
        min(point_number)                           as first_point_number,
        max(point_number)                           as last_point_number,
        min(set_number)                             as set_number,

        -- A tiebreak is exactly the game where the server rotates. Both
        -- signals agree on 4,928 games, so either would do; server_points is
        -- the cheaper one.
        bool_or(server_points is null)              as is_tiebreak,
        count(distinct server_name) > 1             as server_changed,

        -- Whoever won the game's LAST point won the game. True for 100% of
        -- games here -- unlike match winner, which retirements spoil.
        -- Reading server_won_point on that last point answers "held" directly,
        -- with no player-number arithmetic to get backwards.
        (array_agg(server_won_point order by point_number desc))[1] as server_won_last_point,
        (array_agg(server_name      order by point_number))[1]      as first_server_name,
        (array_agg(returner_name    order by point_number))[1]      as first_returner_name,
        -- The LAST point's server, which differs from the first only in a
        -- tiebreak -- and a tiebreak is exactly where it matters.
        (array_agg(server_name   order by point_number desc))[1]    as last_server_name,
        (array_agg(returner_name order by point_number desc))[1]    as last_returner_name,

        count(*) filter (where is_break_point)      as break_points_faced,
        count(*) filter (where is_game_point)       as game_points_held,
        bool_or(is_deuce)                           as reached_deuce,

        -- Biggest hole the server dug. 3 means 0-40 (or worse).
        max(coalesce(returner_points, 0) - coalesce(server_points, 0))
                                                    as max_deficit_faced,

        max(match_date)                             as match_date,
        max(tour)                                   as tour,
        max(surface)                                as surface,
        max(tournament)                             as tournament,
        max(round)                                  as round,
        min(parse_confidence)                       as parse_confidence

    from points
    group by 1, 2

)

select
    {{ dbt_utils.generate_surrogate_key(['match_id', 'game_number']) }} as game_key,
    match_id,
    game_number,
    set_number,
    points_played,
    first_point_number,
    last_point_number,

    is_tiebreak,

    -- NULL rather than wrong on tiebreaks: there is no single server to credit.
    case when is_tiebreak then null else first_server_name end   as server_name,
    case when is_tiebreak then null else first_returner_name end as returner_name,
    case when is_tiebreak then null else server_won_last_point end       as held,
    case when is_tiebreak then null else not server_won_last_point end   as broken,

    -- Named, not numbered. On a tiebreak the "server" is whoever served the
    -- last point, so this stays meaningful where held/broken does not.
    case when server_won_last_point then last_server_name
         else last_returner_name end                              as game_winner_name,
    break_points_faced,
    break_points_faced > 0                                       as faced_break_point,
    game_points_held,
    reached_deuce,
    greatest(max_deficit_faced, 0)                               as max_deficit_faced,

    match_date,
    tour,
    surface,
    tournament,
    round,
    parse_confidence

from agg
