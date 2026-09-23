"""dbt models as Dagster assets.

dagster-dbt reads `manifest.json` and turns every model, seed and test into a
Dagster asset or asset check. That means the lineage in the Dagster UI IS the dbt
DAG -- not a hand-maintained copy of it that drifts.

The `@dbt_assets`-decorated function is a single op that Dagster presents as many
assets. `dbt build` is invoked once per run and its structured events are streamed
back, so each model reports its own success, timing and row count individually.

`dbt build` rather than `dbt run`: build interleaves each model with its tests, so
a failing test stops its own downstream instead of letting the whole graph
complete and reporting the failure afterwards.
"""

# NO `from __future__ import annotations` IN THIS FILE.
# It turns annotations into strings (PEP 563), and Dagster inspects the `context`
# parameter's type at runtime to decide what to pass. With the import, it sees the
# string "AssetExecutionContext" instead of the class and raises
#   "Cannot annotate `context` parameter with type AssetExecutionContext"
# -- an error that names the exact type you used, which makes it maddening.
# Files that define assets taking a context keep real annotations.

from collections.abc import Iterator

from dagster import AssetExecutionContext
from dagster_dbt import DbtCliResource, dbt_assets

from tennis_analytics.orchestration.resources import dbt_project


@dbt_assets(
    manifest=dbt_project.manifest_path,
    # Upstream sources are the ingest assets in ingest_assets.py; dagster-dbt
    # matches them by the key it derives from each dbt source (raw/<table>).
)
def tennis_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource) -> Iterator:
    yield from dbt.cli(["build"], context=context).stream()
