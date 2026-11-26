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
**Decided by:** Claude; reviewed and approved by Kyle 2026-10-07   **Date:** 2026-10-01
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
**Decided by:** Claude; reviewed and approved by Kyle 2026-10-07   **Date:** 2026-09-27
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
**Decided by:** Claude; reviewed and approved by Kyle 2026-10-07   **Date:** 2026-10-07
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

## D6 -- Which LLM does the agent use, and when is the eval baseline fixed?
**Decided by:** Kyle   **Date:** 2026-10-14
**Options:**
- (a) Gemini Flash-Lite now, fix the baseline model later. Cost: the decision
  takes two steps.
- (b) Flash-Lite as the eval baseline now. Cost: weaker schema linking, so the
  eval may measure the model's limits instead of the prompt.
- (c) Wait for Gemini Flash. Cost: it failed every call today.
- (d) A paid API. Cost: money and a second key; reliable availability.
**Evidence:** `scripts/probe_models.py`, same 3 SQL questions, same ~6,880-token
schema context, a throwaway one-line instruction. `gemini-3.5-flash-lite`:
available on every call, 1.2-1.7 s, 2 of 3 queries ran (one used a column from
the wrong table). `gemini-3.8-flash`: 0 of 9 calls (503 high demand, then 429).
`gemini-pro-latest`: 429 on the first call, naming the free-tier quotas.
`gemini-2.5-flash`: retired for new keys (404).
**Chosen:** (a). The graph and the eval harness do not depend on the model --
`get_chat_model()` is the only place it is named -- so building on Flash-Lite
loses nothing. **Still open:** the baseline model, decided once Flash can be
measured on the same questions. No eval score is a baseline before then.
**Say it out loud:** "The free tier gave me one model that answered reliably.
I built on it, kept the model behind one function, and refused to call any
score a baseline until I could compare it with the stronger model."

## D7 -- Routing: a separate LLM call, or part of the main call?
**Decided by:** Kyle   **Date:** 2026-10-14
**Options:**
- (a) Separate call, no schema. Cost: it cannot see what the data holds.
- (b) Separate call with the schema. Cost: ~6,900 more input tokens per
  question -- about double -- under free-tier token limits.
- (c) Inline: one structured call returns {route, sql, reason}. Cost: routing
  and SQL text share one prompt, so a routing change can move SQL quality too.
**Evidence:** Flash-Lite, the four Route definitions only, all 16 questions,
labels from each question's `difficulty` (a proxy). Without the schema: 4/16,
~120 tokens, 0.58 s median, and the serve-speed question went to SQL. With the
schema: 8/16, ~6,900 tokens, 1.23 s, and serve speed was refused. Live with
(c): guard-01 refused ("does not store serve speed"); serve-01 ran after two
failed queries were sent back -- the retry loop's first live run.
**Chosen:** (c). The schema is what makes routing work, and inline gets it for
free. The route stays a field, so it is still logged and scored on its own.
**Say it out loud:** "A router that can't see the data can't know what the
data can't answer. I measured that -- 4 of 16 without the schema, 8 with -- so
routing went into the main call, and the route stayed a field I can score."

## D8 -- Where is the routing line? (expected route per eval question)
**Decided by:** Kyle   **Date:** 2026-10-15
**Options, per boundary case:**
- direction-01 (+EV of the backhand down-the-line): (a) sql, answer the
  frequency and caveat the rest; (b) refuse. Chosen (a).
- direction-03 (who redirects most): (a) refuse until fct_shots; (b) sql with
  down-the-line share as a stand-in. Chosen (a): a labelled wrong measure can
  still mislead.
- semantic-01 (momentum-swing comebacks): (a) sql from the score; (b) hybrid
  later; (c) semantic as labelled. Chosen (a).
- "Why did X lose?": (a) sql, what happened and not why; (b) refuse. Chosen (a).
- The general rule: answer when a LITERAL part of the question is answerable,
  with a caveat; refuse when only a related stand-in is. Rejected: "answer
  whenever anything related helps" (answers what was not asked) and "refuse
  unless the core is answerable" (inconsistent with direction-01).
**Evidence:** no table has winners/errors per direction or the previous shot's
direction (fct_shots is not built). Charter notes exist on 4,784 of 11,819
matches but are mostly procedural; "momentum" or "comeback" appears on 16
points. Every point's score and leverage is in the data.
**Result:** 16 labels in evals/route_labels.yml, and <routing> written from
them. scripts/eval_routes.py: 12/16 on two runs (upper bound -- the rules came
from these questions). Every miss is refuse-where-sql-was-chosen. Stable
misses: rally-02, direction-02, pressure-02. Flaky: semantic-01, direction-01.
**Say it out loud:** "I decided the line case by case, then found the rule
that explained my choices: answer what was literally asked, refuse what can
only be stood in for. The first prompt from that rule refused too much."

## D9 -- What makes a question valuable? (the question set, round 2)
**Decided by:** Kyle   **Date:** 2026-11-10
**Options (user):** scout/coach, analyst/journalist, or fan. **Chosen: all
three** -- every new question carries a `persona` tag.
**Options (families):** A signature marts, B honesty traps, C held-out routing.
**Chosen: all three** -- 6 + 6 + 8 questions.
**Evidence:** the original 16 predate the warehouse: 8 of the 9 marts they
name do not exist, and 10 built tables -- including mart_pressure_index,
mart_player_style, mart_matchup and mart_data_coverage -- are never named.
Routes were 12 sql / 4 refuse, nothing for semantic or hybrid. Every new
question was checked against the data first: e.g. Nadal's rally slope
+0.0105 vs Federer's -0.0044 (trap-02), pre-2010 rally length all 'low'
confidence (trap-01), and notes exist only in stg_points, which the agent
role cannot read -- so ho-05/06 are semantic/hybrid.
**Chosen:** the 20 questions as drafted. C lives in evals/heldout_routing.yml
and is never read while editing <routing>, so it gives the first honest
routing score. Still open: whether A and B join the routing eval.
**Say it out loud:** "My question set was written before the warehouse, so it
tested marts that didn't exist and ignored the ones that did. I rebuilt it in
three families: what only this data can answer, the traps an honest answer
must name, and a held-out set to score routing without fooling myself."

## D10 -- Who is the agent for? (the target, locked)
**Decided by:** Kyle   **Date:** 2026-11-23
**Options:** tour coach / team; performance analyst; journalist / commentator;
teaching coach; club player; strategy enthusiast; bettor; researcher.
**Rejected: tour teams as the primary target.** They already hold far richer
proprietary tracking (ATP/WTA, IBM, Infosys). This data has no edge for them
unless it shows something theirs cannot.
**Chosen:** two jobs. **P (publish):** content analysts, journalists,
commentators, debating enthusiasts -- a surprising, defensible claim with a
number. **T (teach/improve):** teaching coaches and improving players -- a
pattern true across many pros. Every question must serve P or T and pass five
tests: motive, decision, non-obvious, unambiguous, honestly answerable.
**Evidence:** the data is elite pro matches only: 110 of 1,739 players have
50+ charted matches; the 20 most-charted players appear in 42% of matches;
71% of matches are 2015 or later. No club or junior matches. Its edge for P
and T: free, public, citable, decades long, both tours.
**Applied:** 10 questions reworded (several from one player to tour-level),
rally-02 and matchup-02 cut, guard-02 and ho-08 replaced, and 5 tour-level
teach-* questions added, each checked first (e.g. men hold 89.1% after winning
the first point vs 63.2% after losing it). The D8 routing score (12/16) was
measured on the old wording: re-run before quoting it.
**Say it out loud:** "Tour teams have better data than this, so I stopped
building for them. I built for people who explain or learn the game in public
-- they need a number they can cite, or a pattern they can teach."

## D11 -- Which abilities around the SQL agent, and in what order?
**Decided by:** Kyle   **Date:** 2026-11-23
**Options considered:** RAG over notes, fixed tools / semantic layer, code
execution, planner-executor, a critic / verifier, web search, scheduled
content, user memory -- plus abilities: charts, name resolution, a clarify
route, multi-turn follow-ups, uncertainty in answers, citable output.
**Chosen order, as Increment 2.5:** verifier -> name resolution ->
statistics -> charts -> clarify. Nothing before the answer node exists
(<grounding> comes first).
**Why this order:** the first two protect correctness; the last three add
reach for the P and T jobs (D10). The verifier enforces the project's thesis
-- no claim beyond what the data supports -- on every answer, not only in the
eval. Statistics is needed for honest claims ("is this difference real?") and
T11 cannot be tested without a permutation test. Charts serve people who
publish. Clarify answers the ambiguity test.
**Deferred:** web search (mixes trusted and untrusted sources), scheduled
content (needs trustworthy answers first), user memory.
**Evidence:** none measured yet -- this is a sequencing decision. The case for
name resolution is to be measured (near-duplicate names in dim_players).
**Say it out loud:** "Most good agents are one router and several tools. I
kept text-to-SQL as the core and ordered the tools by what protects
correctness first: a verifier, then name resolution, then statistics."

## D12 -- Questions as templates: one case, or a method?
**Decided by:** Kyle   **Date:** 2026-11-23
**Options:** (a) keep one fixed case per question; (b) templates with {slots},
each run with ~5 fillers chosen to stress the agent.
**Evidence:** 4 questions had a {player} slot, but every eval filled it with
the same player; 8 hard-coded a name; 18 were tour-level. A perfect score on a
single famous, deep-data player proves nothing about anyone else.
**Chosen:** (b). 12 templates, 54 fillers, every filler checked first: deep
(Djokovic, 553 matches), WTA (Swiatek), left-handed (Mannarino), ambiguous
hand (Nadal: L in 420 of 425 matches), thin (Cazaux, 12), a misspelling
("Novak Djokovich", trigram 0.82), an absent player ("Teodor Vashkelny",
closest real name 0.13), a control (a 49-match cell: no caveat needed). Names
that ARE the test stay as the first filler (trap-02, trap-03). 30 questions
expand to 72 cases.
**Found on the first run:** the router refuses absent players for unrelated
reasons; and it called a 2026 question "the future" -- the data has 2026
matches.
**Say it out loud:** "A test that only ever asks about Federer only tests
Federer. I turned questions into templates and filled them with the hard
cases: a thin sample, a misspelled name, a player who doesn't exist."

## D13 -- When is a player's hand ambiguous?
**Decided by:** Kyle   **Date:** 2026-11-25
**Options:** (a) flag on ANY disagreement (the old rule); (b) majority rule:
flag only when there is no majority.
**Evidence:** the old flag caught 49 players; 39 of them had a 90%+ majority.
Nadal is L in 420 of 425 matches. Of the other 5: two are hands SWAPPED with
the opponent (Gabashvili 2010, Wawrinka 2017 -- both right-handers recorded
as L), one a typo (vs Isner), two not entered. Only one player has no
majority at all (Filippini, L=1 R=1).
**Chosen:** (b). `hand` stays the majority (it already was); the flag is true
only on a tie, so 1 player instead of 49; new `hand_agreement` shows the
majority's share, so a weak majority on few matches (Bagnis 0.60 on 5) stays
visible without a flag.
**Knock-on:** the two eval fillers that used Nadal as "ambiguous hand" are now
"left_handed_deep".
**Say it out loud:** "One typo in 425 matches made Nadal 'ambiguous'. The
typos were charters swapping the two players' hands. A majority vote fixes
that, and the agreement share keeps the doubt visible where it is real."

## D14 -- Where does the tokenizer live?
**Decided by:** Kyle   **Date:** 2026-11-25
**Options:** (A) Python tokenizer + dbt; (B) all SQL in dbt; (C) the Rust
parser in production (with a batch mode); (D) A, with Rust as an oracle.
**Evidence:** the Rust parser (`~/dev/projects/match-sequence-parser`, 743
lines, typed, 5 tests) builds after `rustup update`. Its JSON tokens are
right, but its English tactical words are wrong ("backhand down the line" for
a righty's backhand to a righty's backhand, which is crosscourt), and it drops
an unknown code silently ("6b28f1Q2" lost "Q2"). Speed does not separate the
options: a Python regex tokenizer split all 1,875,132 rallies (6,919,528 shot
tokens) in 0.8 s; Rust at one process per rally takes 84 min, ~90% of it
process start-up (2.39 ms), so a batch mode would take seconds. Tokenizing is
a once-per-ingest batch, not on the path users wait for. Sackmann's oracles
give counts per player, per match, per shot type and direction -- a strong
check without a second implementation.
**Chosen:** a Python tokenizer as a Dagster asset; hitter and tactical
direction in a dbt `int_` model (window functions over ordered shots); verified
against Sackmann's per-match oracles, plus ONE local diff of tokens against
Rust's JSON. Rust stays out of CI and out of this repo. The tokenizer must
raise on an unknown code.
**Rejected:** Rust in production (a compiled black box in the lineage, Rust in
CI, a second repo -- its main pro was time saved, not capability); Rust as a
permanent oracle (the same costs); all SQL (tokenizer edge cases are hard to
test in SQL).
**Say it out loud:** "I had a working Rust parser and still chose Python. I
measured it: speed didn't separate them, and Rust's real pro was time saved.
I kept it as a one-off check -- that check already found it drops unknown
codes silently."
