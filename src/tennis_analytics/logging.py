"""Structured JSON logging.

JSON rather than printf because every log line doubles as a pipeline metric:
`load.done` carries rows_read / rows_valid / rows_loaded, so the ingest funnel
is greppable now and shippable to Dagster asset metadata later without a rewrite.
"""

from __future__ import annotations

import logging
import sys

import structlog


def configure(json_output: bool = False) -> None:
    renderer = (
        structlog.processors.JSONRenderer()
        if json_output
        else structlog.dev.ConsoleRenderer(colors=sys.stderr.isatty())
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
        cache_logger_on_first_use=True,
    )
