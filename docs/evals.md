# Evals — how the question set works, and why

The agent never sees these questions or their answers when it runs. A user
asks anything; the agent answers from the marts. The question set is a tool
for building the agent, with four jobs:

| Job | What it does |
|---|---|
| **Measure** | Run each question, compare with the answer decided in advance, and get a score. A prompt change is then a measured change, not a guess. |
| **Diagnose** | A failed question points to its fix. direction-02 failed because no column description says that direction plus handedness gives the target wing -- a description fix, not a prompt rule. |
| **Specify** | Each question names the marts and columns it needs. That is how the warehouse was designed. |
| **Teach by example** (optional) | A few questions can become examples in the prompt (`ROUTER_EXAMPLES`). A question used as an example must leave the eval: a model that has seen the answer cannot be tested on it. |

---

## 1. Who the agent is for (D10)

Tour teams were rejected as the primary target: they hold far richer
proprietary tracking. The data is elite pro matches only -- 110 of 1,739
players have 50+ charted matches, the 20 most-charted players appear in 42%
of matches, 71% of matches are 2015 or later, and no club or junior matches.
Its edge is that it is free, public and citable, covers decades and both tours.

So the target is two **jobs**, for people who explain or learn the game in
public:

| Job | Who | A valuable answer |
|---|---|---|
| **P -- publish** | content analysts, journalists, commentators, debating enthusiasts | a surprising, defensible claim with a number |
| **T -- teach / improve** | teaching coaches, improving players | a pattern true across many pros, that can be taught or practised |

## 2. Five tests for a question

A question earns an eval slot only if it passes all five:

1. **Motive** -- which job (P or T) does it serve?
2. **Decision** -- does the answer change an action: a game plan, a drill, a story? If not, it is trivia.
3. **Non-obvious** -- could the asker already guess it?
4. **Unambiguous** -- one reasonable reading; no undefined terms ("clutch", "struggle", "go bigger").
5. **Honestly answerable** -- the data answers it, with caveats it can state.

Routing and guardrail questions are the exception: naive phrasing is realistic
there, because real users ask naive questions.

## 3. The families (`questions.yml`)

| Family | ids | Purpose |
|---|---|---|
| Original | serve-*, rally-*, direction-*, pressure-*, matchup-01, semantic-01, guard-* | the first set, reworded under D10 to tour-level where possible |
| Signature | sig-01 .. sig-06 | what only this warehouse answers: leverage, style similarity, matchup deltas, coverage |
| Honesty traps | trap-01 .. trap-06 | a correct answer MUST state the caveat (era, level-vs-slope, thin sample, the T10 confound, leverage misread as skill, charting selection) |
| Teach | teach-01 .. teach-05 | tour-level patterns for job T, e.g. men hold 89.1% after winning a game's first point vs 63.2% after losing it |
| Held-out | `evals/heldout_routing.yml`, ho-01 .. ho-08 | routing questions never read while editing `<routing>` |

Every question was checked against the data before it was added.

## 4. Templates and fillers (D12)

One question tests one case: a perfect score on "Who plays like Federer?"
proves the agent handles Federer -- a famous, deep-data, right-handed ATP
player -- and nothing else. So a question with `{slots}` is a **template**,
run once per **filler**:

| Filler kind | Example | What it tests |
|---|---|---|
| deep | Novak Djokovic (553 matches) | the normal case |
| wta | Iga Swiatek | the right tour baseline |
| left_handed | Adrian Mannarino (not ambiguous) | handedness-dependent logic |
| ambiguous_hand | Rafael Nadal (L in 420 of 425 matches) | inconsistent upstream data |
| thin | Arthur Cazaux (12 matches) | does the answer say the sample is thin? |
| name_variant | "Novak Djokovich" | name resolution |
| absent | "Teodor Vashkelny" (closest real name: similarity 0.13) | refuse instead of inventing |
| control | Sinner, hard, 2024 (49 matches) | no caveat where none is needed |

A filler carries `must_state` (what a correct answer has to say) and may
override `route` (an absent player is a refusal). `src/deuce/evals/templates.py`
expands them; a slot without a value, or a filler key that matches no slot,
fails loudly. 30 questions expand to 72 cases.

Some names stay fixed because the name IS the test: trap-02 (Nadal vs Federer,
measured slopes) and trap-03 (a known thin cell) keep their original case as
the first filler.

## 5. The evals

| Eval | Checks | Status |
|---|---|---|
| Routing (`scripts/eval_routes.py`) | the route the agent picks vs the label | runs on the expanded cases |
| Answer | the final answer: correct, and states `must_state` | not built -- needs the answer node (`<grounding>`) |

Rules for reading a score:

- **Upper bound vs honest score.** The `<routing>` rules were written from the
  original questions, so their score is an upper bound. The held-out set is
  the honest estimate.
- **Run twice.** At temperature 0 two questions flipped between runs; a
  1-point change is noise.
- **A provider outage is not a mistake.** The runner retries 503s and reports
  any other failure as an error, outside the accuracy. (The first expanded run
  counted 11 outages as misses.)
- **Right route, wrong reason** is still a failure for the answer eval: absent
  players were often refused for an unrelated reason.

## 6. What the evals have found so far

**First clean run on the expanded set (2026-11-23):** 21/36 scored (58%), 1
outage reported separately. 11 of the 15 misses are over-refusal:

- Partial questions are refused when the unanswerable part is the question's
  point ("is it +EV?"): direction-01 (4 fillers), direction-02, pressure-01,
  pressure-02. Rule 2 needs stronger wording.
- matchup-01 is refused in every filler. The "how could an opponent exploit
  them" clause restored in review reads as tactical advice. A rewording that
  helped job P hurt routing.
- Absent players go to sql in 4 cases (rally-01, sig-05, sig-06, trap-04).


- Every routing miss is a refusal where an answer was expected (over-refusal).
- The router cannot see player names, so it cannot know a player is absent
  -- evidence for name resolution (D11). Trigram matching resolves a
  misspelling ("Novak Djokovich" 0.82) but not a nickname ("Fed" 0.21).
- The model assumes its own calendar: it refused a 2026 question as "the
  future". The data contains 2026 matches. The prompt must state the data's
  date range (`<data_contract>`).

## 7. Beyond text-to-SQL (D11)

Increment 2.5, in order: a verifier (every number is in the rows, the caveat
is stated), name resolution, statistics via code execution (T11 needs a
permutation test), charts (people who publish post charts), and a clarify
route (the ambiguity test). Deferred: web search, scheduled content, memory.
