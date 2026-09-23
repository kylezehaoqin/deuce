# Blog backlog

Post seeds. Each has a **hook**, the **evidence already in hand**, and where the
material lives. The point is that none of these start from a blank page — the
work is done, the numbers exist, what's missing is your words.

**Status:** ⬜ unwritten · ✍️ drafting · ✅ published

A seed earns its place by having a **number or a surprise** in it. "Here's how
dbt works" is a tutorial nobody needs. "The index I argued against was 150×
faster" is a post.

---

## Strongest first

These have the sharpest hooks — a concrete number and a reversal.

### ⬜ The index I argued against was 150× faster than the one I picked

**Hook:** I reasoned from column selectivity, stated the prediction out loud,
and lost by two orders of magnitude.

**Evidence:**
```
no index                                     384 ms   90,482 buffers
btree (server_name)      [my pick, 0.9%]     290 ms    3,163 buffers
partial (…) WHERE is_break_point  [9.2%]     1.9 ms    1,035 buffers
```

**The turn:** selectivity tells you how many rows come back, not how much work
that is. Heap fetches dominate. A partial index is a pre-filtered subset, not a
pointer list — which is why a ~10% boolean is a terrible index and an excellent
index *predicate*.

**Material:** `lessons/errors.md` E12 · `lessons/010` · `notes/concepts.md`

---

### ⬜ `CREATE INDEX IF NOT EXISTS` silently did nothing, and the build stayed green

**Hook:** every index on the warehouse vanished. No error. The guard meant to
make the operation safe is what destroyed it.

**The mechanism** (this is the whole post):
```
2. rename  fct_serves          -> fct_serves__dbt_backup   ← still holds the index
4. run post-hooks              ← IF NOT EXISTS sees the name taken, does nothing
5. drop    fct_serves__dbt_backup                          ← index goes with it
```
`IF NOT EXISTS` matches on the index name *within the schema*, not on
`(table, name)`.

**The turn:** three bugs in this project have the identical shape — a string
replace that matched nothing, a gitignore pattern that matched too much, and
this. All fail by **doing nothing while reporting success**, which is worse than
crashing because the next step proceeds on a false premise.

**Material:** `lessons/010` · `errors.md` E4, E9, E11

---

### ⬜ Momentum in tennis is a myth. Here's half a million points.

**Hook:** the naive query says momentum is real. Add one control and the two
halves point in *opposite directions*.

**Evidence:**
```
 returner won prev pt | after short (<=4)  | 320,823 | 0.3949
 returner won prev pt | after LONG (9+)    |  63,575 | 0.4046   +1.0pp
 server won prev pt   | after short (<=4)  | 473,757 | 0.6299
 server won prev pt   | after LONG (9+)    |  78,681 | 0.6099   −2.0pp
```

**The turn:** long rallies favour the returner, and returners win fewer points.
Pooled, you measure *serving* and call it momentum. What people call momentum is
rally length.

**Why it's a good post:** counterintuitive, huge sample, and the methodology is
the actual content — a confound you can see flip the sign.

**Material:** `lessons/006` · `hypotheses-tennis.md` T2

---

### ⬜ I replaced a 743-line parser with one line of regex — and that was correct

**Hook:** a typed Rust state machine and `regexp_replace(…, '[^fbrsvz…]', '')`
agree with the source author's own numbers on 90.0% vs 89.9% of matches.

**The turn:** *a regex answers questions about a multiset of characters; a
parser answers questions about a sequence of records.* Rally length is a
counting question — "how many shot letters are there" — so the cheap tool was
the right tool. Shot selection is a sequence question and regex cannot get
there, no matter how clever.

**The second half:** this is also why the fact table is at shot grain. Point
grain physically cannot express "where the previous ball went," so those
questions aren't harder there — they're unreachable.

**Material:** `lessons/009` · `lessons/004`

---

### ⬜ Your test has never failed. That's not good news.

**Hook:** a test that has never failed is indistinguishable from one that
*cannot* fail.

**Evidence:** three guards in this project, each broken on purpose to confirm it
fires — sabotaged a parser macro (test failed, 3 tiers below threshold), dropped
an index (failed, 1 result), and one that failed *on its first real run* and
found a bug nobody had diagnosed.

**The turn:** assertions find things hypotheses don't, because they don't
require you to have guessed right first. The index test wasn't written to catch
the `IF NOT EXISTS` bug — it caught it anyway.

**Material:** `lessons/010` · `lessons/004` · CLAUDE.md verification discipline

---

## Also good

### ⬜ A column called `row` lied to me

**Hook:** I annotated a schema from a column's name. It was wrong for two hours
and nothing would have noticed.

**The turn:** counting distinct values tells you *what's there*, not what it
*means*. The test that settles it is an **arithmetic identity** — if these are
serve numbers, rows 1 and 2 must sum to Total. They did, for 23,597 of 23,600
groups. Set numbers wouldn't.

**The stakes:** column descriptions get fed to an LLM as schema context. A wrong
description isn't a stale comment, it's a prompt injection you wrote yourself.

**Material:** `lessons/003`

---

### ⬜ I reverse-engineered a spec that was sitting in the repo

**Hook:** three sessions recovering notation conventions by diffing. All of it
was documented, in a file listed on line 2 of the first directory listing I ran.

**The turn — and this is what saves the post from being a confession:** the
reverse-engineering wasn't wasted. The spec says what the codes *mean*; it
cannot say whether your implementation is *correct*. The oracle diff produced
the accuracy numbers and the era gradient, neither of which is in the spec.
**Read the spec first, then diff against the oracle anyway.**

**Material:** `errors.md` E10 · `docs/mcp-notation.md`

---

### ⬜ Charting conventions drifted, and the parser tells you when

**Hook:** the same parser is 91.6% accurate on 2020s matches and 54.0% on
pre-2010 ones. Two *independent* implementations degrade identically, which is
how you know it's the data and not your code.

**The turn:** an aggregate accuracy number hides the only interesting thing
about it. This is why every parsed row carries `parse_confidence` and the agent
must disclose it — provenance is a product constraint, not a metric.

**Material:** `lessons/004` · `hypotheses-data.md` H7

---

### ⬜ What player-similarity can and can't see

**Hook:** my first "who plays like Federer" model returned **Ana Ivanovic**.

**The turn:** two failures worth the post. Pooling ATP and WTA meant the
distances measured *tour*, not style. And the holdout — drop the slice feature
and one-handers fall from 5/10 to 3/10, so the vector was substantially reading
one give-away column.

**The honest limit:** trajectory, pace and spin aren't charted at all. "Flatter
forehand" is unavailable. Style here means *what shots, hit where* — not how the
ball comes off the strings.

**Material:** `hypotheses-tennis.md` T9

---

### ⬜ Every statistic you precompute is one the agent can't get wrong

**Hook:** the mart grain decision and the system prompt are the same decision
seen from two sides.

**The turn:** every column you precompute is a question the agent can no longer
ask; every statistic you leave to it is one it can get subtly wrong. Entropy is
the clean example — three passes and a zero-guard, which an LLM writing SQL on
the fly will fumble some fraction of the time.

**Needs:** the agent to exist first. Park until Increment 2.

**Material:** `dbt/models/marts/mart_serve_patterns.sql` header · `docs/marts.md`

---

## Series idea

Increments 0→4 as a build log, one post per increment, written as they ship.
Weaker hooks individually, but the dated sequence is itself the artifact — and
the brief says the commit history is part of the deliverable.

Worth doing *only* if each post carries one real finding. A build log with no
surprises in it is a changelog.

---

## Parking lot

Half-thoughts. Promote when they grow a number.

- Naming: `fct_serve_points` → `fct_games` needing to read it is what proved the
  name wrong. *When a downstream consumer makes a name sound absurd, the name is
  wrong, not the consumer.*
- 80.2% / 66.5% hold rates matching the real tours — the cheapest validation in
  the project, and a post about *sanity checks as a discipline*.
- Two hypothesis logs, two standards of proof: a format question closes
  permanently, a tennis question never does.
- The oracle rule that was too broad as a slogan and broke on the first concrete
  mart. *A constraint you can't state per-artifact is a preference.*
