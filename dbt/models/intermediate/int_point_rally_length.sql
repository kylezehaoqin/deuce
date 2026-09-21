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

        {{ mcp_rally_length('p.rally_notation') }} as rally_length,

        -- Sackmann's buckets, so this model can be diffed against his directly.
        case
            when {{ mcp_rally_length('p.rally_notation') }} between 1 and 3 then '1-3'
            when {{ mcp_rally_length('p.rally_notation') }} between 4 and 6 then '4-6'
            when {{ mcp_rally_length('p.rally_notation') }} between 7 and 9 then '7-9'
            else '10+'
        end                                        as rally_bucket,

        -- Serve placement needs no tokenizer at all: it is character one.
        case left(p.rally_notation, 1)
            when '4' then 'wide'
            when '5' then 'body'
            when '6' then 'T'
        end                                        as serve_direction,

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

        m.match_date,
        m.tour,
        m.surface,
        {{ mcp_parse_confidence('m.match_date') }} as parse_confidence

    from points p
    left join matches m using (match_id)

)

select * from final
