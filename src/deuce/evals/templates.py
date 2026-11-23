"""Expand question templates into eval cases (D12).

One question tests one case. A template with {slots} and a list of fillers
tests the METHOD: the same question for a deep-data player, a WTA player, a
left-hander, a thin sample, a misspelled name, and a player who is not in the
data. The last two cost nothing and catch the worst failures: a wrong name
resolved silently, and numbers invented for nobody.

A filler is a mapping: `kind`, its slot values, and optionally `route` (which
overrides the question's label -- an absent player is a refusal) and
`must_state` (what a correct answer has to say). Mistakes fail loudly: a slot
with no value, and a filler key that matches no slot (a typo would otherwise
leave a case that silently tests the wrong thing).
"""

from __future__ import annotations

import string
from dataclasses import dataclass

RESERVED = {"kind", "route", "must_state", "note"}


@dataclass(frozen=True)
class Case:
    case_id: str  # "rally-01[thin]", or the question id for a plain question
    question_id: str
    text: str
    kind: str | None
    route: str | None  # expected route; None when the question has no label
    must_state: str | None


def slots(text: str) -> set[str]:
    return {name for _, name, _, _ in string.Formatter().parse(text) if name}


def expand(question: dict, route: str | None = None) -> list[Case]:
    """Cases for one question. `route` is its label from evals/route_labels.yml."""
    qid, text = question["id"], question["question"]
    needed = slots(text)
    fillers = question.get("fillers") or []
    if not fillers:
        if needed:
            raise ValueError(f"{qid}: slots {sorted(needed)} but no fillers")
        return [Case(qid, qid, text, None, route, None)]

    cases, seen = [], set()
    for f in fillers:
        values = {k: str(v) for k, v in f.items() if k not in RESERVED}
        if missing := needed - values.keys():
            raise ValueError(f"{qid}[{f.get('kind')}]: no value for {sorted(missing)}")
        if extra := values.keys() - needed:
            raise ValueError(f"{qid}[{f.get('kind')}]: {sorted(extra)} match no slot")
        kind = f.get("kind", "case")
        case_id = f"{qid}[{kind}]"
        n = 2
        while case_id in seen:  # two fillers of one kind stay distinct
            case_id, n = f"{qid}[{kind}-{n}]", n + 1
        seen.add(case_id)
        cases.append(
            Case(
                case_id=case_id,
                question_id=qid,
                text=text.format(**values),
                kind=kind,
                route=f.get("route", route),
                must_state=f.get("must_state"),
            )
        )
    return cases


def expand_all(questions: list[dict], labels: dict[str, dict] | None = None) -> list[Case]:
    labels = labels or {}
    return [case for q in questions for case in expand(q, (labels.get(q["id"]) or {}).get("route"))]
