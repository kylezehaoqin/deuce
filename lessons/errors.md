# Error log

Every error hit, its root cause, and the general rule it taught. Including — in
fact especially — the self-inflicted ones.

The value isn't the fix. It's the **class** of mistake, because that's what
recurs.

---

| # | Error | Class | Rule learned |
|---|---|---|---|
| [E1](#e1) | `function round(double precision, integer) does not exist` | type system | Postgres `round(x, n)` is numeric-only |
| [E2](#e2) | `invalid input syntax for type integer: "Zindaras"` | upstream data | Shifted rows have no invalid values |
| [E3](#e3) | `ON CONFLICT DO UPDATE cannot affect row a second time` | SQL semantics | Dedupe within the batch before upserting |
| [E4](#e4) | String replace silently did nothing | tooling | An edit that can no-op must assert |
| [E5](#e5) | Consistency test stopped covering new tables | test design | Tests pinned to a filename rot |
| [E6](#e6) | Tiebreak points would have been labelled `'ad'` | SQL semantics | `CASE ELSE` swallows NULL |
| [E7](#e7) | Regex matched 1% of expected | wrong model of the data | Look at the data before tuning the pattern |
| [E8](#e8) | Claimed "several hundred MB" | unverified claim | Measure before you document |
| [E9](#e9) | `.gitignore` swallowed the lessons folder | pattern scope | A leading slash anchors to the repo root |
| [E10](#e10) | Reverse-engineered a spec that was already written | research order | Look for the spec before deriving it |
| [E11](#e11) | Renaming a dbt model left a 474 MB orphan | tool boundaries | A declarative tool only owns what you still declare |
| [E12](#e12) | Guessed which column to index; wrong by 150x | performance intuition | Heap fetches cost, not lookup selectivity |
| [E13](#e13) | `from __future__ import annotations` broke Dagster | runtime introspection | A stringified annotation is invisible to code that reads types at runtime |
| [E14](#e14) | Read group means as if they were the whole variance | statistics | Compare between-group spread to within-group spread, always |
| [E15](#e15) | Invented a physical reason my own data refuted | explanation | An unexplained rule beats a plausible wrong one |
| [E16](#e16) | Judged code by a metadata string, not by its behaviour | provenance | Test the artifact; an author field is not evidence |
| [E17](#e17) | Joined on a GROUPING SETS column with `=`; NULL never matched | three-valued logic | A nullable join key needs `is not distinct from` |

---

## E1
```
UndefinedFunction: function round(double precision, integer) does not exist
```
**Where:** `sql/queries/serve_direction_entropy.sql`, first run.

**Cause:** `p` was `numeric`, but `LN(3)` — integer literal — returns
`double precision`. `numeric / double` is `double`, and Postgres only has a
two-argument `round()` for `numeric`.

**Fix:** `LN(3::numeric)`.

**Rule:** in Postgres, numeric and floating-point are genuinely different types
with different function sets. When a cast fixes a function-not-found, ask which
operand silently promoted — the error names the *symptom*, not the operand.

## E2
```
Database Error in test accepted_values_stg_matches_best_of__False__3__5
  invalid input syntax for type integer: "Zindaras"
```
**Where:** first `dbt build`.

**Cause:** two upstream rows missing both player-name fields; every value shifted
one column left. Not a parsing bug — a source data bug.

**Fix:** field-count validation in the loader, ahead of value validation.

**Rule:** a shifted row has **no invalid values**. Structural checks must run
before semantic ones. → lesson 007.

**Worth noting:** this error was *good*. The TEXT raw layer let the row land so
it could be inspected instead of dying anonymously mid-`COPY`. → lesson 001.

## E3
```
ERROR: ON CONFLICT DO UPDATE command cannot affect row a second time
```
**Cause:** duplicate natural keys **within a single file**. Postgres won't let
one statement update the same target row twice.

**Fix:** `SELECT DISTINCT ON (key) … ORDER BY key` before the insert.

**Rule:** upsert deduplicates *against the table*, not *within the batch*. Those
are different problems and you need both. The dedupe count is logged
(`deduped=1532`) rather than swallowed — correct handling is not a reason to stop
reporting.

## E4
**Symptom:** a Python patch printed `ok`, the test count didn't change, and
`grep` showed the file untouched.

**Cause:** `s.replace(old, new)` where `old` no longer existed —`ruff format` had
collapsed the target dict onto one line since it was written. `str.replace`
returns the string unchanged when there's no match. **No error, no signal.**

**Fix:** `assert target in s, "anchor not found -- refusing to write"`.

**Rule:** any edit that can silently no-op must assert its precondition. This
class of bug is worse than a crash because the *next* action proceeds on a false
premise — here, running tests that appeared to pass because the new code was
never added.

## E5
**Symptom:** after adding three sources, `pytest` still reported 18 tests.
Expected 27.

**Cause:** `tests/test_sources.py` read only `sql/002_raw_tables.sql`. New tables
arrived in `004`, so the DDL-consistency check silently stopped covering them.

**Fix:** glob every `sql/*.sql`.

**Rule:** a test pinned to a filename has a silent expiry date. Pin to the
*pattern* that defines the category — the test's job is "every source has a
table", not "the tables in file 002".

## E6
**Symptom:** caught in review, not at runtime. `court_side` was:

```sql
case when (s + r) % 2 = 0 then 'deuce' else 'ad' end
```

**Cause:** tiebreak scores like `'5-4'` produce NULL for `s` and `r`.
`NULL % 2 = 0` is NULL, not false — so it fell to `ELSE` and every tiebreak point
would have been labelled `'ad'`. Confidently, and wrongly.

**Fix:** explicit `when s is null or r is null then null` first.

**Rule:** `CASE … ELSE` catches NULL along with false. Whenever the input can be
NULL and NULL isn't the same as "the other branch", handle it explicitly. This is
the SQL three-valued-logic trap in its most common disguise.

## E7
**Symptom:** counting `[fb][123]` matched Sackmann's shot totals for **1%** of
matches. A wrong pattern usually gets you *close*; 1% means the model is wrong,
not the tuning.

**Cause:** modifier characters between letter and digit — `f;1`, `z^3`, `j=+2`.
Never looked at enough raw strings before writing the regex.

**Rule:** when a result is catastrophically wrong rather than slightly wrong,
stop tuning and go read the raw data. 20 sample strings would have shown this in
30 seconds.

## E8
**Symptom:** the README claimed the points files were "several hundred MB". They
total **178 MB** and load in 52 seconds.

**Cause:** estimated from the row count, never measured.

**Rule:** anything a reader would use to make a decision — "is this worth
downloading?" — is a claim, and claims get measured. Estimates get labelled as
estimates.

## E9
**Symptom:** `git add -A` staged `lessons/README.md` and `lessons/errors.md` but
none of `lessons/001-*.md` through `008-*.md`. No error.

**Cause:** the rule protecting the private career docs was `0*.md`. A gitignore
pattern with no slash matches **at any depth**, so it also matched
`lessons/001-raw-layer-is-text.md`. Eight files silently excluded.

**Fix:** `/0*.md` — a leading slash anchors the pattern to the repository root.

**Rule:** gitignore patterns without a slash are recursive. An over-broad ignore
fails in the most dangerous direction: `git status` is clean, the commit looks
complete, and the files are simply absent. Any time an ignore rule is written to
exclude a *specific* file, anchor it.

**Related to E4:** both are silent no-ops. The tell in each case was a count that
didn't change — 18 tests instead of 27, 2 staged files instead of 11. **When an
operation should change a number, check the number.**

## E10
**Symptom:** three sessions spent recovering notation conventions by diffing
against Sackmann's aggregations — the errored-shot rule, the unreturned-serve
clamp, the modifier characters, the direction orientation. `docs/mcp-notation.md`
carried ⚠️ and ❓ confidence markers throughout, and `lessons/005` framed the
orientation as "the one genuinely unresolved question."

**Cause:** all of it is documented in the Instructions tab of
`MatchChart 0.3.2.xlsm`, in the upstream repo. That file appeared in the very
first directory listing of the source repo, second line of the output. It was
never opened — dismissed as a spreadsheet template rather than recognised as the
spec. `data_dictionary.txt` was read instead, and it documents only the CSV
*columns*, which made the codes look genuinely undocumented.

**Fix:** read the spreadsheet. `docs/mcp-notation.md` is now transcribed from it
and every ⚠️/❓ is gone.

**Rule:** before reverse-engineering a format, spend five minutes establishing
whether it has a spec — and treat every file in the source repo as a candidate,
including the ones whose extension suggests they're not documentation. The cost
here wasn't the derivation itself; it was **asserting that something was
unknowable when it was merely unread.** `lessons/005` claimed a question was open
that had a published answer.

**The honest counterweight:** the reverse-engineering wasn't wasted, and this is
the part worth keeping. The spec says what the codes *mean*; it cannot say
whether our SQL implements them correctly. The oracle diff produced the 90.0% /
82.5% / 55.2% agreement rates and surfaced the era gradient — **neither of which
is in the spec, and the era gradient is the single most useful finding in the
repo.** So: read the spec *first*, then diff against the oracle anyway. They
answer different questions, and skipping the second is the more expensive mistake.

**Corollaries found on reading it**, each of which would have caused wrong
numbers downstream:
- `7`/`8`/`9` are **service-return depth only**. Our codebook described them as
  general shot depth.
- Shot direction is **optional**. Any direction rate has a denominator of "shots
  with a direction charted", and that missingness is not random.
- **Forced errors need only shot type + `#`** — so they usually carry no
  direction. This is a strong candidate explanation for the open gap in
  `lessons/005`.

## E11
**Symptom:** `fct_serve_points` — 474 MB, 1,875,054 rows — still in the
warehouse after the model was renamed to `fct_points`. `dbt build` green.
Queryable by name. Diverging from the live table on every rebuild.

**Cause:** dbt created the new relation and has no record the two are related.
A rename is a delete plus a create as far as the project is concerned, and dbt
never deletes relations it no longer declares.

The same session showed the mirror case: every index on every analytics table
was missing, including one created by a `post_hook` that had been verified
working two sessions earlier.

**Fix:** dropped the orphan; moved indexes into model config; added
`assert_indexes_exist.sql`, verified by dropping an index and watching it fail.

**Root cause of the missing indexes, found by that test:** the `post_hook` used
`CREATE INDEX IF NOT EXISTS`. During a rebuild dbt keeps the old relation as
`__dbt_backup` until after post-hooks run, and that backup still holds an index
of the same name. `IF NOT EXISTS` matches on name *within the schema*, not on
`(table, name)` — so it found the backup's index, did nothing, and reported
success. The backup was then dropped, taking the index with it. Drop-then-create
fixes it; verified across two consecutive full builds.

That makes `IF NOT EXISTS` a **silent no-op guard**, the same class as E4 and E9:
all three fail by doing nothing while reporting success.

**Rule:** a declarative tool guarantees only what you still declare. Everything
else — relations you renamed away from, side effects like indexes, anything
created by a hook — is **state the tool does not know it owns**, and its absence
or persistence is silent. Every imperative side effect needs its own assertion.

Related: `dbt run-operation` with a cleanup macro, or `--full-refresh` on a
fresh schema, both handle orphans. Neither helps unless something tells you the
orphan is there, which is the actual gap.

## E12
**Symptom:** predicted that indexing the most selective column would fix a slow
query. It gave 1.3x. The index I had argued *against* gave 200x.

```
no index                                     384 ms   90,482 buffers
btree (server_name)        [my pick]         290 ms    3,163 buffers
partial (server_name) where is_break_point   1.9 ms    1,035 buffers
```

**Cause:** reasoning from column selectivity alone. `server_name` is 0.9%
selective and `is_break_point` 9.2%, so the player column looked obviously
right. But the cost is **heap fetches**, not index lookups: a plain index on
`server_name` pulls all 23,821 of that player's rows into the heap and then
filters, while the partial index *contains* only break-point rows and touches
1,663.

**Rule:** selectivity tells you how many rows the index will hand back, not how
much work that is. A partial index is a pre-filtered subset rather than a
pointer list, which is why a ~10% boolean — famously not worth indexing alone —
is an excellent index *predicate*.

**Meta-rule, which is the reusable half:** I stated the prediction before
running it, so the refutation was unambiguous and cost one query. That is the
whole value of writing the prediction down (CLAUDE.md, verification discipline).
Without it this would have been a vague sense that the numbers were fine.

## E13
```
DagsterInvalidDefinitionError: Cannot annotate `context` parameter with type
AssetExecutionContext. `context` must be annotated with AssetExecutionContext,
AssetCheckExecutionContext, OpExecutionContext, or left blank.
```
**Where:** first load of the Dagster definitions.

**Why it's maddening:** the parameter *was* annotated `AssetExecutionContext` —
the error names the exact type I had used and told me to use it.

**Cause:** `from __future__ import annotations` at the top of the module. PEP 563
makes every annotation a **string** rather than the object, evaluated lazily or
never. Dagster inspects `context`'s annotation at decoration time to decide what
to pass, sees the string `"AssetExecutionContext"`, finds it in none of the
accepted classes, and reports the mismatch using the text it read — which is
identical to the correct answer.

**Fix:** drop the future import from any module defining an asset that takes a
context. Both files now carry a comment saying why, because the natural instinct
on seeing a bare module without it is to "tidy up" and add it back.

**Rule:** `from __future__ import annotations` is safe for type checkers and
unsafe for **anything that reads annotations at runtime.** That includes Dagster's
op/asset decorators and, historically, some Pydantic and FastAPI patterns. The
tell is an error message that quotes your annotation back at you as a string.

This is the same class as E11: a tool inspecting state you assumed was declarative
and inert. E11 was dbt not owning an index; this is Dagster reading a type hint as
data. **Whenever a framework derives behaviour from your source text rather than
your values, the text's representation becomes part of the contract.**

## E14
**Claim I committed:** "the residual **is** charter idiosyncrasy."

**What I had:** per-charter mean gaps spanning −15.48 to +12.14 — a 28-shot spread
across volunteers, which looked decisive.

**What I never computed:** the spread *within* each charter.

```
 total variance of gap   111.6
 within-charter           86.4   (77%)
 between-charter          26.5   (24%)
```

Charter identity explains **23.7%**. Three quarters of the variation is between
matches charted by the same person.

**Cause:** I compared group means, saw a large range, and concluded the grouping
variable explained the data. But a between-group difference only matters *relative
to* the within-group noise it sits in — that ratio is the entire content of an
F-test, and I skipped it because the means told a satisfying story.

**Rule:** whenever a grouping variable looks like it explains a pattern, decompose
the variance before saying so. Group means are a hypothesis; the decomposition is
the test. One `var_samp` per group and a weighted sum would have caught this in a
single query.

**Why it mattered here:** the wrong version closed an investigation. "It's the
charters" reads as solved; "charters explain a quarter, 77% is unexplained" is
plainly still open.

## E15
**Claim I committed:** Sackmann excludes net unforced errors because "a ball that
hit the net never crossed the opponent's baseline, so it has no direction to
record."

**What the same dataset says:** **forced** net errors carry a direction 171,427
times, against 198,229 unforced — and those we *count*, matching his numbers. If
the physical argument held, forced net errors would be excluded too.

**Cause:** the rule was found empirically, by testing four candidate subtractions
and keeping the one that landed nearest zero. That is sound. Then I attached a
physical story to it, and the story was so tidy I never checked it against the
adjacent case sitting in the same measurement — the one I had *already run*, which
was how I knew forced net errors were counted.

**Rule:** an empirically-derived rule and an explanation for it are two separate
claims needing two separate tests. Deriving the first does not license the second.
Where the mechanism is unknown, **write "unknown"** — a rule marked unexplained
stays open to revision, while a rule with an invented reason gets defended.

The interview version of this is short: *"I know the rule, I measured it, and I
can't tell you why — here's what I ruled out."* That is a stronger answer than a
confident wrong mechanism, and an interviewer who knows the domain will find the
contradiction in the confident version.

## E16
**Claim I committed:** the Rust shot parser is "AI-generated," and that is a reason
not to make it central — "a liability as a centrepiece."

**Evidence I had:** one string in its CLI definition, `author("MiniMax Agent")`.

**What was actually true:** that string is left over from an early prototype
scaffold; the functional parser was written with Claude Code. So was every other
line in this repository, including the models, the orchestration and the lessons
making the accusation.

**Two distinct mistakes, and the second is the worse one:**

**Inferring provenance from metadata.** An `author` field is a default someone
didn't change. I had the parser building and running — 1.875M rallies, zero
failures, 89.9% oracle agreement — and reached for a config string instead of the
measurement I'd already taken.

**Applying a standard inconsistently.** Even granting the premise, the objection
only works if AI-assisted code is disqualifying, and by that standard nothing here
survives. I held one file to a bar the rest of the repo was exempt from, without
noticing the rest of the repo existed.

**Rule:** judge an artifact by its behaviour against an independent check, which is
the standard this whole repo runs on. And before flagging something as a
disqualifier, apply it to the surrounding work — if the rest would fail too, the
criterion is wrong, not the artifact.

**What survived the correction:** the *integration* objection, which never depended
on provenance. A compiled binary inside a dbt lineage is a black box in the DAG,
and "every output traceable to source" is the story this repo sells. Using the
parser as an oracle for a Python or SQL tokenizer keeps that intact and still saves
writing the state machine.

## E17
**Symptom:** `mart_rally_shape` built successfully and every `win_rate_slope` was
NULL. No error, no failing test.

**Cause:** the slope is computed in a separate CTE (because `regr_slope` aggregates
over the bucket *rows*) and joined back on `(player_name, surface,
_surface_rolled)`. `GROUPING SETS` sets `surface` to NULL on the rolled-up rows,
and **`NULL = NULL` is NULL, not true** — so for exactly the pooled rows, the
`LEFT JOIN` matched nothing and quietly produced NULLs.

**Fix:** `is not distinct from` instead of `=` — Postgres's NULL-safe equality.

```sql
and r.surface is not distinct from s.surface   -- not  r.surface = s.surface
```

**Rule:** the moment a join key can be NULL, `=` is wrong. `GROUPING SETS`,
`ROLLUP`, `CUBE` and outer joins all manufacture NULLs in columns that are
otherwise populated, so any key downstream of them needs the null-safe operator.

**Why it's insidious:** a `LEFT JOIN` that matches nothing looks identical to a
`LEFT JOIN` that correctly found no match. The failure is a column of NULLs, which
is also what "no data yet" looks like. Third member of the family with E6 (`CASE
… ELSE` swallowing NULL) and the tiebreak bug: **Postgres's three-valued logic
fails quietly by design**, so any NULL-capable column in a predicate deserves a
deliberate decision rather than a default operator.
