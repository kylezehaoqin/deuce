-- ORACLE model -- Sackmann's shot directions, already resolved from the raw
-- 1/2/3 codes into TACTICAL terms.
--
-- This is the key to the one genuinely open question in docs/mcp-notation.md.
-- Note the shape of the problem: three direction codes map to five tactical
-- categories. Two categories of information have to come from somewhere else --
-- namely the hitter's court position, which depends on where the PREVIOUS ball
-- went. That is why shot direction needs a stateful parse and serve direction
-- does not. See lessons/005.
--
-- Scope, established empirically (lessons/005): groundstrokes only. Sackmann's
-- 'Total' = F + B + S for 23,432 of 23,604 player-matches, and the forehand
-- slice ('r') is NOT included.

with source as (

    select * from {{ source('raw', 'mcp_stats_shot_direction') }}

),

renamed as (

    select
        match_id,
        player                              as player_name,
        row_label,                          -- 'Total' | 'F' | 'B' | 'S'

        nullif(crosscourt, '')::int         as crosscourt,
        nullif(down_middle, '')::int        as down_middle,
        nullif(down_the_line, '')::int      as down_the_line,
        nullif(inside_out, '')::int         as inside_out,
        nullif(inside_in, '')::int          as inside_in,

        coalesce(nullif(crosscourt, '')::int, 0)
          + coalesce(nullif(down_middle, '')::int, 0)
          + coalesce(nullif(down_the_line, '')::int, 0)
          + coalesce(nullif(inside_out, '')::int, 0)
          + coalesce(nullif(inside_in, '')::int, 0)  as directed_shots,

        _source_file,
        _loaded_at

    from source

)

select * from renamed
