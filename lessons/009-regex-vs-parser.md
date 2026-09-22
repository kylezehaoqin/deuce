# 009 — When a regex is enough, and when you need a parser

> A regex answers questions about a *multiset* of characters. A parser answers
> questions about a *sequence* of records. Knowing which kind of question you
> have saves you from building the wrong thing — in both directions.

**Concept:** tokenization; why grain is forced by the data, not chosen
**Lives in:** `dbt/macros/mcp_rally_length.sql`, `dbt/models/marts/fct_shots.sql`
**Status:** settled

## The thing itself

A tokenizer turns **one string** into **an ordered list of structured records**.
A real rally from the data, point 101 of a 2026 Roland Garros qualifier:

```
4r2j=+2b3z^3*
```

Thirteen characters to a regex. Five shots to a tokenizer:

| # | Token | Len | Shot | Direction | Modifiers | Outcome |
|---|---|---|---|---|---|---|
| 1 | `4` | 1 | serve | out wide | — | in |
| 2 | `r2` | 2 | forehand slice | middle | — | in |
| 3 | `j=+2` | 4 | fh swinging volley | middle | at baseline, approach | in |
| 4 | `b3` | 2 | backhand | righty's BH side | — | in |
| 5 | `z^3*` | 4 | backhand volley | righty's BH side | stop volley | **winner** |

Token lengths: **1, 2, 4, 2, 4.**

That variability is the whole problem. A shot can be `b`, `b3`, `b3n`, `b3n#`,
`b+3`, `f;1`, or `j=+2`. No fixed offsets. No delimiter to split on. You have to
read left to right and decide what each character means given what came before —
which is parsing, by definition.

**How often does the variability actually bite?** Over 900,699 points from the
2020s:

```
 pct with a modifier char (-+=;^)     20.7%
 pct with a 3-char return (dir+depth) 63.0%
 pct with a shot and no direction      2.3%
```

One point in five contains a modifier; nearly two in three contain a
three-character return token. Fixed-width assumptions are not a rare edge case
here, they are the common case.

## The three dodges that worked

We answered real questions for weeks without a tokenizer. Each dodge is
instructive:

| Question | Method | Why it works |
|---|---|---|
| Where did the serve go? | `left(rally, 1)` | Character one is always the serve |
| How long was the rally? | count shot letters | **Counting doesn't need identity** |
| How did the serve miss? | one char after the direction | Fixed position |

The middle one is the interesting case. `regexp_replace(rally,
'[^fbrsvzopuylmhijktq]', '', 'g')` strips everything that isn't a shot letter and
counts what's left. It agrees with Sackmann's own rally-length buckets on **90.0%
of 2020s matches** — statistically tied with a 743-line typed Rust parser at
89.9% (lesson 004, and the Rust comparison in this repo's history).

One line of SQL matched a real state machine. That is not a fluke: *how many shot
letters are there* is a question about a bag of characters, and a bag of
characters is exactly what a regex sees.

## Where it stops

The moment a question names a **specific shot**, the dodge fails:

> "How often does she go down the line **off the backhand**?"

You now need to know that shot 4 was a backhand *and* where it went. You can
regex out backhand-plus-direction pairs — lesson 005 does exactly that, and got
to a 19.5-shot-per-match gap against the oracle. What you cannot reliably
recover is **which position in the rally each match occupied.**

Position is load-bearing:

**1. Attribution.** Shots alternate — odd shots are the server's, even are the
returner's. Ordering is the *only* way to know who hit a shot. Lose it and you
have a table of shots with no player on them.

**2. Relative direction.** Codes `1/2/3` are absolute court thirds
(`docs/mcp-notation.md`). Crosscourt versus down-the-line depends on where the
*hitter* is standing, which depends on where the *previous* ball went. Shot N's
tactical meaning is a function of shot N−1.

That second one is why five tactical categories (crosscourt, down the middle,
down the line, inside-out, inside-in) come out of three direction codes. The
extra information is positional state, and state requires a sequence.

## The consequence for grain

**Point grain physically cannot express "where the previous ball went."** So a
whole class of questions isn't harder at point grain — it's unreachable.

That's the argument for `fct_shots` at one row per shot, and it's worth stating
precisely: the grain is **forced by the questions**, not chosen for tidiness. Any
grain coarser than the unit a question is about will fail that question no matter
how many columns you bolt on.

**Blocked without it:** `questions.yml` #2, #6, #7, #8, #12, #13 · T6 and T7 in
`hypotheses-tennis.md` · the pattern-entropy mart (a transition matrix is
sequence-native) · closing lesson 005's direction mapping.

**Not blocked:** serve placement and entropy · rally length · momentum ·
first-striker vs grinder · fault types · game-grain hold and break · the style
vectors as currently built.

Roughly half of `questions.yml` is in the second list, which is why Increment 2
is not gated on this.

## Two meanings of "token"

Worth separating, because they get conflated:

- **Lexical token** (this lesson): a structured record recovered from a string.
  `j=+2` → *forehand swinging volley, from the baseline, approaching, to the
  middle*.
- **ML token**: a symbol from a chosen vocabulary fed to a model, e.g.
  `FOREHAND_MIDDLE_APPROACH`.

The second comes strictly after the first. You cannot build ML tokens without
parsed records to encode. Parsing recovers *what happened*; vocabulary design
decides *how to represent it*. Conflating them makes the vocabulary look like a
data-loading concern when it's a modelling decision.

## The trade-off

| | Regex in SQL | Tokenizer |
|---|---|---|
| Stays in the dbt lineage | yes | depends on implementation |
| Handles counting questions | yes, as well as anything | yes |
| Handles identity questions | no | yes |
| Handles stateful questions | no | yes |
| Cost to write | one line | a state machine |
| Cost to verify | diff against oracle | diff against oracle |

The trap in both directions:

- **Over-building:** writing a parser to answer a counting question. We nearly
  did; the one-liner tied it.
- **Under-building:** stretching regex at a sequence question. Lesson 005 is a
  live example — three rounds of refinement got the gap from 159 to 19.5 and it
  is still open, because the remaining error lives in exactly the structure a
  regex cannot see.

**Note on the existing Rust parser:** it's a real tokenizer, and its value sits
precisely in the tier we hadn't reached. Measured on rally length it ties a
one-liner, which says nothing bad about it — that's a counting question. Its open
question is integration (a compiled binary inside a dbt lineage; AI-generated
code as a centrepiece), not capability. Using it as the *oracle* for a
Python or SQL tokenizer sidesteps both while still saving the state machine.

## Saying it out loud

> The source data encodes a whole rally as one string, like `4r2j=+2b3z^3*`.
> For a while I answered questions with regex — serve direction is character one,
> and rally length is just counting shot letters, which matched the data author's
> own numbers on 90% of matches. But regex sees a bag of characters, and the
> moment a question is about a *specific* shot you need a sequence: shots
> alternate, so ordering is the only thing that tells you who hit what, and
> crosscourt versus down-the-line depends on where the previous ball went. That's
> a parser, and it's also why the fact table has to be one row per shot — point
> grain can't express "the previous ball", so those questions aren't harder
> there, they're unreachable.

## Try it yourself

Take `6f27f;1f3f3b2f3b3f3s1n#` and tokenize it by hand using
`docs/mcp-notation.md`. Then ask: which shots were hit by the server? Now do it
again assuming you only have the *multiset* of characters, with no ordering.
The second question is the one regex is stuck with.
