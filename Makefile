# Increment 0 workflow:  make setup && make up && make db-init && make ingest && make demo PLAYER="Carlos Alcaraz"

SHELL := /bin/bash
DBT   := uv run dbt --profiles-dir dbt --project-dir dbt
PLAYER ?= Carlos Alcaraz

.DEFAULT_GOAL := help

help:  ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- setup ----

setup:  ## Create the venv and install deps (pins Python 3.12 -- dbt/dagster do not support 3.13+)
	uv sync --all-extras
	@test -f .env || (cp .env.example .env && echo "created .env from .env.example")

up:  ## Start Postgres + pgvector
	docker compose up -d
	@until docker compose exec -T postgres pg_isready -U $${POSTGRES_USER:-tennis} >/dev/null 2>&1; do sleep 1; done
	@echo "postgres ready on port $${POSTGRES_PORT:-5433}"

down:  ## Stop Postgres (keeps the data volume)
	docker compose down

nuke:  ## Stop Postgres and DELETE the data volume
	docker compose down -v

psql:  ## Open a psql shell
	docker compose exec postgres psql -U $${POSTGRES_USER:-tennis} -d $${POSTGRES_DB:-tennis}

# -------------------------------------------------------------- ingest ----

db-init:  ## Apply sql/*.sql (idempotent)
	uv run tennis init-db

ingest:  ## Load matches + serve-direction stats (fast -- enough for `make demo`)
	uv run tennis load matches
	uv run tennis load stats_serve_direction

ingest-points:  ## Load the point-by-point files (178 MB, ~1.9M points, ~60s)
	uv run tennis load points

ingest-oracles:  ## Load Sackmann's own aggregations (ground truth for our parser)
	uv run tennis load stats_rally
	uv run tennis load stats_shot_types
	uv run tennis load stats_shot_direction

ingest-all: ingest ingest-points ingest-oracles  ## Everything

status:  ## Row counts, ingest runs, dead-letter count
	uv run tennis status

demo:  ## Increment 0 proof-of-life -- make demo PLAYER="Iga Swiatek"
	uv run tennis demo "$(PLAYER)"

# ----------------------------------------------------------------- dbt ----

dbt-deps:  ## Install dbt packages
	$(DBT) deps

dbt-build:  ## Run + test every model
	$(DBT) build

dbt-test:  ## Tests only
	$(DBT) test

dbt-docs:  ## Generate and serve the data catalog
	$(DBT) docs generate && $(DBT) docs serve

# ------------------------------------------------------ orchestration ------

DAGSTER_HOME ?= $(PWD)/.dagster

dagster:  ## Start the Dagster UI at :3000 (asset graph, run history, backfills)
	@mkdir -p $(DAGSTER_HOME)
	DAGSTER_HOME=$(DAGSTER_HOME) uv run dagster dev

dagster-validate:  ## Load the definitions without running anything (CI gate)
	uv run dagster definitions validate

refresh:  ## Materialize the daily job: small sources + full dbt rebuild
	@mkdir -p $(DAGSTER_HOME)
	DAGSTER_HOME=$(DAGSTER_HOME) uv run dagster job execute -j daily_refresh -m tennis_analytics.orchestration

backfill:  ## Reload ONE points file -- make backfill PARTITION=charting-m-points-2020s.csv
	@test -n "$(PARTITION)" || (echo "set PARTITION=<filename>; see: make partitions"; exit 1)
	@mkdir -p $(DAGSTER_HOME)
	DAGSTER_HOME=$(DAGSTER_HOME) uv run dagster asset materialize \
		--select 'raw/mcp_points' --partition '$(PARTITION)' -m tennis_analytics.orchestration

partitions:  ## List the valid PARTITION values for `make backfill`
	@uv run python -c "from tennis_analytics.ingest import SOURCES; [print(' ', f) for f in SOURCES['points'].files]"

# ------------------------------------------------------- investigations ----

investigate:  ## Run an investigation harness -- make investigate FILE=005_shot_direction_scope.sql
	@docker compose exec -T postgres psql -U $${POSTGRES_USER:-tennis} -d $${POSTGRES_DB:-tennis} \
		-v ON_ERROR_STOP=1 -f - < sql/investigations/$(FILE)

# ---------------------------------------------------------------- dev -----

lint:  ## Ruff check + format check
	uv run ruff check .
	uv run ruff format --check .

fmt:  ## Ruff autofix + format
	uv run ruff check --fix .
	uv run ruff format .

test:  ## Python tests
	uv run pytest -q

.PHONY: help setup up down nuke psql db-init ingest ingest-points ingest-oracles ingest-all status demo investigate dagster dagster-validate refresh backfill partitions \
        dbt-deps dbt-build dbt-test dbt-docs lint fmt test
