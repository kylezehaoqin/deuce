# Tennis Analytics Agent — working notes

Natural-language analytics agent over Jeff Sackmann's Match Charting Project data.
Two stacked layers in one repo: a dbt/Dagster/Postgres warehouse, and a LangGraph
text-to-SQL agent on top of it. See README.md for the vision and the increment plan.

## Commands

    make help              every target
    make up / down         Postgres + pgvector on :5433
    make db-init           apply sql/*.sql (idempotent)
    make ingest            matches + serve-direction stats (fast)
    make ingest-points     point-by-point files (large)
    make status            ingest funnel + dead-letter count
    make demo PLAYER="…"   Increment 0 proof-of-life query
    make dbt-build         run + test all dbt models
    make lint test         ruff + pytest

Python is pinned to 3.12 (`.python-version`) — dbt-core and Dagster do not support
3.13+. Do not bump it to match a newer system Python.

## Conventions

- **Raw is TEXT.** `raw.*` mirrors the upstream CSVs with no casting. Casting,
  renaming and business rules belong in dbt. Never "fix" data in the loader.
- **Layers:** `stg_` = 1:1 with raw, clean/cast/rename only. `int_` = joins and
  logic, no aggregation. `fct_`/`mart_` = what the agent queries.
- **Adding a source:** one `SourceSpec` in `src/tennis_analytics/ingest/sources.py`
  + one table in `sql/002_raw_tables.sql`. `tests/test_sources.py` enforces that
  the two agree.
- Column naming: `_at` timestamps, `is_` booleans, `_id` keys, snake_case.
- Ingest metadata columns are underscore-prefixed (`_run_id`, `_loaded_at`) so they
  never collide with an upstream column name.

## Landmines

- Upstream `Gm#` is `'X'` or `'X (Y)'` depending on charting era; `TbSet` is
  `'1'/'0'` or `'True'/'False'`. Both are handled in `stg_points` — assume more of
  this kind of variance exists.
- The shot-notation codebook (`docs/mcp-notation.md`) is **not** fully verified,
  especially shot-direction orientation. Validate any parser against Sackmann's own
  `charting-*-stats-*.csv` aggregations before building metrics on it.
- 11 rows in the upstream matches files are field-shifted (missing both player-name
  fields). The loader rejects them on field count; they are in `raw.error_records`.
  Re-loading does not delete rows that *became* invalid -- truncate and reload if a
  validation rule tightens.
- Never commit match data or the private career docs (`0*.md`,
  `tennis-questions.yml`) — both are gitignored. This repo is public.

## Open work

- `dbt/models/marts/fct_shots.sql` — stub, `enabled=false`. Grain decision written
  up in the file header.
- `src/tennis_analytics/agent/prompts.py` — `SYSTEM_PROMPT` is a TODO.
