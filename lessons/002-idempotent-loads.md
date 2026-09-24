# 002 — Loads you can re-run

> Re-running the pipeline must be boring. If it isn't, nobody will re-run it at
> 3am, which is exactly when they'll need to.

**Concept:** idempotency, staging tables, `ON CONFLICT`, the limits of upsert
**Lives in:** `src/deuce/ingest/loader.py`
**Status:** settled

## What happened

Every load goes: `COPY` into a `TEMP` table → check → `INSERT … SELECT … ON
CONFLICT (natural key) DO UPDATE`. Three properties fall out of that shape.

**1. Re-running is safe.** The natural key (`match_id`, or `match_id + pt`)
decides identity, so loading the same file twice produces the same table.

**2. Nothing lands until the whole file is read.** The rejection rate is checked
*before* the `INSERT`. A file that's 40% garbage aborts having written zero rows,
rather than half-loading and leaving the warehouse in a state nobody can reason
about.

**3. Duplicate keys inside one file must be collapsed first.** Postgres refuses
an `ON CONFLICT DO UPDATE` that would touch the same row twice in one statement:

```
ERROR: ON CONFLICT DO UPDATE command cannot affect row a second time
```

Hence `SELECT DISTINCT ON (key) … ORDER BY key` before the insert. This is not
hypothetical — the upstream files are full of them.

## The evidence

```
load.done file=charting-m-points-to-2009.csv  rows_read=379569 rows_loaded=378037 deduped=1532
load.done file=charting-m-stats-Rally.csv     rows_read=96706  rows_loaded=96544  deduped=162
```

`deduped` is logged, never swallowed. 1,532 duplicate point keys in one file is
the kind of thing you want to *know*, even when the handling is correct.

## The trade-off

`COPY` → temp → upsert writes every row twice and needs a second table's worth of
space. A straight `COPY` into the target is roughly twice as fast.

We pay it for the circuit breaker. You cannot inspect data you have already
committed to the destination table, so "validate, then decide, then write" needs
somewhere to put the data in between.

**The gap worth knowing:** upsert never *deletes*. When we tightened validation
and 11 previously-loaded rows became invalid, they stayed in the table — the new
run simply rejected them instead of updating them. We truncated and reloaded.
Upsert converges only when the rules stay the same; when the rules tighten, you
need a full refresh or a tombstone strategy. Say this out loud before an
interviewer asks it.

## Saying it out loud

> The loads are idempotent — rows go through a temp table and land with
> `ON CONFLICT DO UPDATE` on the natural key, so re-running is a no-op. The temp
> table isn't free, it roughly doubles the write, but it's what makes the circuit
> breaker possible: I check the rejection rate before anything reaches the real
> table, so a bad file writes nothing instead of half-loading. The one thing
> upsert doesn't give you is deletes — if I tighten a validation rule, rows that
> were already loaded stay loaded. That needs a full refresh, and it's worth
> knowing which of your tables are in that category.

## Try it yourself

Run `make ingest` twice and diff `raw.ingest_runs`. Then find a source where the
natural key you picked *isn't* actually unique upstream — what does `DISTINCT ON`
choose, and is "first row wins" the right answer for that table?
