"""Guards on the Python <-> dbt seam.

The asset graph joins up only because the key this repo derives for an ingest
asset happens to equal the key dagster-dbt derives for the corresponding dbt
source. Nothing enforces that at runtime: if it drifts, dbt models appear as
graph ROOTS with no upstream, every staleness signal silently becomes wrong, and
`dbt build` still passes. A green build with a lying lineage is the failure mode
worth a test.
"""

from __future__ import annotations

import json

import pytest

from deuce.config import REPO_ROOT
from deuce.ingest import SOURCES

MANIFEST = REPO_ROOT / "dbt" / "target" / "manifest.json"

pytestmark = pytest.mark.skipif(
    not MANIFEST.exists(), reason="dbt manifest not built; run `make dbt-build` first"
)


@pytest.fixture(scope="module")
def dbt_source_tables() -> set[tuple[str, str]]:
    manifest = json.loads(MANIFEST.read_text())
    return {(node["schema"], node["identifier"]) for node in manifest["sources"].values()}


def test_every_ingest_source_is_declared_to_dbt(dbt_source_tables) -> None:
    """A landed table dbt doesn't know about is invisible to the lineage."""
    ingested = {tuple(spec.table.split(".")) for spec in SOURCES.values()}
    missing = ingested - dbt_source_tables
    assert not missing, (
        f"ingested but not declared in dbt _sources.yml: {sorted(missing)} -- "
        "dbt models cannot depend on these, so Dagster will show them as orphans"
    )


def test_asset_keys_match_dbt_sources(dbt_source_tables) -> None:
    """The actual seam: our asset key must equal dagster-dbt's source key.

    dagster-dbt's default translator maps a dbt source to
    AssetKey([schema, identifier]). Our `_asset_key` must agree exactly.
    """
    from deuce.orchestration.ingest_assets import _asset_key

    for spec in SOURCES.values():
        key = tuple(_asset_key(spec).path)
        assert key in dbt_source_tables, (
            f"{spec.name}: asset key {key} matches no dbt source. "
            f"Known sources: {sorted(dbt_source_tables)}"
        )


def test_definitions_load_and_have_no_orphan_models() -> None:
    """Loading the Definitions is itself the strongest check available.

    It catches the `from __future__ import annotations` trap (which stringifies
    the `context` annotation and breaks Dagster's runtime type inspection), plus
    any key collision or missing resource.
    """
    from deuce.orchestration import defs

    graph = defs.get_repository_def().asset_graph
    keys = list(graph.get_all_asset_keys())
    assert len(keys) >= len(SOURCES), "fewer assets than ingest sources"

    orphans = [
        k.to_user_string() for k in keys if k.path[0] != "raw" and not graph.get(k).parent_keys
    ]
    assert not orphans, f"dbt models with no upstream -- the seam is broken: {orphans}"


def test_points_source_is_partitioned_by_its_files() -> None:
    """Partition keys are filenames, so they must stay in step with the spec."""
    from deuce.orchestration.ingest_assets import POINT_FILES

    assert set(POINT_FILES.get_partition_keys()) == set(SOURCES["points"].files)
