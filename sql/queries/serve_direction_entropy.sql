-- ============================================================================
-- INCREMENT 0 PROOF-OF-LIFE  --  serve placement + direction entropy
--
-- Answers: "Where does this player serve, and how predictable is it?"
--
-- Runs against raw.mcp_stats_serve_direction (Sackmann's own per-match
-- aggregation), NOT against parsed shot notation. That is the whole point of
-- shipping it today: it proves the pipeline end-to-end -- CSV -> Postgres ->
-- a real tactical answer -- before the shot-grain parser exists.
--
-- The modeled version of this metric belongs in dbt/models/marts/, sliced by
-- pressure (break point, 30-40), serve number, and opponent handedness.
--
-- ENTROPY: -SUM(p * ln p), normalised by ln(3) so it lands in [0, 1].
--   1.00 = perfectly balanced across wide/body/T -- unreadable
--   0.00 = every serve to the same spot -- a returner's dream
-- ============================================================================

WITH per_match AS (
    SELECT
        match_id,
        NULLIF(deuce_wide,   '')::int AS deuce_wide,
        NULLIF(deuce_middle, '')::int AS deuce_middle,
        NULLIF(deuce_t,      '')::int AS deuce_t,
        NULLIF(ad_wide,      '')::int AS ad_wide,
        NULLIF(ad_middle,    '')::int AS ad_middle,
        NULLIF(ad_t,         '')::int AS ad_t
    FROM raw.mcp_stats_serve_direction
    WHERE player = %(player)s
      -- 'Total' is the whole-match row; the file also carries per-set and
      -- per-situation rows, which would double-count if included.
      AND row_label = 'Total'
),

-- Six count columns -> long form, so entropy is a single aggregate rather than
-- six hand-written terms.
unpivoted AS (
    SELECT 'deuce' AS court_side, 'wide' AS direction, SUM(deuce_wide)   AS serves FROM per_match
    UNION ALL
    SELECT 'deuce',               'body',              SUM(deuce_middle)            FROM per_match
    UNION ALL
    SELECT 'deuce',               'T',                 SUM(deuce_t)                 FROM per_match
    UNION ALL
    SELECT 'ad',                  'wide',              SUM(ad_wide)                 FROM per_match
    UNION ALL
    SELECT 'ad',                  'body',              SUM(ad_middle)               FROM per_match
    UNION ALL
    SELECT 'ad',                  'T',                 SUM(ad_t)                    FROM per_match
),

shares AS (
    SELECT
        court_side,
        direction,
        COALESCE(serves, 0) AS serves,
        COALESCE(serves, 0)::numeric
            / NULLIF(SUM(COALESCE(serves, 0)) OVER (PARTITION BY court_side), 0) AS p
    FROM unpivoted
)

SELECT
    court_side,
    direction,
    serves,
    ROUND(p, 4) AS share,
    -- Window aggregate: one entropy value per court side, repeated on each row.
    -- LN(3) would be double precision, and Postgres has no two-argument ROUND for
    -- double -- hence the explicit numeric cast on the base.
    ROUND(
        (-SUM(p * LN(NULLIF(p, 0))) OVER (PARTITION BY court_side)) / LN(3::numeric),
        4
    ) AS serve_direction_entropy,
    -- Grounding: never report a rate without the sample it came from.
    (SELECT COUNT(*) FROM per_match) AS matches_charted
FROM shares
ORDER BY court_side DESC, serves DESC;
