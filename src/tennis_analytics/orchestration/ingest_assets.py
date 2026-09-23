"""Ingest as software-defined assets.

WHY ONE ASSET PER SOURCE, NOT ONE "INGEST" ASSET
------------------------------------------------
Three things fall out of the finer grain, and none of them are available from a
single monolithic step:

  * FAILURE ISOLATION. A 403 on the ShotTypes file does not stop the matches load
    or anything downstream of it.
  * CORRECT LINEAGE. dbt declares these tables as sources, so dagster-dbt derives
    the asset key `raw/<table>` for each. Matching those keys here means the dbt
    models wire themselves to the right upstream automatically -- no hand-drawn
    dependencies, and the graph cannot silently disagree with the SQL.
  * MEANINGFUL STALENESS. Dagster can say "stg_points is stale because
    raw/mcp_points was reloaded", which is only true if the two are separate.

WHY THE POINTS SOURCE IS PARTITIONED
------------------------------------
Upstream publishes six point files split by tour and era, and rewrites them in
place. There is no date to partition on -- but the *file* is a real unit of
independent reload: re-ingesting the 2020s men's file should not touch the
2010s women's file.

So the partition key is the filename. That makes backfill honest rather than
decorative:

    dagster asset materialize --select raw/mcp_points \\
        --partition charting-m-points-2020s.csv

Partitioning by a fake date, which is the more common portfolio choice, would
give the same UI affordance while silently reprocessing everything.
"""

# NO `from __future__ import annotations` IN THIS FILE.
# It turns annotations into strings (PEP 563), and Dagster inspects the `context`
# parameter's type at runtime to decide what to pass. With the import, it sees the
# string "AssetExecutionContext" instead of the class and raises
#   "Cannot annotate `context` parameter with type AssetExecutionContext"
# -- an error that names the exact type you used, which makes it maddening.
# Files that define assets taking a context keep real annotations.

from dagster import (
    AssetExecutionContext,
    AssetKey,
    Backoff,
    MaterializeResult,
    MetadataValue,
    RetryPolicy,
    StaticPartitionsDefinition,
    asset,
)

from tennis_analytics.ingest import SOURCES, SourceSpec
from tennis_analytics.ingest.loader import LoadResult, load

# Transient failures here are network failures -- GitHub rate limits, a dropped
# connection mid-stream. Exponential backoff, because retrying a rate limit
# immediately is worse than waiting.
NETWORK_RETRY = RetryPolicy(max_retries=3, delay=10, backoff=Backoff.EXPONENTIAL)

POINT_FILES = StaticPartitionsDefinition(list(SOURCES["points"].files))


def _asset_key(spec: SourceSpec) -> AssetKey:
    """The key dagster-dbt derives for a dbt source, so the graphs join up.

    dbt source `raw.mcp_matches` -> AssetKey(["raw", "mcp_matches"]). If this
    mapping ever drifts, the dbt models appear as roots with no upstream and the
    lineage silently lies -- which is what `test_asset_keys_match_dbt_sources`
    exists to prevent.
    """
    schema, table = spec.table.split(".")
    return AssetKey([schema, table])


def _metadata(results: list[LoadResult]) -> dict[str, MetadataValue]:
    """Emit the ingest funnel as asset metadata.

    The same numbers already go to raw.ingest_runs. Emitting them here too puts
    them on the asset's timeline in the UI, so "rows dropped by 40% last Tuesday"
    is visible as a plot rather than a query someone has to think to write.
    """
    read = sum(r.rows_read for r in results)
    rejected = sum(r.rows_rejected for r in results)
    loaded = sum(r.rows_loaded for r in results)
    valid = sum(r.rows_valid for r in results)

    return {
        "dagster/row_count": MetadataValue.int(loaded),
        "rows_read": MetadataValue.int(read),
        "rows_valid": MetadataValue.int(valid),
        "rows_rejected": MetadataValue.int(rejected),
        "reject_rate": MetadataValue.float(rejected / read if read else 0.0),
        # rows_valid > rows_loaded means the file held duplicate natural keys,
        # which DISTINCT ON collapsed. Correct handling, still worth surfacing.
        "deduped": MetadataValue.int(valid - loaded),
        "files": MetadataValue.json([r.source_file for r in results]),
        "status": MetadataValue.text(
            "aborted" if any(r.status == "aborted" for r in results) else "success"
        ),
    }


def _build_asset(spec: SourceSpec, *, partitioned: bool = False):
    is_oracle = spec.name in {"stats_rally", "stats_shot_types", "stats_shot_direction"}

    @asset(
        # `key` alone -- Dagster rejects key together with name/key_prefix.
        key=_asset_key(spec),
        group_name="ingest",
        description=(
            f"Land `{spec.files[0].rsplit('-', 1)[0]}-*.csv` into `{spec.table}`. "
            + (
                "ORACLE -- Sackmann's own aggregation, read only by dbt tests."
                if is_oracle
                else "All TEXT; casting happens in dbt staging."
            )
        ),
        compute_kind="python",
        partitions_def=POINT_FILES if partitioned else None,
        retry_policy=NETWORK_RETRY,
        metadata={
            "natural_key": ", ".join(spec.key_columns),
            "upstream_files": len(spec.files),
            "license": "CC BY-NC-SA 4.0 (Match Charting Project)",
        },
        op_tags={"oracle": "true"} if is_oracle else {},
    )
    def _ingest(context: AssetExecutionContext) -> MaterializeResult:
        files = [context.partition_key] if partitioned else None
        results = load(SOURCES[spec.name], files=files)

        if any(r.status == "aborted" for r in results):
            # The loader's circuit breaker already wrote nothing. Failing loudly
            # here is what stops Dagster marking the asset fresh and letting dbt
            # build on data that never arrived.
            aborted = [r.source_file for r in results if r.status == "aborted"]
            raise RuntimeError(
                f"ingest aborted (reject rate over threshold): {aborted}. "
                "Inspect raw.error_records; upstream schema may have changed."
            )

        return MaterializeResult(metadata=_metadata(results))

    return _ingest


# `points` is the only partitioned source: it is the only one shipped as several
# independently-reloadable files large enough for that to matter.
ingest_assets = [
    _build_asset(spec, partitioned=(name == "points")) for name, spec in SOURCES.items()
]
