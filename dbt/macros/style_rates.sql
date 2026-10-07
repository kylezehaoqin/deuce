{#
  The 12 style rates, defined ONCE. mart_player_style and mart_matchup both
  compute rates from the same count columns (int_player_match_style), and two
  copies of a formula drift apart without any error. The reasons for each
  feature are in mart_player_style's `features` CTE.

  Call it in a select whose FROM exposes the int_player_match_style count
  columns. `rounded=false` keeps full precision, for rates that are averaged
  again (mart_matchup's matched baseline).
#}

{% macro style_rate_names() %}
  {{ return([
    'fh_dominance', 'bh_slice_rate', 'net_rate', 'drop_shot_rate',
    'point_ending_rate', 'fh_inside_out_rate', 'fh_down_the_line_rate',
    'bh_down_the_line_rate', 'first_serve_t_rate', 'deuce_serve_entropy',
    'ad_serve_entropy', 'first_serve_in_rate', 'avg_rally_length'
  ]) }}
{% endmacro %}

{#
  Normalised entropy over three serve directions: -sum(p ln p) / ln 3. The SAME
  formula as mart_serve_patterns, so 0 = one direction always, 1 = uniform.
  A p of 0 contributes 0 (the limit of p ln p), not NULL.
#}
{% macro serve_entropy(wide, body, t) %}
    -(  coalesce({{ wide }}::numeric / nullif({{ wide }} + {{ body }} + {{ t }}, 0)
               * ln(nullif({{ wide }}::numeric / nullif({{ wide }} + {{ body }} + {{ t }}, 0), 0)), 0)
      + coalesce({{ body }}::numeric / nullif({{ wide }} + {{ body }} + {{ t }}, 0)
               * ln(nullif({{ body }}::numeric / nullif({{ wide }} + {{ body }} + {{ t }}, 0), 0)), 0)
      + coalesce({{ t }}::numeric / nullif({{ wide }} + {{ body }} + {{ t }}, 0)
               * ln(nullif({{ t }}::numeric / nullif({{ wide }} + {{ body }} + {{ t }}, 0), 0)), 0)
     ) / ln(3::numeric)
     -- NULL, not 0, when the side has no serves: an empty side is not "predictable".
     * case when {{ wide }} + {{ body }} + {{ t }} > 0 then 1 end
{% endmacro %}

{% macro _style_round(expr, rounded, places=4) -%}
  {%- if rounded -%} round({{ expr }}, {{ places }}) {%- else -%} ({{ expr }}) {%- endif -%}
{%- endmacro %}

{% macro style_rates(rounded=true) %}
        {{ _style_round("fh_drives::numeric / nullif(fh_drives + bh_drives, 0)", rounded) }}      as fh_dominance,
        {{ _style_round("bh_slices::numeric / nullif(bh_side_shots, 0)", rounded) }}              as bh_slice_rate,
        {{ _style_round("net_shots::numeric / nullif(shots, 0)", rounded) }}                      as net_rate,
        {{ _style_round("drop_shots::numeric / nullif(shots, 0)", rounded) }}                     as drop_shot_rate,
        {{ _style_round("point_ending_shots::numeric / nullif(shots, 0)", rounded) }}             as point_ending_rate,
        {{ _style_round("fh_inside_out::numeric / nullif(fh_directed, 0)", rounded) }}            as fh_inside_out_rate,
        {{ _style_round("fh_down_the_line::numeric / nullif(fh_directed, 0)", rounded) }}         as fh_down_the_line_rate,
        {{ _style_round("bh_down_the_line::numeric / nullif(bh_directed, 0)", rounded) }}         as bh_down_the_line_rate,
        {{ _style_round("(deuce_t + ad_t)::numeric
                / nullif(deuce_wide + deuce_body + deuce_t + ad_wide + ad_body + ad_t, 0)", rounded) }}
                                                                                as first_serve_t_rate,
        {{ _style_round(serve_entropy('deuce_wide', 'deuce_body', 'deuce_t'), rounded) }}         as deuce_serve_entropy,
        {{ _style_round(serve_entropy('ad_wide', 'ad_body', 'ad_t'), rounded) }}                  as ad_serve_entropy,
        {{ _style_round("first_serves_in::numeric / nullif(first_serves, 0)", rounded) }}         as first_serve_in_rate,
        {{ _style_round("rally_length_sum::numeric / nullif(points_rally_scoreable, 0)", rounded, 2) }}
                                                                                as avg_rally_length
{%- endmacro %}
