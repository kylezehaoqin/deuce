{{ config(
    enabled=false,
    materialized='table'
) }}

-- ============================================================================
--  mart_serve_patterns  --  THE FIRST SHIPPABLE MART. YOU WRITE THE SELECT.
--
--  Flip `enabled=false` to `enabled=true` once the final SELECT is written.
-- ============================================================================
--
--  WHY THIS ONE MATTERS
--
--  The repo currently has no marts, so Layer 2 has nothing to query. This mart
--  unblocks the agent WITHOUT the tokenizer, because serve placement is
--  character one of the notation string -- no shot parsing required.
--
--  It answers questions.yml #1 (serve placement under pressure) and #9 (do
--  players serve conservatively on break point), and it is the reference data
--  behind T3, T4 and T5 in lessons/hypotheses-tennis.md.
--
-- ----------------------------------------------------------------------------
--  THE DECISION: WHAT GRAIN DOES A MART EXPOSE?
--
--  `serve_context` below is one row per serve. The question is what this model
--  hands to the agent.
--
--  A) ONE ROW PER SERVE  (pass serve_context through, plus surrogate key)
--     + the agent can slice by anything -- surface, era, opponent hand, score
--     + new questions need no new model
--     - ~1.9M rows; every agent query is an aggregation it has to get right
--     - entropy must be computed in the agent's SQL each time, and entropy is
--       exactly the thing an LLM will get subtly wrong
--
--  B) PRE-AGGREGATED  (one row per player x court_side x pressure x serve_number)
--     + serve_direction_entropy computed once, correctly, here
--     + small and fast; the agent does simple filters
--     + the hard statistics live in tested SQL instead of generated SQL
--     - every new slice is a schema change
--     - you must pick the pressure buckets NOW and they constrain the product
--
--  C) BOTH -- fact grain here, a narrow aggregate beside it
--     + the usual production answer
--     - two models to keep consistent; the aggregate can silently drift
--
--  Worth weighing: the agent's failure mode is confident wrong SQL. Every
--  statistic you precompute is a statistic it cannot get wrong. Every column you
--  precompute is a question it can no longer ask. That tension is the whole
--  design, and it is genuinely a judgment call.
--
--  If you pick (B) or (C), the entropy expression is already written and
--  verified in sql/queries/serve_direction_entropy.sql -- note the LN(3::numeric)
--  cast (errors E1) and that it must be normalised by ln(k) for k buckets.
--
-- ----------------------------------------------------------------------------
--  THINGS THAT WILL BITE YOU
--
--  1. DENOMINATORS. Serve direction is optional in the charting spec
--     (docs/mcp-notation.md). serve_direction is null when uncharted. Any share
--     must divide by "serves with a direction charted", not "serves" -- and the
--     model should expose both counts so the agent can state the difference.
--
--  2. PARSE CONFIDENCE. Carry it. A pre-aggregated mart that pools eras hides
--     the one caveat the agent is required to disclose. If you aggregate, either
--     group by it or filter to high/medium and say so in the description.
--
--  3. SECOND SERVES. `serve_direction` here is the FIRST serve's direction --
--     it reads character one of rally_notation, which is the serve that was
--     actually played. On a second-serve point that is the second serve. Decide
--     whether that is what you want, and name the column accordingly. This is
--     the kind of thing that is correct-but-misleading for a year.
--
--  4. SMALL CELLS. Sliced by player x court x pressure x serve number, the tail
--     is thin. questions.yml keeps saying "if N < 20, say the sample is thin".
--     A mart that ships `n` alongside every rate makes that possible; one that
--     ships only rates makes it impossible.
--
--  5. DESCRIPTIONS ARE PROMPT CONTEXT. Whatever you build, every column goes in
--     _marts.yml with a description -- the agent reads those to write SQL. A
--     column documented badly is a column used badly. (lesson 003)
-- ============================================================================

with serves as (

    select * from {{ ref('int_point_rally_length') }}
    where serve_direction is not null
       or true   -- keep undirected serves so denominators stay honest (bite #1)

),

matches as (

    select
        match_id,
        player_1_name,
        player_2_name,
        player_1_hand,
        player_2_hand
    from {{ ref('stg_matches') }}

),

serve_context as (

    -- One row per serve, with everything resolved. This part is plumbing --
    -- names, handedness, pressure arithmetic. The judgment is what you do with it.

    select
        s.match_id,
        s.point_number,
        s.game_number,

        -- Player 1 is always whoever served first (upstream data_dictionary.txt),
        -- so server_player_num indexes into the match's two names.
        case when s.server_player_num = 1 then m.player_1_name else m.player_2_name end
                                                        as server_name,
        case when s.server_player_num = 1 then m.player_2_name else m.player_1_name end
                                                        as returner_name,
        case when s.server_player_num = 1 then m.player_1_hand else m.player_2_hand end
                                                        as server_hand,
        -- The returner's hand decides which physical corner a direction code
        -- names (docs/mcp-notation.md: 1 = to a RIGHT-HANDER's forehand side),
        -- so it belongs on every serve row, not bolted on later.
        case when s.server_player_num = 1 then m.player_2_hand else m.player_1_hand end
                                                        as returner_hand,

        s.serve_direction,                              -- 'wide' | 'body' | 'T' | null
        s.court_side,                                   -- 'deuce' | 'ad' | null (tiebreaks)
        s.is_second_serve_point,
        s.is_tiebreak_set,
        s.point_score,
        s.server_points,
        s.returner_points,

        -- Pressure, defined as arithmetic on the score rather than a magic list
        -- of score strings. Break point = the returner can win the game with
        -- this point; game point = the server can.
        coalesce(s.returner_points = 4
                 or (s.returner_points = 3 and s.server_points < 3), false)
                                                        as is_break_point,
        coalesce(s.server_points = 4
                 or (s.server_points = 3 and s.returner_points < 3), false)
                                                        as is_game_point,
        coalesce(s.server_points = 3 and s.returner_points = 3, false)
                                                        as is_deuce,

        s.point_winner_num = s.server_player_num        as server_won_point,
        s.rally_length,
        s.rally_bucket,

        s.match_date,
        s.tour,
        s.surface,
        s.parse_confidence

    from serves s
    left join matches m using (match_id)

)

-- TODO(kyle): decide the grain, then write the final SELECT.
--
-- select * from serve_context                     -- option A
--
-- select server_name, court_side, ...             -- option B
--        count(*) as serves,
--        count(serve_direction) as serves_with_direction,   <- bite #1
--        ...entropy...
-- from serve_context group by ...
