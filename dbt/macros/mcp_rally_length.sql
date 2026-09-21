{#
  Rally length from a Match Charting Project notation string.

  Not the full parser -- deliberately. It answers "how many shots?" without
  answering "what were they?", which turns out to be most of what rally-shape
  questions need, and it is checkable against Sackmann's own numbers.

  Three rules, two of them discovered by diffing rather than from any spec
  (lessons/004):
    1. Every shot-type letter is one shot. +1 for the serve. Direction digits,
       depth digits, error codes and terminators are not shots.
    2. A shot that MISSED is not counted -- a rally ending '@' (unforced) or
       '#' (forced) loses its last shot. This matches Sackmann's convention.
    3. ...but never below 1. An unreturned serve ('4#') is a rally of 1, not 0.

  Measured agreement with charting-*-stats-Rally.csv: 91.6% of 2020s matches
  exact on all four buckets, 83.1% of 2010s, 54.0% pre-2010. Regression-tested
  in tests/assert_rally_length_matches_oracle.sql.
#}
{% macro mcp_rally_length(notation) %}
greatest(
    1,
    1
    + length(regexp_replace({{ notation }}, '[^fbrsvzopuylmhijktq]', '', 'g'))
    - case when {{ notation }} ~ '[@#]$' then 1 else 0 end
)
{% endmacro %}


{#
  Which era a match was charted in, and therefore how much to trust a parse of it.

  Charting conventions drifted over the project's history. This is not cosmetic:
  the same parser is ~92% accurate on 2020s matches and ~54% on pre-2010 ones.
  Any number derived from parsed shots should carry this, and the agent should
  refuse to compare across confidence levels without saying so.
#}
{% macro mcp_parse_confidence(match_date) %}
case
    when {{ match_date }} is null                        then 'unknown'
    when extract(year from {{ match_date }}) >= 2020     then 'high'
    when extract(year from {{ match_date }}) >= 2010     then 'medium'
    else 'low'
end
{% endmacro %}
