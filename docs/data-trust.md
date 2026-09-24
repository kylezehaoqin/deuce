# What we can and can't trust

Every number in this warehouse falls somewhere on this page. If a question isn't
answerable from Tier A or B, the honest answer says so.

**Two kinds of trust, and you need both:**

- **Parse trust** — did we decode the notation correctly? Settled by diffing
  against an oracle. Objective, closeable.
- **Inference trust** — does the conclusion survive its confounds? Settled by
  controls and sample size. Never fully closeable.

They're independent. A perfectly parsed number can support a wrong conclusion
(T2's naive version was backwards on clean data). A well-controlled analysis on
a bad parse is also wrong. Check both.

---

## Tier A — verified against external ground truth

Someone else computed these independently and we agree with them.

| Fact | Evidence |
|---|---|
| **Serve direction** (wide/body/T) | Character one of the notation. Spec-confirmed; reconciles with `ServeDirection.csv` |
| **Serve fault type** (net/wide/deep/wide+deep) | 99.78% of 333,028 faulted 2020s serves yield a direction, 99.75% a fault type |
| **Rally length** | 90.0% / 82.5% / 55.2% exact agreement with `Rally.csv` by era. Regression-tested |
| **Hold / break rates** | 80.2% men, 66.5% women — both match the real tours |
| **Game winner** | Derivable from the last point for 100% of 296,288 games |
| **Tiebreak detection** | Exact: server rotates in all 4,928, in no regular game |

The hold-rate check is the cheapest and most persuasive of these: it isn't "the
code ran," it's "the number the world already agrees with."

## Tier B — deductively exact, no oracle needed

No external check, but the derivation is closed-form. These can't be wrong
unless the source is.

- **Court side** (deuce/ad) — score parity. Tiebreaks resolve to NULL, not
  guessed.
- **Pressure flags** (break point / game point / deuce) — arithmetic on the
  score, mutually exclusive by construction.
- **Set and game numbers**, points played, score state.
- **Player identity** — 1,739 names, **zero** case or punctuation variants.
  Handedness by majority vote; 49 players had charter disagreements and the vote
  resolves all spot-checked cases correctly.
- **First-serve percentage**, second-serve rates — counting at serve grain.

## Tier C — usable, with the caveat stated

| Fact | Caveat |
|---|---|
| Rally length **pre-2010** | 55.2% agreement. Fine for coarse buckets, not for precise claims |
| Any **direction rate** | Direction is optional in the spec. Denominator is "shots with a direction charted," not "shots" — and missingness correlates with charter and era, so it is **not random** |
| Shot-direction **scope** | Settled: which shots Sackmann counts. Median gap 2/match, 5.7% exact. Good enough to reconcile totals, not to attribute individual shots |
| Anything from a **thin cell** | `questions.yml` says N<20 is thin. `mart_data_coverage` makes this queryable — 19,569 rows of (player, surface, season) with populated-field rates |
| **Charter-skewed** samples | Direction charting ranges 62.3%–90.6% across charters; residual gap spans −9.8 to +10.0 per match by charter |

## Tier D — not trustworthy yet

- **Tactical direction** — crosscourt / down-the-line / inside-out / inside-in.
  The *scope* is solved; the *mapping* is not. Three codes produce five
  categories and the extra information is hitter position, which needs
  `fct_shots`.
- **Anything naming a specific shot** — serve+1 patterns, backhand
  down-the-line, direction changes. Needs the tokenizer (lesson 009).
- **Style similarity vectors** — the holdout showed the vector was largely
  reading one give-away feature. One-handers fell 5/10 → 3/10 without it (T9).
- **Player evolution trends** — surface mix moves underneath the trend.
  Controlling for it killed two of six apparent Alcaraz trends (T10).
- **Match winner** — never derived. Retirements make the last-point shortcut
  unsafe, unlike games.

## Not in the data at all

Not "hard to get" — **absent**. Don't design around them.

- **Trajectory, pace, spin.** "Flatter forehand" is unavailable.
- **Groundstroke depth.** `7/8/9` is service-return depth only.
- **Player rankings, age, fitness, injury.**
- **Court positioning** beyond the `-`/`=`/`+` modifiers.
- **Anything about the 305 orphan points** whose match row is missing upstream.

---

## Deductions we can defend

Ordered by how much weight they'd bear.

**1. Momentum is a rally-length effect, not psychology.** (T2) The strongest
finding here. Half a million points, one control — restrict to consecutive
points within the same game — and the two halves move in *opposite* directions
(returner +1.0pp, server −2.0pp). The naive version says momentum is real; the
controlled version says what looks like momentum is contestability.

**2. Medvedev barely uses the body serve.** (T4) 4.5% on the ad court against
8.8–17.7% for peers. A 3–4× gap on ~10,000 serves. Cleanest single fact in the
project.

**3. First-striker vs grinder is a real, measurable axis.** (T1) Federer:
shortest rallies, most short points, and the only one whose win rate *declines*
as rallies lengthen. Nadal is the mirror. **Read the slope, not the level** —
levels differ by opponent quality.

**4. Fault patterns shift under pressure, per player.** Alcaraz nets 44.9% of
break-point faults vs 39.8% otherwise (decelerating); Medvedev and Sinner go the
other way. New, from `fct_serves`.

**5. Serve predictability under pressure is a player property, not a rule.**
(T3) Djokovic and Alcaraz get *less* readable on break point; Federer, Nadal,
Medvedev, Sinner slightly more. **Caveat: effect sizes are ±0.02 entropy on
~1,000 serves and no significance test has been run.** Treat as suggestive.

**6. Structural rates** — hold, break, deuce frequency, 0–40 recovery — by
player, surface and era.

## Deductions we cannot defend

- **T5** (Alcaraz readable on the ad court). Undercut by T3: his ad-court
  entropy *rises* under pressure, so the tendency vanishes exactly where it
  would matter.
- **Any cross-era comparison** without disclosing `parse_confidence`.
- **Any cross-player comparison of levels** rather than slopes.
- **Style similarity, player evolution** — see Tier D.
- **T3's effect sizes** as precise quantities. Needs a bootstrap CI.

---

## Deciding for a new question

1. Which tier does every input sit in? The answer inherits the **lowest**.
2. What's the denominator, and is the missingness random? (Usually not.)
3. What's `n` for the thinnest cell? Check `mart_data_coverage`.
4. What confound would produce this pattern without the claim being true?
   T2 is the cautionary case — the naive answer was confidently backwards.
5. Is the comparison a slope or a level? Levels rarely survive.

**The habit underneath all five:** write the prediction before running the
query. Without it, a surprising result just looks like a result.
