# Lessons

Working notes on *why* this repo is built the way it is — written as it happened,
not reconstructed afterwards.

Each lesson is one decision or one discovery: what we hit, what we did, what it
cost, and how to explain it out loud. They exist because the code shows *what*
was decided and the commit log shows *when*, but neither shows the alternative
that was rejected — and the rejected alternative is the entire content of an
interview answer.

## Index

| # | Lesson | Concept | Status |
|---|---|---|---|
| [001](001-raw-layer-is-text.md) | The raw layer is all TEXT | Fidelity vs. correctness; where failures should surface | settled |
| [002](002-idempotent-loads.md) | Loads you can re-run | Idempotency, staging tables, `ON CONFLICT` | settled |
| [003](003-never-trust-a-column-name.md) | Never trust a column name | Reconciliation as verification | settled |
| [004](004-validating-a-parser.md) | Validating a parser with no labels | Oracle testing; baselines over perfection | settled |
| [005](005-open-direction-orientation.md) | Shot direction orientation | Stateful vs. stateless parsing | **open** |
| [006](006-controlling-for-confounds.md) | Is momentum a myth? | Confounds; what a correlation is allowed to mean | settled |
| [007](007-structure-before-semantics.md) | Field counts before field values | Structural vs. semantic validation | settled |
| [008](008-forward-only-migrations.md) | Forward-only migrations | Environment drift | settled |

Plus two running logs:

- **[hypotheses-data.md](hypotheses-data.md)** — claims about the *format*: what
  a column means, how the notation encodes a rally. Someone already knows the
  answer; these get settled against the spec or an oracle and then they're done.
- **[hypotheses-tennis.md](hypotheses-tennis.md)** — claims about *the game*:
  "Federer is not a grinder", "momentum is a myth". Nobody holds the answer key,
  so these need a stated falsifier, a named confound and a scope — and they stay
  provisional. They double as the agent's eval set.
- **[errors.md](errors.md)** — every error hit, its root cause, and the general
  rule it taught. Including the self-inflicted ones.

Keeping the two hypothesis logs apart matters more than it looks. They have
different standards of proof: a format question is settled by reconciliation and
is then closed, while a tennis question is settled by evidence and can be
reopened by a bigger sample or a confound nobody thought of. Filing them together
invites applying the wrong standard to both.

## How to use this

**Write the lesson before you write the code.** If you can't state the trade-off,
you haven't made a decision yet — you've made a default.

**Re-derive, don't re-read.** A week after writing one of these, try to reproduce
its evidence from a blank query window. If you can't, you learned the conclusion
but not the method, and the conclusion is the part an interviewer can't use.

**Be suspicious of the settled ones.** 003 is in this folder because a "settled"
fact was wrong for two hours and nobody would have noticed. Everything here has a
falsifiable claim attached on purpose.

## Lesson template

```markdown
# NNN — Title

> One-sentence takeaway.

**Concept:** the transferable idea
**Lives in:** path:line
**Status:** settled | open

## What happened
## The evidence          <- real numbers, real queries
## The trade-off         <- what the alternative would have cost
## Saying it out loud    <- ~60 seconds, first person, no jargon padding
## Try it yourself       <- a question you can answer with one query
```
