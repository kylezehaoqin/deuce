# Mart design

What the warehouse exposes, at what grain, and why.

This is a **map, not a commitment**. Marts marked *buildable* have their inputs
verified and could be written today; marts marked *gated* name what blocks them.
Nothing here is built unless it exists in `dbt/models/marts/`.

Read `lessons/009-regex-vs-parser.md` first if you haven't — the split between
buildable and gated is entirely the split between counting questions and
sequence questions.

---

## 1. The grain ladder

Every question has a natural unit. A mart coarser than that unit cannot answer
it — not "less precisely", *cannot* (lesson 009).

| Grain | Key | State |
|---|---|---|
| Shot | `(match, point, shot_no)` | gated — tokenizer |
| Serve | `(match, point, serve_no)` | built — `fct_serves` |
| Point | `(match, point)` | built — `fct_points` |
| Game | `(match, game_no)` | built — `fct_games` |
| Set | `(match, set_no)` | buildable, low value |
| Match-player | `(match, player)` | exists only as oracle tables |
| Player-period | `(player, year, surface)` | **buildable** |
| Matchup | `(player, opponent)` | **buildable** |
| Transition | `(player, from_shot, to_shot)` | gated — tokenizer |

The interesting gaps are **serve** and **game**: both cheap, both unlock a
question class, neither exists anywhere upstream.

---

## 2. Infrastructure

Unglamorous. The agent does not work without these.

### `dim_players` — BUILT
**Grain:** one row per player.
**Columns:** canonical name, handedness, tour, first/last charted date, match
count, `pg_trgm` index on name.
**Why:** the agent is asked about "Alcaraz", not "Carlos Alcaraz". Name
resolution is the first thing every query needs.
**Verified:** 1,739 distinct names, **zero** case or punctuation variants — no
entity resolution required, which makes this genuinely trivial.
**Built.** Fuzzy lookup verified: `'federr'` → Roger Federer, `'swiatek'` → Iga
Swiatek. The trigram index exists and the planner correctly ignores it at 1,739
rows / 568 kB — kept because it costs nothing, but it is not doing work today.
`mode()` resolves handedness by majority vote, which matters: 49 players have
charter disagreements, including Nadal and Kvitova, and the vote gets all of
them right.

### `dim_charters`
**Grain:** one row per `charted_by`.
**Columns:** matches charted, date range, and **completeness rates** — share of
points with shot direction, with return depth, with court-position modifiers.
**Why:** charting is optional-by-layer in the spec, and charters differ. Measured
across 18 charters with ≥20 matches in the 2020s:

```
 direction charted:  min 0.623  |  median 0.873  |  max 0.906
 court position:     0.068 → 0.251   (a 4x spread)
```

A player charted mostly by a 62% charter has systematically thinner direction
data than one charted by a 90% charter. **Every direction-based rate inherits
this**, and nothing currently models it.
**Status:** buildable. Feeds `mart_data_coverage`.

### `mart_data_coverage`
**Grain:** `(player, surface, year)`.
**Columns:** matches, points, `parse_confidence` mix, and per-field populated
rates (direction, return depth, court position), inherited from the charters who
did the work.
**Why:** this is the mart the agent queries **before answering**, to decide
whether it can. `questions.yml` repeatedly says *"if N < 20 say the sample is
thin"* — that's only enforceable if the sample size is a queryable fact rather
than something the agent has to remember to compute.
**Status:** buildable. The single highest-leverage mart for grounding.

---

## 3. Buildable today — no tokenizer

### `fct_serves` — BUILT
**Grain:** `(match, point, serve_no)` — one row per serve, **including faults**.
**Why it's new:** `int_point_rally_length` carries `serve_direction` at *point*
grain, which silently means "the serve that was actually played". On a
second-serve point the faulted first serve is invisible. Exploding to serve grain
recovers it — and with it the fault letter (`n` net, `w` wide, `d` deep, `x`
wide+deep, `g` foot fault).

That gives a column nobody has: **how a player misses, sliced by pressure.**

> *"He misses his first serve into the net 62% of the time on break point, but
> long 55% of the time at 40-0."*

Netting is decelerating; going long is over-hitting. Sackmann tracks fault types
in `ServeDirection.csv` but only at match grain — no score context.

Also fixes first-serve percentage, which is awkward at point grain and natural
here.
**Columns:** serve number, direction, landed/faulted, fault type, court side,
pressure flags, server/returner + handedness, surface, `parse_confidence`.

### `mart_serve_patterns` — BUILT
**Grain:** `(server, court_side, pressure, serve_number, parse_confidence)`.
Option C was chosen: fact tables (`fct_points`, `fct_serves`) **and** this
aggregate, reconciled by `assert_serve_patterns_matches_fact`.
**Why:** `questions.yml` #1 and #9; reference data for T3/T4/T5.
**Note:** the fact-vs-aggregate trade-off is written up in the scaffold header.
Every statistic precomputed here is one the agent cannot get wrong; every column
precomputed is a question it can no longer ask.

### `fct_games` — BUILT
**Grain:** `(match, game_no)`.
**Columns:** server, held/broken, reached deuce, max deficit faced, points
played, set/game score at start.
**Why:** a game is the natural unit of a *pressure episode*, and nobody models
it. Unlocks:
- **The let-down game** (`questions.yml` #11, T8) — needs game *sequence*, which
  is exactly what T2's within-game control discarded.
- 0–40 recovery rate. Who saves triple break point?
- Hold rate under conditions rather than in aggregate.
- Game-level momentum — which is where the folk belief actually lives. People say
  "he lost momentum" about games, not points.

**Built.** Sanity-checked against reality: men's hold rate **80.2%**, women's
**66.5%**. Tiebreaks are structurally not games — the server rotates every two
points — so `server_name`, `held` and `broken` are NULL on those 4,928 rows
rather than wrong. The detector is exact: every tiebreak shows a server change
and no regular game does.

### `mart_rally_shape`
**Grain:** `(player, rally_bucket, surface, year)`.
**Columns:** points, win rate, share of points, plus the **slope** of win rate
across buckets.
**Why:** T1 (first-striker vs grinder). The slope is the interpretable part; the
level is opponent quality. Precomputing the slope stops the agent from comparing
levels across players, which is the mistake it will otherwise make confidently.

### `mart_pressure_index`
**Grain:** `(match, point)` — an extension of the point grain.
**Columns:** a leverage score per point — how much the game/set/match outcome
probability swings on this point.
**Why:** T3 flagged break point as a *coarse* proxy for pressure. A continuous
leverage index (the tennis analogue of baseball's leverage index) lets "clutch"
questions be asked properly, and makes 30-40, set point and match point
comparable on one scale.
**Buildable from:** score state alone, with a hold-probability model that can be
as simple as empirical rates from the data itself.

### `mart_player_style`
**Grain:** `(player, year, surface)`.
**Columns:** the style feature vector — shot mix, direction tendencies, net rate,
winner/unforced profile, serve placement entropy — plus `n` for every rate.
**Why:** the shared substrate under three features: player evolution (T10),
style similarity (T9), and analogical scouting. Build the grain once, project it
three ways.
**Surface is not optional here:** controlling for it killed two of six apparent
Alcaraz "trends".
**Feeds:** `pgvector`, for style-similarity search.
**Warning:** see §5 on oracle circularity — this mart's source must change when
`fct_shots` lands.

### `mart_matchup`
**Grain:** `(player, opponent)`.
**Columns:** head-to-head, plus the interesting part — **how the player's profile
shifts against this opponent versus their own baseline** (serve placement delta,
rally length delta, aggression delta).
**Why:** this is the table the analogical-scouting idea actually queries: *"how
does A deviate against players like B."* Also where the retrodiction eval lives.

---

## 4. Gated on the tokenizer

### `fct_shots`
**Grain:** `(match, point, shot_no)`. The fact table. Scaffolded at
`dbt/models/marts/fct_shots.sql`.
**Design constraint carried from the positioning decision:** keep stable shot
ordering and factored fields (type / direction / depth / outcome / modifiers as
separate columns, not a composite code), and don't pre-aggregate away anything a
sequence model would need. Costs nothing now; keeps that door open.

### `mart_shot_patterns` — pattern entropy
**Grain:** `(player, from_shot, from_direction, to_shot, to_direction)`.
**Why:** `serve_direction_entropy` is entropy over a 3-way distribution. The same
metric over a **transition matrix** gives *pattern* entropy — low entropy on a
transition means a predictable pattern.

That makes `questions.yml` #12 — *"their 3 most predictable patterns and where
they're exploitable"* — an `ORDER BY entropy ASC LIMIT 3`.

The signature metric generalises. That's the strongest single argument for shot
grain.

### `mart_serve_plus_one`
**Why:** `questions.yml` #2.
**Candidate shortcut, NOT validated:** the serve is shot 1 and the return is
always shot 2, so their positions are *fixed* — which suggests they're extractable
with an anchored regex without a general tokenizer. Two rounds of oracle diffing
against `ShotTypes.serve_return` have not closed the gap:

```
 anchored extraction, raw           12.2% exact,  avg gap +16.91 / match
 minus returns that errored          2.0% exact,  avg gap  -8.38 / match
```

Over-corrected, so the true rule is somewhere between. **Treat the shortcut as
unproven** — if someone wants it, it's an investigation, not a given.

---

## 5. Agent-serving marts

The project end goal is an agent, and an agent needs tables about *itself*.

### `mart_agent_queries`
**Grain:** one row per agent invocation.
**Columns:** question text, route taken (SQL / semantic / hybrid / refuse),
generated SQL, rows returned, marts touched, latency, error, user feedback.
**Why:** this is the Langfuse/eval loop made queryable. It answers "which
questions does it get wrong", "which marts are never used", "where does routing
fail" — none of which a trace viewer answers in aggregate.
**Bonus:** *"which marts are never queried"* is the honest test of whether
anything here was worth building.

### `mart_eval_results`
**Grain:** `(eval_run, question_id)`.
**Columns:** the three scores from `questions.yml` — query correctness,
grounding, answer correctness — plus run timestamp and model/prompt version.
**Why:** `make eval` should print a number that moves over time, and regressions
should be attributable to a prompt change. Same reasoning as the parser
regression test: a baseline you can regress against beats a score you look at
once.

### `emb_player_style` / `emb_point_descriptions`
**Grain:** `(player, period)` and `(match, point)` respectively.
**Why:** the pgvector leg. Style vectors give semantic search a real job —
better than the brief's original "semantic search over match notes", since the
notes column is sparse and mostly records challenges and medical timeouts.
**Note:** the Rust parser's `to_natural_language()` is the obvious generator for
point descriptions, and generation sits outside the SQL lineage anyway.

---

## 6. Design rules

**The oracle rule has a hole.** `CLAUDE.md` says "nothing in a mart may read the
oracle tables" — but T9's style vector read `stg_stats_shot_types`, an oracle.
The rule is too broad. The real constraint:

> An oracle may not feed the mart whose parser it validates.

Reading `ShotTypes` for style features is fine **until** `fct_shots` exists — at
which point `mart_player_style` must switch to reading our own shots, or the
validation becomes circular. Decide per mart, and write it in the mart's
description.

**Every mart carries its denominators.** Shot direction is optional in the
charting spec, so every rate needs both `n` and `n_with_field_charted` exposed. A
mart that ships only rates makes the caveat unstateable — and the agent is
required to state it.

**Provenance survives aggregation or it dies.** `parse_confidence` must be a
grouping key, never averaged away. The moment it's aggregated out, the
"don't compare across eras" guarantee becomes unenforceable downstream.

**Column descriptions are prompt context.** The agent reads `schema.yml`
descriptions to write SQL. A badly documented column is a badly used column
(lesson 003). Every mart column gets a description and at least one test.

**Consolidate for the MCP server.** Increment 4 exposes marts as tools. A small
number of well-named marts with clear parameters beats many narrow ones — tool
proliferation is its own failure mode.

---

## 7. Build order

Cheapest-to-most-valuable, with dependencies respected:

1. **`dim_players`** — blocking for Increment 2, trivial, no dependencies.
2. **`fct_serves`** → **`mart_serve_patterns`** — no tokenizer, novel column
   (fault direction under pressure), answers `questions.yml` #1 and #9.
3. **`fct_games`** — cheap, unlocks a whole question class including T8.
4. **`dim_charters`** + **`mart_data_coverage`** — makes grounded refusal
   enforceable rather than aspirational.
5. **`mart_player_style`** — substrate for three separate features.
6. **`mart_agent_queries`** + **`mart_eval_results`** — arrive with Increment 2/3.
7. Everything tokenizer-gated, after `fct_shots`.

Items 1–3 are enough for the agent to answer real questions. Item 4 is what makes
those answers trustworthy.

---

## 8. Open questions

- **`mart_serve_patterns` grain** — fact vs. pre-aggregated vs. both. Written up
  in the scaffold; still undecided.
- **The serve+1 anchored shortcut** — unproven, see §4.
- **Leverage model for `mart_pressure_index`** — empirical hold rates from this
  data, or a parametric model? Empirical is simpler and self-consistent.
- **Does `dim_charters` feed `parse_confidence`?** Currently confidence is purely
  era-based. Charter completeness is a second, independent axis, and combining
  them may be better than either alone — or may over-complicate a field whose
  value is that it's simple to explain.
