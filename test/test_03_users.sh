#! /bin/bash

echo "`basename $0 .sh` - Checking user access controls -"
psql -d vpd 2>&1 <<EOF 
\set ON_ERROR_STOP
\set QUIET
\pset tuples_only on

\echo ...checking session setup...
select 99 where 99 = test.expect_n(
    'select 1
      from (select errtext from test.connect_plaintext(-1, ''password'', 1)) x
     where errtext = ''AUTHFAIL''', 1,
     'Expected AUTHFAIL for user -1 who has no connect privilege');

select 99 where 99 = test.expect_n(
    'select 1
      from (select success from test.connect_plaintext(-2, ''password2'', 1)) x
     where success', 1,
     'Expected success for user -2');

-- Try again with new nonce
select 99 where 99 = test.expect_n(
    'select 1
      from (select success from test.reconnect_plaintext(''password2'', 13)) x
     where success', 1,
     'Expected success for user -2 (2)');

-- Try again with another new nonce
select 99 where 99 = test.expect_n(
    'select 1
      from (select success from test.reconnect_plaintext(''password2'', 7)) x
     where success', 1,
     'Expected success for user -2 (3)');

-- re-use a nonce
select * from test.reconnect_plaintext('password2', 13);


EOF
status=$?

# Show output from psql, with any blank lines (empty result sets) removed.
#echo "${result}" | grep .

exit ${status}

