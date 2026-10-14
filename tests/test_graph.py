"""The SQL branch of the agent graph, with a scripted model and no database."""

from __future__ import annotations

import pytest

pytest.importorskip("langgraph")

from langchain_core.language_models.fake_chat_models import FakeListChatModel  # noqa: E402

from deuce.agent.graph import MAX_ATTEMPTS, build_graph  # noqa: E402
from deuce.agent.sql_tools import QueryResult, check_sql, strip_fences  # noqa: E402


def fake_runner(failing: set[str]):
    """Fails the queries in `failing`, succeeds on anything else."""

    def run(sql: str) -> QueryResult:
        if sql in failing:
            return QueryResult(sql=sql, error="UndefinedColumn: column x does not exist")
        return QueryResult(sql=sql, columns=["n"], rows=[(1,)])

    return run


def test_success_on_first_write():
    llm = FakeListChatModel(responses=["select 1"])
    out = build_graph(llm, "sys", fake_runner(set())).invoke({"question": "q"})
    assert out["result"].ok and out["attempts"] == 1


def test_an_error_is_sent_back_and_corrected():
    llm = FakeListChatModel(responses=["select x", "select 1"])
    out = build_graph(llm, "sys", fake_runner({"select x"})).invoke({"question": "q"})
    assert out["result"].ok
    assert out["sql"] == "select 1"
    assert out["attempts"] == 2


def test_retries_stop_at_the_limit():
    llm = FakeListChatModel(responses=["select x"] * (MAX_ATTEMPTS + 2))
    out = build_graph(llm, "sys", fake_runner({"select x"})).invoke({"question": "q"})
    assert not out["result"].ok
    assert out["attempts"] == MAX_ATTEMPTS


def test_fences_are_stripped_before_running():
    llm = FakeListChatModel(responses=["```sql\nselect 1;\n```"])
    out = build_graph(llm, "sys", fake_runner(set())).invoke({"question": "q"})
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
