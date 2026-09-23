-- One row per point, with the rally length parsed out of the notation string.
--
-- This is the shallow end of parsing: it counts shots without identifying them.
-- The deep end -- one row per shot, with type, direction and hitter -- is
-- fct_shots, and it needs a real tokenizer.
--
-- Keeping them separate is the point. Everything here is verifiable against an
-- external oracle today, so rally-shape questions (#3, #4, #5, #10 in
-- questions.yml) can be answered and trusted before the tokenizer exists.

with points as (

    select
        *,
        -- Score -> points played, per side. Null for any score that is not a
        -- standard game score, which is exactly how tiebreak points opt out.
        case split_part(point_score, '-', 1)
            when '0' then 0 when '15' then 1 when '30' then 2
            when '40' then 3 when 'AD' then 4 end as server_points,
        case split_part(point_score, '-', 2)
            when '0' then 0 when '15' then 1 when '30' then 2
            when '40' then 3 when 'AD' then 4 end as returner_points
    from {{ ref('stg_points') }}
    where rally_notation is not null

),

matches as (

    select match_id, match_date, tour, surface from {{ ref('stg_matches') }}

),

final as (

    select
        p.match_id,
        p.point_number,
        p.game_number,
        p.point_score,
        p.server_player_num,
        p.point_winner_num,
        p.is_second_serve_point,
        p.is_tiebreak_set,

        -- Set context. Upstream carries sets-won-so-far, so the set in progress
        -- is one more than the sets already decided.
        p.p1_sets_won,
        p.p2_sets_won,
        p.p1_sets_won + p.p2_sets_won + 1          as set_number,
        p.p1_games_won,
        p.p2_games_won,

        {{ mcp_rally_length('p.rally_notation') }} as rally_length,

        -- Sackmann's buckets, so this model can be diffed against his directly.
        case
            when {{ mcp_rally_length('p.rally_notation') }} between 1 and 3 then '1-3'
            when {{ mcp_rally_length('p.rally_notation') }} between 4 and 6 then '4-6'
            when {{ mcp_rally_length('p.rally_notation') }} between 7 and 9 then '7-9'
            else '10+'
        end                                        as rally_bucket,

        -- Serve placement needs no tokenizer at all -- it is the first character
        -- (after any lets). Both serves are exposed, not just the one that was
        -- played, because the FAULTED first serve carries real information:
        -- where he was aiming, and how he missed.
        {{ mcp_serve_direction('p.first_serve_notation') }}  as first_serve_direction,
        {{ mcp_serve_fault_type('p.first_serve_notation') }} as first_serve_fault_type,
        p.second_serve_notation is null                      as is_first_serve_in,
        {{ mcp_serve_direction('p.second_serve_notation') }} as second_serve_direction,
        {{ mcp_serve_fault_type('p.second_serve_notation') }} as second_serve_fault_type,

        -- The serve that was actually played: second if the first faulted.
        {{ mcp_serve_direction('p.rally_notation') }}        as serve_direction,

        -- Deuce vs ad is NOT in the data. Derive it from the score: convert both
        -- sides to points played and take the parity -- even = deuce court.
        -- Tiebreak scores ('5-4') and anything non-standard resolve to null in
        -- `scored` below, and must stay null here: a CASE whose ELSE catches
        -- nulls would silently label every tiebreak point 'ad'.
        case
            when p.server_points is null or p.returner_points is null then null
            when (p.server_points + p.returner_points) % 2 = 0 then 'deuce'
            else 'ad'
        end                                        as court_side,

        -- Score as points played, per side. Exposed rather than kept private
        -- because every pressure definition downstream (break point, game point,
        -- deuce) is arithmetic on these two numbers -- and a mart that
        -- re-derives them will eventually re-derive them differently.
        p.server_points,
        p.returner_points,

        m.match_date,
        m.tour,
        m.surface,
        {{ mcp_parse_confidence('m.match_date') }} as parse_confidence

    from points p
    left join matches m using (match_id)

)

select * from final
