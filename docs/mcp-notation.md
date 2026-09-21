# Match Charting Project shot notation — working codebook

Every point in `raw.mcp_points` carries its rally as a single string in
`first_serve` / `second_serve`. Example:

```
4b37y1r3n#
```

Read left to right: **serve out wide** (`4`) → **backhand** (`b`) **to direction 3**
(`3`) **at depth 7** (`7`) → **backhand drop shot** (`y`) **to direction 1** (`1`) →
**forehand slice** (`r`) **to direction 3** (`3`) → **into the net** (`n`) as a
**forced error** (`#`).

Turning that string into one row per shot is the whole shot-grain modelling job.

---

## Confidence levels

This file is a **working** codebook. Codes are marked:

- ✅ **verified** — confirmed against `data_dictionary.txt` or observed unambiguously in the data
- ⚠️ **community consensus** — widely used, but confirm before you build a metric on it
- ❓ **unverified** — orientation/meaning genuinely ambiguous; see *How to verify* below

The authoritative source is the **Instructions tab of `MatchChart 0.3.2.xlsm`** in
[the upstream repo](https://github.com/JeffSackmann/tennis_MatchChartingProject).
`data_dictionary.txt` documents the *columns*, not the *codes*.

---

## Serve

| Code | Meaning | Confidence |
|---|---|---|
| `4` | out wide | ⚠️ |
| `5` | body | ⚠️ |
| `6` | down the T | ⚠️ |
| `0` | direction unknown / not charted | ⚠️ |

Which physical corner "wide" and "T" point at depends on the court side, and the
court side alternates every point within a game. Derive it — don't chart it:
point 1 of a game is the deuce court, and it alternates from there. `point_in_game`
in `stg_points` exists for exactly this.

A **second serve** is present (`second_serve` non-empty) iff the first serve was a
fault. `stg_points.rally_notation` already picks the serve that was actually played.

## Rally shot types

| Code | Shot | Code | Shot |
|---|---|---|---|
| `f` | forehand (topspin/flat) | `b` | backhand |
| `r` | forehand slice | `s` | backhand slice |
| `v` | forehand volley | `z` | backhand volley |
| `o` | overhead / smash | `p` | backhand overhead |
| `u` | forehand drop shot | `y` | backhand drop shot |
| `l` | forehand lob | `m` | backhand lob |
| `h` | forehand half-volley | `i` | backhand half-volley |
| `j` | forehand swinging volley | `k` | backhand swinging volley |
| `t` | trick shot (tweener etc.) | `q` | unknown |

Confidence: ⚠️ across the table. The forehand/backhand split is the part you can
sanity-check cheaply (see below).

## Direction

A digit `1` / `2` / `3` immediately after a shot-type letter.

| Code | Meaning | Confidence |
|---|---|---|
| `1` | one side of the court | ❓ orientation |
| `2` | middle | ⚠️ |
| `3` | the other side | ❓ orientation |

**This is the single most important thing to verify**, because "did they go
down-the-line or crosscourt?" depends entirely on getting the orientation right,
and getting it backwards produces answers that look plausible and are wrong.

## Depth and terminators

| Code | Meaning | Confidence |
|---|---|---|
| `7` / `8` / `9` | shallow / mid / deep | ⚠️ |
| `*` | winner | ⚠️ |
| `@` | unforced error | ⚠️ |
| `#` | forced error | ⚠️ |
| `n` `w` `d` `x` | error was: net / wide / deep / wide+deep | ⚠️ |
| `+` `-` `=` `^` `!` | approach, net approach, and shot-quality markers | ❓ |

---

## How to verify (do this before trusting a parser)

Sackmann ships his **own** aggregations of these same strings. That makes them a
free oracle for your parser:

| Your parse of… | Cross-check against |
|---|---|
| shot type counts | `charting-m-stats-ShotTypes.csv` |
| shot directions | `charting-m-stats-ShotDirection.csv` |
| direction → outcome | `charting-m-stats-ShotDirOutcomes.csv` |
| serve placement | `charting-m-stats-ServeDirection.csv` (already ingested) |
| rally lengths | `charting-m-stats-Rally.csv` |

Pick ~20 matches, parse them, aggregate to the same grain, and diff. If your
forehand count matches Sackmann's for 20 matches, your shot-type mapping is right.
If your `direction = 3` counts match his crosscourt column, your orientation is right.

**Make that diff a dbt test**, not a one-off script. It is the strongest data-quality
story in this repo: a parser validated against an independent implementation of the
same spec, re-checked on every build.
