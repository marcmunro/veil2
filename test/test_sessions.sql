--  test_sessions.sql
--
--     Unit tests for Veil2 session handling. 
--
--     Copyright (c) 2020 Marc Munro
--     Author:  Marc Munro
--     License: GPL V3
--
-- Usage:  Called from test_veil2.sql
--

-- TODO:
-- test privileges after close

create view apc as select * from veil2.accessor_privileges_cache;
grant select on veil2.accessor_privileges_cache to public;
grant select on apc to public;


begin;
select '...test veil2 session handling...';

create view session_context as
select * from veil2.session_context()
 where accessor_id is not null;

grant select on session_context to public;

select plan(107);

-- Perform a reset session without returning a row.  This ensures the
-- temporary table is created.
with reset_session as
  (
    select 1 as result from veil2.reset_session()
  )
select null
  from reset_session
 where result != 1;

select is((select count(*) from session_context)::integer,
           0, 'Expecting empty session_context');

--insert into veil2_session_context(accessor_id) values (1);

select *
  from veil2.session_context(1, 2, 3, 4, 5, 6, 7, 8)
 where accessor_id != 1;

-- Ensure that we can see the inserted session record.
select is((select count(*) from session_context)::integer,
          1, 'Expecting session_context record');

-- Test that resetting session causes veil2_session_context record to be
-- removed.
with reset_session as
  (
    select 1 as result from veil2.reset_session()
  )
select null
  from reset_session
 where result != 1;

-- Create_session
select is((select count(*) from session_context)::integer,
           0, 'Expecting empty session_context table(2)');

with session as (select * from veil2.create_session('gerry', 'wibble'))
select is ((session_id is not null),
           true, 'create_session() returns session id')
  from session
union all
select is((session_token is not null),
          true, 'create_session() returns session token')
  from session
union all
select is(cnt, 0, 'No session context created for invalid session')
  from (select count(*)::integer cnt
          from session_context) x
union all
select is(cnt, 0, 'No session record created for invalid session')
  from (select count(*)::integer cnt
          from session s
	 inner join veil2.sessions vs
	    on vs.session_id = s.session_id) x;

-- Invalid authentication type with valid accessor yields
-- a session that will subsequently not open
with session as (select * from veil2.create_session('eve', 'wibble'))
select is((session.session_id is not null),
          true, 'Session id should have been returned(2)')
 from session
union all
select is((session.session_token is not null),
          true, 'Session token should have been returned(2)')
 from session;

with sessions as
  (
    select sp.session_id as reported_session_id, s.session_id
      from session_context sp
     left outer join veil2.sessions s
        on s.session_id = sp.session_id
  )
select is((reported_session_id is null), false,
          'There should be a reported session_id(2)')
  from sessions
 union all
select is((session_id is null), false,
           'There should not be an actual session_id(2)')
  from sessions;

-- We have a created session from the last tests above.  Now we will try
-- opening that session.  Given that the authentication method was
-- invalid, we expect appropriate failures.
create temporary table prev_context as
select * from session_context;

with session as
  (
    select os.*
      from prev_context pc
     cross join veil2.open_connection(pc.session_id, 1, 'wibble') os
  )
select is(success, false, 'Authentication should have failed(1)')
  from session
union all
select is(errmsg, 'AUTHFAIL',
       	  'Authentication message should be AUTHFAIL(1)')
  from session;

-- Try creating and opening a session with valid credentials but no
-- connect privilege.
with session as
  (
    select o.*
      from veil2.create_session('fred', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password') o
  )
select is(success, false, 'Authentication should have failed(2)')
  from session 
union all
select is(errmsg, 'AUTHFAIL',
       	  'Authentication message should be AUTHFAIL(2)')
  from session;


-- Allow plaintext authentication.
update veil2.authentication_types
   set enabled = true
 where shortname = 'plaintext';

-- Try creating and opening a session with valid credentials and
-- connect privilege - to establish that this works before the next
-- test.

with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select is(success, true, 'Authentication should have succeeded')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message')
  from session;


-- Record the first session_id in a temp table.
create temporary table mytest_session (
  session_id1 integer, session_id2 integer);

insert into mytest_session (session_id1)
select session_id from session_context;

-- Disconnect and reconnect the above session.  Since this is a
-- continuation of an existing session, we use the continuation
-- authentication mechanism.
with reset_session as
  (
    select 1 as result from veil2.reset_session()
  )
select null
  from reset_session
 where result != 1;

with session as
  (
    select o.*, ms.session_id1
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 2,
        encode(digest(s.token || to_hex(2), 'sha1'), 'base64')) o
  )
select is(success, true, 'Authentication should have succeeded (2)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message (2)')
  from session;

-- Create another valid session - this one for accessor -6
with session as
  (
    select o.*
      from veil2.create_session('alice', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password6') o
  )
select is(success, true, 'Authentication should have succeeded(2)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message(2)')
  from session;

-- Record the second session_id.
update mytest_session
   set session_id2 = (select session_id from session_context);

-- Switch to the original session
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 3,
        encode(digest(s.token || to_hex(3), 'sha1'), 'base64')) o
  )
select is(success, true,
          'Authentication should have succeeded (3)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message (3)')
  from session;

-- Switch to the second session
with session as
  (
    select o.*, ms.session_id2 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id2 
     cross join veil2.open_connection(ms.session_id2, 2,
        encode(digest(s.token || to_hex(2), 'sha1'), 'base64')) o
  )
select is(success, true,
          'Authentication should have succeeded (4)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message (4)')
  from session;

-- Attempt to switch to the original session with a reused nonce
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     cross join veil2.open_connection(ms.session_id1, 3, 'password2') o
  )
select is(success, false,
          'Authentication should have failed (5)')
  from session
union all
select is(errmsg, 'NONCEFAIL',
       	  'There should be a NONCEFAIL message (5)')
  from session;

-- Again with a valid nonce
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 5,
        encode(digest(s.token || to_hex(5), 'sha1'), 'base64')) o
  )
select is(success, true,
          'Authentication should have succeeded (6)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message (6)')
  from session;

-- Again with a valid nonce lower than the last
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 4,
        encode(digest(s.token || to_hex(4), 'sha1'), 'base64')) o
  )
select is(success, true,
          'Authentication should have succeeded (7)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message (7)')
  from session;

-- Again with a valid nonce but significantly larger
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     cross join veil2.open_connection(ms.session_id1, 300, 'password2') o
  )
select is(success, false,
          'Authentication should have failed (8)')
  from session
union all
select is(errmsg, 'NONCEFAIL',
       	  'There should be a NONCEFAIL message (8)')
  from session;

-- Again with a valid nonce but slightly larger
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 364,
        encode(digest(s.token || to_hex(364), 'sha1'), 'base64')) o
  )
select is(success, true,
          'Authentication should have succeeded (9)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message (9)')
  from session;

-- Ditto
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 427,
        encode(digest(s.token || to_hex(427), 'sha1'), 'base64')) o
  )
select is(success, true,
          'Authentication should have succeeded (10)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message (10)')
  from session;

-- Again
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 480,
        encode(digest(s.token || to_hex(480), 'sha1'), 'base64')) o
  )
select is(success, true,
          'Authentication should have succeeded (11)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message (11)')
  from session;

-- ...while we are here, let's ensure that we have some privileges.
select is(veil2.i_have_global_priv(0), true,
       	  'Session should have connect privilege(1)');

select is(veil2.i_have_priv_in_scope_or_global(0, 9, 9), true,
       	  'Session should have connect privilege(2)');

select is(veil2.i_have_priv_in_scope_or_superior_or_global(0, 9, 9), true,
       	  'Session should have connect privilege(3)');

-- Last time - should be forgetting those early nonces by now
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 540,
        encode(digest(s.token || to_hex(540), 'sha1'), 'base64')) o
  )
select is(success, true,
          'Authentication should have succeeded (12)')
  from session
union all
select is(errmsg is null, true,
       	  'There should be no error message (12)')
  from session;

-- Now with an unused nonce that is too low
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     cross join veil2.open_connection(ms.session_id1, 17, 'password2') o
  )
select is(success, false,
         'Authentication should have failed (13)')
  from session
union all
select is(errmsg, 'NONCEFAIL',
       	  'There should be a NONCEFAIL message (13)')
  from session;

-- ...while we are here, let's ensure that we no longer have privileges.
select is(veil2.i_have_global_priv(0), false,
       	  'Session should not have connect privilege');

-- Check close_session()
select null
  from veil2.create_session('alice', 'plaintext') c
 cross join veil2.open_connection(c.session_id, 1, 'password6') o
 where not o.success;   -- Ensure no rows returned to make output untidy

select is(veil2.i_have_global_priv(0), true,
       	  'Open session should have connect privilege');

select null
  from veil2.close_connection()
 where not close_connection;  -- Ensure no rows returned

select is(veil2.i_have_global_priv(0), false,
       	  'Closed session should not have connect privilege');

-- Check dbuser-based session handling

-- Get host and port info so we can connect as alice

set session authorization veil2_alice;

select null where not veil2.hello();  -- Establish our session

select is(cnt > 0, true, 'Expect to see rows from scope_types')
  from (select count(*)::integer as cnt
          from veil2.scope_types) x;

select is(cnt > 0, true, 'Expect to see rows from scopes')
  from (select count(*)::integer as cnt
          from veil2.scopes) x;

select is(cnt > 0, true, 'Expect to see rows from privileges')
  from (select count(*)::integer as cnt
          from veil2.privileges) x;

select is(cnt > 0, true, 'Expect to see rows from role_types')
  from (select count(*)::integer as cnt
          from veil2.role_types) x;

select is(cnt > 0, true, 'Expect to see rows from roles')
  from (select count(*)::integer as cnt
          from veil2.roles) x;

select is(cnt > 0, true, 'Expect to see rows from context_roles')
  from (select count(*)::integer as cnt
          from veil2.context_roles) x;

select is(cnt > 0, true, 'Expect to see rows from role_privileges')
  from (select count(*)::integer as cnt
          from veil2.role_privileges) x;

select * -- call reload_xxx without returning a row.
  from veil2.reload_connection_privs()
 where reload_connection_privs is null;

select is(cnt > 0, true, 'Expect to see rows from role_roles')
  from (select count(*)::integer as cnt
          from veil2.role_roles) x;

select is(cnt > 0, true, 'Expect to see rows from accessors')
  from (select count(*)::integer as cnt
          from veil2.accessors) x;

select is(cnt > 0, true, 'Expect to see rows from authentication_types')
  from (select count(*)::integer as cnt
          from veil2.authentication_types) x;

select is(cnt > 0, true, 'Expect to see rows from authentication_details')
  from (select count(*)::integer as cnt
          from veil2.authentication_details) x;

select * -- call reload_xxx without returning a row.
  from veil2.reload_connection_privs()
 where reload_connection_privs is null;

select is(cnt > 0, true, 'Expect to see rows from accessor_roles')
  from (select count(*)::integer as cnt
          from veil2.accessor_roles) x;

select is(cnt > 0, true, 'Expect to see rows from sessions')
  from (select count(*)::integer as cnt
          from veil2.sessions) x;

select is(cnt > 0, true, 'Expect to see rows from system_parameters')
  from (select count(*)::integer as cnt
          from veil2.system_parameters) x;

-- Return to previous session connection
reset session authorization;

-- check handling of context in session handling...

-- Invalid context.  Authentication will fail.
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext', -3, -31) c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select is(success, false, 'Authentication should have failed (invalid context)')
  from session
union all
select is(errmsg, 'AUTHFAIL',
       	  'Authentication message should be AUTHFAIL(3)')
  from session;

-- Make the context a valid one
create or replace
view veil2.my_accessor_contexts (
  accessor_id, context_type_id, context_id
) as
select accessor_id, 1, 0
  from veil2.accessors
 union all select -2, -3, -31  -- Give Eve two authentication contexts
 union all select -2, -3, -3;

select *
  from veil2.init()
 where init is null;

-- Now we should have connect privilege.  Authentication should succeed.
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext', -3, -31) c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select is(success, true, 'Authentication should not have failed')
  from session;

-- become_user...
-- Modify user -2 (eve) to have role 7 (almost superuser) and connect
delete from veil2.accessor_roles where accessor_id = -2 and role_id = 1;
insert into veil2.accessor_roles
       (accessor_id, role_id, context_type_id, context_id)
values (-2, 7, 1, 0),
       (-5, 0, 1, 0); -- Bob also needs connect

-- Check that Bob (-5) authenticates and has some expected privileges
with session as
  (
    select o.*
      from veil2.create_session('bob', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password5') o
  )
select is(success, true, 'Bob should be authenticated (global login)')
  from session;

select is(veil2.i_have_priv_in_scope(20, -5, -51), true,
          'Bob should have priv 20 in context -5,-51')
union all
select is(veil2.i_have_priv_in_scope_or_global(21, -5, -51), true,
         'Bob should have priv 21 in context -5,-51 (2)')
union all
select is(veil2.i_have_priv_in_scope_or_superior_or_global(21, -5, -51), true,
         'Bob should have priv 21 in context -5,-51 (3)')
union all
select is(veil2.i_have_priv_in_scope(23, -5, -51), true,
         'Bob should have priv 23 in context -5,-51')
union all
select is(veil2.i_have_priv_in_scope(24, -5, -51), true,
         'Bob should have priv 24 in context -5,-51')
union all
select is(veil2.i_have_priv_in_scope(25, -4, -41), true,
         'Bob should have priv 25 in context -4,-41');

-- connect as eve
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select is(success, true, 'Eve should be authenticated (global)')
  from session;

select is(accessor_id, -2, 'Eve''s accessor_id is Eve')
  from session_context;

-- eve becomes bob
-- Need to record the session_token for later use.
create temporary table session_tt (
  session_id integer,
  session_token text,
  success boolean,
  errmsg text);

with session as
  (
    select * from veil2.become_user('bob', 1, 0)
  )
insert into session_tt select * from session;
select is(success, true, 'Eve should have successully become Bob')
  from session_tt;


select is(accessor_id, -9, 'Bob''s accessor_id is Eve')
  from session_context
 where login_context_type_id is null;

-- Check Eve-as-Bob's privs: should be mostly the same but without
-- priv 20 which Eve did not have.
select is(veil2.i_have_priv_in_scope(20, -5, -51), false,
         'Bob should not have priv 20 in context -5,-51')
union all
select is(veil2.i_have_priv_in_scope(21, -5, -51), true,
          'Bob should have priv 21 in context -5,-51 (2)')
union all
select is(veil2.i_have_priv_in_scope(23, -5, -51), true,
          'Bob should have priv 23 in context -5,-51 (2)');

select * -- call reload_xxx without returning a row.
  from veil2.reload_connection_privs()
 where reload_connection_privs is null;
	  
select is(veil2.i_have_priv_in_scope(24, -5, -51), true,
          'Bob should have priv 24 in context -5,-51 (2)')
union all
select is(veil2.i_have_priv_in_scope(25, -4, -41), true,
          'Bob should have priv 25 in context -4,-41 (2)');

select is(accessor_id, -5, 'Eve should now have Bob''s accessor_id')
  from session_context;

-- ......continuation...
select is(o.success, true, 'Bob''s session should have continued')
  from session_tt
 cross join veil2.open_connection(session_id, 2,
              encode(digest(session_token || to_hex(2), 'sha1'),
	             'base64')) o;

-- Recheck Eve-as-Bob's privs: should be mostly the same but without
-- priv 20 which Eve did not have.
select is(veil2.i_have_priv_in_scope(20, -5, -51), false,
         'Bob should not have priv 20 in context -5,-51 again')
union all
select is(veil2.i_have_priv_in_scope(21, -5, -51), true,
          'Bob should have priv 21 in context -5,-51 (2) again')
union all
select is(veil2.i_have_priv_in_scope(23, -5, -51), true,
          'Bob should have priv 23 in context -5,-51 (2) again')
union all
select is(veil2.i_have_priv_in_scope(24, -5, -51), true,
          'Bob should have priv 24 in context -5,-51 (2) again')
union all
select is(veil2.i_have_priv_in_scope(25, -4, -41), true,
          'Bob should have priv 25 in context -4,-41 (2) again');

select is(accessor_id, -5, 'Eve should now have Bob''s accessor_id again')
  from session_context;


-- ...contextual role mapppings...
-- We will use eve with some new role assignments
delete from veil2.accessor_roles where accessor_id = -2;
insert into veil2.accessor_roles
       (accessor_id, role_id, context_type_id, context_id)
values (-2, 0, 1, 0),     -- global connect
       (-2, 5, -3, -3),   -- test_role_1
       (-2, 6, -3, -3),   -- test_role_2
       (-2, 6, -3, -31),  -- test_role_3
       (-2, 7, -3, -31);  -- test_role_3

-- Recreate role mappings for roles 5->9 in contexts
delete from veil2.role_roles where primary_role_id in (5,6,7,8,9);
insert into veil2.role_roles
       (primary_role_id, assigned_role_id, context_type_id, context_id)
values (6, 8, -3, -3),
       (6, 9, -3, -31);

-- Update target scope
update veil2.system_parameters
   set parameter_value = '-3'
 where parameter_name = 'mapping context target scope type';

-- Odd query structure so that no rows are returned but function is
-- called.
with init as
  (
    select 1 as result from veil2.init()
  )
select null
  from init
 where result != 1;


-- connect as eve for scope -3,-3
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext', -3, -3) c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select is(success, true, 'Eve should be authenticated (login -3, -3)')
  from session;


-- Ensure Eve has roles for scope -3, -3 but not -3, -31
with sess as
  (
    select *
      from veil2_session_privileges
     where scope_type_id = -3
  )
select is(1, (select count(*)::integer from sess),
          'Eve should only have corp assignments in one scope')
union all
select is(scope_id, -3,
          'Eve should only have corp assignments in scope -3')
  from sess
union all
select is(roles ? 5, true,
          'Eve should have role 5')
  from sess
union all
select is(roles ? 6, true,
          'Eve should have role 6')
  from sess
union all
select is(roles ? 8, true,
          'Eve should have role 8')
  from sess
union all
select is(roles ? 9, false,
          'Eve should not have role 9')
  from sess;


-- connect as eve for scope -3,-31
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext', -3, -31) c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select is(s.success, true, 'Eve should be authenticated (login -3, -31)')
  from session s;

select is(veil2.i_have_priv_in_superior_scope(4, -6, -62), true,
          'Eve should have priv 4 in a scope superior to -6, -62');

select is(veil2.i_have_priv_in_scope_or_superior(4, -6, -62), true,
          'Eve should have priv 4 in a scope superior to -6, -62 (1)');

select is(veil2.i_have_priv_in_scope_or_superior_or_global(4,-6, -62), true,
          'Eve should have priv 4 in a scope superior to -6, -62 (2)');

select is(veil2.i_have_priv_in_superior_scope(4, -6, -61), false,
          'Eve should not have priv 4 in a scope superior to -6, -61');

with sess as
  (
    select *
      from veil2_session_privileges
     where scope_type_id = -3
  )
select is(1, (select count(*)::integer from sess),
          'Eve should only have corp assignments in one scope')
union all
select is(scope_id, -31,
          'Eve should only have corp assignments in scope -31')
  from sess
union all
select is(roles ? 5, false,
          'Eve should not have role 5')
  from sess
union all
select is(roles ? 6, true,
          'Eve should have role 6')
  from sess
union all
select is(roles ? 7, true,
          'Eve should have role 7')
  from sess
union all
select is(roles ? 9, true,
          'Eve should have role 9')
  from sess;




select * from finish();

/*
\set QUIET 0
\pset format aligned
\pset tuples_only false
*/

rollback;
