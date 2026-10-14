"""The agent graph -- the SQL branch.

    question -> write_sql -> run_sql --ok--------------> END
                   ^           |
                   +--error----+  (at most MAX_ATTEMPTS writes in total)

Built: the SQL branch, which every routing design needs.
Not built yet, on purpose:
  - the ROUTER: one call or a separate classifier is an open decision
    (prompts.py, "STILL OPEN");
  - the ANSWER node: it writes from <grounding> and <style>, which are not
    written yet. Until then the graph returns the query result, not prose.

The model and the query runner are passed in, so tests run with a fake model
and no database.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import TypedDict

from langchain_core.language_models.chat_models import BaseChatModel
from langgraph.graph import END, START, StateGraph

from deuce.agent.sql_tools import QueryResult, run_sql, strip_fences

# The first write plus two corrections. A model that misses three times on the
# same error is not converging; a fourth try spends tokens and latency for little.
MAX_ATTEMPTS = 3


class AgentState(TypedDict, total=False):
    question: str
    sql: str
    attempts: int
    result: QueryResult


def _text(content) -> str:
    """Providers return a string or a list of content parts."""
    if isinstance(content, str):
        return content
    return "".join(p.get("text", "") if isinstance(p, dict) else str(p) for p in content)


def build_graph(
    llm: BaseChatModel,
    system_prompt: str,
    runner: Callable[[str], QueryResult] = run_sql,
):
    """Compile the SQL branch. `system_prompt` is the fully rendered prompt."""

    def write_sql(state: AgentState) -> AgentState:
        messages = [("system", system_prompt), ("human", state["question"])]
        previous = state.get("result")
        if previous is not None and not previous.ok:
            # Give the model its own query and the exact error: that is what it
            # needs to correct it. The error text is Postgres's or the checker's.
            messages += [
                ("ai", previous.sql),
                ("human", f"That query failed:\n{previous.error}\nWrite a corrected query."),
            ]
        reply = llm.invoke(messages)
        return {"sql": strip_fences(_text(reply.content)), "attempts": state.get("attempts", 0) + 1}

    def execute(state: AgentState) -> AgentState:
        return {"result": runner(state["sql"])}

    def after_run(state: AgentState) -> str:
        if state["result"].ok or state["attempts"] >= MAX_ATTEMPTS:
            return END
        return "write_sql"

    graph = StateGraph(AgentState)
    graph.add_node("write_sql", write_sql)
    graph.add_node("run_sql", execute)
    graph.add_edge(START, "write_sql")
    graph.add_edge("write_sql", "run_sql")
    graph.add_conditional_edges("run_sql", after_run, ["write_sql", END])
    return graph.compile()
