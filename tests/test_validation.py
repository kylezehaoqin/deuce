from __future__ import annotations

import pytest
from pydantic import ValidationError

from deuce.ingest.schemas import RawPoint


def test_accepts_a_normal_point() -> None:
    RawPoint(match_id="20260521-M-Roland_Garros-Q3-A-B", pt="92", svr="2", pt_winner="2")


def test_blank_player_refs_are_tolerated() -> None:
    """Retired matches leave these empty; that is data, not corruption."""
    RawPoint(match_id="m", pt="1", svr="", pt_winner="")


def test_rejects_a_third_player() -> None:
    with pytest.raises(ValidationError):
        RawPoint(match_id="m", pt="1", svr="3")


def test_rejects_non_numeric_point_number() -> None:
    with pytest.raises(ValidationError):
        RawPoint(match_id="m", pt="n/a")
