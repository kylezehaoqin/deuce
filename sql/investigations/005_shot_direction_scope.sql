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
-- FROM THE SPEC (MatchChart 0.3.2.xlsm, Instructions tab -- authoritative):
--   * Direction 1/2/3 is ABSOLUTE: 1 = to a righty's forehand side, 3 = to a
--     righty's backhand side. Not relative to the hitter.
--   * Direction is OPTIONAL on every shot. 'fbh' is a valid rally. So our count
--     already silently skips undirected shots -- and so, presumably, does his.
--   * Forced errors need only shot-type + '#'. 'b#' is complete. Point-ending
--     forced errors therefore usually carry NO direction, which means they were
--     never in our count to begin with -- H10a can only explain the gap via
--     UNFORCED errors, which do often carry one.
--   * 7/8/9 are SERVICE-RETURN depth, not general shot depth.
--
-- RESOLVED -- both H10a and H10b were true, and the residual is neither.
--
--   start                    +19.55 avg gap   1.19% exact
--   H10b  let fix            +16.89
--   H10a  net unforced only   +2.34            5.69% exact, median +2
--
--   Residual is CHARTER IDIOSYNCRASY, not a missing rule. Per-charter mean gap
--   spans -15.48 (Angel Moreno) to +12.14 (Isaac) while within-charter spread is
--   a near-constant sd ~7-8. Zindaras, the highest-volume charter at 1,480
--   matches, sits at +1.41. So the scope rule is right and different volunteers
--   apply the notation slightly differently -- which is exactly what
--   dim_charters was built to measure.
--
--   Note it is now era-INDEPENDENT (+2.09 / +2.34 / +4.50 across 2010s / 2020s /
--   pre-2010), unlike the rally-length parser's 90/82/55%. A scope rule
--   generalises across charting eras; a token-level parse does not.
--
--   H10c (undirected shots counted under a default) was never needed.
--
-- ---------------------------------------------------------------------------
-- YOUR PREDICTION (write it BEFORE running -- rule 1):
--
--   Round __ :  I am testing ___H10a, Point-ending shots excluded  
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
        -- Serve + return removed.
        -- The leading `c*` is load-bearing: 19,687 points in the 2020s begin with
        -- a LET ('c', repeatable), so an anchor of '^[0-9]' silently fails to
        -- match and the whole rally -- including the return -- survives into
        -- `tail`. Worth ~2.7 shots/match of overcount, found by grouping on
        -- left(rally,1) rather than by reading the regex again.
        regexp_replace(COALESCE(NULLIF(second_serve,''), NULLIF(first_serve,'')),
                       '^c*[0-9][-+=;^!]*[a-z][-+=;^!]*[1-9]?', '')  AS tail
    FROM raw.mcp_points
    WHERE COALESCE(NULLIF(second_serve,''), NULLIF(first_serve,'')) IS NOT NULL
      AND left(match_id, 4)::int >= :era_floor

),

candidate AS (

    -- SETTLED. Two corrections took the gap from +19.55 to a median of +2
    -- (all eras: mean 2.70, p25 -3, p75 +8).
    --
    --   1. The let fix, in `prepared` above.
    --   2. Subtract the point-ending shot ONLY when it was an unforced error
    --      into the NET. WHY is unknown -- do not invent a reason. The obvious
    --      physical story ("a netted ball never crossed the baseline") is
    --      refuted here: forced net errors carry a direction 171,427 times and
    --      ARE counted. Empirically solid rule, unexplained mechanism.
    --
    -- Rejected alternatives, each measured (avg gap per match):
    --      all unforced errors          -19.65   over-corrects 8x
    --      net errors, any terminator    -5.21   forced net errors ARE counted
    --      + shank / unknown-error       +2.32   indistinguishable from net-only
    --      net unforced only             +2.34   <-- kept
    --
    -- The clamp is not decoration. When the shot that missed IS the return, it
    -- was already stripped from `tail`, so the count is 0 and the subtraction
    -- would go negative. That case needs no separate test: if the return missed
    -- the point ended there, so a 0 count and a matching subtraction always
    -- coincide.

    SELECT
        match_id,
        SUM(
            GREATEST(
                0,
                cardinality(regexp_split_to_array(tail, '[fbs][-+=;^!]*[123]')) - 1
                - (rally ~ '[fbs][-+=;^!]*[123]n@$')::int
            )
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
