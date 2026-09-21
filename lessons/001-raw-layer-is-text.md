# 001 — The raw layer is all TEXT

> Fidelity first. A raw table's job is to preserve what arrived, not to judge it.

**Concept:** where in a pipeline failures should surface
**Lives in:** `sql/002_raw_tables.sql`, `dbt/models/staging/`
**Status:** settled

## What happened

Every data column in `raw.*` is `TEXT`. No casts, no coercion, no dropping. The
first instinct is the opposite — `best_of` is obviously an integer, so type it as
one. We didn't, and within an hour that paid off.

`dbt build` failed on `stg_matches`:

```
invalid input syntax for type integer: "Zindaras"
```

`Zindaras` is a person — the volunteer who charted the match. Two rows in the
upstream matches files are missing both player-name fields, so every value shifts
one column left and the charter's name lands in `Best of`.

## The evidence

```sql
SELECT match_id, player_1, player_2, tournament, best_of
FROM raw.mcp_matches WHERE best_of !~ '^[0-9]+$';
```
```
 player_1 | player_2 | tournament |     round      | best_of
----------+----------+------------+----------------+----------
 R        | R        | 15:15      | Unipol Arena   | Zindaras
```

`player_1` holds a handedness. `tournament` holds a time. Every field is
individually plausible; the row is nonsense.

Because raw was TEXT, those rows **loaded**, and the problem appeared in the
staging layer — named, located, with the offending value printed. Had raw been
typed, the `COPY` would have aborted mid-file with a line number and no context,
and the natural fix would have been to skip the bad row and move on. We'd have
lost the evidence.

## The trade-off

| | Cast at ingest | Cast in staging (chosen) |
|---|---|---|
| Bad data | fails immediately | lands, then fails visibly downstream |
| Diagnosis | a line number | a named column, a value, a model |
| Upstream schema drift | breaks the loader | breaks one staging model |
| Rebuild after a fix | re-download and re-ingest | `dbt build`, seconds |
| Cost | — | one extra layer; every staging model must cast explicitly |

The real argument is the last row. Marts are **rebuildable** from raw, so raw is
the rollback point. If raw is lossy, there's nothing to roll back to.

The cost is real: every staging column needs an explicit `::type`, and forgetting
one means a silent `text` column downstream. That's what the `dbt` schema tests
are for.

## Saying it out loud

> I keep the landing tables untyped on purpose. The raw layer's job is fidelity,
> not correctness — if I cast at ingest, a bad row kills the load and I lose the
> evidence. Casting in staging means bad data still lands, but it fails in a named
> model with the actual value in the error, and I can fix it and rebuild in
> seconds without re-downloading anything. It cost me one extra layer and it
> caught a real column-shift bug in the source on day one.

## Try it yourself

`stg_matches` casts `best_of` to `int`. Which other staging casts would break if
upstream shipped one malformed row — and which of those would fail *loudly* vs.
silently produce a NULL? (Hint: `::int` vs. `nullif(x,'')::int` behave very
differently.)
