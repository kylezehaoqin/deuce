# Concepts

Reference. Look things up; don't copy them into writing.

- [Kimball and dimensional modelling](#kimball-and-dimensional-modelling)
- [The model prefixes](#the-model-prefixes)
- [GROUP BY vs window functions](#group-by-vs-window-functions)
- [Postgres indexes](#postgres-indexes)
- [NULL and three-valued logic](#null-and-three-valued-logic)
- [Normal forms, as they actually bite](#normal-forms-as-they-actually-bite)
- [Entropy as a metric](#entropy-as-a-metric)
- [Oracle testing](#oracle-testing)
- [Idempotency](#idempotency)
- [Two kinds of trust](#two-kinds-of-trust)

---

## Kimball and dimensional modelling

**Ralph Kimball** — a person. His 1996 *The Data Warehouse Toolkit* defined how
most analytical databases have been laid out since.

**The argument.** Before him the instinct was to design a warehouse like an
application database: fully normalised, no redundancy. Kimball's point was that
a warehouse has a different job — read-mostly, queried by analysts, not by
transactions. So optimise for the thing that matters: *can a human read this
schema and write a correct query?*

**The method.** Two kinds of table:

- **Facts** — measurements of events. Long, narrow, constantly appended.
- **Dimensions** — descriptive context. Short, wide, slowly changing.

Fact in the middle, dimensions around it: a **star schema**, named for the
diagram's shape. Every question becomes the same move — *filter the dimensions,
aggregate the fact.*

**The trade.** Kimball deliberately breaks normalisation. Dimension tables
repeat data a purist would split out. The classic objection is update
anomalies — change a value in one place, forget the other, they disagree. His
counter: that risk comes from *updating*, and warehouses mostly reload rather
than update. You're paying a cost you don't incur, to buy fewer joins.

**What the argument doesn't cover.** Anomalies aren't the only bill.
Denormalisation also costs storage and cache pressure, which arrives as a table
too big to scan. Cheap disk made the trade easy; it never made it free.

**The rival.** **Bill Inmon** argued the opposite — build a normalised
enterprise warehouse first, derive dimensional marts downstream. Slower to
deliver, better at organisation-wide consistency. "Kimball vs Inmon" is a real
interview question and the honest answer is that most modern stacks are hybrids.

**Where modern practice drifted.** A **wide fact table** (sometimes "one big
table") carries descriptive columns directly on the fact row instead of keying
out to dimensions. Columnar storage and cheap disk made it viable. For a
text-to-SQL agent it's actively better: every join the agent doesn't write is a
join it can't get wrong.

So a lot of projects use Kimball's *vocabulary* and *trade* without his *shape*.

---

## The model prefixes

Two vocabularies stitched together, which is why they don't form one clean
scheme.

| Prefix | Word | Means | From |
|---|---|---|---|
| `stg_` | staging | cleaned copy of one source; cast, rename, nothing else | dbt |
| `int_` | intermediate | working step; joins and derivations, not queried directly | dbt |
| `fct_` | fact | the events — one row per thing that happened | Kimball |
| `dim_` | dimension | the nouns — one row per thing that exists | Kimball |
| `mart_` | (data) mart | final presentation layer, aggregated to a question | dbt |

`stg_`/`int_` describe **how far along the pipeline** a model is. `fct_`/`dim_`
describe **what kind of thing** it holds. Different axes.

The split that matters: **facts are verbs, dimensions are nouns.** A serve
happened; a player exists.

**Row-count discipline** is what makes the layers checkable:

- `stg_` must not change cardinality. A staging model that adds or drops rows is
  a bug by definition — which is why it earns a uniqueness test.
- `int_` may fan out (a join, an unpivot).
- `fct_` sets a grain: preserves or fans out, never aggregates.
- `mart_` collapses.

---

## GROUP BY vs window functions

Both compute a group total. Only one destroys rows.

```sql
GROUP BY server, court        -- REDUCES: one row per distinct combination
SUM(x) OVER (PARTITION BY …)  -- ANNOTATES: group total stapled onto every row
```

**The rule for `GROUP BY`:** every column in `SELECT` must be in the `GROUP BY`
or inside an aggregate. Otherwise the engine asks "you gave me three rows for
this group — which value did you want?"

**When you need both.** Any share-of-group calculation. Each row has to know its
group's total *before* it can be collapsed, so:

1. `GROUP BY` down to one row per category → counts
2. `SUM(…) OVER (PARTITION BY …)` → staple on the group total, rows survive
3. `GROUP BY` again → collapse, combining the shares

**Postgres conveniences:**

```sql
count(*) FILTER (WHERE x = 'a')   -- conditional count, no CASE needed
count(col)                        -- counts NON-NULL only → a free denominator
```

That second one is quietly important whenever a field is optional: `count(*)` is
all rows, `count(col)` is rows where the thing was actually recorded, and
dividing by the wrong one silently changes what your rate means.

---

## Postgres indexes

**What costs is heap fetches, not lookup selectivity.** This is the whole thing.

An index scan finds row *pointers* fast. Then the database has to go fetch the
actual rows from the table ("the heap"), and that's random I/O. An index that
hands back 20,000 pointers has done a fast lookup and created an expensive
fetch.

Measured, on 2.58M rows for a query keeping 1,206 of them:

```
no index                                     384 ms   90,482 buffers
btree (server_name)        [0.9% selective]  290 ms    3,163 buffers
partial (server_name) WHERE is_break_point   1.9 ms    1,035 buffers
```

The most selective *column* lost by 150×. The partial index wins because it
*contains* only matching rows — 1,663 instead of 23,821 — so the heap fetch is
small. **Pre-filtering the index beats narrowing the lookup.**

**Partial index** — `CREATE INDEX … WHERE predicate`. Indexes a subset. The
classic use: a low-selectivity boolean (~10%) is famously not worth indexing
alone, because the planner prefers a seq scan over hundreds of thousands of
random fetches. As a *predicate* that same column is excellent.

**B-tree** — the default. Stores whole values in sort order. Great for `=`,
ranges, and prefix matches (`LIKE 'abc%'`). **Cannot serve an unanchored
pattern** (`LIKE '%abc%'`) — there's no prefix to seek to.

**GIN + trigram** (`gin_trgm_ops`) — indexes the three-character substrings
(`alc`, `lca`, `car`), turning substring search into set containment. This is
what makes fuzzy name lookup and `ILIKE '%…%'` fast. Needs the `pg_trgm`
extension.

**The planner is allowed to ignore your index, and is often right.** On a
1,739-row, 576 kB table a sequential scan is genuinely cheaper. Check with
`EXPLAIN (ANALYZE, BUFFERS)`; force with `SET enable_seqscan = off` to confirm
an index is *usable* even when unused.

**Indexes aren't free.** They're rebuilt whenever the table is, and cost write
time and storage. Worth it when reads dominate and someone is waiting on them.

**Report buffers, not milliseconds.** Same query, same plan, no index either
time:

```
cold cache   1,600 ms      warm cache   384 ms      (both: 90,482 buffers)
```

A 4x spread from `shared_buffers` state alone. After indexing, the same split is
518 ms cold and 2.2 ms warm.

Buffers are the work the query actually did and don't move with cache warmth.
Milliseconds are that work multiplied by how lucky you were. So: buffers answer
*did my index help*, wall time answers *is this fast enough for a user*. They are
different questions, and quoting the second at the first is how you end up
claiming a 4x win you didn't earn.

---

## NULL and three-valued logic

SQL has three truth values: true, false, and **unknown**. Almost every NULL bug
is forgetting the third.

```sql
NULL = NULL            -- unknown, NOT true
NULL <> NULL           -- unknown
NULL % 2 = 0           -- unknown
```

Two failure modes, opposite directions, both hit in one evening:

**`CASE … ELSE` swallows NULL.** `ELSE` catches false *and* unknown, so a NULL
input silently takes the else branch. Guard explicitly:

```sql
CASE WHEN x IS NULL THEN NULL
     WHEN x % 2 = 0 THEN 'even'
     ELSE 'odd' END
```

**`=` rejects NULL.** A `JOIN … ON a.k = b.k` never matches NULL keys, so a
matched pair gets reported as two unmatched rows in a `FULL OUTER JOIN`.

**Fixes:**

- `IS NOT DISTINCT FROM` — NULL-safe equality. But Postgres refuses it in a
  `FULL JOIN` ("only supported with merge-joinable or hash-joinable conditions").
- `EXCEPT` / `INTERSECT` — compare whole rows, treat NULLs as equal, no join
  needed. Usually the right tool for "do these two relations agree?"
- `COALESCE(x, sentinel)` — works, but you have to pick a sentinel that can't
  occur.

**Aggregate behaviour:** `count(*)` counts rows; `count(col)` skips NULLs;
`sum`/`avg` skip NULLs (so `avg` divides by the non-NULL count, not the row
count). That's occasionally what you want and occasionally a silent bug.

---

## Normal forms, as they actually bite

**1NF — atomic attributes.** Violated when one column holds structure the
database can't address: a delimited string, an encoded sequence, a repeating
group across numbered columns (`player_1`, `player_2`).

The formal definition is contested — Date's critique is that "atomic" was never
rigorously defined, and a string is atomic to the DBMS. The version that
survives scrutiny: *the attribute has internal structure the relational algebra
can't reach, so you're forced into string functions, and string functions can't
express relationships between elements.*

A **decomposition** into rows is the fix — and it's not cosmetic, because some
questions are unreachable without it, not merely harder.

**Repeating groups: slots vs roles.** `player_1` / `player_2` is a repeating
group. You can normalise it to *slots* (one row per player-match) or pivot to
*roles* (server / returner). **Roles win when every question is about the role**
— nobody asks about "player 1."

**3NF — no transitive dependency.** `serve_key → match_id → surface` means
`surface` depends on the key only *through* another attribute. Textbook
violation; deliberately committed in marts.

The justification is the Kimball one: anomalies come from updating, and marts
are rebuilt rather than updated. The honest addition is that anomalies aren't
the only cost — see the last paragraph of the Kimball entry.

---

## Entropy as a metric

From information theory. Measures **how unpredictable a distribution is**.

```
H = -Σ p·ln(p)
```

Normalise by `ln(k)` for `k` categories and it lands in `[0, 1]`:

- **1.0** — perfectly even. Maximum surprise, nothing to read.
- **0.0** — always the same outcome. Fully predictable.

Useful whenever "how readable is this behaviour?" is the actual question —
serve placement, shot selection, next-move distributions. It turns a pattern
into one comparable number.

**Practical notes:**

- `ln(0)` is undefined. Guard zero-probability categories.
- In Postgres, `ln(3)` returns *double precision*, and there's no two-argument
  `round()` for double. `ln(3::numeric)`.
- Report **how many categories were actually used** alongside it. An entropy of
  0 over one category means something different from 0 over three.

**Generalisation worth remembering:** applied to a *transition matrix* rather
than a flat distribution, the same formula measures how predictable a *sequence*
is. Low entropy on a transition = a readable pattern.

---

## Oracle testing

**When you have no labelled data, look for someone who implemented the same spec.**

If a second implementation of the same rules exists, its output is ground truth
for yours. No labelling effort, and the disagreements are where the
undocumented conventions live.

**The method:**

1. Diff on one case small enough to read by eye.
2. Find the *systematic* offset — not the random one.
3. Form one hypothesis. Change one thing.
4. Re-measure. Repeat.
5. When it converges, freeze the agreement rate as a **regression test**.

**Set the threshold below the measured baseline, not at perfection.** A test
that fails on upstream noise gets muted, and a muted test is a green checkmark
that means nothing. The threshold encodes "this used to be 90%; tell me if it
drops."

**Differential testing** is the same idea between two of *your* implementations.
Two independent implementations degrading identically is strong evidence the
problem is upstream, not in either one.

---

## Idempotency

**Running it twice produces the same state as running it once.**

The pattern for loads:

```
COPY into a temp table
  → check it
  → INSERT … SELECT … ON CONFLICT (natural key) DO UPDATE
```

The temp table costs a second write and buys the ability to **inspect before
committing** — you can't examine data you've already merged into the target.
That's what makes a circuit breaker possible: reject the whole file if too much
of it is bad, having written nothing.

**Two things that bite:**

**Dedupe within the batch, not just against the table.** `ON CONFLICT DO UPDATE`
refuses to touch the same target row twice in one statement. Duplicate keys
*inside the incoming file* must be collapsed first (`DISTINCT ON`). Upsert
handles collisions with what's stored; it does nothing about collisions with
itself.

**Upsert never deletes.** If you tighten a validation rule, rows that were
already loaded stay loaded — the new run rejects them instead of updating them.
Convergence only holds while the rules do. Tightening a rule needs a full
refresh or a tombstone strategy.

---

## Two kinds of trust

Worth separating, because they're independent and a result needs both.

**Parse trust** — did you decode the source correctly? Settled by diffing
against an oracle or a spec. Objective, and it closes: once the rule is right,
it's right.

**Inference trust** — does the conclusion survive its confounds? Settled by
controls, sample size and significance. Never fully closes — a bigger sample or
an unconsidered confound can reopen it.

The failure modes are symmetric and both look like success:

- Perfect parse, bad inference → clean numbers supporting a backwards
  conclusion. (A pooled query said momentum was real; one control flipped it.)
- Good inference, bad parse → a well-controlled analysis of the wrong quantity.

**A result inherits the lower of the two.** Which is why "how accurate is the
parser" and "does this finding hold" are different questions that both have to
be asked, and why a data-quality tier list is worth writing down rather than
carrying in your head.
