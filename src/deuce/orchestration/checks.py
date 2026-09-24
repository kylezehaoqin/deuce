"""Asset checks -- assertions about data that are not part of producing it.

WHY A CHECK RATHER THAN A TEST INSIDE THE ASSET
-----------------------------------------------
The loader already has a circuit breaker: over a 5% rejection rate it aborts and
writes nothing. That is a *guard on this run*, and it fires on obviously-broken
input.

A volume anomaly is a different failure. Every row can be individually valid and
the file can still be wrong -- upstream truncated it, or a filter changed, and you
get 60% of yesterday's rows with a 0% rejection rate. Nothing in the per-row path
can see that, because it is a property of the run *compared to previous runs*.

Doc 08 lists this as the strong bar for data quality: "alert if count deviates
>2s from the 30-day rolling average". We use a simpler relative threshold, because
with a handful of historical runs a standard deviation is not yet meaningful --
and a check whose statistics you cannot defend is a check people learn to ignore.

Checks are separate from the asset on purpose: the asset can succeed and the check
can fail. That distinction matters here -- the data DID land, and someone should
look at it, but nothing downstream is corrupt.
"""

from __future__ import annotations

from dagster import AssetCheckResult, AssetCheckSeverity, asset_check

from deuce.db import connect
from deuce.ingest import SOURCES, SourceSpec
from deuce.orchestration.ingest_assets import _asset_key

# Below this many prior runs there is no baseline worth comparing against, and the
# check reports PASS with an explanation rather than inventing a threshold.
MIN_HISTORY = 3

# A load landing outside +/- 20% of its own recent average is worth a human look.
# Loose on purpose: upstream genuinely adds matches daily, so a tight band would
# fire constantly and get muted (lesson 004's argument, applied to a check).
DRIFT_TOLERANCE = 0.20


def _build_check(spec: SourceSpec):
    @asset_check(
        asset=_asset_key(spec),
        name="row_count_within_recent_range",
        description=(
            "Rows loaded are within "
            f"+/-{DRIFT_TOLERANCE:.0%} of the mean of previous successful runs. "
            "Catches a silently truncated upstream file, which per-row validation "
            "cannot see."
        ),
        blocking=False,
    )
    def _check() -> AssetCheckResult:
        with connect() as conn:
            rows = conn.execute(
                """
                SELECT rows_loaded
                FROM raw.ingest_runs
                WHERE target_table = %s AND status = 'success'
                ORDER BY started_at DESC
                LIMIT 31
                """,
                (spec.table,),
            ).fetchall()

        counts = [r[0] for r in rows]
        if len(counts) <= MIN_HISTORY:
            return AssetCheckResult(
                passed=True,
                severity=AssetCheckSeverity.WARN,
                metadata={
                    "runs_recorded": len(counts),
                    "note": (
                        f"Only {len(counts)} successful runs recorded; need more than "
                        f"{MIN_HISTORY} before a baseline means anything."
                    ),
                },
            )

        latest, baseline = counts[0], counts[1:]
        mean = sum(baseline) / len(baseline)
        deviation = (latest - mean) / mean if mean else 0.0

        return AssetCheckResult(
            passed=abs(deviation) <= DRIFT_TOLERANCE,
            severity=AssetCheckSeverity.WARN,
            metadata={
                "latest_rows": latest,
                "baseline_mean": round(mean, 1),
                "deviation": round(deviation, 4),
                "tolerance": DRIFT_TOLERANCE,
                "baseline_runs": len(baseline),
            },
        )

    return _check


ingest_checks = [_build_check(spec) for spec in SOURCES.values()]
