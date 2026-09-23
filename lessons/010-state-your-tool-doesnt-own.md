# 010 — State your tool doesn't know it owns

> dbt's model is *"I declare relations and rebuild them."* Anything it created as
> a side effect, or stopped declaring, falls outside that — and disappears or
> lingers in silence while the build stays green.

**Concept:** declarative tools and invisible state; measuring an index rather
than guessing it
**Lives in:** `dbt/models/marts/fct_serves.sql`, `dbt/tests/assert_indexes_exist.sql`
**Status:** settled

## Three findings, one shape

A review of the physical layout turned up what looked like three unrelated
problems. They're the same problem.

**1. A 474 MB orphan.** `fct_serve_points` was renamed to `fct_points`. dbt
created the new relation and never dropped the old one — it has no record the
two are related. 1,875,054 stale rows sat in the warehouse, queryable by name,
diverging from the live table on every rebuild, with `dbt build` green
throughout.

**2. Every index gone.** Zero indexes across every analytics table. Including
`dim_players`, which had a GIN trigram index that had been verified working two
sessions earlier. Nothing noticed.

The cause turned out to be a silent no-op, found by adding the test below and
watching a full build fail it — see *"Why the indexes actually vanished"*.

**3. Nothing could notice.** No test asserted any of it. An index defined in a
`post_hook` is invisible to the model's own contract — the model compiles,
builds and tests identically whether the index is there or not.

The common structure: **dbt is declarative about relations and imperative about
everything else.** It guarantees "this model exists and matches its SELECT". It
guarantees nothing about indexes it created as a side effect, or about relations
it used to declare and now doesn't.

> If your tool's mental model is declarative, every imperative side effect you
> add needs its own assertion, or it becomes invisible.

## The index, measured rather than guessed

A routine agent query — one player, first serves, break points — against the
2.58M-row, 706 MB `fct_serves`:

```
no index                                     384 ms   90,482 buffers
btree (server_name)                          290 ms    3,163 buffers
partial (server_name) where is_break_point   1.9 ms    1,035 buffers
```

**The intuition that lost:** index the most selective column. `server_name` is
0.9% selective, `is_break_point` is 9.2%, so the player column looks like the
obvious choice. It gave 1.3×.

**Why the partial index gives 200×:** selectivity of the *lookup* is not the
thing that costs. Heap fetches are. A plain index on `server_name` finds all
23,821 of that player's serves and pulls them into the heap before filtering.
The partial index only **contains** break-point rows, so it touches 1,663.

*Pre-filtering the index beats narrowing the lookup.*

The corollary is the useful part: a boolean column at ~10% selectivity is
famously not worth indexing on its own, because the planner will prefer a seq
scan over hundreds of thousands of random heap fetches. But as a **predicate on
a partial index** the same column is exactly what you want — it isn't a pointer
list any more, it's a pre-computed subset.

## Where indexes deliberately aren't

`mart_serve_patterns`: 29,294 rows in 6.7 MB. A sequential scan reads the whole
thing in about a millisecond and the planner would ignore an index anyway.

`dim_players`: 1,739 rows, 576 kB. The GIN trigram index **exists and the
planner ignores it** — verified with `enable_seqscan=off`, which does use it.
Kept because it costs nothing and stops being pointless if the table grows, but
it is not doing work today.

Both are documented in the models. An absent index that was *considered* is a
different artifact from one nobody thought about, and only the comment
distinguishes them.

## Why the indexes actually vanished

The first guess was that something external had rebuilt the tables. Wrong, and
the real cause is better.

`post_hook` had `create index if not exists ix_fct_serves_server_bp on {{ this }}`.
During a table rebuild dbt does roughly:

```
1. create  fct_serves__dbt_tmp   as (select ...)
2. rename  fct_serves            -> fct_serves__dbt_backup
3. rename  fct_serves__dbt_tmp   -> fct_serves
4. run post-hooks                                   <-- index created here
5. drop    fct_serves__dbt_backup
```

At step 4 the backup relation still exists **and still carries the old index
under the same name**. `IF NOT EXISTS` matches on the index name *within the
schema*, not on `(table, name)` — so it finds the backup's index, decides there
is nothing to do, and succeeds silently. Step 5 then drops the backup, taking
the only copy of the index with it.

`dbt build` reports success. No error, no warning, no index.

This is why a *targeted* rebuild appeared to work while a full build did not: in
the targeted case the index had just been dropped by hand, so the name was free.

**Fix:** drop-then-create instead of `IF NOT EXISTS`.

```python
post_hook=[
    "drop index if exists analytics_analytics.ix_fct_serves_server_bp",
    "create index ix_fct_serves_server_bp on {{ this }} (server_name) where is_break_point",
]
```

Verified by running two consecutive full builds and confirming both indexes
survive. The first build was never the problem; the second one was.

Note the shape: `IF NOT EXISTS` is a **silent no-op guard**, exactly the class in
errors E4 (a string replace that matched nothing) and E9 (a gitignore pattern
that matched too much). Every one of them fails by doing nothing and reporting
success.

## Testing it

Two mechanisms make indexes, so the test checks two ways:

| Made by | Name | Assert on |
|---|---|---|
| dbt `indexes` config | hashed — `e8278b7397ae…` | the **leading column** |
| `post_hook` | ours — `ix_fct_serves_server_bp` | the **name** |

dbt's generated names are content hashes, so asserting on them is useless. The
leading column comes from `pg_index.indkey[0]` joined to `pg_attribute`.
Partial indexes can only come from a `post_hook` — dbt's config has no `WHERE`
clause — and there we control the name.

Relations resolve through `ref()` cast to `regclass`, so the test carries no
hardcoded schema.

**Verified with teeth:** dropped `ix_fct_serves_server_bp` by hand, the test
failed with 1 result, `dbt build --select fct_serves` restored it, the test
passed. A test that has never failed is indistinguishable from one that cannot.

## The trade-off

Indexes are not free. Each one is rebuilt on every `dbt build` — these tables
are `materialized='table'`, so every run drops and recreates them, indexes
included. That's write time and storage bought against read time.

The reason it's clearly worth it here: this warehouse is **read-mostly and
rebuilt rarely**, and every read is an agent query someone is waiting on. The
ratio is not close.

Which connects to lesson 001's other half. The marts denormalise deliberately —
`surface` is carried on every fact row rather than joined — and the textbook
cost of denormalising is update anomalies, which don't apply because a mart is
never `UPDATE`d. But that's only half the bill. **The other half is storage and
cache pressure**, and it arrived as a 706 MB table that sequentially scans. It
isn't free; it's paid in I/O, and indexes are how you buy it back.

## Saying it out loud

> A review found three problems that turned out to be one. A renamed model left
> a 474 MB orphan table behind, every index on the warehouse was missing, and
> nothing tested for either — so the build was green the whole time. They share a
> cause: dbt is declarative about relations and imperative about everything else,
> so anything it makes as a side effect, or stops declaring, becomes invisible.
> I fixed the orphan, moved indexes into model config so they survive rebuilds,
> and added a test that asserts they exist — verified by dropping one and
> watching it fail. The index choice was measured, not guessed: I assumed the
> most selective column was the answer and it gave me 1.3x, while a partial
> index on the *less* selective boolean gave 200x, because what costs is heap
> fetches, not lookup selectivity.

## Try it yourself

`fct_games` has indexes on `server_name` and `match_id`. Write the query the
let-down-game question needs (T8 — consecutive games, did the breaker get broken
back), `EXPLAIN ANALYZE` it, and decide whether it wants an index that doesn't
exist yet. Then check whether the planner agrees with you.
