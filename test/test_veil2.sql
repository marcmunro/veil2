--  test_veil2.sql
--
--     Unit tests for Veil2
--
--     Copyright (c) 2020 Marc Munro
--     Author:  Marc Munro
--     License: GPL V3
--
-- Usage: psql -f test_veil2.sql -d dbname
--


\echo Running Veil2 unit tests...

\unset ECHO
\set QUIET 1
\pset format unaligned
\pset tuples_only true
\pset pager off


\if :{?test}
  \o /dev/null
  select case when lower(:'test') like '%view%'
         then true else :'test' = '' end as test_views,
	 case when lower(:'test') like '%auth%'
         then true else :'test' = '' end as test_authent,
	 case when lower(:'test') like '%sess%'
         then true else :'test' = '' end as test_sessions; \gset
  \o
\else
  \set test_views 1
  \set test_authent 1
  \set test_sessions 1
\endif

create extension pgtap;

do
$$
declare
  _result integer;
begin
  select 1 into _result from pg_extension where extname = 'veil2';
  if not found then
    execute 'create extension veil2 cascade';
  end if;
end;
$$;

select * from veil2.init();
\ir setup.sql


\if :test_views
  \ir test_views.sql
\endif


\if :test_authent
  \ir test_authent.sql
\endif

\if :test_sessions
  \ir test_sessions.sql
\endif

\echo Cleaning up...
\ir teardown.sql
