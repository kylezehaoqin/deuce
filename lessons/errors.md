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
