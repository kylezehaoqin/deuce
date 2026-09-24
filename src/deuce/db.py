"""Postgres access. Thin on purpose -- psycopg3 directly, no ORM.

The warehouse is the product here; hiding SQL behind an ORM would work against
the point of the project.
"""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import psycopg

from deuce.config import REPO_ROOT, settings


@contextmanager
def connect(autocommit: bool = False) -> Iterator[psycopg.Connection]:
    """Yield a connection, committing on clean exit and rolling back on error."""
    with psycopg.connect(settings.dsn, autocommit=autocommit) as conn:
        yield conn


def apply_migrations(sql_dir: Path | None = None) -> list[str]:
    """Run every .sql file in `sql/` in filename order.

    The files are written with CREATE ... IF NOT EXISTS so this is idempotent:
    Docker runs them on first boot, and `make db-init` re-runs them against an
    already-running database without complaint.
    """
    sql_dir = sql_dir or REPO_ROOT / "sql"
    applied: list[str] = []
    with connect(autocommit=True) as conn:
        for path in sorted(sql_dir.glob("*.sql")):
            conn.execute(path.read_text())
            applied.append(path.name)
    return applied
