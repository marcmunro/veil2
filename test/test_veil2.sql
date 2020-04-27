-- Test script for checking Veil2.  This is intended to run safely
-- against both an initial Veil2 database and one that has been deployed
-- with real tables.  That said, there are no guarantees.  Just don't
-- run it in production. 
-- 
-- The script may be called with a flags parameter, where flags is a
-- list of characters in the following set:
--     s   Do not run setup    
--     t   Do not run teardown
--     r   Do not run tests
--
-- eg: psql -v flags="st" -f <this-file>
--

-- Format our output for quiet tests.
\set ECHO none
\set QUIET 1
\pset format unaligned
\pset tuples_only true
\pset pager

--
-- Begin Parameter Handling
--

-- THIS IS A DIRTY HACK TO DEAL WITH THE flags PARAMETER EVEN IF UNDEFINED
\o tmp.tmp
\set given = :flags
\o
\i tmp.tmp
\! rm tmp.tmp

-- The queries below return rows beginning with '##' which can be easily
-- filtered from output using grep.
select '##' as ignore, :'given' != '=:flags' as have_flags; \gset
\if :have_flags
-- Read flags into script control variables
select '##' as ignore,
       strpos(:'flags', 's') = 0 as do_setup,
       strpos(:'flags', 't') = 0 as do_teardown,
       strpos(:'flags', 'r') = 0 as do_runtests; \gset
\else
-- Set all script control variables to true
\set do_setup 1
\set do_teardown 1
\set do_runtests 1
\endif
--
-- End Parameter Handling
--

\if :do_setup
\echo RUNNING SETUP
\ir setup.sql
\else
\echo SKIPPING TEST SETUP
\endif

\if :do_runtests
\echo RUNNING TESTS
\ir test_views.sql
\ir test_authent.sql
\ir test_sessions.sql

\echo TESTS COMPLETE
\endif

\if :do_teardown
\echo RUNNING TEARDOWN
\ir teardown.sql
\else
\echo SKIPPING TEST TEARDOWN
\endif


