"""The agent graph, with a scripted decision step and no database."""

from __future__ import annotations

import pytest

pytest.importorskip("langgraph")

from deuce.agent.graph import MAX_ATTEMPTS, AgentStep, build_graph  # noqa: E402
from deuce.agent.prompts import Route  # noqa: E402
from deuce.agent.sql_tools import QueryResult, check_sql, strip_fences  # noqa: E402


def scripted(*steps: AgentStep):
    """A decision step that replays `steps` and records what it was sent."""
    queue = list(steps)
    seen: list = []

    def decide(messages):
        seen.append(messages)
        return queue.pop(0)

    decide.seen = seen
    return decide


def sql_step(sql: str) -> AgentStep:
    return AgentStep(route=Route.SQL, sql=sql)


def fake_runner(failing: set[str]):
    def run(sql: str) -> QueryResult:
        if sql in failing:
            return QueryResult(sql=sql, error="UndefinedColumn: column x does not exist")
        return QueryResult(sql=sql, columns=["n"], rows=[(1,)])

    return run


def test_success_on_first_decision():
    out = build_graph(scripted(sql_step("select 1")), "sys", fake_runner(set())).invoke(
        {"question": "q"}
    )
    assert out["route"] == Route.SQL and out["result"].ok and out["attempts"] == 1


def test_an_error_is_sent_back_and_corrected():
    decide = scripted(sql_step("select x"), sql_step("select 1"))
    out = build_graph(decide, "sys", fake_runner({"select x"})).invoke({"question": "q"})
    assert out["result"].ok and out["sql"] == "select 1" and out["attempts"] == 2
    # The retry carries the failed query and the exact error.
    retry = decide.seen[1]
    assert ("ai", "select x") in retry
    assert "UndefinedColumn" in retry[-1][1]


def test_retries_stop_at_the_limit():
    decide = scripted(*[sql_step("select x")] * (MAX_ATTEMPTS + 2))
    out = build_graph(decide, "sys", fake_runner({"select x"})).invoke({"question": "q"})
    assert not out["result"].ok and out["attempts"] == MAX_ATTEMPTS


@pytest.mark.parametrize("route", [Route.REFUSE, Route.SEMANTIC, Route.HYBRID])
def test_non_sql_routes_end_without_running_sql(route):
    ran = []
    step = AgentStep(route=route, reason="serve speed is not charted")
    out = build_graph(scripted(step), "sys", lambda s: ran.append(s)).invoke({"question": "q"})
    assert out["route"] == route and out["reason"] == "serve speed is not charted"
    assert ran == [] and "result" not in out


def test_fences_are_stripped_before_running():
    out = build_graph(
        scripted(sql_step("```sql\nselect 1;\n```")), "sys", fake_runner(set())
    ).invoke({"question": "q"})
    assert out["sql"] == "select 1"


@pytest.mark.parametrize(
    "sql, ok",
    [
        ("select 1", True),
        ("with x as (select 1) select * from x", True),
        ("select 1 union select 2", True),
        ("commit; drop table t", False),
        ("drop table t", False),
        ("delete from t", False),
        ("selec 1 frm", False),
    ],
)
def test_check_sql_allows_one_read_only_statement(sql, ok):
    assert (check_sql(sql) is None) is ok


def test_strip_fences_without_a_language_tag():
    assert strip_fences("```\nselect 1\n```") == "select 1"
