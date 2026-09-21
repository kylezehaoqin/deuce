-- REGRESSION TEST for the rally-length parser.
--
-- Sackmann independently implemented the same notation spec and published his
-- aggregations. Diffing against them turns "I think the parser works" into a
-- number that CI can defend.
--
-- Thresholds are set just below the measured baseline (91.6% / 83.1% / 54.0%
-- exact on all four buckets -- see lessons/004), so this fails when a parser
-- change makes things WORSE, not merely when things are imperfect. A test
-- pinned to perfection on messy upstream data gets muted within a week; a test
-- pinned to a baseline gets trusted.
--
-- dbt singular test: returning any row fails the build.

{% set thresholds = {'high': 88.0, 'medium': 78.0, 'low': 45.0} %}

with ours as (

    select
        match_id,
        parse_confidence,
        count(*) filter (where rally_bucket = '1-3') as b13,
        count(*) filter (where rally_bucket = '4-6') as b46,
        count(*) filter (where rally_bucket = '7-9') as b79,
        count(*) filter (where rally_bucket = '10+') as b10
    from {{ ref('int_point_rally_length') }}
    group by match_id, parse_confidence

),

theirs as (

    select
        match_id,
        max(points) filter (where rally_bucket = '1-3') as b13,
        max(points) filter (where rally_bucket = '4-6') as b46,
        max(points) filter (where rally_bucket = '7-9') as b79,
        max(points) filter (where rally_bucket = '10+') as b10
    from {{ ref('stg_stats_rally') }}
    where serve_split = 'all_serves'
    group by match_id

),

agreement as (

    select
        o.parse_confidence,
        count(*) as matches_compared,
        round(100.0 * count(*) filter (
            where o.b13 = t.b13 and o.b46 = t.b46
              and o.b79 = t.b79 and o.b10 = t.b10
        ) / count(*), 1) as pct_exact
    from ours o
    join theirs t using (match_id)
    group by o.parse_confidence

)

select
    parse_confidence,
    matches_compared,
    pct_exact,
    case parse_confidence
        {%- for tier, floor in thresholds.items() %}
        when '{{ tier }}' then {{ floor }}
        {%- endfor %}
    end as threshold
from agreement
where matches_compared >= 100     -- don't fail a tier on a handful of matches
  and pct_exact < case parse_confidence
        {%- for tier, floor in thresholds.items() %}
        when '{{ tier }}' then {{ floor }}
        {%- endfor %}
      end
