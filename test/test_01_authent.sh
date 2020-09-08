#! /bin/bash

echo "`basename $0 .sh` - Checking authentication functions -"
echo "...checking vpd.authenticate()..."

result=`psql -d vpd 2>&1 <<EOF 
\set ON_ERROR_STOP
\set QUIET
\pset tuples_only on

update veil2.authentication_types
   set enabled = false
 where shortname = 'plaintext';

-- Plaintext authentication is not enabled
-- (where clause is designed to return no rows in order to keep output clean
select 99 where 99 = test.expect_n(
    'select 1 from veil2.authentication_types
     where shortname = ''plaintext'' and not enabled', 1,
    'Expecting disabled plaintext authentication');

-- Authentication fails when authent_type is not enabled.
-- (where clause is desigbned to return no rows in order to keep output clean
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-1, ''plaintext'', ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(1)');

update veil2.authentication_types
   set enabled = true
 where shortname = 'plaintext';

-- Authentication succeeds when authent_type is enabled.
-- (where clause is designed to return no rows in order to keep output clean
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-1, ''plaintext'', ''password'')
     when true then 1 else 0 end',
     1, 'AUTHENTICATION SHOULD HAVE FAILED(2)');

-- Authentication fails when password is incorrect
-- (where clause is designed to return no rows in order to keep output clean
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-1, ''plaintext'', ''password3'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(3)');

-- Authentication fails when auth type is incorrect
-- (where clause is designed to return no rows in order to keep output clean
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-1, ''unimplemented-authentication-type'', 
                             ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(4)');

-- Authentication fails when auth type does not exist
-- (where clause is designed to return no rows in order to keep output clean
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-1, ''wibble'', ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(5)');

-- Authentication fails when party does not exist
-- (where clause is designed to return no rows in order to keep output clean
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-99, ''plaintext'', ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(6)');


-- Test bcrypt authentication - incorrect password
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-1, ''bcrypt'', ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(7)');

-- Test bcrypt authentication - incorrect password
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-1, ''bcrypt'', ''bassword2'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(8)');

-- Test bcrypt authentication - correct password
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-1, ''bcrypt'', ''bassword'')
     when true then 1 else 0 end',
     1, 'BCRYPT AUTHENTICATION SHOULD HAVE PASSED');

-- Test bcrypt authentication - correct password again
select 99 where 99 = test.expect_n(
    'select 
     case veil2.authenticate(-2, ''bcrypt'', ''bassword2'')
     when true then 1 else 0 end',
     1, 'BCRYPT AUTHENTICATION SHOULD HAVE PASSED(2)');




EOF`
status=$?

# Show output from psql, with any blank lines (empty result sets) removed.
echo "${result}" | grep .

exit ${status}
