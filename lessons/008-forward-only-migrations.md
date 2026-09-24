# 008 — Forward-only migrations

> Never edit a migration that has already run somewhere.

**Concept:** environment drift
**Lives in:** `sql/`, `src/deuce/db.py` → `apply_migrations`
**Status:** settled

## What happened

Adding three oracle tables, the obvious move was to append them to
`sql/002_raw_tables.sql` — that's where the raw tables live. We created
`sql/004_raw_stats_oracles.sql` instead.

The reason: `002` has already been applied to a running database. Editing it
means the file and the database no longer describe the same thing. A fresh clone
runs the *new* 002 and gets the tables; the existing database ran the *old* 002
and doesn't. Both are "up to date". That divergence is the entire mechanism by
which "works on my machine" happens to schemas.

Forward-only, numbered, additive. `002` is history now, wrong comments and all —
except the comments, which are documentation and safe to correct.

## The trade-off

Every migration ever written stays in the repo forever, and the numbering carries
no meaning beyond order. After a year you have 60 files and no sense of the
current schema.

The standard answers: a periodic squash into a baseline for fresh environments,
and treating `dbt docs` as the description of the *current* state while `sql/`
describes *how it got there*. We're at four files, so neither is needed yet —
but knowing when you'd need them is the part that matters.

## Why `IF NOT EXISTS` everywhere

`apply_migrations()` re-runs every file in order, every time. That's only safe
because each statement is idempotent. It gives us one nice property: Docker runs
these on first boot via `docker-entrypoint-initdb.d`, and `make db-init` runs the
identical files against an already-running database. **One definition, two entry
points, no drift.**

The limit: `CREATE TABLE IF NOT EXISTS` does not reconcile an existing table with
a changed definition. Add a column to `002` today and nothing happens to a
database that already has the table. That's the point at which this hand-rolled
approach should be replaced with a real migration tool (Alembic, sqitch) that
tracks which migrations have run and refuses to skip one silently.

## Saying it out loud

> Migrations are forward-only — I added a new numbered file rather than editing
> the one that had already been applied, because once a migration has run
> somewhere, editing it means the file and the database disagree and you can't
> tell which environments are which. Everything is `IF NOT EXISTS` so the same
> files work as Docker's init scripts and as a re-runnable command. The honest
> limitation is that this doesn't handle *altering* an existing table — at that
> point I'd move to a tool that tracks applied migrations rather than assuming
> idempotency.

## Try it yourself

Add a column to `raw.mcp_matches` by editing `002` and run `make db-init`. Then
check whether the column exists. What would you have to write instead?
