# Hypothesis log

Every claim made about this data, how it was tested, and whether it survived.
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
| [H10](#h10) | `ShotDirection` excludes serve returns and non-groundstrokes | ⚠️ partial — **open** |

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
