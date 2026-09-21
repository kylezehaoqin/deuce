# 003 — Never trust a column name

> A column called `row` told me it held pressure situations. It held serve
> numbers. Nothing would have failed.

**Concept:** reconciliation as verification; the difference between documented
and verified
**Lives in:** `sql/002_raw_tables.sql`, `dbt/models/staging/_sources.yml`
**Status:** settled

## What happened

`charting-*-stats-ServeDirection.csv` has a column literally named `row`. While
writing the DDL I annotated it from intuition:

```sql
row_label TEXT NOT NULL,  -- source header: 'row' -- e.g. 'Total', 'Deuce', '1st', 'BP'
```

Plausible. Wrong. Nothing tested it, so it sat in the schema as documentation
that other code — and later, an LLM reading the schema — would have believed.

The actual values:

```
 row_label | rows
-----------+-------
 Total     | 23600
 1         | 23600
 2         | 23599
```

`1` and `2` are **serve number**, first and second. Not set number, not pressure.

## The evidence

Counting distinct values shows you *what's there*; it doesn't tell you what it
*means*. `1` and `2` could still have been sets. The test that settles it is
arithmetic: **if these are serve numbers, rows `1` and `2` must sum to `Total`
for every match and player.**

```sql
WITH pivoted AS (
    SELECT match_id, player,
           SUM(serves) FILTER (WHERE row_label = 'Total')       AS total,
           SUM(serves) FILTER (WHERE row_label IN ('1','2'))    AS parts
    FROM ... GROUP BY match_id, player
)
SELECT count(*) AS player_matches,
       count(*) FILTER (WHERE total = parts) AS reconciled
FROM pivoted;
```
```
 player_matches | reconciled | mismatched
----------------+------------+------------
          23600 |      23597 |          3
```

23,597 of 23,600. Set numbers would not do that.

## Why it mattered beyond the comment

The first question in `questions.yml` is *"where does he serve on second-serve
points at 30–40?"*. Believing `row` held pressure contexts implied that question
was answerable from the small pre-aggregated file. It isn't — **that file has no
score dimension at all.** The wrong annotation would have mis-scoped a whole
increment.

It also matters for the agent. Column descriptions are fed to the model as schema
context: a wrong description isn't a stale comment, it's a prompt injection you
wrote yourself.

## The trade-off

Verification costs a query each time. The alternative is documentation that
degrades silently.

The cheap discipline: **every claim in a schema comment should name the check
that would falsify it.** The corrected comment now reads:

```sql
-- Verified values: 'Total', '1', '2' -- where 1/2 are SERVE NUMBER, not set
-- number. Confirmed arithmetically: rows 1+2 sum to Total for 23,597 of
-- 23,600 player-matches.
```

## Saying it out loud

> I'd annotated a column from its name and it was wrong — I assumed it held
> pressure situations and it was serve number. The fix wasn't to look harder, it
> was to find an arithmetic identity that would only hold if my reading was
> right: the parts have to sum to the total. They did, for 23,597 of 23,600
> groups. Now every schema comment I write names the check that would disprove
> it, because those descriptions get fed to an LLM as context and a wrong one is
> worse than a missing one.

## Try it yourself

`stg_stats_rally.row_label` packs two dimensions into one string (`'7-9-2'`).
Find the reconciliation identity that proves the split is right — and then find
the rows where it *doesn't* hold.
