-- Staging rule: clean, cast, rename. The notation strings pass through untouched;
-- decoding them is intermediate/mart work.
-- 1:1 with raw.mcp_points.

with source as (

    select * from {{ source('raw', 'mcp_points') }}

),

renamed as (

    select
        match_id,
        pt::int                                   as point_number,

        set1::int                                 as p1_sets_won,
        set2::int                                 as p2_sets_won,
        gm1::int                                  as p1_games_won,
        gm2::int                                  as p2_games_won,
        -- Upstream 'Gm#' is either 'X' or 'X (Y)' depending on when the match was
        -- charted: X = game number in the match, Y = point number in that game.
        -- A naive ::int cast dies on the parenthesised form.
        nullif(split_part(gm_num, ' ', 1), '')::int                        as game_number,
        nullif(regexp_replace(gm_num, '^[^(]*\((\d+)\)$', '\1'), gm_num)::int
                                                                           as point_in_game,

        nullif(pts, '')                           as point_score,      -- e.g. '30-40', 'AD-40'

        -- Also charting-era dependent: older rows use '1'/'0', newer ones 'True'/'False'.
        lower(nullif(tb_set, '')) in ('1', 'true')                         as is_tiebreak_set,

        nullif(svr, '')::int                      as server_player_num,   -- 1 | 2
        nullif(pt_winner, '')::int                as point_winner_num,    -- 1 | 2

        -- The payload. Present on the first-serve column when the first serve
        -- went in; when it was a fault, `second_serve` carries the rally.
        nullif(first_serve, '')                   as first_serve_notation,
        nullif(second_serve, '')                  as second_serve_notation,
        coalesce(nullif(second_serve, ''), nullif(first_serve, ''))
                                                  as rally_notation,
        nullif(second_serve, '') is not null      as is_second_serve_point,

        nullif(notes, '')                         as notes,
        _source_file,
        _loaded_at

    from source

)

select * from renamed
