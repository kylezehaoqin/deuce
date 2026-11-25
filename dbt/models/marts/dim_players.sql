{{ config(
    materialized='table',
    post_hook=[
        "drop index if exists analytics_analytics.ix_dim_players_name_trgm",
        "create index ix_dim_players_name_trgm on {{ this }} using gin (player_name gin_trgm_ops)",
    ]
) }}

-- ============================================================================
--  dim_players -- one row per player. The agent's name-resolution table.
--
--  Unglamorous and blocking: the agent is asked about "Alcaraz", not "Carlos
--  Alcaraz". Every other mart keys on the full charted name, so something has
--  to bridge the two.
--
--  Fuzzy lookup, which is what the agent actually runs:
--
--    select player_name from dim_players
--    where player_name % 'alcaraz'            -- % is trigram similarity
--    order by similarity(player_name, 'alcaraz') desc limit 5;
--
--  Resolves misspellings: 'federr' -> Roger Federer, 'swiatek' -> Iga Swiatek.
--  pg_trgm is created in sql/001_schemas.sql.
--
--  On the index: it exists, it is correct, and the planner IGNORES it -- at
--  1,739 rows and 568 kB a sequential scan is genuinely cheaper, and Postgres
--  is right to pick one. Verified with enable_seqscan=off, which does use the
--  index. It is kept because it costs nothing and stops being pointless if this
--  ever grows; it is not doing any work today, and the comment says so rather
--  than implying a speedup that is not happening.
--
--  EASIER THAN EXPECTED: 1,739 distinct names with zero case or punctuation
--  variants -- checked before building this. There is no entity-resolution
--  problem here, so this stays a dimension table rather than a matching system.
--
--  Coverage columns exist so the agent can refuse well. questions.yml keeps
--  saying "if N < 20 say the sample is thin"; that is only enforceable when
--  sample size is a queryable fact.
-- ============================================================================

with player_matches as (

    -- Unpivot the two-players-per-row match table into player-match grain.
    select
        match_id, match_date, tour, surface,
        player_1_name as player_name,
        player_1_hand as hand,
        player_2_name as opponent_name
    from {{ ref('stg_matches') }}

    union all

    select
        match_id, match_date, tour, surface,
        player_2_name,
        player_2_hand,
        player_1_name
    from {{ ref('stg_matches') }}

),

hand_votes as (

    -- How often each hand is recorded for each player. NULL hands (not
    -- entered) are not votes.
    select player_name, hand, count(*) as votes
    from player_matches
    where player_name is not null and hand is not null
    group by 1, 2

),

hand_majority as (

    select
        player_name,
        max(votes)::numeric / sum(votes)                         as hand_agreement,
        -- A tie is the only case with no majority: e.g. L=1 R=1.
        count(*) filter (where votes = (select max(v.votes) from hand_votes v
                                        where v.player_name = hv.player_name)) > 1
                                                                 as is_hand_tied
    from hand_votes hv
    group by 1

),

points_per_match as (

    select match_id, count(*) as points
    from {{ ref('fct_points') }}
    group by 1

),

final as (

    select
        pm.player_name,

        -- MAJORITY RULE (Kyle, 2026-11-25). A player's hand IS constant in
        -- reality, but charters mistype it: 49 players have disagreeing rows.
        -- Nadal is L in 420 of 425 matches; of the other 5, two are hands
        -- SWAPPED with the opponent (Gabashvili 2010, Wawrinka 2017), one a
        -- typo, two not entered. So `hand` is the majority, and
        -- is_hand_ambiguous is true only with NO majority -- a tie (1 player).
        -- It used to be true on any disagreement, which flagged 49, 39 of them
        -- with a 90%+ majority. hand_agreement keeps the disagreement visible.
        mode() within group (order by pm.hand)          as hand,
        coalesce(min(hm.hand_agreement), 1.0)           as hand_agreement,
        coalesce(bool_or(hm.is_hand_tied), false)       as is_hand_ambiguous,

        mode() within group (order by pm.tour)          as tour,
        count(distinct pm.tour) > 1                     as plays_both_tours,

        count(distinct pm.match_id)                     as matches_charted,
        count(distinct pm.opponent_name)                as opponents_faced,
        coalesce(sum(ppm.points), 0)                    as points_played,

        min(pm.match_date)                              as first_charted_date,
        max(pm.match_date)                              as last_charted_date,

        count(distinct pm.match_id) filter (where pm.surface = 'Hard')   as matches_hard,
        count(distinct pm.match_id) filter (where pm.surface = 'Clay')   as matches_clay,
        count(distinct pm.match_id) filter (where pm.surface = 'Grass')  as matches_grass,
        count(distinct pm.match_id) filter (where pm.surface is null)    as matches_unknown_surface,

        -- Charting conventions drifted, so a player whose record is mostly
        -- pre-2010 carries weaker parsed statistics than the match count
        -- suggests. Surface this rather than let it hide.
        count(distinct pm.match_id) filter (where pm.match_date >= '2020-01-01') as matches_2020s,
        count(distinct pm.match_id) filter (where pm.match_date <  '2010-01-01') as matches_pre_2010

    from player_matches pm
    left join hand_majority hm using (player_name)
    left join points_per_match ppm using (match_id)
    where pm.player_name is not null
    group by 1

)

select * from final
