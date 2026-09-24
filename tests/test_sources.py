"""Guardrails on the source catalog.

These are cheap and they catch the failure mode that actually happens: someone
adds a column to sql/002_raw_tables.sql and forgets ingest/sources.py, or vice
versa, and a column silently loads as all-NULL.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from deuce.config import REPO_ROOT
from deuce.ingest import SOURCES

# Read every migration, not just 002 -- new tables arrive in new numbered files,
# and a check pinned to one file silently stops covering anything added later.
DDL = "\n".join(p.read_text() for p in sorted((REPO_ROOT / "sql").glob("*.sql")))


def _ddl_columns(table: str) -> set[str]:
    body = re.search(
        rf"CREATE TABLE IF NOT EXISTS {re.escape(table)}\s*\((.*?)\n\);",
        DDL,
        re.DOTALL,
    )
    assert body, f"no CREATE TABLE found for {table}"
    cols = set()
    for line in body.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("--") or line.upper().startswith("PRIMARY KEY"):
            continue
        cols.add(line.split()[0])
    return cols


@pytest.mark.parametrize("spec", SOURCES.values(), ids=lambda s: s.name)
def test_every_mapped_column_exists_in_ddl(spec) -> None:
    missing = set(spec.column_map.values()) - _ddl_columns(spec.table)
    assert not missing, f"{spec.name}: mapped columns absent from DDL: {sorted(missing)}"


@pytest.mark.parametrize("spec", SOURCES.values(), ids=lambda s: s.name)
def test_key_columns_are_mapped(spec) -> None:
    mapped = set(spec.column_map.values())
    missing = set(spec.key_columns) - mapped
    assert not missing, f"{spec.name}: key columns not produced by column_map: {sorted(missing)}"


@pytest.mark.parametrize("spec", SOURCES.values(), ids=lambda s: s.name)
def test_required_headers_are_source_side(spec) -> None:
    """`required` names UPSTREAM headers, not our column names -- easy to mix up."""
    unknown = set(spec.required) - set(spec.column_map)
    assert not unknown, f"{spec.name}: required headers not in column_map: {sorted(unknown)}"


def test_ddl_files_are_ordered() -> None:
    """Docker runs sql/*.sql alphabetically; schemas must exist before tables."""
    names = sorted(p.name for p in (REPO_ROOT / "sql").glob("*.sql"))
    assert names[0].startswith("001"), f"expected 001_* first, got {names}"
    assert Path(REPO_ROOT / "sql" / "001_schemas.sql").exists()
