-- ============================================================================
-- RAW LAYER
--
-- Design rule: raw tables mirror the source CSVs. Every data column is TEXT.
-- Nothing is cast, coerced, renamed beyond snake_case, or dropped here.
--
-- Why: the raw layer's job is FIDELITY, not correctness. If Sackmann adds a
-- column or starts writing "N/A" in a numeric field, ingest keeps working and
-- the breakage surfaces in dbt staging -- where it is visible, tested, and
-- cheap to fix -- instead of silently eating rows at load time.
--
-- Corollary: marts are always rebuildable from raw. Raw is the rollback point.
-- ============================================================================

-- charting-m-matches.csv / charting-w-matches.csv
CREATE TABLE IF NOT EXISTS raw.mcp_matches (
    match_id      TEXT PRIMARY KEY,
    player_1      TEXT,
    player_2      TEXT,
    pl_1_hand     TEXT,
    pl_2_hand     TEXT,
    date          TEXT,
    tournament    TEXT,
    round         TEXT,
    time          TEXT,
    court         TEXT,
    surface       TEXT,
    umpire        TEXT,
    best_of       TEXT,
    final_tb      TEXT,
    charted_by    TEXT,
    -- ingest metadata (underscore-prefixed so it never collides with a source column)
    _source_file  TEXT        NOT NULL,
    _run_id       UUID        NOT NULL,
    _loaded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- charting-{m,w}-points-{to-2009,2010s,2020s}.csv
-- The payload is `first_serve` / `second_serve`: the shot-by-shot notation string
-- (e.g. '4b37y1r3n#'). Kept verbatim -- parsing it is a staging concern.
-- See docs/mcp-notation.md for the codebook.
CREATE TABLE IF NOT EXISTS raw.mcp_points (
    match_id      TEXT NOT NULL,
    pt            TEXT NOT NULL,   -- point number within the match
    set1          TEXT,
    set2          TEXT,
    gm1           TEXT,
    gm2           TEXT,
    pts           TEXT,            -- game score at point start, e.g. '30-40'
    gm_num        TEXT,            -- source header: 'Gm#'
    tb_set        TEXT,
    svr           TEXT,            -- 1 or 2 -- which player is serving
    first_serve   TEXT,            -- source header: '1st'
    second_serve  TEXT,            -- source header: '2nd'
    notes         TEXT,
    pt_winner     TEXT,            -- 1 or 2
    _source_file  TEXT        NOT NULL,
    _run_id       UUID        NOT NULL,
    _loaded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (match_id, pt)
);

CREATE INDEX IF NOT EXISTS ix_mcp_points_match ON raw.mcp_points (match_id);

-- charting-{m,w}-stats-ServeDirection.csv
-- Sackmann's own aggregation: serve placement counts per match/player/context.
-- This is what makes Increment 0 answerable end-to-end WITHOUT a notation parser.
CREATE TABLE IF NOT EXISTS raw.mcp_stats_serve_direction (
    match_id       TEXT NOT NULL,
    player         TEXT NOT NULL,
    row_label      TEXT NOT NULL,  -- source header: 'row' -- e.g. 'Total', 'Deuce', '1st', 'BP'
    deuce_wide     TEXT,
    deuce_middle   TEXT,
    deuce_t        TEXT,
    ad_wide        TEXT,
    ad_middle      TEXT,
    ad_t           TEXT,
    err_net        TEXT,
    err_wide       TEXT,
    err_deep       TEXT,
    err_wide_deep  TEXT,
    err_foot       TEXT,
    err_unknown    TEXT,
    _source_file   TEXT        NOT NULL,
    _run_id        UUID        NOT NULL,
    _loaded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (match_id, player, row_label)
);
