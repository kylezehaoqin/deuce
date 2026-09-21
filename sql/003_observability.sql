-- ============================================================================
-- OBSERVABILITY + DEAD LETTER
--
-- Two tables that cost 20 lines and answer the two questions every reviewer
-- asks about a pipeline: "how do you know it ran?" and "where do bad rows go?"
-- ============================================================================

-- One row per ingest invocation. Dagster will later read/emit the same numbers
-- as asset metadata; keeping them in Postgres means they survive the orchestrator.
CREATE TABLE IF NOT EXISTS raw.ingest_runs (
    run_id         UUID PRIMARY KEY,
    source_file    TEXT        NOT NULL,
    target_table   TEXT        NOT NULL,
    started_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at    TIMESTAMPTZ,
    status         TEXT        NOT NULL DEFAULT 'running',  -- running | success | failed | aborted
    rows_read      INTEGER     NOT NULL DEFAULT 0,
    rows_valid     INTEGER     NOT NULL DEFAULT 0,
    rows_rejected  INTEGER     NOT NULL DEFAULT 0,
    rows_loaded    INTEGER     NOT NULL DEFAULT 0,
    error_message  TEXT
);

-- Rejected rows are NOT discarded and NOT allowed to fail the whole file.
-- They land here with the raw payload and the reason, so a rejection rate can
-- be trended and a bad row can be replayed after a parser fix.
CREATE TABLE IF NOT EXISTS raw.error_records (
    error_id       BIGSERIAL PRIMARY KEY,
    run_id         UUID        NOT NULL REFERENCES raw.ingest_runs (run_id),
    source_file    TEXT        NOT NULL,
    source_lineno  INTEGER,
    reason         TEXT        NOT NULL,
    payload        JSONB       NOT NULL,
    rejected_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_error_records_run ON raw.error_records (run_id);
