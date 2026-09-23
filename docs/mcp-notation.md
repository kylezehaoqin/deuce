# Match Charting Project shot notation — codebook

Every point in `raw.mcp_points` carries its rally as a single string in
`first_serve` / `second_serve`. Example:

```
4b37y1r3n#
```

Serve **out wide** (`4`) → **backhand** (`b`) **to a righty's backhand side** (`3`)
**landing inside the service boxes** (`7` — return depth) → **backhand drop shot**
(`y`) **to a righty's forehand side** (`1`) → **forehand slice** (`r`) **to a
righty's backhand side** (`3`) → **into the net** (`n`), **forced error** (`#`).

**Source of record:** the *Instructions* tab of `MatchChart 0.3.2.xlsm` in
[the upstream repo](https://github.com/JeffSackmann/tennis_MatchChartingProject).
That file is the spec; `data_dictionary.txt` documents only the CSV *columns*.
Everything below is transcribed from it and is therefore **authoritative**, not
inferred. Where our parser deviates from the spec, that's a bug in the parser.

---

## Serves

Direction — **identical in both the deuce and ad courts**:

| Code | Meaning |
|---|---|
| `4` | out wide |
| `5` | body |
| `6` | down the T |
| `0` | direction unknown |

Fault types, appended to the direction:

| Code | Meaning |
|---|---|
| `n` | net (including net cords that aren't lets) |
| `w` | wide |
| `d` | deep |
| `x` | wide *and* deep |
| `g` | foot fault |
| `e` | unknown fault type |
| `!` | shank (used instead of the fault-type letter) |

Other serve codes: `c` = a let (repeatable — `cc4e` is two lets then a wide fault
of unknown direction), `V` = server lost a first serve to a time violation,
`+` = serve-and-volley attempt, placed after the direction (`4+`, or `4+w` if it
faulted).

**Points that never get past the serve:**

| Code | Meaning |
|---|---|
| `5*` | ace |
| `6#` | **unreturnable** — returner touched it but couldn't return it |

Sackmann's rule for "unreturnable": the returner failed to get a full racquet on
the ball, failed to get the return to the net, or wildly missed. Anything else is
a return error, coded as a rally shot with `#` or `@`.

## Rally shot types

| Code | Shot | Code | Shot |
|---|---|---|---|
| `f` | forehand groundstroke | `b` | backhand groundstroke |
| `r` | forehand slice / chip | `s` | backhand slice / chip |
| `v` | forehand volley | `z` | backhand volley |
| `o` | overhead / smash | `p` | "backhand" overhead |
| `u` | forehand drop shot | `y` | backhand drop shot |
| `l` | forehand lob | `m` | backhand lob |
| `h` | forehand half-volley | `i` | backhand half-volley |
| `j` | forehand swinging volley | `k` | backhand swinging volley |
| `t` | trick shot (tweener, behind-the-back) | `q` | unknown shot |

Slices exclude drop shots, which have their own codes.

## Direction — the part that matters most

| Code | Meaning |
|---|---|
| `1` | to a **right-hander's forehand** side / a left-hander's backhand side |
| `2` | down the middle |
| `3` | to a **right-hander's backhand** side / a left-hander's forehand side |
| `0` | unknown |

Three consequences, all load-bearing:

**1. Direction is absolute, not relative to the hitter.** `1` and `3` name fixed
halves of the court, defined by reference to a right-handed receiver. They do not
mean "crosscourt" or "down the line" — those depend on where the *hitter* is
standing, which depends on where the previous ball went. Converting `1/2/3` into
crosscourt / down-the-line / inside-out / inside-in therefore requires a
**stateful** parse that tracks court position across shots. See `lessons/005`.

**2. Direction is measured at the baseline, not at the bounce.** Where the ball
crossed (or would have crossed) the opponent's baseline. A crosscourt return off
a wide serve may bounce mid-court and still be a `1`.

**3. Direction is OPTIONAL.** `fbh` — forehand, backhand, half-volley with no
directions at all — is explicitly valid. Any parser keyed on "shot letter followed
by a direction digit" silently skips these, and any *rate* computed over them has
a denominator that isn't what you think it is.

Zone sizes are approximate: think `2` as the middle ~40% of the court and `1`/`3`
as the outer ~30% each.

## Depth — return depth only

| Code | Meaning |
|---|---|
| `7` | within the service boxes |
| `8` | behind the service line, nearer the service line than the baseline |
| `9` | nearer the baseline than the service line |

**These apply to service returns only**, not to groundstrokes generally. A service
return that lands in takes three keystrokes: type, direction, depth (`f37`). Also
optional.

## Rally endings

| Code | Meaning |
|---|---|
| `*` | winner |
| `@` | unforced error |
| `#` | forced error |

The errored shot **is coded**, including the shot the loser tried to make, with an
error type (`n` `w` `d` `x` `!` `e`) before the `@` / `#`.

Required keystrokes differ, and this asymmetry matters for parsing:

- **Unforced error:** shot type + error type + `@`. Direction optional.
- **Forced error:** shot type + `#` only. `b#` is valid and complete.

So point-ending forced errors frequently carry **no direction at all**, while
unforced errors often do.

## Court-position modifiers

Placed **immediately after the shot letter, before the direction**:

| Code | Meaning | Example |
|---|---|---|
| `+` | approach shot (or serve-and-volley on a serve) | `b+2` |
| `-` | shot taken at the net | `f-1` |
| `=` | shot taken at the baseline | `o=2` |
| `;` | clipped the net cord | `f;1*` |
| `^` | stop volley / drop volley | `z^2*` |

Volleys, half-volleys, swinging volleys and smashes are assumed at the net;
groundstrokes, slices, drop shots, lobs and trick shots at the baseline. `-` and
`=` exist to say otherwise.

## Unusual situations

| Code | Meaning |
|---|---|
| `S` / `R` | charter missed the point; server / returner won it |
| `P` / `Q` | point penalty against the server / returner |
| `C` | play stopped for a challenge that proved incorrect |

---

## Coverage is deliberately uneven

Sackmann instructs charters to learn the system in layers — shot types first,
then direction, then return depth, then court position — and to prefer an
"unknown" code over missing the next shot. There is an unknown code at every
level: `0` (direction), `q` (shot type), `e` (error type), `S`/`R` (whole point).

His own framing: *"having 95% of the data from a match is usually sufficient to
identify patterns and tendencies."*

For us that means **missingness is not random**. It correlates with charter
experience, broadcast quality and how fast the point was. Any rate computed from
these fields needs its denominator stated, and `parse_confidence` exists because
the same bias shows up across charting eras.

---

## Measured accuracy — rally length

The spec settles what the codes *mean*; it doesn't settle whether our SQL
implements them correctly. That still needs an oracle.

```sql
GREATEST(1,
    1                                                                  -- the serve
  + length(regexp_replace(rally, '[^fbrsvzopuylmhijktq]', '', 'g'))    -- shot letters
  - CASE WHEN rally ~ '[@#]$' THEN 1 ELSE 0 END)                       -- the miss doesn't count
```

Two conventions were recovered by diffing against
`charting-*-stats-Rally.csv` before the spec was consulted, and both are
consistent with it: Sackmann excludes the errored shot, but an unreturned serve
still counts as a rally of 1.

Agreement on all four of his buckets (1-3 / 4-6 / 7-9 / 10+):

| Charting era | Matches | Exact | Within 2 points |
|---|---:|---:|---:|
| 2020s | 5,886 | **90.0%** | — |
| 2010s | 3,516 | **82.5%** | — |
| pre-2010 | 2,376 | **55.2%** | — |

Regression-guarded in `dbt/tests/assert_rally_length_matches_oracle.sql`.

**Charting conventions drifted.** A parser tuned on modern matches degrades badly
on old ones, so every parsed row carries `parse_confidence` and the agent must
disclose it rather than compare across eras silently.

## Still to verify against the oracles

| Claim | Oracle | State |
|---|---|---|
| Rally length | `stats-Rally.csv` | ✅ 90.0% (2020s), regression-tested |
| Shot-type letters | `stats-ShotTypes.csv` | not yet diffed |
| Direction → tactical terms | `stats-ShotDirection.csv` | scope resolved (median +1/match); mapping still open — `lessons/005` |
| Direction → outcome | `stats-ShotDirOutcomes.csv` | not yet diffed |

The spec tells you what the parser *should* do. The oracle tells you what yours
*does*. You need both.
