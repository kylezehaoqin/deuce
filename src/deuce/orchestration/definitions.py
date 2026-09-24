"""The Dagster entry point: assets, resources, schedules and checks.

Run it with `make dagster` (wraps `dagster dev`).

WHAT THIS BUYS OVER THE CLI
---------------------------
`make ingest && make dbt-build` already works, and for one person on one laptop
it is fine. The asset graph adds four things a shell script cannot:

  * STALENESS. Dagster knows `stg_points` depends on `raw/mcp_points`, so it can
    say what is out of date rather than re-running everything.
  * PARTIAL RE-RUNS. Reload one era's point file and rebuild only what reads it.
  * PER-ASSET HISTORY. Row counts and reject rates plotted over time, per asset,
    so a 40% drop is a visible step change instead of a number nobody compared.
  * A SCHEDULE WITH A FAILURE SURFACE. A cron entry that fails silently is worse
    than no schedule.
"""

from __future__ import annotations

from dagster import (
    AssetSelection,
    DefaultScheduleStatus,
    Definitions,
    ScheduleDefinition,
    define_asset_job,
)

from deuce.orchestration.checks import ingest_checks
from deuce.orchestration.dbt_assets import tennis_dbt_assets
from deuce.orchestration.ingest_assets import ingest_assets
from deuce.orchestration.resources import dbt_resource

# The unpartitioned sources plus every dbt model. The points source is excluded
# because a partitioned asset cannot be materialised by an unpartitioned job --
# it is backfilled explicitly, which matches reality: point files change rarely
# and reloading 1.9M rows nightly would be waste, not diligence.
daily_refresh = define_asset_job(
    name="daily_refresh",
    selection=(AssetSelection.assets(*ingest_assets) - AssetSelection.assets(["raw", "mcp_points"]))
    | AssetSelection.assets(tennis_dbt_assets),
    description=(
        "Re-land the small sources and rebuild the warehouse. Excludes the "
        "partitioned points source, which is backfilled on demand."
    ),
)

# 08:00 UTC is the freshness SLA: upstream commits land overnight, and a morning
# run means the warehouse is current before anyone asks it a question. Stopped by
# default so cloning the repo does not start scheduling work on someone's laptop.
daily_schedule = ScheduleDefinition(
    name="daily_refresh_schedule",
    job=daily_refresh,
    cron_schedule="0 8 * * *",
    default_status=DefaultScheduleStatus.STOPPED,
    execution_timezone="UTC",
)

defs = Definitions(
    assets=[*ingest_assets, tennis_dbt_assets],
    asset_checks=ingest_checks,
    jobs=[daily_refresh],
    schedules=[daily_schedule],
    resources={"dbt": dbt_resource},
)
