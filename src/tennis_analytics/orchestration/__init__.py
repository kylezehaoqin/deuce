"""Dagster orchestration. The asset graph, its schedule, and its checks.

`definitions` is the entry point Dagster loads (see `pyproject.toml`
[tool.dagster] and `make dagster`).
"""

from tennis_analytics.orchestration.definitions import defs

__all__ = ["defs"]
