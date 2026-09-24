"""Shared resources.

A resource is Dagster's dependency-injection seam: assets declare what they need
rather than constructing it, so the same asset code runs against a local
Postgres, CI, or a cloud warehouse by swapping the resource definition.
"""

from __future__ import annotations

from dagster_dbt import DbtCliResource, DbtProject

from deuce.config import REPO_ROOT

# DbtProject locates the project and its manifest. `prepare_if_dev()` regenerates
# the manifest on `dagster dev` so editing a model shows up in the UI without a
# separate `dbt parse` -- but it deliberately does NOT run in production, where
# the manifest is a build artifact that should be committed or built in CI.
dbt_project = DbtProject(
    project_dir=REPO_ROOT / "dbt",
    profiles_dir=REPO_ROOT / "dbt",
)
dbt_project.prepare_if_dev()

dbt_resource = DbtCliResource(project_dir=dbt_project)
