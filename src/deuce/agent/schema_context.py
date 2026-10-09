"""The schema the agent sees, rendered into SYSTEM_PROMPT's {schema_context}.

Built from TWO sources, because neither is enough on its own:

- The dbt manifest gives DESCRIPTIONS. That is where every caveat lives (era,
  thin cells, what a baseline controls for). Column descriptions are prompt
  context (lesson 003).
- Postgres gives every column NAME and TYPE that actually exists. The manifest
  only knows the columns the yml documents -- mart_matchup documents 19 of its
  columns and has far more. A context built from descriptions alone hides the
  rest, and a model that cannot see a column invents one.

Only the agent layer is exposed: fct_, dim_ and mart_ models. Staging and
intermediate models are implementation detail, and an agent that queries them
skips every rule the marts encode.

Generated, never hand-written, so the agent's view cannot drift from the
warehouse.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

from deuce.config import REPO_ROOT

MANIFEST_PATH = REPO_ROOT / "dbt" / "target" / "manifest.json"
AGENT_LAYER_PREFIXES = ("fct_", "dim_", "mart_")


@dataclass(frozen=True)
class Column:
    name: str
    data_type: str | None
    description: str


@dataclass(frozen=True)
class Table:
    name: str
    schema: str
    description: str
    columns: list[Column] = field(default_factory=list)

    @property
    def documented_share(self) -> float:
        if not self.columns:
            return 0.0
        return sum(1 for c in self.columns if c.description) / len(self.columns)


def _squash(text: str) -> str:
    """yml folded blocks keep line breaks; one line per description reads better."""
    return " ".join(text.split())


def load_agent_models(manifest_path: Path = MANIFEST_PATH) -> list[Table]:
    """Agent-layer models from the dbt manifest, with documented columns only.

    Disabled models (fct_shots) are not in `nodes`, so they never appear.
    """
    manifest = json.loads(manifest_path.read_text())
    tables = []
    for node in manifest["nodes"].values():
        if node["resource_type"] != "model" or not node["name"].startswith(AGENT_LAYER_PREFIXES):
            continue
        columns = [
            Column(c["name"], c.get("data_type"), _squash(c["description"]))
            for c in node["columns"].values()
        ]
        tables.append(
            Table(
                name=node["name"],
                schema=node["schema"],
                description=_squash(node["description"]),
                columns=columns,
            )
        )
    return sorted(tables, key=lambda t: t.name)


def merge_live_columns(tables: list[Table], live: dict[str, list[tuple[str, str]]]) -> list[Table]:
    """Replace each table's column list with the LIVE one, keeping descriptions.

    `live` maps table name -> [(column, type), ...] in table order. A table
    missing from `live` keeps its manifest columns (not built yet).
    """
    merged = []
    for t in tables:
        if t.name not in live:
            merged.append(t)
            continue
        described = {c.name: c.description for c in t.columns}
        columns = [Column(n, typ, described.get(n, "")) for n, typ in live[t.name]]
        merged.append(Table(t.name, t.schema, t.description, columns))
    return merged


def fetch_live_columns(tables: list[Table]) -> dict[str, list[tuple[str, str]]]:
    """Every column of every agent-layer table, from information_schema."""
    from deuce.db import connect

    names = [t.name for t in tables]
    schemas = sorted({t.schema for t in tables})
    sql = """
        select table_name, column_name, data_type
        from information_schema.columns
        where table_schema = any(%s) and table_name = any(%s)
        order by table_name, ordinal_position
    """
    live: dict[str, list[tuple[str, str]]] = {}
    with connect() as conn:
        for table, column, data_type in conn.execute(sql, (schemas, names)):
            live.setdefault(table, []).append((column, data_type))
    return live


def render(tables: list[Table]) -> str:
    """Plain text, one block per table. Undocumented columns still appear."""
    blocks = []
    for t in tables:
        lines = [f"## {t.schema}.{t.name}"]
        if t.description:
            lines.append(t.description)
        for c in t.columns:
            typ = f" {c.data_type}" if c.data_type else ""
            desc = f" -- {c.description}" if c.description else ""
            lines.append(f"- {c.name}{typ}{desc}")
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks)


def build_schema_context(live: bool = True) -> str:
    """The rendered context. `live=False` skips Postgres (descriptions only)."""
    tables = load_agent_models()
    if live:
        tables = merge_live_columns(tables, fetch_live_columns(tables))
    return render(tables)
