# Deuce — working notes

Natural-language analytics agent over Jeff Sackmann's Match Charting Project data.
The Python package, dbt project and CLI are all `deuce`. The Postgres database
stays `tennis` -- it is named for the data, not the project, and renaming it
would mean re-ingesting 1.9M points for nothing.
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
`src/deuce/agent/prompts.py`,
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
    make dagster           asset graph + run history at :3000
    make refresh           materialize the daily job (small sources + dbt)
    make backfill PARTITION=…  reload ONE points file; `make partitions` lists them
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
- **Adding a source:** one `SourceSpec` in `src/deuce/ingest/sources.py`
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
- **Indexes are model config, never manual DDL.** `materialized='table'` drops and
  recreates on every build, so a hand-made index vanishes silently. Plain indexes
  go in the `indexes=[...]` config; partial indexes need a `post_hook` because
  that config has no WHERE clause. Both are asserted by
  `assert_indexes_exist.sql` -- an index is state dbt does not consider part of
  the model contract. (lesson 010, errors E11)
- **Measure an index, don't reason about it.** Selectivity says how many rows come
  back, not how much work it is. A partial index on a ~10% boolean beat a plain
  index on a 0.9%-selective column by 150x here, because heap fetches dominate.
  (errors E12)

## Orchestration

`src/deuce/orchestration/` holds the Dagster layer: one asset per
ingest source, dbt models as assets via `dagster-dbt`, a stopped-by-default daily
schedule, and a volume-anomaly asset check per source. 20 assets, 38 checks.

**The seam is fragile by nature and guarded by tests.** The graph joins up only
because the asset key we derive (`raw/<table>`) equals the key dagster-dbt derives
for the matching dbt source. If that drifts, dbt models become graph roots, every
staleness signal silently lies, and `dbt build` still passes. See
`tests/test_orchestration.py`.

**Never put `from __future__ import annotations` in a module defining an asset
that takes `context`.** PEP 563 stringifies the annotation and Dagster inspects it
at runtime, producing an error that names the exact type you used. (errors E13)

Only the points source is partitioned -- by filename, because the six era files
are the real unit of independent reload. A partition key that is a fake date would
give the same UI affordance while reprocessing everything.

## Schema

`docs/schema.md` is the current *state*: physical layout with row counts, ER
diagrams for raw and marts, a layer flow diagram, grain statements for every
table, and the normalisation reasoning (raw breaks 1NF deliberately, marts break
3NF deliberately). `docs/marts.md` is the *plan*; this is what exists.

Both findings recorded there are now **fixed**: the `fct_serve_points` orphan is
dropped, and the fact tables are indexed via model config with
`assert_indexes_exist.sql` asserting they stay that way. The cited agent query
went from 384 ms / 90,482 buffers to 28 ms / 1,026. (lesson 010)

## What to trust

`docs/data-trust.md` tiers every fact in the warehouse: verified against an
external oracle (A), deductively exact (B), usable with a stated caveat (C), not
yet trustworthy (D), and absent from the source entirely. It also lists the
deductions that are defensible and the ones that are not.

**Read it before answering any analytical question**, and before writing the
agent's system prompt -- it is the grounding contract in prose form. An answer
inherits the lowest tier of its inputs.

## Mart design

`docs/marts.md` is the map: the grain ladder, every proposed mart with its grain
and what it unlocks, what is buildable today vs gated on the tokenizer, the build
order, and the open questions. Update it when a mart lands or an assumption
changes — a stale map is worse than none.

## Notes (personal reference + writing backlog)

`notes/` is Kyle's, and distinct from `lessons/`: lessons hold what happened *in
this repo* and why (written for an interviewer); notes hold the **transferable
concept**, plainly (written for future him). Lesson 010 is "we lost every index
and here's the story"; `notes/concepts.md` is "how Postgres indexes work".

- `notes/concepts.md` — reference, appended as concepts come up
- `notes/blog-backlog.md` — post seeds, each with a hook and evidence in hand

When a session produces a genuinely transferable concept or a finding with a
number attached, offer to append it. **Do not draft blog prose** — the posts are
his words; these files are raw material only.

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
- **19,687 points in the 2020s start with `c` (a let).** Any regex anchored at
  `^[0-9]` on a rally string silently matches nothing on those and leaves the whole
  rally intact. Use `^c*[0-9]`. Generally: when a regex "works", check what it
  silently declines to match. (lesson 005)
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

**State:** Increments 0 and 1 complete. `dbt build` 56 pass / 1 warn, pytest 31.
Marts: `fct_points` -> `fct_serves` / `fct_games`, `mart_serve_patterns`,
`dim_players`, `dim_charters`, `mart_data_coverage`. Dagster orchestrates
ingest + dbt. Everything on `main`, **not pushed to a remote yet** -- the brief
wants public dated commits, so that is worth fixing.

Kyle's, in priority order:

- **`src/deuce/agent/prompts.py`** -- `SYSTEM_PROMPT` is a TODO and is
  now genuinely unblocked: three marts exist to route to, and
  `docs/data-trust.md` is the grounding contract it has to encode. This is the
  critical path to Increment 2.
- **`dbt/models/marts/fct_shots.sql`** -- stub, `enabled=false`. Needs a
  tokenizer first (lesson 009); decide its home (Python in `ingest/`, SQL in
  dbt, or the existing Rust parser as an oracle for one of those). Days, not
  hours. Unblocks the tactical direction mapping, serve+1, T6, T7.
- **Three review corrections to lesson 005**, raised and not yet applied:
  the median is 2 not 1 (all eras: mean 2.70, median 2, p25 -3, p75 +8);
  "charter idiosyncrasy" is 23% of residual variance, not the residual
  (between-charter 25.2 of 111.6 total, within-charter 86.4); and the physical
  rationale for the net-unforced-error rule contradicts the measured finding
  that *forced* net errors ARE counted. The rule is solid, the stated reason
  is not -- better to say the mechanism is unknown.

Mine, queued:

- `mart_rally_shape`, `mart_pressure_index`, `mart_player_style`,
  `mart_matchup` -- see `docs/marts.md` build order.
- The pgvector leg once a style mart exists.
