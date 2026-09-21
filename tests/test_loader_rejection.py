"""The rejection rules, tested as pure functions.

The shifted-row case is the one worth guarding: upstream really does ship match
rows that are missing both player-name fields, and every value in such a row is
individually plausible. Only the field count gives it away.
"""

from __future__ import annotations

from tennis_analytics.ingest import loader
from tennis_analytics.ingest.sources import MATCHES

GOOD = {
    "match_id": "20241124-M-Davis_Cup_Finals-RR-A-B",
    "Player 1": "Botic Van De Zandschulp",
    "Player 2": "Matteo Berrettini",
    "Pl 1 hand": "R",
    "Pl 2 hand": "R",
    "Date": "20241124",
    "Tournament": "Davis Cup Finals",
    "Round": "RR",
    "Time": "16:15",
    "Court": "15",
    "Surface": "Hard",
    "Umpire": "Carlos Bernardes",
    "Best of": "3",
    "Final TB?": "1",
    "Charted by": "Zindaras",
}


def _reason(row):
    mapped = {col: loader._clean(row.get(h)) for h, col in MATCHES.column_map.items()}
    return loader._reject_reason(MATCHES, row, mapped, validator=None)


def test_well_formed_row_is_accepted() -> None:
    assert _reason(GOOD) is None


def test_shifted_row_is_rejected() -> None:
    """Drop the two player-name fields: every remaining value shifts left by two.

    'Best of' would read 'Zindaras' and load as a plausible-looking string.
    """
    shifted = dict(GOOD)
    values = [v for k, v in GOOD.items() if k not in ("Player 1", "Player 2")]
    for key, value in zip(GOOD, values, strict=False):
        shifted[key] = value
    for key in list(GOOD)[len(values) :]:
        shifted[key] = loader._MISSING

    reason = _reason(shifted)
    assert reason is not None
    assert "shifted" in reason


def test_extra_trailing_fields_are_rejected() -> None:
    row = {**GOOD, loader._EXTRA_KEY: ["stray", "values"]}
    reason = _reason(row)
    assert reason is not None and "too many fields" in reason


def test_missing_required_value_is_rejected() -> None:
    reason = _reason({**GOOD, "match_id": "   "})
    assert reason == "missing required field: match_id"
