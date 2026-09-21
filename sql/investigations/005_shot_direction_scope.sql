-- ============================================================================
-- INVESTIGATION 005 -- which shots does ShotDirection.csv count?
--
-- Goal: make OUR count of directed shots equal SACKMANN'S, per match. Once the
-- scope agrees, only the 1/2/3 -> crosscourt/DTL mapping is left, and that is
-- the last ❓ in docs/mcp-notation.md.
--
-- Full trail: lessons/005-open-direction-orientation.md
--
-- ---------------------------------------------------------------------------
-- ESTABLISHED (don't re-litigate):
--   * His 'Total' row = F + B + S            -> groundstrokes only
--   * Modifiers sit between letter and digit -> f;1, z^3, j=+2
--   * Forehand slice 'r' is NOT counted      -> [fbs] beats [fbsr]
--   * Serve returns appear to be excluded    -> stripping them helped a lot
--
-- BASELINE to beat (the expression currently in CANDIDATE below):
--   avg gap  +19.5 shots/match   |   exact agreement  1.2%
--   We are counting TOO MANY. The remaining error is ~5%.
--
-- REMAINING HYPOTHESES (test ONE at a time):
--   H10a  Point-ending shots are excluded, mirroring his rally-length rule
--         where the shot that missed doesn't count (lessons/004). Most likely:
--         it is the same convention, and he is consistent elsewhere.
--   H10b  The serve+return strip is wrong. It assumes a fixed token shape;
--         serve-and-volley and second-serve strings may not match it.
--   H10c  Shots charted without a direction digit are counted under a default.
--
-- ---------------------------------------------------------------------------
-- YOUR PREDICTION (write it BEFORE running -- rule 1):
--
--   Round __ :  I am testing ________________________________________
--               I expect the gap to go from +19.5 to about _________
--               because ______________________________________________
--
-- ---------------------------------------------------------------------------
-- HOW TO READ THE OUTPUT
--   Query 1  one match, shot by shot -- eyeball it, this is where hypotheses
--            come from. Query 2 only tells you whether you were right.
--   Query 2  the score. `avg_gap` positive = counting too many.
--            `pct_exact` is the real target; avg_gap can average to zero while
--            every individual match is wrong.
-- ============================================================================

\set match_id '20260521-M-Roland_Garros-Q3-Jesper_De_Jong-Michael_Zheng'
\set era_floor 2020


-- ─────────────────────────────────────────────────────────────────────────────
-- QUERY 1 -- one match, up close.
-- Read the strings. Sackmann's number for this match is printed alongside.
-- ─────────────────────────────────────────────────────────────────────────────
\echo '=== one match: raw notation (first 15 points in play) ==='

SELECT
    pt::int                                                   AS pt,
    pts                                                       AS score,
    COALESCE(NULLIF(second_serve,''), NULLIF(first_serve,'')) AS rally,
    -- the tail after stripping serve + return, which is what CANDIDATE sees
    regexp_replace(COALESCE(NULLIF(second_serve,''), NULLIF(first_serve,'')),
                   '^[0-9][-+=;^!]*[a-z][-+=;^!]*[1-9]?', '') AS tail
FROM raw.mcp_points
WHERE match_id = :'match_id'
  AND COALESCE(NULLIF(second_serve,''), NULLIF(first_serve,'')) IS NOT NULL
ORDER BY pt::int
LIMIT 15;

\echo ''
\echo '=== his count for that match (Total = F + B + S, groundstrokes only) ==='

SELECT player_name, row_label, directed_shots
FROM analytics_analytics.stg_stats_shot_direction
WHERE match_id = :'match_id'
ORDER BY player_name, row_label;


-- ─────────────────────────────────────────────────────────────────────────────
-- QUERY 2 -- the score.
--
-- >>> EDIT ONLY THE `candidate` CTE. Everything below it is the harness. <<<
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '=== reconciliation vs oracle ==='

WITH prepared AS (

    SELECT
        match_id,
        COALESCE(NULLIF(second_serve,''), NULLIF(first_serve,'')) AS rally,
        -- Serve + return removed. If you are testing H10b, this is the line to
        -- attack -- move it into `candidate` and rewrite it there.
        regexp_replace(COALESCE(NULLIF(second_serve,''), NULLIF(first_serve,'')),
                       '^[0-9][-+=;^!]*[a-z][-+=;^!]*[1-9]?', '')  AS tail
    FROM raw.mcp_points
    WHERE COALESCE(NULLIF(second_serve,''), NULLIF(first_serve,'')) IS NOT NULL
      AND left(match_id, 4)::int >= :era_floor

),

candidate AS (

    -- ┌──────────────────────────────────────────────────────────────────────┐
    -- │ TODO(kyle) -- THE HYPOTHESIS UNDER TEST                              │
    -- │                                                                      │
    -- │ Return one row per match: `directed_shots`, our count of the shots   │
    -- │ we believe Sackmann counts in ShotDirection.csv.                     │
    -- │                                                                      │
    -- │ Below is the current baseline (+19.5 / 1.2%). Change ONE thing.      │
    -- │                                                                      │
    -- │ For H10a you need to exclude shots that ended the point. The signal  │
    -- │ is in `rally`, not `tail`: a rally ending '@' or '#' means the LAST  │
    -- │ shot missed. Note the asymmetry -- you are counting tokens in `tail` │
    -- │ but the terminator lives at the end of `rally`. A point that ends in │
    -- │ a winner ('*') did NOT have a missed shot.                           │
    -- │                                                                      │
    -- │ Useful shapes:                                                       │
    -- │   cardinality(regexp_split_to_array(tail, '<pattern>')) - 1          │
    -- │       -- count occurrences of <pattern>                              │
    -- │   rally ~ '[@#]$'                                                    │
    -- │       -- did this point end in an error                              │
    -- │   greatest(0, <count> - <adjustment>)                                │
    -- │       -- the clamp that mattered in lessons/004. Ask whether it      │
    -- │          matters here too, and what the floor should be.             │
    -- └──────────────────────────────────────────────────────────────────────┘

    SELECT
        match_id,
        SUM(
            cardinality(regexp_split_to_array(tail, '[fbs][-+=;^!]*[123]')) - 1
        )::int AS directed_shots
    FROM prepared
    GROUP BY match_id

),

-- ───────────── harness below this line -- leave it alone ─────────────

oracle AS (

    SELECT match_id, SUM(directed_shots)::int AS directed_shots
    FROM analytics_analytics.stg_stats_shot_direction
    WHERE row_label = 'Total'
    GROUP BY match_id

),

compared AS (

    SELECT
        c.match_id,
        left(c.match_id, 4)::int      AS yr,
        c.directed_shots              AS ours,
        o.directed_shots              AS theirs,
        c.directed_shots - o.directed_shots AS gap
    FROM candidate c
    JOIN oracle o USING (match_id)

)

SELECT
    CASE WHEN yr >= 2020 THEN '2020s'
         WHEN yr >= 2010 THEN '2010s'
         ELSE 'pre-2010' END                                  AS era,
    count(*)                                                  AS matches,
    round(100.0 * count(*) FILTER (WHERE gap = 0) / count(*), 2)  AS pct_exact,
    round(100.0 * count(*) FILTER (WHERE abs(gap) <= 2) / count(*), 2) AS pct_within_2,
    round(avg(gap), 2)                                        AS avg_gap,
    round(avg(abs(gap)), 2)                                   AS avg_abs_gap,
    -- Sign tells you which direction to move; spread tells you whether it is
    -- one systematic rule or several competing ones.
    count(*) FILTER (WHERE gap > 0)                           AS too_many,
    count(*) FILTER (WHERE gap < 0)                           AS too_few
FROM compared
GROUP BY 1
ORDER BY 1;
