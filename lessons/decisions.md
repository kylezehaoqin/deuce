# Decisions

One entry per judgment call. Kyle decides. Claude writes the code. The point of
this file is the **rejected** options: the code shows what was chosen, and the
commit log shows when, but neither shows what was turned down and why. That is
the content of an interview answer.

`Decided by` is either **Kyle**, or **Claude (Kyle to review)** when Kyle said
"you decide". A Claude decision is provisional until Kyle reviews it.

Template:

```
## D<n> -- <the question, one line>
**Decided by:** Kyle | Claude (Kyle to review)   **Date:** YYYY-MM-DD
**Options:**
- (a) ... -- cost: ...
- (b) ... -- cost: ...
**Evidence:** the measured number that made the trade-off concrete.
**Chosen:** (x), because ...
**Say it out loud:** one or two sentences, first person.
```

---

## D1 -- Point->game probability for the leverage index: empirical or parametric?
**Decided by:** Claude (Kyle to review)   **Date:** 2026-10-01
**Options:**
- (a) Empirical: the share of games held from each score. Cost: selection bias.
  The servers who reach 0-40 are mostly weak ones, so the leverage mixes the
  score with player quality.
- (b) Parametric: one point-win rate per tour x surface, points assumed iid.
  Cost: the iid assumption.
**Evidence:** H12. Parametric overstates hold at 0-0 by 0.6-1.6pp (the cost of
iid). Empirical P(hold | deuce) is .733 against .769 for a typical server, which
is the selection. The rank order of states barely moves.
**Chosen:** (b). Leverage should describe the score, not who tends to reach it.
Baseball's leverage index makes the same choice.
**Say it out loud:** "I measured both. The empirical model was biased by who
gets to deuce. The parametric one cost under two points of accuracy at 0-0, and
I could state that cost exactly."

## D2 -- Tiebreak points in the leverage index: model them now, or leave NULL?
**Decided by:** Claude (Kyle to review)   **Date:** 2026-09-27
**Options:**
- (a) Model them now. Cost: a separate state table, with the server rotating
  every two points.
- (b) NULL in v1, with `is_tiebreak_game` on every row. Cost: the
  highest-leverage points in tennis are missing.
**Evidence:** 59,348 tiebreak points out of 1,875,130 (3.2%).
**Chosen:** (b), as a stated gap. Open in `docs/marts.md` §8.
**Say it out loud:** "I shipped without tiebreaks and made the gap a column, so
nobody can quote a leverage number without seeing it."

## D3 -- Style vector: which features?
**Decided by:** Claude (Kyle to review)   **Date:** 2026-10-07
**Options:**
- (a) Everything available, including points won and winner/error ratios.
  Cost: "plays like X" turns into "is as good as X".
- (b) Style only, one feature per concept. Cost: some judgment calls about
  what counts as style.
**Evidence:** T9. A 10-feature vector with two slice features mostly measured
slice: one-handers fell from 5 of 10 neighbours to 3 when slice was removed.
**Chosen:** (b), 12 features. One exception on purpose: `point_ending_rate`
also carries quality, but it is the first-strike signal from T1.
**Say it out loud:** "Two correlated features act as one feature with double
weight. T9 did that to slice without anyone choosing to, so here each concept
appears once."

## D4 -- Forehand and backhand directed drives: one denominator or two?
**Decided by:** Kyle   **Date:** 2026-10-07
**Options:**
- (a) One combined count. Cost: a forehand rate can end up over all drives.
- (b) Two counts, never summed.
**Evidence:** T10 divided a forehand rate by all directed drives. Also, `+`
gives NULL when one side is NULL: 3 cells lost their forehand data that way.
**Chosen:** (b).
**Say it out loud:** "A combined denominator invites the wrong rate. A player
who hits more forehands would look like they hit more inside-out forehands."

## D5 -- `mart_matchup`: what does the delta control for?
**Decided by:** Kyle   **Date:** 2026-10-07
**Options:**
- (a) Grain `(player, opponent, surface)`. Cost: thin cells.
- (b) Grain `(player, opponent)`, pooled baseline. Cost: the delta mixes the
  opponent effect with the surface mix (the T10 confound).
- (c) Grain `(player, opponent)`, with the baseline weighted to the pair's
  surface (and maybe season) mix. Cost: more SQL, and the season part makes
  the baseline noisy.
**Evidence:** 7,788 pairs. 6,001 (77%) have exactly one charted match. 235
have 5+. Split by surface, only 139 cells have 5+. For pairs with 5+ matches,
the median total variation distance between the pair's surface mix and the
player's own is 0.115, and 19% are at 0.2 or more. Federer v Nadal: 45.7% clay
against 18.0%. Pooled-baseline bias on his slice delta: -2.6 pp. Leaving the
pair out of its own baseline moves that baseline from .313 to .328.
**Chosen:** (c), matched on surface only. Not season: seasons are too thin.
Keep one-match pairs, consistent with the other marts. The pair is left out of
its own baseline.
**Say it out loud:** "Most pairs played once, so splitting by surface left
nothing to measure. I weighted the baseline to the pair's surface mix instead,
and measured that the bias I removed was a tenth of the effect."
