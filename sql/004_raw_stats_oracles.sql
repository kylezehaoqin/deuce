-- ============================================================================
-- ORACLE TABLES
--
-- Sackmann independently implemented the same notation spec we are implementing,
-- and publishes his aggregations. That makes these files ground truth for OUR
-- parser: no labelling effort, ~100K rows of it, free.
--
-- They are landed exactly like any other source (all TEXT, same ingest path) --
-- but they are consumed differently. Nothing downstream of a mart should read
-- them. They exist to be DIFFED against, in dbt tests.
--
-- New migration file rather than an edit to 002: 002 has already been applied to
-- a running database, and editing an applied migration is how environments drift
-- apart. Forward-only, numbered, additive.
-- ============================================================================

-- charting-{m,w}-stats-Rally.csv
-- Grain: (match_id, row). `row` buckets rally length: 'Total', '1-3', '4-6',
-- '7-9', '10' -- optionally suffixed '-1' / '-2' for first / second serve.
-- ORACLE FOR: rally length parsing.
CREATE TABLE IF NOT EXISTS raw.mcp_stats_rally (
    match_id      TEXT NOT NULL,
    server        TEXT,
    returner      TEXT,
    row_label     TEXT NOT NULL,
    pts           TEXT,           -- points falling in this rally-length bucket
    pl1_won       TEXT,
    pl1_winners   TEXT,
    pl1_forced    TEXT,
    pl1_unforced  TEXT,
    pl2_won       TEXT,
    pl2_winners   TEXT,
    pl2_forced    TEXT,
    pl2_unforced  TEXT,
    _source_file  TEXT        NOT NULL,
    _run_id       UUID        NOT NULL,
    _loaded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (match_id, row_label)
);

-- charting-{m,w}-stats-ShotTypes.csv
-- Grain: (match_id, player, row). `row` is the shot class ('Total', 'Fside',
-- 'Bside', 'F', 'B', 'S', ...).
-- ORACLE FOR: the shot-type mapping (does 'f' really mean forehand?).
CREATE TABLE IF NOT EXISTS raw.mcp_stats_shot_types (
    match_id           TEXT NOT NULL,
    player             TEXT NOT NULL,
    row_label          TEXT NOT NULL,
    shots              TEXT,
    pt_ending          TEXT,
    winners            TEXT,
    induced_forced     TEXT,
    unforced           TEXT,
    serve_return       TEXT,
    shots_in_pts_won   TEXT,
    shots_in_pts_lost  TEXT,
    _source_file       TEXT        NOT NULL,
    _run_id            UUID        NOT NULL,
    _loaded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (match_id, player, row_label)
);

-- charting-{m,w}-stats-ShotDirection.csv
-- Grain: (match_id, player, row). Counts by TACTICAL direction, not by the raw
-- 1/2/3 code -- crosscourt, down the middle, down the line, inside-out, inside-in.
--
-- ORACLE FOR: the single genuinely unresolved question in docs/mcp-notation.md --
-- what orientation do the direction digits 1/2/3 use? Sackmann has already
-- resolved 1/2/3 into tactical terms here, conditional on shot type and
-- handedness. Fit our mapping against these counts and the ambiguity is settled
-- empirically instead of assumed. See lessons/005.
CREATE TABLE IF NOT EXISTS raw.mcp_stats_shot_direction (
    match_id       TEXT NOT NULL,
    player         TEXT NOT NULL,
    row_label      TEXT NOT NULL,
    crosscourt     TEXT,
    down_middle    TEXT,
    down_the_line  TEXT,
    inside_out     TEXT,
    inside_in      TEXT,
    _source_file   TEXT        NOT NULL,
    _run_id        UUID        NOT NULL,
    _loaded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (match_id, player, row_label)
);
