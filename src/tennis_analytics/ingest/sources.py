"""Catalog of Match Charting Project files we ingest.

One `SourceSpec` per CSV. Adding a source = adding an entry here plus a table in
`sql/002_raw_tables.sql`; the loader is generic over the spec.

Data: Jeff Sackmann's Match Charting Project, CC BY-NC-SA 4.0. See ATTRIBUTION.md.
"""

from __future__ import annotations

from dataclasses import dataclass, field

BASE_FILES = "https://github.com/JeffSackmann/tennis_MatchChartingProject"


@dataclass(frozen=True)
class SourceSpec:
    """How one upstream CSV maps onto one raw table.

    `column_map` is deliberately explicit rather than a `slugify(header)` call.
    Upstream headers include `Gm#`, `Final TB?` and `1st` -- names that do not
    survive naive slugification, and a silent mismatch would drop a column
    without failing. An explicit map turns that into a loud KeyError instead.
    """

    name: str
    files: tuple[str, ...]
    table: str
    key_columns: tuple[str, ...]
    column_map: dict[str, str]
    # Columns that must be non-empty for the row to be loadable at all.
    required: tuple[str, ...] = field(default_factory=tuple)


MATCHES = SourceSpec(
    name="matches",
    files=("charting-m-matches.csv", "charting-w-matches.csv"),
    table="raw.mcp_matches",
    key_columns=("match_id",),
    required=("match_id",),
    column_map={
        "match_id": "match_id",
        "Player 1": "player_1",
        "Player 2": "player_2",
        "Pl 1 hand": "pl_1_hand",
        "Pl 2 hand": "pl_2_hand",
        "Date": "date",
        "Tournament": "tournament",
        "Round": "round",
        "Time": "time",
        "Court": "court",
        "Surface": "surface",
        "Umpire": "umpire",
        "Best of": "best_of",
        "Final TB?": "final_tb",
        "Charted by": "charted_by",
    },
)

POINTS = SourceSpec(
    name="points",
    files=(
        "charting-m-points-to-2009.csv",
        "charting-m-points-2010s.csv",
        "charting-m-points-2020s.csv",
        "charting-w-points-to-2009.csv",
        "charting-w-points-2010s.csv",
        "charting-w-points-2020s.csv",
    ),
    table="raw.mcp_points",
    key_columns=("match_id", "pt"),
    required=("match_id", "Pt"),
    column_map={
        "match_id": "match_id",
        "Pt": "pt",
        "Set1": "set1",
        "Set2": "set2",
        "Gm1": "gm1",
        "Gm2": "gm2",
        "Pts": "pts",
        "Gm#": "gm_num",
        "TbSet": "tb_set",
        "Svr": "svr",
        # The shot-by-shot notation strings. The whole project rests on these two.
        "1st": "first_serve",
        "2nd": "second_serve",
        "Notes": "notes",
        "PtWinner": "pt_winner",
    },
)

STATS_SERVE_DIRECTION = SourceSpec(
    name="stats_serve_direction",
    files=(
        "charting-m-stats-ServeDirection.csv",
        "charting-w-stats-ServeDirection.csv",
    ),
    table="raw.mcp_stats_serve_direction",
    key_columns=("match_id", "player", "row_label"),
    required=("match_id", "player", "row"),
    column_map={
        "match_id": "match_id",
        "player": "player",
        "row": "row_label",
        "deuce_wide": "deuce_wide",
        "deuce_middle": "deuce_middle",
        "deuce_t": "deuce_t",
        "ad_wide": "ad_wide",
        "ad_middle": "ad_middle",
        "ad_t": "ad_t",
        "err_net": "err_net",
        "err_wide": "err_wide",
        "err_deep": "err_deep",
        "err_wide_deep": "err_wide_deep",
        "err_foot": "err_foot",
        "err_unknown": "err_unknown",
    },
)

SOURCES: dict[str, SourceSpec] = {s.name: s for s in (MATCHES, POINTS, STATS_SERVE_DIRECTION)}
