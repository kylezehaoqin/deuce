-- INDEX EXISTENCE TEST.
--
-- An index is state dbt does not treat as part of a model's contract. Nothing
-- in the model definition asserts one, so an index can disappear -- dropped by
-- hand, lost to a rebuild outside dbt, or silently never created -- and
-- `dbt build` stays green while every agent query falls back to a seq scan.
--
-- That already happened here: dim_players' trigram index was gone and nothing
-- noticed. Same failure shape as the 474 MB orphan table left by a model
-- rename. (lesson 010, errors E11)
--
-- TWO WAYS TO CHECK, because there are two ways indexes get made:
--
--   dbt `indexes` config  -> names are HASHED (e8278b7397ae...), so the name is
--                            useless to assert on. Check the LEADING COLUMN.
--   post_hook             -> we choose the name, so assert the name directly.
--                            This is the only way to check a partial index,
--                            since dbt's config has no WHERE clause.
--
-- Relations are resolved through ref() so this carries no hardcoded schema.
--
-- dbt singular test: any returned row fails the build.

with expected_leading_column as (

    select * from (values
        ('{{ ref("fct_serves") }}'::regclass::oid, 'fct_serves', 'server_name'),
        ('{{ ref("fct_serves") }}'::regclass::oid, 'fct_serves', 'match_id'),
        ('{{ ref("fct_points") }}'::regclass::oid, 'fct_points', 'server_name'),
        ('{{ ref("fct_points") }}'::regclass::oid, 'fct_points', 'match_id'),
        ('{{ ref("fct_games")  }}'::regclass::oid, 'fct_games',  'server_name'),
        ('{{ ref("fct_games")  }}'::regclass::oid, 'fct_games',  'match_id')
    ) as t (relid, model_name, leading_column)

),

actual_leading_column as (

    -- indkey is an int2vector; element 0 is the index's first column.
    select i.indrelid as relid, a.attname as leading_column
    from pg_index i
    join pg_attribute a
      on a.attrelid = i.indrelid
     and a.attnum   = i.indkey[0]

),

missing_columns as (

    select e.model_name, e.leading_column as detail, 'no index with this leading column' as problem
    from expected_leading_column e
    where not exists (
        select 1 from actual_leading_column a
        where a.relid = e.relid and a.leading_column = e.leading_column
    )

),

expected_named as (

    select * from (values
        -- the partial index that measured 200x faster than no index
        ('{{ ref("fct_serves")  }}'::regclass::oid, 'fct_serves',  'ix_fct_serves_server_bp'),
        -- GIN trigram, for fuzzy player-name resolution
        ('{{ ref("dim_players") }}'::regclass::oid, 'dim_players', 'ix_dim_players_name_trgm')
    ) as t (relid, model_name, index_name)

),

missing_named as (

    select e.model_name, e.index_name as detail, 'named index absent' as problem
    from expected_named e
    where not exists (
        select 1
        from pg_index i
        join pg_class c on c.oid = i.indexrelid
        where i.indrelid = e.relid and c.relname = e.index_name
    )

)

select * from missing_columns
union all
select * from missing_named
