"""`deuce` -- the command surface.

    deuce init-db                 apply sql/*.sql (idempotent)
    deuce download [SOURCE]       fetch Match Charting Project CSVs
    deuce load [SOURCE]           validate + upsert into the raw schema
    deuce status                  ingest funnel, row counts, rejects
    deuce demo PLAYER             the end-to-end proof-of-life query

In Increment 1 Dagster wraps these same functions as software-defined assets;
the CLI stays as the manual/backfill entry point.
"""

from __future__ import annotations

from typing import Annotated

import typer

from deuce import logging as tlog

app = typer.Typer(add_completion=False, help=__doc__)

_SOURCE_HELP = "matches | points | stats_serve_direction"


@app.callback()
def _main(
    json_logs: Annotated[bool, typer.Option("--json-logs", help="Emit JSON log lines.")] = False,
) -> None:
    tlog.configure(json_output=json_logs)


@app.command("init-db")
def init_db() -> None:
    """Create schemas, extensions, raw tables, and the observability tables."""
    from deuce.db import apply_migrations

    for name in apply_migrations():
        typer.echo(f"applied {name}")


@app.command()
def download(
    source: Annotated[str | None, typer.Argument(help=_SOURCE_HELP)] = None,
    force: Annotated[bool, typer.Option(help="Re-download even if the file exists.")] = False,
) -> None:
    """Fetch source CSVs into data/raw/."""
    from deuce.ingest.loader import download as do_download

    for spec in _select(source):
        do_download(spec, force=force)


@app.command()
def load(
    source: Annotated[str | None, typer.Argument(help=_SOURCE_HELP)] = None,
    limit: Annotated[int | None, typer.Option(help="Load only the first N rows per file.")] = None,
    validate: Annotated[bool, typer.Option(help="Run Pydantic shape validation.")] = True,
) -> None:
    """Download if needed, then validate and upsert into raw.*."""
    from deuce.ingest.loader import load as do_load

    for spec in _select(source):
        for result in do_load(spec, validate=validate, limit=limit):
            typer.echo(
                f"{result.status:8} {result.source_file:42} "
                f"read={result.rows_read} loaded={result.rows_loaded} "
                f"rejected={result.rows_rejected} ({result.reject_rate:.2%})"
            )


@app.command()
def status() -> None:
    """Row counts per raw table plus the last few ingest runs."""
    from deuce.db import connect
    from deuce.ingest import SOURCES

    with connect() as conn:
        typer.secho("\ntable row counts", bold=True)
        for spec in SOURCES.values():
            (count,) = conn.execute(f"SELECT COUNT(*) FROM {spec.table}").fetchone()
            typer.echo(f"  {spec.table:34} {count:>10,}")

        typer.secho("\nrecent ingest runs", bold=True)
        rows = conn.execute(
            """
            SELECT source_file, status, rows_read, rows_loaded, rows_rejected, finished_at
            FROM raw.ingest_runs ORDER BY started_at DESC LIMIT 10
            """
        ).fetchall()
        for src_file, st, read, loaded, rej, _ in rows:
            typer.echo(f"  {st:8} {src_file:42} read={read:>8,} loaded={loaded:>8,} rejected={rej}")

        (errors,) = conn.execute("SELECT COUNT(*) FROM raw.error_records").fetchone()
        typer.echo(f"\ndead-letter rows: {errors:,}")


@app.command()
def demo(
    player: Annotated[str, typer.Argument(help="Player name as charted, e.g. 'Carlos Alcaraz'")],
) -> None:
    """Increment 0 proof-of-life: serve placement + direction entropy for one player."""
    from pathlib import Path

    from deuce.config import REPO_ROOT
    from deuce.db import connect

    query = (Path(REPO_ROOT) / "sql" / "queries" / "serve_direction_entropy.sql").read_text()
    with connect() as conn, conn.cursor() as cur:
        cur.execute(query, {"player": player})
        cols = [d.name for d in cur.description]
        rows = cur.fetchall()

    if not rows:
        typer.secho(f"No charted serves found for {player!r}.", fg="yellow")
        raise typer.Exit(1)

    typer.echo("  ".join(f"{c:>18}" for c in cols))
    for row in rows:
        typer.echo("  ".join(f"{v!s:>18}" for v in row))


def _select(source: str | None):
    from deuce.ingest import SOURCES

    if source is None:
        return list(SOURCES.values())
    if source not in SOURCES:
        raise typer.BadParameter(f"unknown source {source!r}; pick one of {list(SOURCES)}")
    return [SOURCES[source]]


if __name__ == "__main__":
    app()
