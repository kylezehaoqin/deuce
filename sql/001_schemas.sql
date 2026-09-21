-- Runs once, on first boot of an empty Postgres volume (docker-entrypoint-initdb.d).
-- Re-run manually with:  make db-init

CREATE EXTENSION IF NOT EXISTS vector;   -- pgvector, for Increment 3 semantic search
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- trigram, for hybrid (lexical + semantic) retrieval

-- raw       : Match Charting Project CSVs landed as-is. Append-only, all TEXT.
-- analytics : dbt's output (staging / intermediate / marts).
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS analytics;
