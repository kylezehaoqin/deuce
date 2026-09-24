"""Pydantic shape-validation for raw rows.

Scope note: these models validate SHAPE, not TYPES. The raw table is all TEXT on
purpose (see sql/002_raw_tables.sql), so the question here is only "is this row
structurally usable?" -- not "is Date a real date?". Type coercion and business
rules belong in dbt staging, where they are testable and visible in the lineage.

A row that fails here goes to raw.error_records with the reason; it does not
fail the file.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, field_validator


class _RawRow(BaseModel):
    model_config = ConfigDict(extra="allow", str_strip_whitespace=True)


class RawMatch(_RawRow):
    match_id: str = Field(min_length=1)
    player_1: str = Field(min_length=1)
    player_2: str = Field(min_length=1)


class RawPoint(_RawRow):
    match_id: str = Field(min_length=1)
    pt: str = Field(min_length=1)
    svr: str = ""
    pt_winner: str = ""

    @field_validator("pt")
    @classmethod
    def _pt_is_numeric(cls, v: str) -> str:
        if not v.isdigit():
            raise ValueError(f"point number is not numeric: {v!r}")
        return v

    @field_validator("svr", "pt_winner")
    @classmethod
    def _player_ref(cls, v: str) -> str:
        # Blank is tolerated (retired matches, unscored points); a third player is not.
        if v and v not in {"1", "2"}:
            raise ValueError(f"expected player reference 1 or 2, got {v!r}")
        return v


class RawServeDirection(_RawRow):
    match_id: str = Field(min_length=1)
    player: str = Field(min_length=1)
    row_label: str = Field(min_length=1)


VALIDATORS: dict[str, type[_RawRow]] = {
    "matches": RawMatch,
    "points": RawPoint,
    "stats_serve_direction": RawServeDirection,
}
