"""The agent graph.

    question -> decide --route=sql--> run_sql --ok--------------> END
                  ^                      |
                  +-------error----------+  (at most MAX_ATTEMPTS decisions)
                decide --route=refuse|semantic|hybrid--> END  (with `reason`)

ROUTING IS INLINE (D7, lessons/decisions.md). One structured call returns the
route AND the SQL, because the router must see the schema to know what the data
can answer: measured, a router without the schema scored 4/16 and sent the
serve-speed question to SQL; with the schema, 8/16 and refused it. A separate
call with the schema would cost ~6,900 more input tokens per question. The
route is still a field, so routing is logged and scored on its own.

Not built yet, on purpose:
  - SEMANTIC / HYBRID retrieval: pgvector arrives in Increment 3. Those routes
    end with the model's reason.
  - The ANSWER node: it writes from <grounding> and <style>, which are not
    decided yet. Until then the graph returns the query result, not prose.

The decision step and the query runner are passed in, so tests run with a
scripted model and no database.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import TypedDict

from langchain_core.language_models.chat_models import BaseChatModel
from langgraph.graph import END, START, StateGraph
from pydantic import BaseModel, Field

from deuce.agent.prompts import Route
from deuce.agent.sql_tools import QueryResult, run_sql, strip_fences

# The first decision plus two corrections. A model that misses three times on
# the same error is not converging; a fourth try spends tokens and latency.
MAX_ATTEMPTS = 3


class AgentStep(BaseModel):
    """What the model returns on every call: a route, and SQL when the route is sql."""

    route: Route = Field(description="Where the question goes.")
    sql: str | None = Field(
        default=None, description="One PostgreSQL SELECT query. Required when route is 'sql'."
    )
    reason: str | None = Field(
        default=None,
        description="Why this route. For sql, name any part of the question the data "
        "cannot answer. Required when route is not 'sql'.",
    )


Messages = list[tuple[str, str]]


class AgentState(TypedDict, total=False):
    question: str
    route: Route
    reason: str | None
    sql: str
    attempts: int
    result: QueryResult


def structured_decider(llm: BaseChatModel) -> Callable[[Messages], AgentStep]:
    """The production decision step: the model, constrained to AgentStep."""
    return llm.with_structured_output(AgentStep).invoke


def build_graph(
    decide: Callable[[Messages], AgentStep],
    system_prompt: str,
    runner: Callable[[str], QueryResult] = run_sql,
):
    """Compile the graph. `system_prompt` is the fully rendered prompt."""

    def decide_node(state: AgentState) -> AgentState:
        messages: Messages = [("system", system_prompt), ("human", state["question"])]
        previous = state.get("result")
        if previous is not None and not previous.ok:
            # Give the model its own query and the exact error: that is what
            # it needs to correct it. The text is Postgres's or the checker's.
            messages += [
                ("ai", previous.sql),
                ("human", f"That query failed:\n{previous.error}\nWrite a corrected query."),
            ]
        step = decide(messages)
        out: AgentState = {
            "route": step.route,
            "reason": step.reason,
            "attempts": state.get("attempts", 0) + 1,
        }
        if step.route == Route.SQL:
            out["sql"] = strip_fences(step.sql or "")
        return out

    def execute(state: AgentState) -> AgentState:
        return {"result": runner(state["sql"])}

    def after_decide(state: AgentState) -> str:
        return "run_sql" if state["route"] == Route.SQL else END

    def after_run(state: AgentState) -> str:
        if state["result"].ok or state["attempts"] >= MAX_ATTEMPTS:
            return END
        return "decide"

    graph = StateGraph(AgentState)
    graph.add_node("decide", decide_node)
    graph.add_node("run_sql", execute)
    graph.add_edge(START, "decide")
    graph.add_conditional_edges("decide", after_decide, ["run_sql", END])
    graph.add_conditional_edges("run_sql", after_run, ["decide", END])
    return graph.compile()
