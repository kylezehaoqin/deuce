# 005 — Shot direction orientation

> Three direction codes produce five tactical categories. The extra information
> has to come from somewhere — and that "somewhere" is what makes shot parsing
> stateful.

**Concept:** stateless vs. stateful parsing; why grain is a real decision
**Lives in:** `docs/mcp-notation.md`, `dbt/models/staging/stg_stats_shot_direction.sql`
**Status:** scope **RESOLVED**; the tactical mapping is the remaining work.

## The question

A shot in the notation is a letter then a digit: `b3` is a backhand to
direction 3. What is direction 3?

This is the one code in `docs/mcp-notation.md` still marked ❓, and it is the
most consequential: *"how often does she go down the line off the backhand"*
depends entirely on the orientation, and getting it backwards produces answers
that look completely plausible and are exactly wrong.

## Resolved by the spec (2026-09-21)

The Instructions tab of `MatchChart 0.3.2.xlsm` states it outright:

> `1` = to a right-hander's forehand side / left-hander's backhand side
> `2` = down the middle of the court
> `3` = to a right-hander's backhand side / left-hander's forehand side

**Direction is absolute**, naming fixed halves of the court by reference to a
right-handed receiver. Not relative to the hitter. Everything derived below from
first principles was right — and was also written down the whole time, in a file
listed in the upstream repo. See `errors.md` E10.

Two further facts from the spec that bear directly on the remaining gap:

- **Forced errors require only shot type + `#`.** `b#` is complete and valid, so
  point-ending forced errors frequently carry **no direction**.
- **Direction is optional on every shot.** `fbh` is a valid rally.

## The structural insight (confirmed by the spec)

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

## Resolved — and the residual turned out to be people

Two corrections, both measured, took the per-match gap from **+19.55 to a median
of +1**:

```
 start                                    +19.55 avg gap   1.19% exact
 H10b  allow leading lets in the strip    +16.89
 H10a  subtract net unforced errors        +2.34            5.69% exact
```

**H10b — the let.** 19,687 points in the 2020s begin with `c` (a let, repeatable).
The serve+return strip was anchored `^[0-9]`, so on those points it silently
matched nothing and the whole rally — return included — survived into the count.
Found by grouping on `left(rally, 1)`, not by re-reading the regex. **When a regex
"works", check what it silently declines to match.**

**H10a — but only into the net.** Sackmann excludes the point-ending shot, as in
rally length (lesson 004) — but only when it was an **unforced error into the
net**. That is physically exactly right: a ball that hit the net never crossed the
opponent's baseline, so there is no direction to record. A ball that went wide or
long did cross it, and he counts those.

The rejected alternatives are the evidence:

| Subtraction rule | avg gap |
|---|---:|
| all unforced errors | −19.65 (over-corrects 8×) |
| net errors, any terminator | −5.21 (forced net errors *are* counted) |
| + shank / unknown-error | +2.32 (indistinguishable) |
| **net unforced only** | **+2.34** |

**The residual is charter idiosyncrasy, not a missing rule.** Per-charter mean gap:

```
 Angel Moreno   104 matches   -15.48   sd 7.42
 Ludo           835           -4.09    sd 5.60
 Zindaras      1480           +1.41    sd 7.84
 BG             625           +7.16    sd 9.82
 Isaac          837          +12.14    sd 8.28
```

Between-charter means span 28 shots; within-charter spread is a near-constant
sd ≈ 7–8. The highest-volume charter sits at +1.41. So the rule is right and
different volunteers apply the notation slightly differently — which is precisely
what `dim_charters` exists to measure. A thing built to document a nuisance ended
up explaining a three-session mystery.

Two corroborating signals that this is noise and not a rule:

- **Direction flipped.** At the start, 5,817 matches over-counted and **1** under-
  counted — the signature of a missing exclusion. Now it is 3,218 over and 2,335
  under. Balanced error is what "we have the rule, people are inconsistent" looks
  like.
- **It is era-independent** (+2.09 / +2.34 / +4.50 across 2010s / 2020s /
  pre-2010), unlike the rally-length parser's 90 / 82 / 55%. A *scope* rule
  generalises across charting eras; a *token-level parse* does not. Worth
  remembering as a way to tell which kind of thing you are looking at.

H10c — undirected shots counted under a default — was never needed.

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
