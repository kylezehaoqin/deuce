-- Staging rule: clean, cast, rename. No joins, no aggregation, no business logic.
-- 1:1 with raw.mcp_matches.

with source as (

    select * from {{ source('raw', 'mcp_matches') }}

),

renamed as (

    select
        match_id,

        -- match_id encodes date / tour / tournament / round. Splitting it here
        -- (rather than in a mart) means every downstream model gets the same
        -- parse and a rename upstream breaks in exactly one place.
        split_part(match_id, '-', 2)                          as tour,          -- 'M' | 'W'
        to_date(split_part(match_id, '-', 1), 'YYYYMMDD')     as match_date,
        replace(split_part(match_id, '-', 3), '_', ' ')       as tournament_slug,

        player_1                                              as player_1_name,
        player_2                                              as player_2_name,
        nullif(pl_1_hand, '')                                 as player_1_hand,   -- 'R' | 'L'
        nullif(pl_2_hand, '')                                 as player_2_hand,

        tournament,
        round,
        nullif(court, '')                                     as court,
        nullif(surface, '')                                   as surface,
        nullif(umpire, '')                                    as umpire,
        nullif(best_of, '')::int                              as best_of,
        nullif(final_tb, '') = 'A'                            as has_final_set_tiebreak,
        charted_by,

        _source_file,
        _loaded_at

    from source

)

select * from renamed
