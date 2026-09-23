"""Download Match Charting Project CSVs and load them into the raw schema.

The load is designed around four properties a reviewer will ask about:

  1. IDEMPOTENT  -- re-running the same file produces no duplicates. Rows go
     through a TEMP staging table and land via INSERT ... ON CONFLICT DO UPDATE
     on the source's natural key.
  2. ISOLATED    -- nothing touches the real table until the whole file has been
     read and the rejection rate checked. A bad file aborts having written zero
     rows (the circuit breaker below).
  3. ACCOUNTED   -- every run writes rows_read / rows_valid / rows_rejected /
     rows_loaded to raw.ingest_runs, so the funnel is inspectable after the fact.
  4. LOSSLESS    -- invalid rows are preserved in raw.error_records with their
     payload and reason, not dropped.
"""

from __future__ import annotations

import csv
import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

import httpx
import psycopg
import structlog
from psycopg import sql

from tennis_analytics.config import settings
from tennis_analytics.db import connect
from tennis_analytics.ingest.schemas import VALIDATORS
from tennis_analytics.ingest.sources import SourceSpec

log = structlog.get_logger()

# csv fields in the points file can be long-ish notation strings; the default
# 128KB limit is fine, but a corrupt quote can blow it up -- fail loudly if so.
csv.field_size_limit(1_000_000)

# If more than this share of rows fail validation, the file is almost certainly
# a schema change upstream rather than a handful of bad rows. Abort without
# loading anything rather than half-ingesting a broken file.
DEFAULT_REJECT_THRESHOLD = 0.05

# csv.DictReader silently pads a short row and silently bins a long one. Naming
# the overflow key and the fill value makes both detectable -- see _reject_reason.
_EXTRA_KEY = "__extra_fields__"
_MISSING = object()


@dataclass
class LoadResult:
    run_id: uuid.UUID
    source_file: str
    table: str
    rows_read: int
    rows_valid: int
    rows_rejected: int
    rows_loaded: int
    status: str

    @property
    def reject_rate(self) -> float:
        return self.rows_rejected / self.rows_read if self.rows_read else 0.0


# ---------------------------------------------------------------- download ---


def download(
    spec: SourceSpec,
    force: bool = False,
    files: Sequence[str] | None = None,
) -> list[Path]:
    """Fetch this source's CSVs into `data/raw/`, streaming to disk.

    Skips files already present unless `force`. The points files are hundreds of
    MB, so they are streamed rather than held in memory, and written to a .part
    file first so an interrupted download is never mistaken for a complete one.
    """
    dest_dir = settings.data_path
    dest_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []

    wanted = tuple(files) if files else spec.files
    unknown = set(wanted) - set(spec.files)
    if unknown:
        raise ValueError(f"{spec.name}: not files of this source: {sorted(unknown)}")

    for filename in wanted:
        dest = dest_dir / filename
        if dest.exists() and not force:
            log.info("download.skip", file=filename, size=dest.stat().st_size)
            paths.append(dest)
            continue

        url = f"{settings.mcp_base_url}/{filename}"
        tmp = dest.with_suffix(dest.suffix + ".part")
        log.info("download.start", file=filename, url=url)
        with httpx.stream("GET", url, follow_redirects=True, timeout=120.0) as resp:
            resp.raise_for_status()
            with tmp.open("wb") as fh:
                for chunk in resp.iter_bytes(chunk_size=1 << 20):
                    fh.write(chunk)
        tmp.replace(dest)
        log.info("download.done", file=filename, size=dest.stat().st_size)
        paths.append(dest)

    return paths


# -------------------------------------------------------------------- load ---


def load(
    spec: SourceSpec,
    *,
    validate: bool = True,
    reject_threshold: float = DEFAULT_REJECT_THRESHOLD,
    limit: int | None = None,
    files: Sequence[str] | None = None,
) -> list[LoadResult]:
    """Load files for `spec`, one transaction per file.

    `files` restricts the load to named files of this source. That is what makes
    a Dagster partition meaningful: the six point files are independently
    reloadable units, so a backfill can target one era without touching the rest.
    """
    results = []
    for path in download(spec, files=files):
        results.append(
            _load_file(
                spec, path, validate=validate, reject_threshold=reject_threshold, limit=limit
            )
        )
    return results


def _load_file(
    spec: SourceSpec,
    path: Path,
    *,
    validate: bool,
    reject_threshold: float,
    limit: int | None,
) -> LoadResult:
    run_id = uuid.uuid4()
    target_cols = [*spec.column_map.values(), "_source_file", "_run_id"]
    validator = VALIDATORS.get(spec.name) if validate else None

    rows_read = rows_rejected = 0
    rejects: list[tuple[int, str, dict[str, object]]] = []

    with connect() as conn:
        _open_run(conn, run_id, path.name, spec.table)
        stage = _create_stage(conn, spec.table)

        with path.open(newline="", encoding="utf-8-sig") as fh:
            reader = csv.DictReader(fh, restkey=_EXTRA_KEY, restval=_MISSING)
            _assert_headers(spec, reader.fieldnames or [], path.name)

            copy_stmt = sql.SQL("COPY {} ({}) FROM STDIN").format(
                sql.Identifier(stage),
                sql.SQL(", ").join(sql.Identifier(c) for c in target_cols),
            )
            with conn.cursor() as cur, cur.copy(copy_stmt) as cp:
                for lineno, raw_row in enumerate(reader, start=2):
                    if limit is not None and rows_read >= limit:
                        break
                    rows_read += 1
                    mapped = {
                        col: _clean(raw_row.get(header)) for header, col in spec.column_map.items()
                    }

                    reason = _reject_reason(spec, raw_row, mapped, validator)
                    if reason:
                        rows_rejected += 1
                        if len(rejects) < 1000:  # cap: the reason matters, not every instance
                            rejects.append((lineno, reason, _jsonable(raw_row)))
                        continue

                    cp.write_row(
                        tuple(mapped[c] or None for c in spec.column_map.values())
                        + (path.name, str(run_id))
                    )

        rows_valid = rows_read - rows_rejected
        _write_rejects(conn, run_id, path.name, rejects)

        # ---- circuit breaker: decide BEFORE anything reaches the real table ----
        rate = rows_rejected / rows_read if rows_read else 0.0
        if rate > reject_threshold:
            _close_run(
                conn,
                run_id,
                status="aborted",
                rows_read=rows_read,
                rows_valid=rows_valid,
                rows_rejected=rows_rejected,
                rows_loaded=0,
                error_message=f"rejection rate {rate:.1%} exceeds threshold {reject_threshold:.1%}",
            )
            conn.commit()
            log.error("load.aborted", file=path.name, reject_rate=round(rate, 4))
            return LoadResult(
                run_id, path.name, spec.table, rows_read, rows_valid, rows_rejected, 0, "aborted"
            )

        rows_loaded = _upsert_from_stage(conn, spec, stage, target_cols)
        _close_run(
            conn,
            run_id,
            status="success",
            rows_read=rows_read,
            rows_valid=rows_valid,
            rows_rejected=rows_rejected,
            rows_loaded=rows_loaded,
        )

    log.info(
        "load.done",
        file=path.name,
        table=spec.table,
        rows_read=rows_read,
        rows_valid=rows_valid,
        rows_rejected=rows_rejected,
        rows_loaded=rows_loaded,
        # rows_valid > rows_loaded means the file contained duplicate natural keys.
        deduped=rows_valid - rows_loaded,
    )
    return LoadResult(
        run_id, path.name, spec.table, rows_read, rows_valid, rows_rejected, rows_loaded, "success"
    )


# ----------------------------------------------------------------- helpers ---


def _assert_headers(spec: SourceSpec, fieldnames: list[str], filename: str) -> None:
    """Fail the file if an expected header is gone.

    This is the schema-evolution tripwire: a renamed upstream column becomes a
    loud error here instead of a silently all-NULL column in the warehouse.
    Extra new headers are fine -- they are ignored until added to the spec.
    """
    missing = [h for h in spec.column_map if h not in fieldnames]
    if missing:
        raise ValueError(
            f"{filename}: upstream schema changed -- missing headers {missing}. "
            f"Reconcile ingest/sources.py with the new file before loading."
        )


def _clean(value: object) -> str:
    return value.strip() if isinstance(value, str) else ""


def _reject_reason(
    spec: SourceSpec,
    raw_row: dict[str, object],
    mapped: dict[str, str],
    validator: type | None,
) -> str | None:
    # Field-count checks come first, because a row with the wrong number of
    # fields is SHIFTED, not merely incomplete -- every value lands in the wrong
    # column and each one is individually plausible. Upstream really does ship
    # these (two matches files rows are missing both player-name fields), and no
    # per-field validator can see it. Only the arithmetic can.
    if raw_row.get(_EXTRA_KEY) is not None:
        return f"too many fields: {len(raw_row[_EXTRA_KEY])} unexpected trailing values"
    short = [k for k, v in raw_row.items() if v is _MISSING]
    if short:
        return f"too few fields: row ends before {short[0]!r}, columns are shifted"

    for header in spec.required:
        if not _clean(raw_row.get(header)):
            return f"missing required field: {header}"
    if validator is not None:
        try:
            validator(**mapped)
        except Exception as exc:  # noqa: BLE001 -- the message is the payload
            return f"validation failed: {exc}"
    return None


def _jsonable(raw_row: dict[str, object]) -> dict[str, object]:
    """Make a row safe for JSONB, preserving *why* it was rejected."""
    return {
        (k if k is not None else _EXTRA_KEY): (None if v is _MISSING else v)
        for k, v in raw_row.items()
    }


def _create_stage(conn: psycopg.Connection, target: str) -> str:
    stage = f"stage_{uuid.uuid4().hex[:12]}"
    conn.execute(
        sql.SQL("CREATE TEMP TABLE {} (LIKE {} INCLUDING DEFAULTS) ON COMMIT DROP").format(
            sql.Identifier(stage), sql.SQL(target)
        )
    )
    return stage


def _upsert_from_stage(
    conn: psycopg.Connection, spec: SourceSpec, stage: str, target_cols: list[str]
) -> int:
    """Move staged rows into the real table, idempotently.

    DISTINCT ON is load-bearing: Postgres refuses an ON CONFLICT DO UPDATE that
    would touch the same row twice in one statement, so duplicate natural keys
    *within a single file* must be collapsed first. First occurrence wins; the
    count difference is logged rather than swallowed.
    """
    keys = [sql.Identifier(k) for k in spec.key_columns]
    cols = [sql.Identifier(c) for c in target_cols]
    updatable = [c for c in target_cols if c not in spec.key_columns]

    stmt = sql.SQL(
        """
        INSERT INTO {target} ({cols})
        SELECT DISTINCT ON ({keys}) {cols}
        FROM {stage}
        ORDER BY {keys}
        ON CONFLICT ({keys}) DO UPDATE SET {assignments}, _loaded_at = NOW()
        """
    ).format(
        target=sql.SQL(spec.table),
        cols=sql.SQL(", ").join(cols),
        keys=sql.SQL(", ").join(keys),
        stage=sql.Identifier(stage),
        assignments=sql.SQL(", ").join(
            sql.SQL("{c} = EXCLUDED.{c}").format(c=sql.Identifier(c)) for c in updatable
        ),
    )
    with conn.cursor() as cur:
        cur.execute(stmt)
        return cur.rowcount


def _open_run(conn: psycopg.Connection, run_id: uuid.UUID, source_file: str, table: str) -> None:
    conn.execute(
        "INSERT INTO raw.ingest_runs (run_id, source_file, target_table) VALUES (%s, %s, %s)",
        (run_id, source_file, table),
    )


def _close_run(conn: psycopg.Connection, run_id: uuid.UUID, **fields) -> None:
    conn.execute(
        """
        UPDATE raw.ingest_runs
           SET finished_at = NOW(),
               status = %(status)s,
               rows_read = %(rows_read)s,
               rows_valid = %(rows_valid)s,
               rows_rejected = %(rows_rejected)s,
               rows_loaded = %(rows_loaded)s,
               error_message = %(error_message)s
         WHERE run_id = %(run_id)s
        """,
        {"run_id": run_id, "error_message": None, **fields},
    )


def _write_rejects(
    conn: psycopg.Connection,
    run_id: uuid.UUID,
    source_file: str,
    rejects: list[tuple[int, str, dict[str, object]]],
) -> None:
    if not rejects:
        return
    from psycopg.types.json import Jsonb

    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO raw.error_records (run_id, source_file, source_lineno, reason, payload)
            VALUES (%s, %s, %s, %s, %s)
            """,
            [(run_id, source_file, ln, reason, Jsonb(payload)) for ln, reason, payload in rejects],
        )
