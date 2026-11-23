"""Score the routing decision alone: expected route vs the model's route.

    uv run python -u scripts/eval_routes.py [MODEL]

Expands every question into its cases first (templates x fillers, D12; see
src/deuce/evals/templates.py), then scores each case that has an expected
route. Sends <routing> plus the schema -- the sections written so far -- through the
agent's structured decision step. No SQL runs. Labels come from
evals/route_labels.yml (Kyle's decisions, D8); question text from questions.yml.

WARNING: the <routing> rules were written from decisions about these same 16
questions. The score is an UPPER BOUND, not an unbiased estimate. A held-out
question set is the real test.
"""

from __future__ import annotations

import sys
import time

import yaml

from deuce.agent.graph import structured_decider
from deuce.agent.llm import get_chat_model
from deuce.agent.prompts import ROUTING, SCHEMA_CONTEXT_PLACEHOLDER, assemble
from deuce.agent.schema_context import build_schema_context
from deuce.config import REPO_ROOT
from deuce.evals.templates import expand_all

PAUSE_SECONDS = 5
# 503 "high demand" is temporary: retry it a few times. Any other failure is
# reported as an ERROR and kept out of the accuracy, never counted as a miss --
# a provider outage is not a routing mistake.
RETRIES_ON_503 = 3
RETRY_WAIT_SECONDS = 15


def decide_with_retry(decide, messages):
    for attempt in range(RETRIES_ON_503 + 1):
        try:
            return decide(messages)
        except Exception as e:  # noqa: BLE001
            if "503" not in str(e) or attempt == RETRIES_ON_503:
                raise
            time.sleep(RETRY_WAIT_SECONDS)


def main(model: str | None) -> None:
    labels = yaml.safe_load((REPO_ROOT / "evals" / "route_labels.yml").read_text())
    questions = yaml.safe_load((REPO_ROOT / "questions.yml").read_text())["questions"]
    cases = [c for c in expand_all(questions, labels) if c.route]
    system = assemble({"routing": ROUTING}).replace(
        SCHEMA_CONTEXT_PLACEHOLDER, build_schema_context()
    )
    decide = structured_decider(get_chat_model(model, timeout=60, max_retries=0))

    right = errors = 0
    for case in cases:
        try:
            step = decide_with_retry(decide, [("system", system), ("human", case.text)])
            got = step.route.value
        except Exception as e:  # noqa: BLE001 -- a failed call is reported, not scored
            got, step = f"ERROR {str(e).splitlines()[0][:40]}", None
        if step is None:
            errors += 1
            print(f"ERR  {case.case_id:<26} {got}")
            time.sleep(PAUSE_SECONDS)
            continue
        ok = got == case.route
        right += ok
        mark = "ok  " if ok else "MISS"
        reason = (step.reason or "")[:90] if step else ""
        print(f"{mark} {case.case_id:<26} expected {case.route:<7} got {got:<7} {reason}")
        time.sleep(PAUSE_SECONDS)
    scored = len(cases) - errors
    print(
        f"\naccuracy {right}/{scored} scored, {errors} errors not scored"
        "  (upper bound: rules written from these questions)"
    )


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
