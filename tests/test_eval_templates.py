"""Template expansion, and the real question file."""

from __future__ import annotations

import pytest
import yaml

from deuce.config import REPO_ROOT
from deuce.evals.templates import expand, expand_all

Q = {"id": "q", "question": "How does {player} serve?"}


def test_plain_question_is_one_case():
    (case,) = expand({"id": "p", "question": "Who serves best?"}, "sql")
    assert case.case_id == "p" and case.route == "sql" and case.kind is None


def test_each_filler_is_a_case_with_its_slot_filled():
    cases = expand(
        {**Q, "fillers": [{"kind": "deep", "player": "A"}, {"kind": "wta", "player": "B"}]}, "sql"
    )
    assert [c.case_id for c in cases] == ["q[deep]", "q[wta]"]
    assert cases[1].text == "How does B serve?" and cases[1].route == "sql"


def test_a_filler_route_overrides_the_label():
    (case,) = expand(
        {**Q, "fillers": [{"kind": "absent", "player": "X", "route": "refuse"}]}, "sql"
    )
    assert case.route == "refuse"


def test_same_kind_twice_stays_distinct():
    f = [{"kind": "deep", "player": "A"}, {"kind": "deep", "player": "B"}]
    assert [c.case_id for c in expand({**Q, "fillers": f})] == ["q[deep]", "q[deep-2]"]


@pytest.mark.parametrize(
    "question, match",
    [
        (Q, "no fillers"),
        ({**Q, "fillers": [{"kind": "deep"}]}, "no value"),
        ({**Q, "fillers": [{"kind": "deep", "player": "A", "plyer": "typo"}]}, "match no slot"),
    ],
)
def test_mistakes_fail_loudly(question, match):
    with pytest.raises(ValueError, match=match):
        expand(question)


def test_the_real_question_file_expands():
    questions = yaml.safe_load((REPO_ROOT / "questions.yml").read_text())["questions"]
    labels = yaml.safe_load((REPO_ROOT / "evals" / "route_labels.yml").read_text())
    cases = expand_all(questions, labels)
    assert len({c.case_id for c in cases}) == len(cases)
    assert all(
        c.route == "refuse" for c in cases if c.kind == "absent" and c.question_id != "trap-02"
    )
