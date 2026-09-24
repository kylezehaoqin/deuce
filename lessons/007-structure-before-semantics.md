# 007 — Field counts before field values

> A shifted row has no invalid values. Every field is plausible; they're just in
> the wrong columns. Only the arithmetic can see it.

**Concept:** structural vs. semantic validation
**Lives in:** `src/deuce/ingest/loader.py` → `_reject_reason`
**Status:** settled

## What happened

The loader validates rows with Pydantic: `match_id` non-empty, `pt` numeric,
player references in `{1, 2}`. Reasonable, and it passed this row:

```
20240915-M-Davis_Cup_World_Group-RR-Botic_Van_De_Zandschulp-Matteo_Berrettini,R,R,20240915,…
```

Compare a good row:

```
20241124-M-Davis_Cup_Finals-RR-…,Botic Van De Zandschulp,Matteo Berrettini,R,R,20241124,…
```

The bad row is missing both player-name fields — 13 fields where 15 are expected.
Every remaining value shifts left by two: handedness into `Player 1`, a time into
`Tournament`, the charter's name into `Best of`.

**No individual field is invalid.** `R` is a fine string. `15:15` is a fine
string. A per-field validator cannot possibly catch this, because per-field is
the wrong unit of analysis.

## The fix

Check the *shape* of the row before checking any value in it:

```python
if raw_row.get(_EXTRA_KEY) is not None:
    return f"too many fields: {len(raw_row[_EXTRA_KEY])} unexpected trailing values"
short = [k for k, v in raw_row.items() if v is _MISSING]
if short:
    return f"too few fields: row ends before {short[0]!r}, columns are shifted"
```

This needed a change to how the reader is constructed. `csv.DictReader` silently
pads short rows with `None` and silently bins extra fields under a `None` key —
both failure modes are invisible by default. Naming them makes them detectable:

```python
csv.DictReader(fh, restkey=_EXTRA_KEY, restval=_MISSING)
```

`_MISSING` is a sentinel object, not `None`, because `None` is also a legitimate
value — a distinction worth making deliberately.

## The evidence

```
                              reason                              | count
------------------------------------------------------------------+-------
 too few fields: row ends before 'Final TB?', columns are shifted |     8
 too few fields: row ends before 'Umpire', columns are shifted    |    14
```

22 rows across the matches files. They now sit in `raw.error_records` with the
full payload, and `dbt build` went from 1 error to green.

## The general rule

Validation has levels, and they catch disjoint classes of problem:

| Level | Question | Catches |
|---|---|---|
| **Structural** | Is this row the right shape? | shifts, truncation, unescaped delimiters |
| **Type** | Does each value parse? | `"Zindaras"` in an int column |
| **Semantic** | Is each value legal? | serve direction = `'Q'` |
| **Relational** | Do rows agree with each other? | a match with three winners |
| **Statistical** | Is the distribution normal? | null rate jumps from 2% to 40% |

Most pipelines implement levels 2 and 3 and skip 1 — which is backwards, because
a structural failure **invalidates every other check you run on that row**. A
type check on a shifted row is worse than useless: it can pass.

Run them cheapest-and-most-fundamental first.

## The trade-off

Strict field counts can over-reject: a legitimate row with trailing empty fields
and no trailing commas looks short. We measured before trusting it — 22 rows out
of 11,830, all genuinely malformed. If it had rejected 5%, the right response
would have been a warning tier rather than a rejection.

**Measure the rejection rate before you trust a rejection rule.**

## Saying it out loud

> My row validation passed a row that was completely wrong. Two fields were
> missing from the source, so every value shifted one column left — handedness
> ended up in the player-name column, the charter's name ended up in "best of".
> Nothing was individually invalid, so a per-field validator can't see it; you
> have to check the field count. I reordered validation so structural checks run
> before value checks, because a shifted row makes every other check meaningless
> — it can pass type validation and still be garbage. Then I measured the
> rejection rate before trusting the new rule: 22 rows out of 11,830, all real.

## Try it yourself

`raw.mcp_points` has 1.87M rows and zero rejections. Is that because the points
files are clean, or because the checks don't apply there? Find a level-4
(relational) check that *would* have something to say about them.
