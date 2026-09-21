# Investigations

Throwaway-shaped SQL that isn't throwaway.

An investigation is a **measurement harness with one hole in it.** Everything
except the hypothesis under test is written and fixed: the oracle side, the join,
the metrics, the per-era breakdown. You edit one expression, re-run, and read a
number that is directly comparable to the last number.

That constraint is the whole point. The failure mode when chasing a discrepancy
is changing two things at once and improving the result — after which you know
you're closer but not why, and you can't undo the half that hurt. (That happened
in this very investigation; see `lessons/hypotheses.md` H10.)

## Running one

```bash
make investigate FILE=005_shot_direction_scope.sql
```

Fast enough to run every 30 seconds. That's deliberate — a loop you can run
absent-mindedly is a loop you'll actually use.

## Rules

1. **Write your prediction before you run.** Each file has a slot for it. The gap
   between prediction and result is the learning signal; without the prediction a
   surprising result just looks like a result.
2. **Change one thing.** If you can't attribute the improvement, you haven't
   learned anything you can reuse.
3. **Log the round in `lessons/hypotheses.md`** — including the rounds that made
   it worse. Especially those.
4. **When it converges, promote it.** A settled investigation becomes a macro
   plus a dbt test (see `mcp_rally_length` and
   `assert_rally_length_matches_oracle`), and the file stays here as the record
   of how it was settled.
