"""Check and run the SQL a model wrote.

Two layers, and the database is the one that matters:

1. `check_sql` -- a parser check: exactly one statement, and it reads. This is
   for the MODEL's benefit: a clear message it can correct itself with.
2. `run_sql` -- runs as `deuce_agent` (sql/005_agent_role.sql): SELECT on the
   marts only, read-only sessions, a 10 s statement timeout. Shown to hold:
   `commit; drop table ...` fails with "read-only transaction", and with
   read-only switched off it still fails with "must be owner".

A failure is returned as text, never raised: the graph sends it back to the
model so it can correct the query.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import psycopg
import sqlglot
from sqlglot import exp

from deuce.config import settings

# Rows returned to the model. Enough to answer and to cite; a model asked to
# read 10,000 rows will summarise them badly. `truncated` says when it bit.
ROW_LIMIT = 200


@dataclass
class QueryResult:
    sql: str
    columns: list[str] = field(default_factory=list)
    rows: list[tuple] = field(default_factory=list)
    truncated: bool = False
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None


def check_sql(sql: str) -> str | None:
    """None if the SQL is one read-only statement; otherwise the reason."""
    try:
        statements = [s for s in sqlglot.parse(sql, read="postgres") if s is not None]
    except sqlglot.errors.ParseError as e:
        return f"The SQL does not parse: {str(e).splitlines()[0]}"
    if len(statements) != 1:
        return f"Write exactly one statement; found {len(statements)}."
    stmt = statements[0]
    # A SELECT may sit under a WITH or a set operation (UNION ...).
    if not isinstance(stmt, exp.Query):
        return f"Only a SELECT query is allowed; found {stmt.key.upper()}."
    return None


def strip_fences(text: str) -> str:
    """Models often wrap SQL in ```sql fences. Remove them and a trailing ';'."""
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else ""
        text = text.rsplit("```", 1)[0]
    return text.strip().rstrip(";").strip()


def run_sql(sql: str, row_limit: int = ROW_LIMIT) -> QueryResult:
    """Run one checked query as the agent role. Errors come back as text."""
    problem = check_sql(sql)
    if problem:
        return QueryResult(sql=sql, error=problem)
    try:
        with psycopg.connect(settings.agent_dsn) as conn, conn.cursor() as cur:
            cur.execute(sql)
            columns = [d.name for d in cur.description or []]
            rows = cur.fetchmany(row_limit + 1)
        return QueryResult(
            sql=sql,
            columns=columns,
            rows=rows[:row_limit],
            truncated=len(rows) > row_limit,
        )
    except psycopg.Error as e:
        return QueryResult(sql=sql, error=f"{type(e).__name__}: {str(e).strip()}")
