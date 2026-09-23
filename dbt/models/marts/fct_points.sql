{{ config(
    materialized='table',
    indexes=[
        {'columns': ['server_name']},
        {'columns': ['match_id']},
    ]
) }}

-- ============================================================================
--  fct_points -- FACT GRAIN. One row per point, everything resolved.
--
--  The point-grain fact table the rest of the mart layer derives from:
--    fct_points   (this)  -- one row per point
--    fct_serves           -- unpivoted to one row per SERVE
--    fct_games            -- aggregated up to one row per GAME
--
--  Named for its grain, not its columns. It carries serve context, rally shape
--  and pressure because all three are properties of a point.
--
--  Why both: the agent can slice this table any way a question demands, and
--  reach for the aggregate when it needs a statistic that is easy to get wrong.
--  The cost of the pair is drift -- so the two are reconciled by a dbt test
--  (assert_serve_patterns_matches_fact). That test is the reason this is safe.
--
-- ----------------------------------------------------------------------------
--  GRAIN NOTE -- read this before using serve columns.
--
--  One row per POINT, not per serve. A point may contain two serves; the column
--  `played_serve_direction` is the direction of the serve that was actually
--  PLAYED -- the first serve if it landed, otherwise the second. The faulted
--  first serve is NOT represented here.
--
--  `is_second_serve_point` tells you which case you are looking at. If you need
--  fault directions ("how does he miss?"), that is fct_serves at true serve
--  grain -- see docs/marts.md, not built yet.
-- ============================================================================

with points as (

    select * from {{ ref('int_point_rally_length') }}

),

matches as (

    select
        match_id,
        player_1_name,
        player_2_name,
        player_1_hand,
        player_2_hand,
        round,
        tournament
    from {{ ref('stg_matches') }}

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['p.match_id', 'p.point_number']) }}
                                                        as point_key,
        p.match_id,
        p.point_number,
        p.game_number,

        -- Player 1 is always whoever served first (upstream data_dictionary.txt),
        -- so server_player_num indexes into the match's two names.
        case when p.server_player_num = 1 then m.player_1_name else m.player_2_name end
                                                        as server_name,
        case when p.server_player_num = 1 then m.player_2_name else m.player_1_name end
                                                        as returner_name,
        case when p.server_player_num = 1 then m.player_1_hand else m.player_2_hand end
                                                        as server_hand,
        -- The returner's hand decides which physical corner a direction code
        -- names (docs/mcp-notation.md: 1 = to a RIGHT-HANDER's forehand side).
        case when p.server_player_num = 1 then m.player_2_hand else m.player_1_hand end
                                                        as returner_hand,

        -- NULL when the charter did not record a direction. Optional in the
        -- spec, so this is data, not a defect -- count(...) over these columns
        -- is the honest denominator for any share.
        --
        -- Both serves, not just the played one: a faulted first serve says where
        -- the server was aiming AND how he missed, and that is a scouting tell.
        p.first_serve_direction,
        p.first_serve_fault_type,
        p.is_first_serve_in,
        p.second_serve_direction,
        p.second_serve_fault_type,
        p.serve_direction                               as played_serve_direction,
        p.court_side,
        p.is_second_serve_point,
        p.is_tiebreak_set,
        p.set_number,
        p.p1_games_won,
        p.p2_games_won,
        p.point_score,
        p.server_points,
        p.returner_points,

        -- Pressure as arithmetic on the score, not a list of magic strings.
        -- These three are mutually exclusive: at 40-40 only is_deuce is true,
        -- because neither player is one point from the game.
        coalesce(p.returner_points = 4
                 or (p.returner_points = 3 and p.server_points < 3), false)
                                                        as is_break_point,
        coalesce(p.server_points = 4
                 or (p.server_points = 3 and p.returner_points < 3), false)
                                                        as is_game_point,
        coalesce(p.server_points = 3 and p.returner_points = 3, false)
                                                        as is_deuce,

        -- One categorical column, because grouping by three booleans produces
        -- eight combinations of which only four can occur.
        case
            when p.returner_points = 4
                 or (p.returner_points = 3 and p.server_points < 3) then 'break_point'
            when p.server_points = 4
                 or (p.server_points = 3 and p.returner_points < 3) then 'game_point'
            when p.server_points = 3 and p.returner_points = 3      then 'deuce'
            when p.server_points is null                            then 'unknown'
            else 'neutral'
        end                                             as pressure,

        p.point_winner_num = p.server_player_num        as server_won_point,
        p.rally_length,
        p.rally_bucket,

        m.tournament,
        m.round,
        p.match_date,
        p.tour,
        p.surface,
        p.parse_confidence

    from points p
    left join matches m using (match_id)

)

select * from final
