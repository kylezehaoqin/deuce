-- One row per point: WAS each optional field actually charted?
--
-- The charting spec makes shot direction, return depth and court position all
-- optional, and tells charters to learn the system in layers. So a missing
-- direction is not corruption -- it is a charter who hadn't got to that layer,
-- or a point that went too fast.
--
-- Critically, charters OMIT rather than mark unknown. The spec provides '0' for
-- unknown direction, 'q' for unknown shot and 'e' for unknown error, and they
-- are barely used: over 900,699 points from the 2020s, unknown-direction is
-- 0.00%, unknown-shot 0.23%, whole-point-missed 0.21%. Missingness is therefore
-- INVISIBLE unless you measure presence. That is what this model is for.
--
-- Consumed by dim_charters and mart_data_coverage. Kept separate from
-- int_point_rally_length because "how complete is this record" is a different
-- concern from "what happened in the rally", and the two have different reasons
-- to change.

with points as (

    select
        match_id,
        point_number,
        rally_notation
    from {{ ref('stg_points') }}
    where rally_notation is not null

)

select
    match_id,
    point_number,

    -- A shot letter followed by optional modifiers and a direction digit.
    -- Modifiers sit between the letter and the digit (f;1, z^3, j=+2), so the
    -- character class is not optional here. (docs/mcp-notation.md)
    rally_notation ~ '[fbrsvzopuylmhijktq][-+=;^!]*[123]'
                                                    as has_shot_direction,

    -- Return depth is a THIRD character after the direction, and applies to
    -- service returns only -- never to groundstrokes generally.
    rally_notation ~ '[fbrsvzopuylmhijktq][-+=;^!]*[123][789]'
                                                    as has_return_depth,

    -- Approach (+), at-net (-), at-baseline (=), net cord (;), stop volley (^).
    -- The spec calls this the lowest-priority layer, so it is the sharpest
    -- signal of how thorough a charter is.
    rally_notation ~ '[-+=;^]'                      as has_court_position,

    -- Explicit "I did not see it" codes. Rare, but honest when present.
    rally_notation ~ 'q'                            as has_unknown_shot,
    rally_notation ~ '[fbrsvzopuylmhijktq][-+=;^!]*0'
                                                    as has_unknown_direction,

    -- Whole point not charted: S/R give the point to server/returner, P/Q are
    -- point penalties. Single-character rally strings.
    rally_notation ~ '^[SRPQ]$'                      as is_point_uncharted

from points
