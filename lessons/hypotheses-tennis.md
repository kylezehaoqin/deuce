# Hypothesis log — tennis

Claims about **the game and the players**: "Federer is not a grinder", "momentum
is a myth", "players get more predictable under pressure."

These are a different kind of claim from the ones in
[hypotheses-data.md](hypotheses-data.md). A format question has a right answer
that someone already knows; you settle it by reconciling against the spec or an
oracle and then it's done. A tennis question has no answer key. It's settled by
evidence, and it stays provisional — a bigger sample, a different era, or a
confound you hadn't thought of can reopen it.

So each entry needs three things a data hypothesis doesn't:

- **What would falsify it** — stated *before* the query. A claim that survives
  any result isn't a hypothesis, it's a vibe.
- **The confound** — what else could produce this pattern. Skip this and you get
  lesson 006, where the naive answer was confidently backwards.
- **The scope** — sample size, era, `parse_confidence`, and who the opponents
  were. Elite players mostly play elite players; absolute rates aren't
  comparable across players even when they look like they are.

**These are also the eval set.** Each one is a question the agent will be asked,
and the verdict here is the reference answer — including the caveats, which is
the part the agent has to reproduce to count as grounded.

---

| # | Hypothesis | Verdict |
|---|---|---|
| [T1](#t1) | Federer is a first-striker; Nadal is a grinder | ✅ supported |
| [T2](#t2) | Momentum is real | ❌ refuted |
| [T3](#t3) | Players get more predictable under pressure | ❌ refuted (it's player-specific) |
| [T4](#t4) | Medvedev has no body serve | ✅ supported |
| [T5](#t5) | Alcaraz is readable on the ad court | ⚠️ suggestive — needs the pressure slice |
| [T6](#t6) | The serve+1 forehand into the open court is a real pattern | ⬜ untested |
| [T7](#t7) | The backhand down the line is a highlight-reel trap | ⬜ untested |
| [T8](#t8) | Breaking serve makes you more likely to get broken back | ⬜ untested |
| [T9](#t9) | Players can be clustered by play style from shot-mix data | ⚠️ partial — the naive vector is misleading |
| [T10](#t10) | Alcaraz's direction tendencies changed over his career | ⚠️ confounded by charter drift — do not report yet |

---

## T1
**Claim:** Federer is a first-strike player, not a grinder. Nadal is the inverse.

**Falsifiable if:** their win rate by rally-length bucket doesn't slope in
opposite directions, or their rally-length distributions look alike.

**Test:** win rate by rally length (1-4 / 5-8 / 9+), per player, over every point
they played.

```
     player      | points | avg_rally | share_short | win_1_4 | win_5_8 | win_9_plus
-----------------+--------+-----------+-------------+---------+---------+------------
 Roger Federer   | 125338 |      4.47 |       0.636 |   0.541 |   0.533 |      0.530
 Rafael Nadal    |  70896 |      5.32 |       0.550 |   0.514 |   0.545 |      0.543
 Novak Djokovic  |  93603 |      5.34 |       0.559 |   0.528 |   0.541 |      0.545
 Jannik Sinner   |  47739 |      4.92 |       0.590 |   0.539 |   0.539 |      0.544
 Carlos Alcaraz  |  36949 |      4.65 |       0.599 |   0.524 |   0.548 |      0.543
 Daniil Medvedev |  45534 |      5.43 |       0.572 |   0.523 |   0.521 |      0.540
```

**Verdict: ✅ supported.** Federer: shortest average rally (4.47), most short
points (63.6%), and the only player whose win rate *declines* as rallies lengthen
(.541 → .533 → .530). Nadal is the mirror: fewest short points, win rate *rises*
(.514 → .545 → .543).

**Read the slope, not the level.** Absolute win rates cluster near .53 because
these players mostly beat people; the differences between players are opponent
quality as much as style. Only the within-player slope is interpretable.

**Caveats:** opponent quality uncontrolled; era uncontrolled (Federer's sample
skews older, where `parse_confidence` is lower); surface uncontrolled, which
matters enormously for Nadal specifically. **Medvedev breaks the neat story** —
longest average rally (5.43) but a non-monotonic slope (.523 → .521 → .540).
Being a long-rally player and being a *good* long-rally player are different
things, and this two-axis framing (rally length vs. slope) is the better model.

**UPDATE — Federer's half of this is bucketing-dependent.** `mart_rally_shape`
recomputes the slope on Sackmann's four buckets (1-3 / 4-6 / 7-9 / 10+) rather than
the 1-4 / 5-8 / 9+ used above, and fits it by least squares with a goodness-of-fit:

```
 Roger Federer   .5325  .5518  .5045  .5335   slope -0.0044   r2 0.086
 Rafael Nadal    .5141  .5562  .5547  .5495   slope +0.0105   r2 0.463
 Iga Swiatek                                  slope +0.0175   r2 0.999
 Hubert Hurkacz                               slope -0.0228   r2 0.603
```

Federer's pattern is **not monotone** on four buckets, and r² of 0.086 says a line
explains essentially none of it. The "only player whose win rate declines" claim
came from three coarser buckets that smoothed the 7-9 dip away.

**Nadal's half survives** (positive slope, r² 0.46), and the slope ranks the wider
field sensibly — Hurkacz, a serve-dominant player, is the most negative; Swiatek is
near-perfectly monotone the other way.

**Revised verdict: ⚠️ half supported.** Nadal is a grinder by this measure.
Federer is *not* demonstrably a declining-with-length player; he is a player whose
mass sits in short rallies (61% of his points in 1-3, the highest in the group),
which is a claim about `share_of_points`, not about win rate.

**The lesson is about bucket boundaries.** Choosing three buckets instead of four
changed a finding. Any claim that depends on a discretisation should be re-run under
a different one before it is reported — and reporting the fit alongside the slope
is what made this visible at all.

## T2
**Claim:** momentum is real — winning a hard-fought point makes you likelier to
win the next one.

**Falsifiable if:** the effect disappears, or points in opposite directions, once
the service advantage is held constant.

**Confound (the whole story):** long rallies favour the returner, and returners
win fewer points overall. Pooled, you measure serving and call it momentum.

**Test:** consecutive points *within the same game* (server constant), split by
who won the previous point.

```
       control        |    previous_point     |   n    | same_player_wins_next
----------------------+-----------------------+--------+-----------------------
 returner won prev pt | after short pt (<=4)  | 320823 |                0.3949
 returner won prev pt | after LONG rally (9+) |  63575 |                0.4046
 server won prev pt   | after short pt (<=4)  | 473757 |                0.6299
 server won prev pt   | after LONG rally (9+) |  78681 |                0.6099
```

**Verdict: ❌ refuted.** The halves move in **opposite directions** — returner
+1.0pp, server −2.0pp. Momentum would help whoever just won. What's actually
happening: a long rally predicts the next point is also contestable, and
contestable points favour the returner.

**Scope:** 2010+ only (parser reliability). 63K–474K per cell, so not noise.
Cross-game transitions were excluded by the control — which is exactly the data
T8 needs, so that's a separate query, not a looser control here. → lesson 006.

## T3
**Claim:** players become more predictable when serving under pressure.

**Falsifiable if:** serve-direction entropy on break points is *higher* than
elsewhere, for some or all players.

**Test:** ad-court first serves, entropy over wide/body/T, break point vs. all
other points.

```
     server      |  situation  | serves | wide  | body  |   t   | entropy
-----------------+-------------+--------+-------+-------+-------+---------
 Carlos Alcaraz  | all other   |   7008 | 0.490 | 0.156 | 0.354 |  0.9165
 Carlos Alcaraz  | break point |    878 | 0.510 | 0.195 | 0.295 |  0.9303
 Novak Djokovic  | all other   |  17934 | 0.515 | 0.088 | 0.396 |  0.8400
 Novak Djokovic  | break point |   2300 | 0.476 | 0.097 | 0.427 |  0.8589
 Roger Federer   | all other   |  23840 | 0.564 | 0.060 | 0.376 |  0.7822
 Roger Federer   | break point |   2559 | 0.521 | 0.045 | 0.435 |  0.7651
 Rafael Nadal    | break point |   1937 | 0.558 | 0.153 | 0.290 |  0.8845
 Daniil Medvedev | break point |   1164 | 0.550 | 0.036 | 0.414 |  0.7408
 Jannik Sinner   | break point |   1135 | 0.563 | 0.062 | 0.375 |  0.7856
```

**Verdict: ❌ refuted as a general claim.** Djokovic and Alcaraz get *less*
readable on break point (entropy up). Federer, Nadal, Medvedev and Sinner get
slightly more readable. There is no tour-wide tendency — **it's a player
property**, which makes it a scouting feature rather than a rule.

**Caveats:** effect sizes are small (±0.02 entropy) and no significance test has
been run — the next honest step is a bootstrap CI, because with ~1,000 break
points per player these differences may not clear noise. Break point is a coarse
proxy for pressure; 30-40 specifically, or set/match points, may separate more.

## T4
**Claim:** Medvedev essentially doesn't use the body serve.

**Falsifiable if:** his body-serve share is comparable to peers.

**Test:** see T3. Medvedev **4.5%** body on the ad court, against 15.6%
(Alcaraz), 17.7% (Nadal), 8.8% (Djokovic).

**Verdict: ✅ supported**, and it's the cleanest single finding so far — a 3–4×
gap on ~10K serves, not a marginal effect. He is effectively a two-option server
on the ad court, which is why his entropy (0.77) is among the lowest.

**Actionable form:** if you return against Medvedev on the ad court, you can
essentially ignore the body serve and cheat toward the two corners.

## T5
**Claim:** Alcaraz is materially more predictable on the ad court than the deuce
court.

**Test:** `make demo PLAYER="Carlos Alcaraz"` — 221 charted matches.

```
 court_side | direction | serves | share  | entropy
------------+-----------+--------+--------+---------
 deuce      | wide      |   3595 | 0.3871 |  0.9800
 deuce      | T         |   3487 | 0.3754 |  0.9800
 deuce      | body      |   2206 | 0.2375 |  0.9800
 ad         | wide      |   4424 | 0.5289 |  0.9225
 ad         | T         |   2243 | 0.2682 |  0.9225
 ad         | body      |   1697 | 0.2029 |  0.9225
```

**Verdict: ⚠️ suggestive, not settled.** Deuce court is near-maximally
unpredictable (0.98, an almost even three-way split); ad court drops to 0.92 with
**53% going wide**. Directionally real, but 0.92 is still high in absolute terms
— "leans wide" is honest, "readable" overstates it.

**Why it isn't settled:** this is pooled across all situations, and T3 shows
Alcaraz's ad-court entropy *rises* under pressure. A tendency that disappears
exactly when it would matter isn't a scouting insight. Needs the pressure slice
before it goes in a report.

## T6
**Claim:** after a wide serve on the deuce court, the server's next shot is
disproportionately a forehand into the open court, and it wins at an elevated
rate. (`questions.yml` serve-02)

**Blocked on:** `fct_shots`. Needs shot 2 identified by type *and* direction,
plus "open court" resolved relative to where the serve pulled the returner —
stateful, per `docs/mcp-notation.md`.

**Confound to plan for:** wide serves already produce weak returns. The
comparison isn't "serve+1 forehand vs. all points" but "serve+1 forehand vs.
other serve+1 options *from the same return quality*."

## T7
**Claim:** the backhand down the line produces as many errors as winners — a
highlight-reel shot that's negative expected value. (`questions.yml` #6)

**Blocked on:** the direction orientation (`lessons/005`), then `fct_shots`.
Down-the-line is hitter-position-relative, so it needs the stateful parse.

**Note before testing:** direction is *optional* in the charting spec, so the
denominator is "backhands with a direction charted", not "backhands". State it
or the rate is wrong.

## T8
**Claim:** right after breaking serve, a player is more likely than baseline to
get broken straight back — the "let-down game". (`questions.yml` #11)

**Needs:** game-level aggregation and the cross-game transitions T2's control
deliberately excluded.

**Confound:** players who just broke are often the weaker server in the matchup
(that's frequently *why* the break happened), so the baseline has to be that
player's own hold rate, not the tour's.

## T9
**Claim:** players can be clustered by play style from shot-mix and direction
data, well enough that "who plays like Federer" returns a list a coach would
recognise. (Kyle's idea: use A's results against B's style-neighbours to scout
A vs B — Djokovic beat Federer this way, Dimitrov plays like Federer, so…)

**Falsifiable if:** the neighbours are implausible, or the clustering collapses
when an obvious give-away feature is held out.

**Test 1 — can the data see a one-handed backhand?** Proxy: share of
backhand-side shots that are slices.

```
 Grigor Dimitrov    | 0.521 | 1HBH        Andy Murray      | 0.235 | 2HBH  <- intruder
 Roger Federer      | 0.365 | 1HBH        Richard Gasquet  | 0.224 | 1HBH
 Lorenzo Musetti    | 0.354 | 1HBH        Novak Djokovic   | 0.121 | 2HBH
 Dominic Thiem      | 0.320 | 1HBH        Jannik Sinner    | 0.059 | 2HBH
 Stan Wawrinka      | 0.308 | 1HBH        Daniil Medvedev  | 0.059 | 2HBH
```

Strong separation, with Murray (a slice-heavy two-hander) crossing into
one-hander territory and Gasquet (a one-hander who drives rather than slices)
falling below him. **The feature measures style, not grip** — which for this
purpose is the right thing to measure.

**Test 2 — nearest neighbours to Federer**, 10-feature z-scored vector
(shot mix, net share, winner/unforced rate, direction distribution), players with
≥50 charted matches.

First attempt returned **Ana Ivanovic** as the closest player to Federer, with
Venus Williams and Ekaterina Alexandrova also in the top 12. Cause: the ATP and
WTA populations were pooled, so both the z-scores and the distances were
dominated by tour-level differences in shot mix rather than by style.

Restricted to ATP and re-standardised within it:

```
 Dominic Thiem 2.13 | Ivan Lendl 2.15 | Lorenzo Musetti 2.22 | Tsonga 2.34
 Tsitsipas 2.50 | Dimitrov 2.50 | Berdych 2.57 | Kuerten 2.65
```

Plausible — four one-handers plus three flat, aggressive baseliners.

**Test 3 — the holdout.** Remove both slice features and rebuild:

```
 Ugo Humbert | Nick Kyrgios | Khachanov | Davydenko | Fonseca
 Musetti(1H) | Alcaraz | Kuerten(1H) | Feliciano Lopez(1H) | Davidovich Fokina
```

One-handers drop from 5 of 10 to 3 of 10, and what remains is a generic
"aggressive shot-maker" axis that ignores backhand entirely.

**Verdict: ⚠️ partial.** The signal is real but shallow — the vector was
substantially reading one give-away feature. Two honest limits:

1. **The data cannot see what Kyle described.** Trajectory, pace and spin are
   not charted at all, so "flatter forehand" is unavailable. What *is* available:
   shot mix, direction tendencies, court position, error profile. Style here
   means "what shots, hit where", not "how they come off the strings".
2. **Equal feature weighting is a guess.** Dimitrov — the obvious answer, and
   #1 by slice rate — lands 6th, because slice is 1/10th of the distance. Nobody
   knows the right weights a priori, which is precisely why this needs an
   external objective rather than eyeballing the neighbour list.

**The plausibility trap:** the pooled-tour version *looked* fine. Lendl, Thiem,
Tsonga were all in it; you notice Ivanovic only if you read past the first row.
A similarity model returns a ranked list whatever you feed it, and a ranked list
of famous names reads as insight. This is the strongest argument for making the
evaluation quantitative before trusting any of it.

**Next step if pursued:** retrodiction. Hold out matches; predict something
measurable about A vs B (serve-direction distribution, rally-length mix, point
win rate) from A's record against B's k nearest style-neighbours, and check it
beats two baselines — A's own overall average, and A against randomly chosen
opponents. If style-neighbours don't beat random, there is no product here.

## T10
**Claim:** Alcaraz's shot-direction tendencies changed measurably over his career
— notably inside-out forehands falling from 17.6% to 12.2% of directed shots.

**Falsifiable if:** the trend disappears once surface is held constant, or once
data-collection changes are accounted for.

**Test 1 — surface control.** Restricting to hard courts, four of six apparent
trends survived (slice up, inside-out down, net rate up, winner rate up) and two
dissolved (forehand share, unforced error rate). Those two were surface mix, not
the player.

**Test 2 — the confound I didn't think of.** `mart_data_coverage` now exposes
charting coverage per player-season, and it moves in the same window:

```
 season | matches | dominant_charter | direction_charted_rate
--------+---------+------------------+------------------------
   2019 |       2 | Zindaras         |                 0.9427
   2020 |       3 | Zindaras         |                 0.9007
   2021 |      14 | BG               |                 0.9003
   2022 |      38 | Edo              |                 0.8836
   2023 |      49 | BG               |                 0.8547
   2024 |      43 | Ludo             |                 0.8466
   2025 |      59 | Ludo             |                 0.7965
```

**Direction coverage declines monotonically, 0.943 → 0.797**, as `Ludo` (901
matches at a 0.685 career direction rate) becomes his dominant charter. The
reported inside-out decline sits inside exactly that window.

**Verdict: ⚠️ confounded — not reportable.** The rate is a share of *charted*
directions, so a uniform drop in coverage cancels in the denominator and the
share would be fine. It is only biased if missingness is **non-random with
respect to direction** — and that is plausible rather than paranoid: a charter
skipping direction under time pressure skips the fastest shots, and inside-out
forehands are among the fastest. Untested either way.

**What would settle it:** restrict to matches charted by a single high-coverage
charter and re-run the trend. If it survives on Zindaras-only or BG-only matches,
it's the player. If it vanishes, it was the collection process.

**The general lesson**, which outlives the claim: in a crowdsourced dataset, the
*observation process* has its own time series. Any longitudinal finding needs the
data-collection trend plotted beside it — otherwise you cannot tell a change in
the player from a change in who was watching.
