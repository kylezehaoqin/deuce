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


{#
  Serve direction from a serve notation string.

  Spec (docs/mcp-notation.md): optional lets ('c', repeatable), then the
  direction digit -- 4 out wide, 5 body, 6 down the T, 0 unknown. Identical in
  both the deuce and ad courts.

  Anchored with leading lets allowed, because `left(notation, 1)` returns 'c' on
  a let-then-serve string. Rare, but silently wrong.

  Returns NULL when the charter recorded no direction -- which the spec permits,
  and which 0.2% of faulted serves do ('n' alone means "netted it, didn't see
  where"). NULL here is data, not a defect.
#}
{% macro mcp_serve_direction(notation) %}
case substring({{ notation }} from '^c*([0456])')
    when '4' then 'wide'
    when '5' then 'body'
    when '6' then 'T'
end
{% endmacro %}


{#
  Fault type from a serve notation string, or NULL if the serve landed.

  A fault is the direction followed by an error letter (optionally after '+',
  the serve-and-volley marker): 4w = wide serve missed wide, 6n = T serve into
  the net, 5d = body serve long.

  Measured distribution on 333,028 faulted 2020s serves:
    net 41% | deep 34% | wide 18% | wide+deep 6% | unknown/foot/shank <1%

  Note this reads the FAULT LETTER, not whether a second serve exists. A serve
  that landed has no fault letter, so this returns NULL for it.
#}
{% macro mcp_serve_fault_type(notation) %}
case substring({{ notation }} from '^c*[0456]\+?([nwdxge!])')
    when 'n' then 'net'
    when 'w' then 'wide'
    when 'd' then 'deep'
    when 'x' then 'wide_and_deep'
    when 'g' then 'foot_fault'
    when '!' then 'shank'
    when 'e' then 'unknown'
end
{% endmacro %}
