# Routing variants -- one change per step

Each file is a full `<routing>` text. Each changes ONE thing from the one
before, so a score change can be attributed (the sql/investigations rule).
Score one with:

    uv run python -u scripts/eval_routes.py --routing-file evals/routing_variants/v1.txt

| File | Change from the previous |
|---|---|
| v0.txt | the `<routing>` in prompts.py on 2026-11-25 (D8) |
| v1.txt | rule 2: answer the literal part even when the missing part is the main point |
| v2.txt | rule 4: only questions that need the ORDER of shots refuse; "how often / where" is sql |
| v3.txt | rule 8: the data covers 1960 to September 2026, so a year in that range is not the future |
| v4.txt | v0 + rule 8 only (v1 and v2 dropped: no measurable gain) |

## Results (2026-11-25, two runs each, of 37)

| v0 | v1 | v2 | v3 |
|---|---|---|---|
| 26, 25 | 25, 24 | 24, 26 | 25, 25 |

No variant beats v0; all within noise. The stable misses fail in all 8 runs
whatever the wording: absent players (need name resolution), matchup-01 (its
"exploit" clause reads as tactical advice), pressure-02 and direction-02 (need
column descriptions). v3 made trap-03[absent] fail in both runs, as predicted:
fixing the 'future' reason removed a lucky refusal.

Examples inside a variant must not be eval questions -- the eval would then
grade its own examples.
