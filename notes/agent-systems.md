# Agent systems

Reference for a first agent build. Ordered by when Deuce needs each part.
Look things up; don't copy them into writing.

- [How an LLM behaves](#how-an-llm-behaves)
- [Workflows vs agents](#workflows-vs-agents)
- [Tool design](#tool-design)
- [Text-to-SQL](#text-to-sql)
- [Evals](#evals)
- [Observability](#observability)
- [Security](#security)
- [Retrieval](#retrieval)
- [MCP](#mcp)
- [What to skip for now](#what-to-skip-for-now)
- [Study order](#study-order)

---

## How an LLM behaves

- **Tokens and the context window.** Everything the model knows during a call is
  in the prompt. Schema context, instructions and the question share one budget.
- **Non-determinism.** The same question can give two different SQL queries. An
  eval needs repeated runs or a fixed temperature, not one lucky run.
- **Structured output and tool use.** The model returns JSON that matches a
  schema, or it calls a function. A router that returns one `Route` value is
  structured output.
- **Cost and latency per call.** A cheap model can route and a strong model can
  write SQL -- but only if each is a separate call.

---

## Workflows vs agents

A **workflow** follows fixed steps. An **agent** chooses its next step in a loop.
Anthropic's "Building Effective Agents": use the simplest pattern that works.
Most good systems are mostly workflow.

Deuce is a workflow with one decision point: route -> write SQL -> run -> cite ->
answer.

| Pattern | In Deuce |
|---|---|
| Routing | `Route.SQL / SEMANTIC / HYBRID / REFUSE` |
| Prompt chaining | write SQL -> check SQL -> write the answer |
| Evaluator-optimizer | SQL fails -> send the error back -> retry, at most N times |
| Tool use | `run_sql`, later `similar_players` |

---

## Tool design

- **A tool description is a prompt.** The model reads it to decide when and how
  to call the tool. Write it like an instruction, not like a docstring.
- **Errors are information.** Pass `column "x" does not exist` back to the model.
  It can correct itself.
- **Least privilege.** A read-only database role, a statement timeout, a row
  limit. A model can write `DROP TABLE` too.

---

## Text-to-SQL

The failure modes, most of them already met in this repo:

- **Schema linking.** The model picks the wrong table or invents a column.
  Column descriptions are the defence.
- **Re-aggregation.** Averaging rates across rows. `mart_rally_shape` precomputes
  its slope for exactly this reason.
- **Silent wrong answers.** The SQL runs, returns numbers, and is wrong. Far worse
  than an error, and only evals catch it.
- **Validation.** Parse the SQL before it runs (`sqlglot`), and `EXPLAIN` it for
  cost.

BIRD and Spider are the standard benchmarks. Their error breakdowns show which
question types models get wrong.

---

## Evals

The skill that separates good agent builders from the rest.

| Concept | Meaning |
|---|---|
| Golden set | Questions with known correct answers (`questions.yml`) |
| Separate scores | Router accuracy, SQL correctness, grounding, answer quality -- each on its own |
| Execution match | Compare result rows, not SQL text. Two different queries can both be right. |
| LLM-as-judge | Useful for "is this grounded?", but check the judge against your own labels |
| Error analysis | Read 20 failed traces by hand before changing the prompt |
| Regression | A baseline score each prompt change must beat |

Hamel Husain's eval essays ("Your AI Product Needs Evals") are the practical
reference. Lesson 004's rule transfers directly: set the threshold just under
the measured baseline, not at perfection.

---

## Observability

Log every step of every run: prompt, route, SQL, rows, answer, tokens, latency.
That is Langfuse's job. Without traces there is no error analysis, only guessing.

---

## Security

- **Prompt injection through data.** Text in the database can carry
  instructions. The `notes` column is free text written by charters. It is
  untrusted input, never instructions.
- **SQL safety.** Read-only role, timeout, no write permission anywhere.

---

## Retrieval

- **Embeddings and vector search.** How pgvector finds the nearest rows.
- **Numeric features vs text embeddings.** Style vectors are z-scored rates, not
  text embeddings. No LLM makes them. That is a strength worth saying out loud.
- **Hybrid retrieval.** A SQL filter first (tour, surface, n >= 20), then the
  vector search.

---

## MCP

A standard way to expose tools to any agent. Learn it at Increment 4. It is
mostly tool design again.

---

## What to skip for now

- Fine-tuning. Prompts, descriptions and evals come first.
- Multi-agent frameworks. A four-route router does not need them.
- Most of LangGraph. State, nodes, conditional edges and a retry limit are
  enough.

---

## Study order

1. **Before `SYSTEM_PROMPT`:** LLM behaviour, workflows vs agents, text-to-SQL.
   Read "Building Effective Agents" and Anthropic's prompt-engineering and
   tool-use docs.
2. **While scaffolding the graph:** tool design, security, LangGraph's core
   concepts.
3. **Before Increment 3:** evals, observability, retrieval. Start eval notes
   early -- they shape how the prompt gets written.

**The transfer worth noticing:** oracle tests become evals, "write the prediction
first" becomes eval hypotheses, trust tiers become grounding rules. The common
beginner mistake is tuning a prompt by feel. The fix is the one already in use:
change one thing, measure it, log it.
