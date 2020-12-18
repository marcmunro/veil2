--  test_authent.sql
--
--     Unit tests for authentication mechanisms.
--
--     Copyright (c) 2020 Marc Munro
--     Author:  Marc Munro
--     License: GPL V3
--
-- Usage:  Called from test_veil2.sql
--

begin;
select '...test authentication functions...';

select plan(8);


-- Plaintext authentication is not enabled
select is((select 1 from veil2.authentication_types
            where shortname = 'plaintext' and not enabled),
       1, 'Expecting disabled plaintext authentication');

-- Authentication fails when authent_type is not enabled.
select is((select 
             case veil2.authenticate(-1, 'plaintext', 'password')
             when true then 1 else 0 end),
          0, 'Disabled plaintext authentication should have failed');

-- Allow plaintext authentication.
update veil2.authentication_types
   set enabled = true
 where shortname = 'plaintext';

select is((select 
             case veil2.authenticate(-1, 'plaintext', 'password')
             when true then 1 else 0 end),
          1, 'Plaintext authentication succeeds when enabled');

-- Authentication fails when password is incorrect
select is((select 
             case veil2.authenticate(-1, 'plaintext', 'password3')
	     when true then 1 else 0 end),
          0, 'Authentication fails with incorrect password');

select is((select 
             case veil2.authenticate(-1, 'unimplemented-authentication-type', 
                             	     'password')
	     when true then 1 else 0 end),
	  0, 'Authentication fails with invalid authentication type');

select is((select 
             case veil2.authenticate(-99, 'plaintext', 'password')
	     when true then 1 else 0 end),
          0, 'Authentication fails with invalid party');

-- Test bcrypt authentication - incorrect password
select is((select 
             case veil2.authenticate(-1, 'bcrypt', 'password')
	     when true then 1 else 0 end),
	  0, 'Bcrypt authentication fails with incorrect password'); 

select is((select 
             case veil2.authenticate(-1, 'bcrypt', 'bassword')
	     when true then 1 else 0 end),
	  1, 'Bcrypt authentication passes');

select * from finish();


/*
\set QUIET 0
\pset format aligned
\pset tuples_only false
*/


rollback;

