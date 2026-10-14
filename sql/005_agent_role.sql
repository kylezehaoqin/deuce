-- ============================================================================
--  005 -- the agent's database role: read-only, marts only, time-limited.
--
--  The agent runs SQL that a model wrote. A read-only TRANSACTION is not a
--  guard on its own: `COMMIT; DROP TABLE ...` ends the transaction and runs
--  the write in a new one. Least privilege has to live in the database.
--
--    * The role can SELECT, and nothing else.
--    * It can read only the agent layer (fct_/dim_/mart_). dbt grants SELECT
--      per model (`grants` in dbt_project.yml), so staging and intermediate
--      models stay invisible -- an agent that reads them skips every rule the
--      marts encode.
--    * Every session is read-only and has a 10 s statement timeout, set on
--      the role itself, so no client setting can forget them.
--
--  The password is a dev default, like tennis/tennis in .env.example. Change
--  both before this database is ever reachable from outside localhost.
--
--  Idempotent, like every migration here: Docker init and `make db-init` run
--  the same file.
-- ============================================================================

do $$
begin
    if not exists (select from pg_roles where rolname = 'deuce_agent') then
        create role deuce_agent login password 'deuce_agent';
    end if;
end
$$;

alter role deuce_agent set default_transaction_read_only = on;
alter role deuce_agent set statement_timeout = '10s';

-- dbt creates this schema on its first build. Creating it here as well lets
-- the USAGE grant succeed on a fresh database, before dbt has run.
create schema if not exists analytics_analytics;
grant usage on schema analytics_analytics to deuce_agent;

-- No other schema: raw, observability and public stay closed to the agent.
revoke all on schema public from deuce_agent;
