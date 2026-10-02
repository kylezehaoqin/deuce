# Hypothesis log — the data

Claims about **the format**: what the columns mean, how the notation encodes a
rally, what upstream conventions are. These are questions with a right answer
that someone already knows — they get settled by reconciliation against the spec
or an oracle, not by statistics.

Claims about **tennis** — "Federer is a first-striker", "momentum is a myth" —
live in [hypotheses-tennis.md](hypotheses-tennis.md). Those are different in kind:
nobody holds the answer key, so they're settled by evidence, sample size and a
control, and they stay provisional.

Append, don't edit — a refuted hypothesis is the most useful entry in the file.

**Format:** what I believed → how I could be wrong → what the data said → verdict.

---

| # | Hypothesis | Verdict |
|---|---|---|
| [H1](#h1) | `ServeDirection.row` holds pressure contexts | ❌ refuted |
| [H2](#h2) | `ServeDirection.row` values `1`/`2` are serve number | ✅ confirmed |
| [H3](#h3) | `Pts` is server-first | ✅ confirmed |
| [H4](#h4) | Court side is derivable from the score | ✅ confirmed |
| [H5](#h5) | Counting shot letters gives rally length | ⚠️ partial → refined |
| [H6](#h6) | Sackmann excludes the shot that missed | ✅ confirmed |
| [H7](#h7) | Parser accuracy is uniform across the dataset | ❌ refuted (big) |
| [H8](#h8) | Direction digit follows the shot letter immediately | ❌ refuted |
| [H9](#h9) | `ShotDirection` covers all shots | ❌ refuted |
| [H10](#h10) | `ShotDirection` excludes serve returns and non-groundstrokes | ✅ confirmed |
| [H11](#h11) | He excludes the point-ending shot, as in rally length | ⚠️ confirmed *only for net unforced errors* |

---

## H1
**Believed:** the `row` column in `ServeDirection.csv` holds contexts like
`'Total'`, `'Deuce'`, `'1st'`, `'BP'`. Written straight into the DDL as a comment.

**Falsifiable if:** the distinct values aren't those.

**Test:** `SELECT row_label, count(*) … GROUP BY 1`

**Result:** only `Total`, `1`, `2`.

**Verdict: ❌ refuted.** Written from intuition, never checked. → lesson 003.

## H2
**Believed:** `1` and `2` are serve number, not set number.

**Falsifiable if:** rows `1` + `2` don't sum to `Total`. (Distinct values alone
can't distinguish serve number from set number — an identity can.)

**Test:** per match and player, sum serve counts for rows `1`,`2` and compare to
`Total`.

**Result:** reconciled for 23,597 of 23,600 player-matches.

**Verdict: ✅ confirmed.** Consequence: this file has **no score dimension**, so
`questions.yml` serve-01 is unanswerable from it. The points table is required.

## H3
**Believed:** in `Pts`, the left number is the server's score.

**Falsifiable if:** tracing one game shows the wrong side incrementing after a
point the server won.

**Test:** one game, ordered by point number, with `svr` and `pt_winner`.

**Result:** server = player 2; `0-0 → 0-15` after player 1 won; `15-15` after
player 2 won. Left side = server.

**Verdict: ✅ confirmed.** Consequence: `30-40` is a **break point against the
server**, which is what makes it a pressure situation.

## H4
**Believed:** deuce/ad court isn't in the data, but the score determines it —
points played in the game, even = deuce.

**Falsifiable if:** the mapping contradicts known tennis (e.g. `40-40` not deuce).

**Test:** `0-0`→0 even→deuce ✓; `40-40`→6 even→deuce ✓; `AD-40`→7 odd→ad ✓;
`30-40`→5 odd→ad ✓.

**Verdict: ✅ confirmed.** Implemented in `int_point_rally_length.court_side`.
**Watch out:** tiebreak scores (`5-4`) aren't standard game scores and must
resolve to NULL, not fall through a CASE `ELSE` into `'ad'`. That bug was written
and caught before it shipped.

## H5
**Believed:** rally length = 1 + count of shot-type letters.

**Test:** one match vs. `Rally.csv`. Totals matched (141), buckets didn't:
ours 60/39/25/17 vs his 72/30/25/14 — systematically one bucket high.

**Verdict: ⚠️ partial.** Right idea, wrong convention → H6.

## H6
**Believed:** Sackmann doesn't count the shot that missed.

**Test:** subtract 1 when the rally ends `@` or `#`.

**Result:** 71/30/25/14 — three buckets exact, one point missing. The stray was
`4#`, an unreturned serve, driven to length 0. Clamping at 1 → **exact match**.

**Verdict: ✅ confirmed**, with the clamp. Neither rule is documented anywhere;
both were recovered by diffing. → lesson 004.

## H7
**Believed (implicitly):** if the parser is 91.6% accurate, it's 91.6% accurate
everywhere.

**Falsifiable if:** accuracy varies by a data attribute.

**Test:** group agreement by charting era.

**Result:**
```
 2020s    91.6% exact     pre-2010   54.0% exact
 2010s    83.1% exact
```

**Verdict: ❌ refuted, and this was the most valuable refutation so far.**
Charting conventions drifted. Now encoded as `parse_confidence` on every parsed
row. *An aggregate accuracy number hides the only interesting thing about it.*

## H8
**Believed:** a shot is a letter immediately followed by its direction digit —
`[fb][123]`.

**Test:** count matches per match, compare to `ShotDirection.csv`. **1.0% exact.**

**Result:** modifier characters intervene: `f;1`, `z^3`, `j=+2`.

**Verdict: ❌ refuted.** Pattern is `[fbsr][-+=;^!]*[123]`.

## H9
**Believed:** `ShotDirection.csv` covers every shot.

**Test:** is his `Total` row = `F + B + S`?

**Result:** yes, for 23,432 of 23,604 player-matches.

**Verdict: ❌ refuted** — groundstrokes only, no volleys or overheads.

## H10
**Believed:** the remaining gap is (a) serve returns, and (b) forehand slice `r`
being excluded.

**Test:** strip the serve+return token, count `[fbs]` vs `[fbsr]`.

**Result:** average gap per match **159 → 19.5**; `fbs` beats `fbsr`.

**Verdict: ⚠️ partial — OPEN.** Both directionally right, ~5% unexplained.
**Methodological error to avoid repeating:** two hypotheses were tested
simultaneously, so their individual contributions are unknown. → lesson 005.

**Follow-up diagnostic (free, and should have been run first):** of 5,888
matches, 5,817 over-count and **1** under-counts. One-directional error is the
signature of a missing exclusion rule, not a mapping error — a wrong mapping
would scatter both ways. Next round tests H10a in isolation via
`make investigate FILE=005_shot_direction_scope.sql`.

## H11
**Believed:** Sackmann excludes the point-ending shot from `ShotDirection`, the
same convention as rally length (H6).

**Falsifiable if:** subtracting point-ending shots does not move the gap toward 0.

**Test:** four subtraction rules, each measured against the oracle per match.

```
 all unforced errors           -19.65   over-corrects 8x
 net errors, any terminator     -5.21   forced net errors ARE counted
 + shank / unknown error        +2.32   indistinguishable from net-only
 net unforced errors only       +2.34   <-- kept
```

**Verdict: ⚠️ confirmed, but far narrower than stated, and the mechanism is
unknown.** Only unforced errors **into the net** are excluded.

I first explained this physically — a ball into the net never crossed the
opponent's baseline, so it has no direction. **That explanation is refuted by the
same dataset:** forced net errors carry a direction 171,427 times (vs 198,229
unforced), and we count those, matching him. A physical rule would exclude both.
The rule holds; the reason is open.

Combined with H10b's let fix, per-match gap went +19.55 → **mean 2.70, median 2**
(p25 −3, p75 +8, 11,782 matches). Charter identity explains **23.7%** of the
residual variance (total 111.6; within-charter 86.4, between-charter 26.5) — a real
contributor, not the explanation. The other 77% is unexplained. → lesson 005.

**Method note worth keeping:** the first three rounds guessed at *patterns*. The
round that worked started from a **diagnostic** — grouping on `left(rally, 1)`,
which immediately exposed 19,687 rallies beginning with a let that the anchored
strip was silently skipping. Guessing is bounded by imagination; a frequency
table is not.

## H12
**Believed:** for `mart_pressure_index`, a parametric hold model (one point-win
rate per tour × surface, points iid) will (1) overstate hold at 0-0 by 1–3pp,
because hold probability is concave in p above 0.5 and the average p of a mixed
population gives more than the average hold (Jensen); and (2) give 0-40 *more*
leverage than an empirical model, because empirical P(hold | 15-40) is dragged
down by the weak servers who reach it.

**Falsifiable if:** the parametric 0-0 hold lands at or below the measured rate,
or empirical 0-40 leverage is the higher one.

**Test:** parametric P(hold | 0-0) vs measured hold rate, per tour × surface; then
game leverage per state under both models (empirical counts each game once per
state, so deuce revisits don't over-weight long games).

```
 tour | surface |   p   | empirical | parametric |  gap
 M    | Clay    | 0.616 |   0.754   |   0.769    | +0.015
 M    | Grass   | 0.669 |   0.845   |   0.859    | +0.014
 M    | Hard    | 0.646 |   0.806   |   0.823    | +0.016
 W    | Clay    | 0.557 |   0.635   |   0.641    | +0.006
 W    | Grass   | 0.590 |   0.705   |   0.714    | +0.009
 W    | Hard    | 0.570 |   0.663   |   0.671    | +0.008

 game leverage, M Hard   empirical  parametric   diff
 30-40 / AD-out            0.733      0.769     +0.036
 15-40                     0.454      0.497     +0.043
 0-40                      0.279      0.321     +0.042
 deuce                     0.457      0.422     -0.036
 0-0                       0.253      0.220     -0.033
 40-0                      0.030      0.029     -0.001
```

**Verdict: ✅ both confirmed.** The gap is positive in all six cells, and smaller
on the women's tour — also what Jensen predicts, since p sits nearer 0.5 where
the hold curve is close to linear. Leverage splits cleanly: **every state where
the returner is one point from the break gains under parametric; every other
state loses.** The mechanism is selection at deuce: servers who reach it are
weaker than average (empirical P(hold | deuce) .733 vs .769).

**Decision:** parametric. Leverage should describe the score, not who tends to
reach it — baseball's LI makes the same call. The rank order of states barely
moves between the two; what the choice changes is *how much* break points stand
out, by ~5% at 30-40 and ~15% at 0-40. The 0-0 gap (≤1.6pp) is the measured cost
of the iid assumption.

**Not tested:** whether the gap is server heterogeneity (Jensen) or genuine
non-independence (pressure). Both push the same direction. Separating them needs
p per server, not per tour — a question for `mart_player_style`'s era.
