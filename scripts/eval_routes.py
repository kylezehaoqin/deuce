"""Score the routing decision alone: expected route vs the model's route.

    uv run python -u scripts/eval_routes.py [MODEL]

Sends <routing> plus the schema -- the sections written so far -- through the
agent's structured decision step. No SQL runs. Labels come from
evals/route_labels.yml (Kyle's decisions, D8); question text from the private
tennis-questions.yml.

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

PLAYER = "Carlos Alcaraz"
PAUSE_SECONDS = 5


def main(model: str | None) -> None:
    labels = yaml.safe_load((REPO_ROOT / "evals" / "route_labels.yml").read_text())
    questions = {
        q["id"]: q["question"].replace("{player}", PLAYER)
        for q in yaml.safe_load((REPO_ROOT / "tennis-questions.yml").read_text())["questions"]
    }
    system = assemble({"routing": ROUTING}).replace(
        SCHEMA_CONTEXT_PLACEHOLDER, build_schema_context()
    )
    decide = structured_decider(get_chat_model(model, timeout=60, max_retries=0))

    right = 0
    for qid, label in labels.items():
        try:
            step = decide([("system", system), ("human", questions[qid])])
            got = step.route.value
        except Exception as e:  # noqa: BLE001 -- a failed call is a result
            got, step = f"ERROR {str(e).splitlines()[0][:50]}", None
        ok = got == label["route"]
        right += ok
        mark = "ok  " if ok else "MISS"
        reason = (step.reason or "")[:90] if step else ""
        print(f"{mark} {qid:<13} expected {label['route']:<7} got {got:<7} {reason}")
        time.sleep(PAUSE_SECONDS)
    print(f"\naccuracy {right}/{len(labels)}  (upper bound: rules written from these questions)")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
