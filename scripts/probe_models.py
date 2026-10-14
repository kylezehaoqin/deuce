"""Measure candidate LLMs on a few SQL questions. Evidence for the model decision.

    uv run python scripts/probe_models.py [MODEL ...]

For each model and question: latency, input/output tokens, whether the SQL
runs, and the row count. Queries run READ ONLY with a statement timeout.

The instruction below is a THROWAWAY, not the agent's SYSTEM_PROMPT. It
measures the models on the same schema context the agent will get, before the
real prompt exists. Do not compare these numbers with eval runs on the real
prompt -- they are a different baseline.

Questions come from the private tennis-questions.yml (gitignored). Only their
ids are printed.
"""

from __future__ import annotations

import re
import sys
import time

import yaml

from deuce.agent.llm import get_chat_model
from deuce.agent.schema_context import build_schema_context
from deuce.config import REPO_ROOT
from deuce.db import connect

DEFAULT_MODELS = [
    "gemini-3.8-flash",
    "gemini-3.5-flash-lite",
    "gemini-pro-latest",
    "gemini-2.5-flash",
]
QUESTION_IDS = ["serve-01", "serve-03", "rally-01"]
PLAYER = "Carlos Alcaraz"
PAUSE_SECONDS = 6  # stay well under free-tier requests-per-minute limits

THROWAWAY_INSTRUCTION = (
    "Write ONE PostgreSQL query that answers the question, using only the "
    "tables and columns listed below. Return only the SQL, with no explanation."
)


def load_questions() -> list[tuple[str, str]]:
    data = yaml.safe_load((REPO_ROOT / "tennis-questions.yml").read_text())
    by_id = {q["id"]: q["question"] for q in data["questions"]}
    return [(qid, by_id[qid].replace("{player}", PLAYER)) for qid in QUESTION_IDS]


def extract_sql(text: str) -> str:
    fenced = re.search(r"```(?:sql)?\s*(.*?)```", text, re.S | re.I)
    return (fenced.group(1) if fenced else text).strip().rstrip(";")


def run_readonly(sql: str) -> tuple[bool, str]:
    try:
        with connect() as conn:
            conn.execute("set transaction read only")
            conn.execute("set local statement_timeout = '10s'")
            rows = conn.execute(sql).fetchall()
            conn.rollback()
        return True, f"{len(rows)} rows"
    except Exception as e:  # noqa: BLE001 -- any failure is a measurement
        return False, type(e).__name__ + ": " + str(e).splitlines()[0][:70]


def text_of(content) -> str:
    """Gemini may return a string or a list of content parts."""
    if isinstance(content, str):
        return content
    return "".join(p.get("text", "") if isinstance(p, dict) else str(p) for p in content)


def main(models: list[str]) -> None:
    system = THROWAWAY_INSTRUCTION + "\n\n" + build_schema_context()
    questions = load_questions()
    print(f"{'model':<24}{'question':<11}{'sec':>6}{'in_tok':>8}{'out_tok':>8}  result")
    for model in models:
        # No silent retries: a rate limit must show up as a measurement.
        llm = get_chat_model(model, timeout=60, max_retries=0)
        for qid, question in questions:
            start = time.monotonic()
            try:
                reply = llm.invoke([("system", system), ("human", question)])
            except Exception as e:  # noqa: BLE001
                msg = str(e).splitlines()[0][:60]
                print(f"{model:<24}{qid:<11}{'-':>6}{'-':>8}{'-':>8}  CALL FAILED {msg}")
                time.sleep(PAUSE_SECONDS)
                continue
            secs = time.monotonic() - start
            usage = reply.usage_metadata or {}
            ok, detail = run_readonly(extract_sql(text_of(reply.content)))
            status = "RUNS " if ok else "FAILS"
            print(
                f"{model:<24}{qid:<11}{secs:>6.1f}{usage.get('input_tokens', 0):>8}"
                f"{usage.get('output_tokens', 0):>8}  {status} {detail}"
            )
            time.sleep(PAUSE_SECONDS)


if __name__ == "__main__":
    main(sys.argv[1:] or DEFAULT_MODELS)
