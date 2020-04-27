
\echo ...authentication functions...
\echo ......checking plaintext authentication...

update veil2.authentication_types
   set enabled = false
 where shortname = 'plaintext';

-- Plaintext authentication is not enabled
select null
 where test.expect(
    'select 1 from veil2.authentication_types
     where shortname = ''plaintext'' and not enabled', 1,
    'Expecting disabled plaintext authentication');

-- Authentication fails when authent_type is not enabled.
select null
 where test.expect(
    'select 
     case veil2.authenticate(-1, ''plaintext'', ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(1)');

update veil2.authentication_types
   set enabled = true
 where shortname = 'plaintext';


-- Authentication succeeds when authent_type is enabled.
select null
 where test.expect(
    'select 
     case veil2.authenticate(-1, ''plaintext'', ''password'')
     when true then 1 else 0 end',
     1, 'AUTHENTICATION SHOULD HAVE FAILED(2)');

-- Authentication fails when password is incorrect
select null
 where test.expect(
    'select 
     case veil2.authenticate(-1, ''plaintext'', ''password3'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(3)');

-- Authentication fails when auth type is incorrect
select null
 where test.expect(
    'select 
     case veil2.authenticate(-1, ''unimplemented-authentication-type'', 
                             ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(4)');

-- Authentication fails when auth type does not exist
select null
 where test.expect(
    'select 
     case veil2.authenticate(-1, ''wibble'', ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(5)');

-- Authentication fails when party does not exist
select null
 where test.expect(
    'select 
     case veil2.authenticate(-99, ''plaintext'', ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(6)');

\echo ......checking bcrypt authentication...
-- Test bcrypt authentication - incorrect password
select null
 where test.expect(
    'select 
     case veil2.authenticate(-1, ''bcrypt'', ''password'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(7)');

-- Test bcrypt authentication - incorrect password
select null where test.expect(
    'select 
     case veil2.authenticate(-1, ''bcrypt'', ''bassword2'')
     when true then 1 else 0 end',
     0, 'AUTHENTICATION SHOULD HAVE FAILED(8)');
-- Test bcrypt authentication - correct password
select null where test.expect(
    'select 
     case veil2.authenticate(-1, ''bcrypt'', ''bassword'')
     when true then 1 else 0 end',
     1, 'BCRYPT AUTHENTICATION SHOULD HAVE PASSED');

-- Test bcrypt authentication - correct password again
select null where test.expect(
    'select 
     case veil2.authenticate(-2, ''bcrypt'', ''bassword2'')
     when true then 1 else 0 end',
     1, 'BCRYPT AUTHENTICATION SHOULD HAVE PASSED(2)');




