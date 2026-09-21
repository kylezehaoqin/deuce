# 006 — Is momentum a myth?

> The naive query said momentum exists. The controlled query said the two halves
> of the effect point in opposite directions.

**Concept:** confounds; what a correlation is allowed to mean
**Lives in:** `questions.yml` #10
**Status:** settled

## The question

*"After winning a long rally, does a player win the next point more often?"*

The obvious query: for each point, look at the previous point; if the same player
won both, count it. Split by whether the previous rally was long.

## The confound

Long rallies favour the **returner** — the server's advantage decays the longer
the ball stays in play. So the winner of a long rally is disproportionately the
returner, and the returner is *less* likely to win the next point for reasons
that have nothing to do with momentum.

The naive query mixes a real effect (serving) with the effect being measured
(momentum), and reports the sum.

## The control

Two changes:

1. **Restrict to consecutive points within the same game.** Same server, so the
   service advantage is held constant.
2. **Split by who won the previous point** — server or returner — instead of
   pooling them.

```sql
LAG(rally_len) OVER (PARTITION BY match_id ORDER BY pt) AS prev_len,
LAG(pt_winner) OVER (PARTITION BY match_id ORDER BY pt) AS prev_winner,
LAG(gm_num)    OVER (PARTITION BY match_id ORDER BY pt) AS prev_gm
...
WHERE gm_num = prev_gm     -- same game => same server
```

## The evidence

```
       control        |    previous_point     |   n    | same_player_wins_next
----------------------+-----------------------+--------+-----------------------
 returner won prev pt | after short pt (<=4)  | 320823 |                0.3949
 returner won prev pt | after medium (5-8)    | 116031 |                0.3994
 returner won prev pt | after LONG rally (9+) |  63575 |                0.4046
 server won prev pt   | after short pt (<=4)  | 473757 |                0.6299
 server won prev pt   | after medium (5-8)    | 157143 |                0.6156
 server won prev pt   | after LONG rally (9+) |  78681 |                0.6099
```

**The two halves move in opposite directions.** Returner: +1.0pp after a long
rally. Server: **−2.0pp**.

Momentum, if real, would help whoever just won. Instead, a long previous rally
predicts the *next* point is also contestable, and contestable points favour the
returner — regardless of who won the last one.

**Momentum is a myth. What people call momentum is rally length.**

Sample sizes are 63K–474K, so this isn't noise. Restricted to 2010+ matches,
where the parser is trustworthy (lesson 004).

## The trade-off

The control costs sample size — dropping cross-game point pairs threw away every
transition between service games, which is where the "let-down game" narrative
lives (question #11). Controls narrow what you can claim *and* what you can
measure. The right move is a second query for that question, not a looser
control on this one.

## Why this belongs in the agent's prompt

An LLM handed a marts table will happily produce the naive version and state it
confidently. The system prompt has to encode *which comparisons need a control* —
or at minimum, that a claim about causation requires naming what was held
constant. This is a routing/grounding requirement, not a SQL requirement.

## Saying it out loud

> Someone asked whether momentum is real. The naive query showed an effect, but
> there's a confound: long rallies favour the returner, and returners win fewer
> points overall, so you're measuring serving and calling it momentum. I held the
> server constant by restricting to consecutive points inside the same game, then
> split by who won the previous point. The two halves moved in opposite
> directions — the returner gained a point, the server lost two — which is what
> you'd see if the real driver is rally length, not psychology. Half a million
> points, so it's not noise. It also changed the product: the agent's prompt now
> has to know which questions need a control.

## Try it yourself

Question #11 is *"right after breaking serve, how often does a player get broken
straight back?"* — which needs exactly the cross-game transitions this control
threw away. What has to be held constant there, and what's the confound?
