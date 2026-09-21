# 005 — Shot direction orientation *(OPEN)*

> Three direction codes produce five tactical categories. The extra information
> has to come from somewhere — and that "somewhere" is what makes shot parsing
> stateful.

**Concept:** stateless vs. stateful parsing; why grain is a real decision
**Lives in:** `docs/mcp-notation.md`, `dbt/models/staging/stg_stats_shot_direction.sql`
**Status:** **OPEN** — ~5% gap unexplained. This one is yours to close.

## The question

A shot in the notation is a letter then a digit: `b3` is a backhand to
direction 3. What is direction 3?

This is the one code in `docs/mcp-notation.md` still marked ❓, and it is the
most consequential: *"how often does she go down the line off the backhand"*
depends entirely on the orientation, and getting it backwards produces answers
that look completely plausible and are exactly wrong.

## The structural insight (this part is settled)

Sackmann's `ShotDirection.csv` has five columns:

```
crosscourt | down_middle | down_the_line | inside_out | inside_in
```

**Five categories, from three codes.** That is not a lookup table — information
is being added. Specifically: *crosscourt* and *down the line* are defined
relative to **where the hitter is standing**, and where the hitter is standing
depends on **where the previous ball went**.

So:

| | Depends on | Parse |
|---|---|---|
| Serve direction | the character itself | stateless — `left(notation, 1)` |
| Shot direction (raw 1/2/3) | the character itself | stateless |
| Crosscourt vs. down the line | hitter position → previous shot | **stateful** |
| Inside-out vs. inside-in | position *and* handedness | **stateful** |

This is the strongest argument for `fct_shots` at **one row per shot**. At point
grain you cannot express "where the previous ball went", so the tactical
categories are unreachable. The grain decision and this question are the same
question.

## The investigation so far

Goal: reconcile our count of directed shots with his, per match. If the counts
agree, the *scope* is right and only the mapping is left.

**Attempt 1** — count `[fb][123]`, all shots. Exact match: **1.0%**.
Cause: modifier characters sit between the letter and the digit — `f;1`, `z^3`,
`j=+2`. The regex never saw them.

**Attempt 2** — allow modifiers: `[fbsr][-+=;^!]*[123]`. Exact: **0.8%**,
average gap **+159 shots per match**. We were counting ~40% too many.

**Attempt 3** — two hypotheses at once: (a) he excludes the serve return,
(b) groundstrokes only, and the forehand slice `r` is not one of them.

```
 matches | pct_exact_fbs | pct_exact_fbsr | avg_gap_fbs | avg_gap_fbsr
---------+---------------+----------------+-------------+--------------
    5888 |           1.2 |            0.9 |        19.5 |         34.0
```

Gap **159 → 19.5**. Both hypotheses are directionally right, and `fbs` beats
`fbsr`, so **the forehand slice is excluded** from his direction counts.

**Also established:** his `Total` row = `F + B + S` for 23,432 of 23,604
player-matches, confirming groundstrokes-only scope.

## The harness

The investigation is now a re-runnable measurement loop with one hole in it:

```bash
make investigate FILE=005_shot_direction_scope.sql
```

Everything except the hypothesis is fixed — oracle side, join, metrics, per-era
breakdown. You edit one CTE (`candidate`) and read a number directly comparable
to the last one. See `sql/investigations/README.md` for why that constraint
matters.

Baseline it reproduces:

```
  era  | matches | pct_exact | avg_gap | too_many | too_few
-------+---------+-----------+---------+----------+---------
 2020s |    5888 |      1.19 |   19.55 |     5817 |       1
```

**Read the last two columns.** 5,817 matches over-count, exactly **one**
under-counts. The error is entirely one-directional — which is what a *missing
exclusion rule* looks like. A mapping error or a flaky regex would scatter in
both directions. That single statistic is strong evidence for H10a and weak
evidence against H10c, and it cost nothing to compute.

## What's left

~19.5 shots per match, about 5% over. Candidate hypotheses, untested:

1. **Point-ending shots are excluded**, mirroring his rally-length convention
   (lesson 004) where the shot that missed doesn't count. Cheap to test and the
   most likely given his other conventions.
2. **The serve+return strip is imperfect.** The regex
   `^[0-9][-+=;^!]*[a-z][-+=;^!]*[1-9]?` assumes a fixed token shape; second
   serves and serve-and-volley points may not match it.
3. **Uncharted directions.** Shots charted without a direction digit that he
   still counts under some default.

Method: pick *one*, test on a single match where you can read the strings by
eye, then measure across all of them. Resist changing two things at once — the
159→19.5 jump above came from a combined test and we still don't know how much
each hypothesis contributed.

## Saying it out loud

> The direction codes are absolute court thirds, but the tactical terms people
> actually care about — crosscourt, down the line, inside-out — are relative to
> where the player is standing, which depends on where the previous ball went.
> Three codes, five categories: the extra information is positional state. That's
> why the fact table has to be at shot grain, and it's why serve placement was
> answerable on day one while shot direction still isn't. I've reconciled the
> scope against the source author's own aggregation — got the gap from 159 shots
> a match down to 19.5 — and I know the remaining candidates, I just haven't
> isolated them yet.

## Try it yourself

Test hypothesis 1. `stg_points.rally_notation` ending in `@` or `#` means the
last shot missed. Exclude those from the directed-shot count and re-measure the
gap. If it overshoots, you've learned it's *some* errors, not all — which is
itself the next hypothesis.
