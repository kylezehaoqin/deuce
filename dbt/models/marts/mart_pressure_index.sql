{{ config(
    materialized='table',
    indexes=[
      {'columns': ['match_id']},
      {'columns': ['server_name']},
      {'columns': ['returner_name']},
    ]
) }}

-- ============================================================================
--  mart_pressure_index -- how much the MATCH outcome swings on each point.
--
--  T3 used break point as the pressure flag and called it coarse. It is: 30-40
--  at 1-1 in the first set and 30-40 at 5-6 in the fifth are the same flag. A
--  leverage index -- baseball's LI, transplanted -- puts every point on one
--  continuous scale, so "clutch" can be asked properly.
--
--    match_leverage = P(server wins match | wins this point)
--                   - P(server wins match | loses this point)
--
-- ----------------------------------------------------------------------------
--  THE CHAIN RULE -- why this is tractable at all
--
--  The match state space (points x games x sets x server x format) is far too
--  big to estimate directly. But a point can only move the match THROUGH its
--  game, a game only through its set. Under that Markov structure the swing
--  factorises exactly:
--
--    match_leverage = game_leverage   -- point -> game   (hold_prob, parametric)
--                   x set_swing       -- game  -> set    (set_prob)
--                   x match_swing     -- set   -> match  (match_prob)
--
--  Each factor is a small lookup table estimated from this data, and each is
--  exposed as a column, so "30-40 matters because it's 30-40" and "it matters
--  because it's 5-6 in the fifth" stay separable.
--
--  The factorisation assumes the match outcome, given the game outcome, does
--  not depend on HOW the game was won. T2 is the evidence that this is close:
--  the server's next-point win rate barely moves with the previous point.
--
-- ----------------------------------------------------------------------------
--  KNOWN GAPS (NULL, not wrong)
--
--  * TIEBREAK POINTS: game_leverage is NULL. The game->set factor for a
--    tiebreak is exactly 1, but point->tiebreak needs its own state table, and
--    the server rotates inside it. The highest-leverage points in tennis are
--    therefore missing from v1 -- `is_tiebreak_game` is on every row so a
--    consumer cannot forget. Open question in docs/marts.md §8.
--  * States never observed (deep advantage sets, odd formats): NULL factor.
--  * Short sets (first to 4) and matches with no best_of: excluded from the
--    set/match tables, so their points get NULL swings.
--
--  Every factor carries its sample size (`*_state_n`). A leverage built on a
--  cell of 30 is not the same claim as one built on 30,000.
-- ============================================================================

with points as (

    select
        point_key, match_id, point_number, game_number, set_number,
        server_name, returner_name,
        server_points, returner_points,
        server_games_won, returner_games_won,
        server_sets_won, returner_sets_won,
        -- best_of is upstream metadata, and 8 matches contradict it: labelled
        -- best-of-3, played 4 or 5 sets (US Open, Australian Open, old Basel
        -- finals). Trusted only when the sets actually played fit inside it --
        -- otherwise two players can both "reach 2 sets" and a match gets two
        -- winners. Measured: that is what put impossible states like 2-2 in
        -- best-of-3 into match_prob. NULL here means NULL match_swing downstream.
        case when max(server_sets_won + returner_sets_won) over (partition by match_id) + 1
                  <= best_of
             then best_of end                    as best_of,
        coalesce(is_tiebreak_set, true)          as is_tiebreak_set,
        is_tiebreak_game,
        -- 49 games have no tour/surface (the unmatched match_ids). Coalesced so
        -- they join to SOMETHING rather than silently dropping from the lookups.
        coalesce(tour, '?')                      as tour,
        coalesce(surface, 'Unknown')             as surface,
        pressure, server_won_point, match_date, parse_confidence
    from {{ ref('fct_points') }}
    where game_number is not null

),

-- ============================================================================
--  LEVEL 1: point -> game
-- ============================================================================

point_rate as (

    -- One point-win probability per (tour, surface): the iid assumption made
    -- explicit. Regular games only -- tiebreak points rotate the server.
    select
        tour, surface,
        avg(server_won_point::int)::numeric          as p,
        count(*)                                     as n_points
    from points
    where not is_tiebreak_game and server_won_point is not null
    group by 1, 2

),

hold_prob as (

    -- P(server holds | score), PARAMETRIC (docs/marts.md §8, option b).
    --
    -- Why not empirical: a leverage index should describe the SCORE, not who
    -- tends to reach it. Empirical P(hold | 0-40) is computed over the servers
    -- who get to 0-40 -- disproportionately weak ones -- so it would mix player
    -- quality into "how much this point matters". Baseball's LI makes the same
    -- call: league-average run environment, not the batter's. The cost is the
    -- iid assumption; how wrong it is gets measured, not assumed (H12).
    --
    -- Closed form, no recursion. With a = points the server still needs and
    -- D = p^2 / (p^2 + q^2) = P(hold | deuce):
    --
    --   P(hold | s, r) = sum_{j=0}^{2-r} C(a-1+j, j) p^a q^j     -- before deuce
    --                  + C(6-s-r, 3-s) p^(3-s) q^(3-r) D         -- via deuce
    --
    -- The advantage states are one step from deuce and are written out.
    -- state_n is the number of POINTS behind p, not visits to this state.
    select
        pr.tour,
        pr.surface,
        st.s                                          as server_points,
        st.r                                          as returner_points,
        case
            when st.s = 4 then pr.p + pr.q * pr.d                      -- AD-in
            when st.r = 4 then pr.p * pr.d                             -- AD-out
            else
                (select coalesce(sum(
                        factorial(3 - st.s + j) / (factorial(3 - st.s) * factorial(j))
                        * pr.p ^ (4 - st.s) * pr.q ^ j), 0)
                 from generate_series(0, 2 - st.r) as j)
              + factorial(6 - st.s - st.r) / (factorial(3 - st.s) * factorial(3 - st.r))
                * pr.p ^ (3 - st.s) * pr.q ^ (3 - st.r) * pr.d
        end                                           as p_hold,
        pr.n_points                                   as state_n
    from (
        select *, 1 - p as q, p ^ 2 / (p ^ 2 + (1 - p) ^ 2) as d from point_rate
    ) pr
    cross join (
        select s, r from generate_series(0, 3) s, generate_series(0, 3) r
        union all select 4, 3
        union all select 3, 4
    ) st

),

point_outcomes as (

    -- The two states this point can lead to. Deuce is normalised: losing AD-in
    -- or winning AD-out goes back to (3,3), not forward to a 5th point.
    select
        p.*,
        (server_points = 4 or (server_points = 3 and returner_points < 3))   as win_ends_game,
        (returner_points = 4 or (returner_points = 3 and server_points < 3)) as loss_ends_game,

        case when server_points = 3 and returner_points = 4 then 3
             else server_points + 1 end                    as win_server_points,
        case when server_points = 3 and returner_points = 4 then 3
             else returner_points end                      as win_returner_points,

        case when returner_points = 3 and server_points = 4 then 3
             else server_points end                        as loss_server_points,
        case when returner_points = 3 and server_points = 4 then 3
             else returner_points + 1 end                  as loss_returner_points
    from points p

),

game_level as (

    select
        o.*,
        -- Terminal outcomes are certain; everything else is a lookup. Tiebreak
        -- points have NULL server_points, so both CASEs fall through to a
        -- lookup that finds nothing -- NULL, by design (E6: a CASE must not
        -- turn a NULL into a number).
        case when o.win_ends_game  then 1.0 else hw.p_hold end  as p_hold_if_won,
        case when o.loss_ends_game then 0.0 else hl.p_hold end  as p_hold_if_lost,
        hn.state_n                                              as hold_state_n
    from point_outcomes o
    left join hold_prob hw
           on hw.tour = o.tour and hw.surface = o.surface
          and hw.server_points = o.win_server_points
          and hw.returner_points = o.win_returner_points
    left join hold_prob hl
           on hl.tour = o.tour and hl.surface = o.surface
          and hl.server_points = o.loss_server_points
          and hl.returner_points = o.loss_returner_points
    -- The CURRENT state's n, for provenance.
    left join hold_prob hn
           on hn.tour = o.tour and hn.surface = o.surface
          and hn.server_points = o.server_points
          and hn.returner_points = o.returner_points

),

-- ============================================================================
--  LEVEL 2: game -> set
-- ============================================================================

games as (

    select
        match_id, game_number, set_number, is_tiebreak, held, game_winner_name
    from {{ ref('fct_games') }}

),

sets as (

    -- A set is decided by its last game. "Complete" means the scoreline is a
    -- legal finish: 6+ games with a 2-game lead, or a tiebreak last. That
    -- excludes retirements mid-set AND short-set formats (first to 4), which
    -- would otherwise pollute states like 4-3 with "set over".
    select
        match_id,
        set_number,
        (array_agg(game_winner_name order by game_number desc))[1]     as set_winner_name,
        (array_agg(is_tiebreak      order by game_number desc))[1]     as ended_in_tiebreak,
        count(*)                                                        as games_in_set
    from games
    group by 1, 2

),

sets_scored as (

    select
        s.*,
        count(*) filter (where g.game_winner_name = s.set_winner_name) as winner_games,
        count(*) filter (where g.game_winner_name <> s.set_winner_name) as loser_games
    from sets s
    join games g using (match_id, set_number)
    group by s.match_id, s.set_number, s.set_winner_name, s.ended_in_tiebreak, s.games_in_set

),

sets_complete as (

    select
        match_id, set_number, set_winner_name,
        (ended_in_tiebreak or (winner_games >= 6 and winner_games - loser_games >= 2))
            as is_complete
    from sets_scored

),

game_start as (

    -- The scoreboard as each regular game begins, from its first point.
    select distinct on (match_id, game_number)
        match_id, game_number, set_number, server_name, is_tiebreak_set,
        server_games_won, returner_games_won
    from points
    where not is_tiebreak_game
    order by match_id, game_number, point_number

),

game_state as (

    -- Advantage sets (no tiebreak at 6-6) can run to 70-68. Past 5-5 only the
    -- DIFFERENCE matters -- 9-8 is the same situation as 6-5 -- so fold those
    -- states down, or every deep cell is a sample of three.
    select
        g.*,
        case when not is_tiebreak_set and least(server_games_won, returner_games_won) >= 5
             then server_games_won - least(server_games_won, returner_games_won) + 5
             else server_games_won end                                 as server_games_key,
        case when not is_tiebreak_set and least(server_games_won, returner_games_won) >= 5
             then returner_games_won - least(server_games_won, returner_games_won) + 5
             else returner_games_won end                               as returner_games_key
    from game_start g

),

set_prob as (

    -- P(this game's server wins the set | games score, held or broken).
    select
        gs.is_tiebreak_set,
        gs.server_games_key,
        gs.returner_games_key,
        avg((sc.set_winner_name = gs.server_name)::int) filter (where g.held)     as p_set_if_held,
        avg((sc.set_winner_name = gs.server_name)::int) filter (where not g.held) as p_set_if_broken,
        count(*)                                                                  as set_state_n
    from game_state gs
    join games g          using (match_id, game_number)
    join sets_complete sc on sc.match_id = gs.match_id and sc.set_number = gs.set_number
    where sc.is_complete
    group by 1, 2, 3

),

-- ============================================================================
--  LEVEL 3: set -> match
-- ============================================================================

match_result as (

    -- Winner = first to best_of/2 + 1 complete sets. A retirement never gets
    -- there, so it has no winner and drops out of match_prob -- which is the
    -- point: a retired match says nothing about what winning a set is worth.
    select
        s.match_id,
        s.set_winner_name as winner_name
    from sets_complete s
    join (select distinct match_id, best_of from points where best_of is not null) m
      using (match_id)
    where s.is_complete
    group by s.match_id, s.set_winner_name, m.best_of
    having count(*) >= m.best_of / 2 + 1

),

set_start as (

    select distinct on (match_id, set_number)
        match_id, set_number, best_of,
        server_name as player_name, server_sets_won as player_sets,
        returner_sets_won as opponent_sets
    from points
    where best_of is not null
    order by match_id, set_number, point_number

),

match_prob_rows as (

    -- Both perspectives of every set, so the table is symmetric by
    -- construction and any point's server can look himself up.
    select ss.best_of, ss.player_sets, ss.opponent_sets,
           sc.set_winner_name = ss.player_name     as won_set,
           mr.winner_name = ss.player_name         as won_match
    from set_start ss
    join sets_complete sc using (match_id, set_number)
    join match_result mr  using (match_id)
    where sc.is_complete

    union all

    select ss.best_of, ss.opponent_sets, ss.player_sets,
           sc.set_winner_name <> ss.player_name,
           mr.winner_name <> ss.player_name
    from set_start ss
    join sets_complete sc using (match_id, set_number)
    join match_result mr  using (match_id)
    where sc.is_complete

),

match_prob as (

    select
        best_of, player_sets, opponent_sets,
        avg(won_match::int) filter (where won_set)     as p_match_if_won_set,
        avg(won_match::int) filter (where not won_set) as p_match_if_lost_set,
        count(*)                                       as match_state_n
    from match_prob_rows
    group by 1, 2, 3

),

-- ============================================================================
--  Compose
-- ============================================================================

composed as (

    select
        gl.*,
        gl.p_hold_if_won - gl.p_hold_if_lost                         as game_leverage,
        sp.p_set_if_held - sp.p_set_if_broken                        as set_swing,
        sp.set_state_n,
        mp.p_match_if_won_set - mp.p_match_if_lost_set               as match_swing,
        mp.match_state_n
    from game_level gl
    left join game_state gs
           on gs.match_id = gl.match_id and gs.game_number = gl.game_number
    left join set_prob sp
           on sp.is_tiebreak_set = gs.is_tiebreak_set
          and sp.server_games_key = gs.server_games_key
          and sp.returner_games_key = gs.returner_games_key
    left join match_prob mp
           on mp.best_of = gl.best_of
          and mp.player_sets = gl.server_sets_won
          and mp.opponent_sets = gl.returner_sets_won

),

leveraged as (

    select
        *,
        game_leverage * set_swing * match_swing                      as match_leverage
    from composed

)

select
    point_key,
    match_id,
    point_number,
    game_number,
    set_number,
    server_name,
    returner_name,

    server_points,
    returner_points,
    server_games_won,
    returner_games_won,
    server_sets_won,
    returner_sets_won,
    best_of,
    is_tiebreak_game,
    pressure,
    server_won_point,

    round(p_hold_if_won, 4)                                         as p_hold_if_won,
    round(p_hold_if_lost, 4)                                        as p_hold_if_lost,
    round(game_leverage, 4)                                         as game_leverage,
    round(set_swing, 4)                                             as set_swing,
    round(match_swing, 4)                                           as match_swing,
    round(match_leverage, 5)                                        as match_leverage,

    -- Normalised so 1.0 = the average point ON THIS TOUR, as baseball's LI is
    -- normalised to the league. Per tour because base hold rates differ so
    -- much that a pooled mean would make every WTA point look "high leverage".
    round(match_leverage
          / nullif(avg(match_leverage) over (partition by tour), 0), 3) as leverage_index,

    hold_state_n,
    set_state_n,
    match_state_n,

    tour,
    surface,
    match_date,
    parse_confidence

from leveraged
