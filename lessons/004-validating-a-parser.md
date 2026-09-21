# 004 — Validating a parser with no labelled data

> Someone else already implemented your spec. Their output is your test set.

**Concept:** oracle testing; regression baselines instead of perfection
**Lives in:** `dbt/macros/mcp_rally_length.sql`,
`dbt/tests/assert_rally_length_matches_oracle.sql`
**Status:** settled

## What happened

Rallies arrive as one opaque string: `4b37y1r3n#`. Any statistic about rally
length depends on decoding it correctly, and there is no labelled dataset saying
how long each rally was.

Except there is. Sackmann publishes `charting-*-stats-Rally.csv` — **his own
aggregation of the same strings**. An independent implementation of the same
spec. That is ground truth, ~150K rows of it, free.

## The evidence — three rounds of diffing

**Round 1.** Strip everything that isn't a shot-type letter, count what's left,
add 1 for the serve. One match: our totals matched exactly (141 points), buckets
didn't.

```
ours:  1-3: 60   4-6: 39   7-9: 25   10+: 17
his:   1-3: 72   4-6: 30   7-9: 25   10+: 14
```

Systematically one bucket high. **Hypothesis: he excludes the shot that missed.**

**Round 2.** Subtract 1 when the rally ends in `@` (unforced) or `#` (forced):

```
ours:  1-3: 71   4-6: 30   7-9: 25   10+: 14
```

Three buckets exact, one point short, and the buckets no longer summed to 141 —
so one point had fallen to length 0. Found it:

```
 pt |  pts  | first_serve
----+-------+-------------
  7 | 40-40 | 4#
```

An unreturned serve. Rally length 1, not 0. **Clamp with `GREATEST(…, 1)`.**

**Round 3.** Exact match on that match. Then across everything:

```
   era    | matches | pct_exact | within 2 pts | avg % of points misbucketed
----------+---------+-----------+--------------+-----------------------------
 2020s    |    3336 |      91.6 |         96.7 |                        0.18
 2010s    |    2231 |      83.1 |         92.6 |                        0.46
 pre-2010 |    1962 |      54.0 |         67.0 |                        2.73
```

Neither convention — *exclude the miss*, *but never below 1* — is written down
anywhere. Both were **recovered by diffing**.

## The finding that outlived the parser

That era gradient is not noise. **Charting conventions drifted** across the
project's twenty-year history. The same parser is ~92% right on modern matches
and barely better than a coin flip on pre-2010 ones.

So `int_point_rally_length` carries a `parse_confidence` column (`high` /
`medium` / `low`), and the agent is expected to refuse cross-era comparisons
without flagging them. A number is not just a number; it has a provenance, and
provenance belongs in the schema.

## The trade-off: what threshold does the test assert?

The regression test asserts **88% / 78% / 45%** — just under the measured
baseline, not 100%.

| | Assert perfection | Assert the baseline (chosen) |
|---|---|---|
| Catches regressions | yes | yes |
| Fails on upstream noise | constantly | no |
| Outcome after a week | muted or deleted | still trusted |

A test that fails for reasons you can't fix gets ignored, and an ignored test is
worse than no test — it's a green checkmark that means nothing. The threshold
encodes *"this used to be 90%; tell me if it drops"*, which is the actual
question.

## Saying it out loud

> There was no labelled data for the parser, but the data's author publishes his
> own aggregations of the same source strings — so I used his output as an oracle
> and diffed against it. Two of his conventions weren't documented anywhere; I
> recovered them from the diff, one bucket at a time. That got me to 91.6% exact
> agreement on modern matches — but only 54% on pre-2010, because the charting
> conventions drifted. So I carry a parse-confidence column through the models
> and the agent has to disclose it. The regression test asserts just below the
> measured baseline rather than perfection, because a test that fails on noise
> gets muted, and then you have a green build that means nothing.

## Try it yourself

`charting-*-stats-ShotTypes.csv` is the oracle for the *letter* mapping. Build
the same diff for it: does `f` really mean forehand? Start with one match, find
the systematic offset, form a hypothesis, then measure across all of them.
