# Tennis Analytics Agent — working notes

Natural-language analytics agent over Jeff Sackmann's Match Charting Project data.
Two stacked layers in one repo: a dbt/Dagster/Postgres warehouse, and a LangGraph
text-to-SQL agent on top of it. See README.md for the vision and the increment plan.

## Working agreement

**Scaffold, then hand off.** Build the structure, write the comments that name the
trade-off, and leave the 5–15 lines that carry *judgment* as a marked `TODO(kyle)`
with the traps spelled out. Kyle writes those, then asks for review — and review
means pushing back when something is wrong, not rubber-stamping.

What counts as judgment-carrying, and therefore his: grain decisions, parsers,
statistical controls, anything shaping the agent's behavior, and any tennis
hypothesis (`lessons/hypotheses-tennis.md`). What isn't, and therefore isn't worth the round trip:
ingest plumbing, boilerplate, staging models, config, test harnesses.

Two honesty rules on top:

- If a TODO would hand over a problem whose answer is unknown, **say so
  explicitly** rather than dressing a gap up as an exercise. `fct_shots` and
  `lessons/005` are both genuinely open; they say so.
- Never claim something works without running it. Prefer breaking a guard on
  purpose to confirm it fires — that's how `assert_rally_length_matches_oracle`
  was shown to have teeth.

Good scaffold examples to imitate: `dbt/models/marts/fct_shots.sql`,
`src/tennis_analytics/agent/prompts.py`,
`sql/investigations/005_shot_direction_scope.sql`.

## Commands

    make help              every target
    make up / down         Postgres + pgvector on :5433
    make db-init           apply sql/*.sql (idempotent)
    make ingest            matches + serve-direction stats (fast)
    make ingest-points     point-by-point files (178 MB, ~1.9M points, ~60s)
    make ingest-oracles    Sackmann's own aggregations — ground truth for our parser
    make status            ingest funnel + dead-letter count
    make demo PLAYER="…"   Increment 0 proof-of-life query
    make dbt-build         run + test all dbt models
    make investigate FILE=…  run a measurement harness from sql/investigations/
    make lint test         ruff + pytest

Python is pinned to 3.12 (`.python-version`) — dbt-core and Dagster do not support
3.13+. Do not bump it to match a newer system Python.

## Conventions

- **Raw is TEXT.** `raw.*` mirrors the upstream CSVs with no casting. Casting,
  renaming and business rules belong in dbt. Never "fix" data in the loader.
- **Layers:** `stg_` = 1:1 with raw, clean/cast/rename only. `int_` = joins and
  logic, no aggregation. `fct_`/`mart_` = what the agent queries.
- **Migrations are forward-only.** A new table goes in a NEW numbered file in
  `sql/`, never appended to one already applied. Everything is
  `CREATE … IF NOT EXISTS` so Docker's init and `make db-init` run the same files.
  Comments in an old migration may be corrected; statements may not. (lesson 008)
- **Adding a source:** one `SourceSpec` in `src/tennis_analytics/ingest/sources.py`
  + one table in a new `sql/00N_*.sql`. `tests/test_sources.py` enforces that the
  two agree, across every migration file.
- **Oracle sources** (`stats_rally`, `stats_shot_types`, `stats_shot_direction`)
  are Sackmann's own aggregations, ingested like any source. The rule is not
  "no mart may read them" — it is **an oracle may not feed the mart whose parser
  it validates**. Reading `ShotTypes` for style features is fine until
  `fct_shots` exists; after that it is circular. Decide per mart and say so in
  the mart's description. (`docs/marts.md` §6)
- Column naming: `_at` timestamps, `is_` booleans, `_id` keys, snake_case.
- Ingest metadata columns are underscore-prefixed (`_run_id`, `_loaded_at`) so they
  never collide with an upstream column name.

## Verification discipline

- **Every parser claim gets diffed against an oracle**, and the agreement rate
  goes in a dbt test whose threshold sits just *under* the measured baseline — not
  at perfection. A test that fails on upstream noise gets muted, and a muted test
  is a green checkmark that means nothing. (lesson 004)
- **Parsed numbers carry provenance.** `parse_confidence` (high/medium/low by
  charting era) rides on every parsed row; the agent must disclose it rather than
  compare across eras silently.
- **Investigations change one thing at a time.** Use
  `sql/investigations/` — the harness is fixed, one CTE is the hypothesis. Testing
  two at once means you can't attribute the improvement (this already happened —
  `lessons/hypotheses-data.md` H10).
- **Write the prediction before running the query.** The gap between prediction
  and result is the signal; without it a surprising result just looks like a result.

## Mart design

`docs/marts.md` is the map: the grain ladder, every proposed mart with its grain
and what it unlocks, what is buildable today vs gated on the tokenizer, the build
order, and the open questions. Update it when a mart lands or an assumption
changes — a stale map is worse than none.

## Lessons folder

`lessons/` documents *why* decisions were made, plus a running hypothesis log and
an error log. **Append to it as work happens** — a refuted hypothesis or a
diagnosed error is a first-class artifact here, not noise. Entries follow the
template in `lessons/README.md` and always include a "saying it out loud" section:
a ~60-second first-person explanation of the trade-off.

Log errors by *class*, not by fix. The fix is local; the class recurs.

## Landmines

- Upstream `Gm#` is `'X'` or `'X (Y)'` depending on charting era; `TbSet` is
  `'1'/'0'` or `'True'/'False'`. Both are handled in `stg_points` — assume more of
  this kind of variance exists.
- **Charting conventions drifted.** The same parser is ~90% accurate on 2020s
  matches and ~55% pre-2010. Never quote a parsed statistic without its era.
- **The codebook is authoritative now.** `docs/mcp-notation.md` is transcribed
  from the Instructions tab of `MatchChart 0.3.2.xlsm` (the upstream spec). Don't
  re-derive a code from the data — look it up, then verify the *implementation*
  against an oracle. (errors E10)
- **Counting questions don't need a parser; identity questions do.** Rally length
  is one regex and ties a real tokenizer. Anything naming a *specific* shot needs
  ordered records -- shots alternate, so ordering is the only attribution, and
  crosscourt/DTL depends on the previous shot. (lesson 009)
- **Shot direction is OPTIONAL in the spec**, as is return depth. `fbh` is a valid
  rally. Any rate over directions has "shots with a direction charted" as its
  denominator, not "shots". Missingness correlates with charter experience and
  era, so it is not random.
- `7`/`8`/`9` are **service-return depth only**, not general shot depth.
- 11 rows in the upstream matches files are field-shifted (missing both player-name
  fields). The loader rejects them on field count; they land in
  `raw.error_records`. Re-loading does not delete rows that *became* invalid —
  truncate and reload if a validation rule tightens.
- `CASE … ELSE` swallows NULL. Tiebreak scores aren't standard game scores; guard
  them explicitly or every tiebreak point silently becomes `'ad'`. (errors E6)
- Never commit match data or the private career docs (`/0*.md`,
  `/tennis-questions.yml`) — both gitignored, **anchored to the repo root** because
  an unanchored `0*.md` also matches `lessons/001-*.md`. (errors E9)
  This repo is public.

## Open work

- `dbt/models/marts/fct_shots.sql` — stub, `enabled=false`. Grain decision written
  up in the file header. **Kyle's to write.**
- ~~`mart_serve_patterns`~~ — **done.** Kyle chose option C (fact + aggregate):
  `fct_serve_points` (point grain) → `fct_serves` (serve grain, faults included)
  → `mart_serve_patterns` (aggregated, entropy precomputed). Drift between the
  pair is caught by `assert_serve_patterns_matches_fact`.
- `src/tennis_analytics/agent/prompts.py` — `SYSTEM_PROMPT` is a TODO.
  **Kyle's to write.**
- **Shot-direction orientation, `lessons/005`** — ~5% scope gap against Sackmann's
  counts. Harness ready: `make investigate FILE=005_shot_direction_scope.sql`.
  Next step is isolating H10a. Baseline: 1.19% exact, +19.55 avg gap, and the
  error is one-directional (5,817 over-count, 1 under).
