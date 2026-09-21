-- ORACLE model -- Sackmann's shot-type counts.
--
-- Oracle for the letter mapping in docs/mcp-notation.md: if our parse says a
-- player hit 84 forehands and his says 84, 'f' means forehand. `row` uses his
-- own abbreviations ('F', 'B', 'S', 'R', 'V', 'Z', 'O', ...) plus roll-ups
-- ('Total', 'Fside', 'Bside', 'Gs', 'Net', 'Base'), so a mapping table from our
-- notation letters to his row codes is needed before diffing -- that mapping is
-- itself the hypothesis under test.

with source as (

    select * from {{ source('raw', 'mcp_stats_shot_types') }}

),

renamed as (

    select
        match_id,
        player                               as player_name,
        row_label,

        nullif(shots, '')::int               as shots,
        nullif(pt_ending, '')::int           as point_ending_shots,
        nullif(winners, '')::int             as winners,
        nullif(induced_forced, '')::int      as induced_forced_errors,
        nullif(unforced, '')::int            as unforced_errors,
        nullif(serve_return, '')::int        as serve_returns,
        nullif(shots_in_pts_won, '')::int    as shots_in_points_won,
        nullif(shots_in_pts_lost, '')::int   as shots_in_points_lost,

        _source_file,
        _loaded_at

    from source

)

select * from renamed
