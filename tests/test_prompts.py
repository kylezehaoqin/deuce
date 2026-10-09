"""Guards on the prompt scaffold.

The prompt TEXT is Kyle's and is not tested here. What is tested is the
machinery around it: a half-written prompt must never render for a model, and
the schema context must show every live column and only the agent layer.
"""

from __future__ import annotations

import os

import pytest

from deuce.agent.prompts import (
    SCHEMA_CONTEXT_PLACEHOLDER,
    UNWRITTEN,
    assemble,
    render_system_prompt,
    unwritten_sections,
)
from deuce.agent.schema_context import (
    AGENT_LAYER_PREFIXES,
    MANIFEST_PATH,
    Column,
    Table,
    load_agent_models,
    merge_live_columns,
    render,
)

WRITTEN = {"role": "r", "routing": "x"}
HALF = {"role": "r", "routing": UNWRITTEN}


def test_unwritten_sections_are_listed():
    assert unwritten_sections(HALF) == ["routing"]
    assert unwritten_sections(WRITTEN) == []


def test_render_refuses_a_half_written_prompt():
    with pytest.raises(ValueError, match="routing"):
        render_system_prompt("schema", sections=HALF)


def test_render_allows_a_draft_when_asked():
    assert "<routing>" in render_system_prompt("schema", sections=HALF, allow_unwritten=True)


def test_sections_render_in_order_with_schema_last():
    text = assemble(WRITTEN)
    assert text.index("<role>") < text.index("<routing>") < text.index("<schema>")
    assert SCHEMA_CONTEXT_PLACEHOLDER in text


def test_schema_with_braces_survives_rendering():
    # str.format would raise on the braces; the renderer must not.
    assert "{a}" in render_system_prompt("x {a} y", sections=WRITTEN)


def test_merge_keeps_descriptions_and_adds_undocumented_columns():
    manifest = [Table("mart_x", "s", "d", [Column("a", None, "described")])]
    live = {"mart_x": [("a", "integer"), ("b", "text")]}
    (merged,) = merge_live_columns(manifest, live)
    assert [(c.name, c.data_type, c.description) for c in merged.columns] == [
        ("a", "integer", "described"),
        ("b", "text", ""),
    ]
    assert "- b text" in render([merged])


def test_merge_keeps_manifest_columns_for_an_unbuilt_table():
    manifest = [Table("mart_x", "s", "d", [Column("a", None, "described")])]
    assert merge_live_columns(manifest, {}) == manifest


# --- against the real manifest ---------------------------------------------
# Same rule as test_orchestration.py: skip locally, FAIL under CI.
_IN_CI = os.environ.get("CI") == "true"
if not MANIFEST_PATH.exists() and _IN_CI:
    raise RuntimeError(f"{MANIFEST_PATH} missing under CI; the manifest step must run first.")

needs_manifest = pytest.mark.skipif(
    not MANIFEST_PATH.exists(),
    reason="dbt manifest not built; run `make dbt-build` first (local only)",
)


@needs_manifest
def test_only_the_agent_layer_is_exposed():
    names = {t.name for t in load_agent_models()}
    assert names, "no agent-layer models found"
    assert all(n.startswith(AGENT_LAYER_PREFIXES) for n in names)
    assert {"mart_matchup", "mart_pressure_index", "fct_points"} <= names


@needs_manifest
def test_disabled_models_never_appear():
    assert "fct_shots" not in {t.name for t in load_agent_models()}
