-- TODO:
-- test privileges after failed open
-- test i_have_priv_in_superior_scope()
--      and access to veil2.context_roles in various contexts
-- test use of personal_context access rights




\echo ...checking basic veil2 session handling...
  
\echo .....reset_session()...
-- Perform a reset session without returning a row.  This ensures the
-- temporary table is created.
with reset_session as
  (
    select 1 as result from veil2.reset_session()
  )
select null
  from reset_session
 where result != 1;

select null where test.expect(
    (select count(*) from session_parameters)::integer,
    0, 'Expecting empty session_parameters table');

insert into session_parameters(accessor_id) values (1);

-- Ensure that we can see the inserted session record.
select null where test.expect(
    (select count(*) from session_parameters)::integer,
    1, 'Expecting 1 session_parameters row');

-- Test that resetting session causes session_parameters record to be
-- removed.

with reset_session as
  (
    select 1 as result from veil2.reset_session()
  )
select null
  from reset_session
 where result != 1;

select null where test.expect(
    (select count(*) from session_parameters)::integer,
    0, 'Expecting empty session_parameters table (2)');


\echo .....create_session()...
-- Invalid username and authentication type, still yields
-- result data that looks feasible.
with session as (select * from veil2.create_session('gerry', 'wibble'))
select null
  from session
 where test.expect((session.session_id is not null),
                   true, 'Session id should have been returned')
    or test.expect((session.session_token is not null),
                   true, 'Session token should have been returned');

-- Check that session_parameters are defined but there is no actual
-- session created following the above create_session() call.
with session_params as
  (
    select *
      from session_parameters
  ),
sessions as
  (
    select sp.session_id as reported_session_id, s.session_id
      from session_parameters sp
     left outer join veil2.sessions s
        on s.session_id = sp.session_id
  )
select null
  from sessions
 where test.expect((reported_session_id is null), false,
                   'There should be a reported session_id')
    or test.expect((session_id is null), true,
                   'There should not be an actual session_id');

-- Invalid authentication type with vailid accessor yields
-- a valid session that will subsequently not open
with session as (select * from veil2.create_session('eve', 'wibble'))
select null
  from session
 where test.expect((session.session_id is not null),
                   true, 'Session id should have been returned(2)')
    or test.expect((session.session_token is not null),
                   true, 'Session token should have been returned(2)');

with session_params as
  (
    select *
      from session_parameters
  ),
sessions as
  (
    select sp.session_id as reported_session_id, s.session_id
      from session_parameters sp
     left outer join veil2.sessions s
        on s.session_id = sp.session_id
  )
select null
  from sessions
 where test.expect((reported_session_id is null), false,
                   'There should be a reported session_id(2)')
    or test.expect((session_id is null), false,
                   'There should be an actual session_id(2)');


\echo .....open_connection()...
-- We have a created session from the last tests above.  Now we will try
-- opening that session.  Given that the authentication method was
-- invalid, we expect appropriate failures.

with session_params as
  (
    select *
      from session_parameters
  ),
session as
  (
    select os.*
      from session_parameters sp
     cross join veil2.open_connection(sp.session_id, 1, 'wibble') os
  )
select null
  from session s
 where test.expect(s.success, false, 'Authentication should have failed(1)')
    or test.expect(s.errmsg, 'AUTHFAIL',
       		   'Authentication message should be AUTHFAIL(1)');

-- Try creating and opening a session with valid credentials but no
-- connect privilege.
with session as
  (
    select o.*
      from veil2.create_session('fred', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password') o
  )
select null
  from session s
 where test.expect(s.success, false, 'Authentication should have failed(2)')
    or test.expect(s.errmsg, 'AUTHFAIL',
       		   'Authentication message should be AUTHFAIL(2)');

-- Try creating and opening a session with valid credentials and
-- connect privilege - to establish that this works before the next test.
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select null
  from session s
 where test.expect(s.success, true, 'Authentication should have succeeded')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message');

-- Record the first session_id in a temp table.
create temporary table mytest_session (
  session_id1 integer, session_id2 integer);

insert into mytest_session (session_id1)
select session_id from session_parameters;

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
select null
  from session s
 where test.expect(s.success, true, 'Authentication should have succeeded (2)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message (2)');


-- Create another valid session - this one for accessor -6
with session as
  (
    select o.*
      from veil2.create_session('alice', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password6') o
  )
select null
  from session s
 where test.expect(s.success, true, 'Authentication should have succeeded(2)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message(2)');

-- Record the second session_id.
update mytest_session
   set session_id2 = (select session_id from session_parameters);

-- Switch to the original session
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 3,
        encode(digest(s.token || to_hex(3), 'sha1'), 'base64')) o
  )
select null
  from session s
 where test.expect(s.success, true,
                  'Authentication should have succeeded (3)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message (3)');

-- Switch to the second session
with session as
  (
    select o.*, ms.session_id2 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id2 
     cross join veil2.open_connection(ms.session_id2, 2,
        encode(digest(s.token || to_hex(2), 'sha1'), 'base64')) o
  )
select null
  from session s
 where test.expect(s.success, true,
                  'Authentication should have succeeded (4)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message (4)');

\echo .....open_connection(checking nonce handling)...
-- Attempt to switch to the original session with a reused nonce
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     cross join veil2.open_connection(ms.session_id1, 3, 'password2') o
  )
select null
  from session s
 where test.expect(s.success, false,
                  'Authentication should have failed (5)')
    or test.expect(s.errmsg, 'NONCEFAIL',
       		   'There should be a NONCEFAIL message (5)');

-- Again with a valid nonce
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 5,
        encode(digest(s.token || to_hex(5), 'sha1'), 'base64')) o
  )
select null
  from session s
 where test.expect(s.success, true,
                  'Authentication should have succeeded (6)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message (6)');

-- Again with a valid nonce lower than the last
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 4,
        encode(digest(s.token || to_hex(4), 'sha1'), 'base64')) o
  )
select null
  from session s
 where test.expect(s.success, true,
                  'Authentication should have succeeded (7)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message (7)');

-- Again with a valid nonce but significantly larger
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     cross join veil2.open_connection(ms.session_id1, 300, 'password2') o
  )
select null
  from session s
 where test.expect(s.success, false,
                  'Authentication should have failed (8)')
    or test.expect(s.errmsg, 'NONCEFAIL',
       		   'There should be a NONCEFAIL message (8)');


-- Again with a valid nonce but slightly larger
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 364,
        encode(digest(s.token || to_hex(364), 'sha1'), 'base64')) o
  )
select null
  from session s
 where test.expect(s.success, true,
                  'Authentication should have succeeded (9)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message (9)');

-- Ditto
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 427,
        encode(digest(s.token || to_hex(427), 'sha1'), 'base64')) o
  )
select null
  from session s
 where test.expect(s.success, true,
                  'Authentication should have succeeded (10)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message (10)');

-- Again
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 480,
        encode(digest(s.token || to_hex(480), 'sha1'), 'base64')) o
  )
select null
  from session s
 where test.expect(s.success, true,
                  'Authentication should have succeeded (11)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message (11)');

-- ...while we are here, let's ensure that we have some privileges.
select null
 where test.expect(veil2.i_have_global_priv(0), true,
       		   'Session should have connect privilege');

-- Last time - should be forgetting those early nonces by now
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     inner join veil2.sessions s on s.session_id = ms.session_id1 
     cross join veil2.open_connection(ms.session_id1, 540,
        encode(digest(s.token || to_hex(540), 'sha1'), 'base64')) o
  )
select null
  from session s
 where test.expect(s.success, true,
                  'Authentication should have succeeded (12)')
    or test.expect(s.errmsg is null, true,
       		   'There should be no error message (12)');

-- Now with an unused nonce that is too low
with session as
  (
    select o.*, ms.session_id1 as session_id
      from mytest_session ms
     cross join veil2.open_connection(ms.session_id1, 17, 'password2') o
  )
select null
  from session s
 where test.expect(s.success, false,
                  'Authentication should have failed (13)')
    or test.expect(s.errmsg, 'NONCEFAIL',
       		   'There should be a NONCEFAIL message (13)');

-- ...while we are here, let's ensure that we no longer have privileges.
select null
 where test.expect(veil2.i_have_global_priv(0), false,
       		   'Session should not have connect privilege');

\echo ...close_connection()...
select null
  from veil2.create_session('alice', 'plaintext') c
 cross join veil2.open_connection(c.session_id, 1, 'password6') o
 where not o.success;   -- Ensure no rows returned

select null
 where test.expect(veil2.i_have_global_priv(0), true,
       		   'Session should have connect privilege(2)');

select null
  from veil2.close_connection()
 where not close_connection;  -- Ensure no rows returned

select null
 where test.expect(veil2.i_have_global_priv(0), false,
       		   'Session should not have connect privilege(2)');

\echo ...checking dbuser-based session handling...
-- Get host and port info so we can connect as alice
select '##' as ignore,  -- Allows the output of this query to be filtered
       '"user=veil2_alice password=xyzzy host="' ||
       case when c.host like '/%' then '127.0.0.1'
       else c.host end ||
       ' port=' || port ||
       ' dbname=' || dbname || '"' as connector,
       '"user=' || :'USER' ||
       ' host=' || c.host ||
       ' port=' || c.port || 
       ' dbname=' || dbname || '"' as old_connector
  from (select :'HOST'::text as host, :PORT::text as port,
        :'DBNAME'::text as dbname) c; \gset
  
\c :connector

-- We should now be connected as veil2_alice, which is equivalent to
-- accessor -2

select null where not veil2.hello();  -- Establish our session

\echo ......checking visibility of veil2 objects...

with rowexists (x) as
  (
    select 1
      from veil2.scope_types
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from scope_types');

with rowexists (x) as
  (
    select 1
      from veil2.scopes
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from scopes');

with rowexists (x) as
  (
    select 1
      from veil2.privileges
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from privileges');

with rowexists (x) as
  (
    select 1
      from veil2.role_types
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from role_types');

with rowexists (x) as
  (
    select 1
      from veil2.roles
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from roles');

with rowexists (x) as
  (
    select 1
      from veil2.context_roles
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from context_roles');

with rowexists (x) as
  (
    select 1
      from veil2.role_privileges
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from role_privileges');

with rowexists (x) as
  (
    select 1
      from veil2.role_roles
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from role_roles');

with rowexists (x) as
  (
    select 1
      from veil2.accessors
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from accessors');

with rowexists (x) as
  (
    select 1
      from veil2.authentication_types
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from authentication_types');

with rowexists (x) as
  (
    select 1
      from veil2.authentication_details
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from authentication_details');

with rowexists (x) as
  (
    select 1
      from veil2.accessor_roles
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from accessor_roles');

with rowexists (x) as
  (
    select 1
      from veil2.sessions
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from sessions');

with rowexists (x) as
  (
    select 1
      from veil2.system_parameters
     limit 1),
rowcount (x) as
  (
    select count(*)::integer
      from rowexists
  )
select null
  from rowcount
 where test.expect(x, 1, 'Expect to see rows from system_parameters');


-- Reconnect as default user
\echo :old_connector
\c :old_connector

\echo ...context in session handling...

\echo .....create and open session(invalid context)...
-- Invalid context.  Authentication will fail.
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext', -3, -31) c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select null
  from session s
 where test.expect(s.success, false, 'Authentication should have failed')
    or test.expect(s.errmsg, 'AUTHFAIL',
       		   'Authentication message should be AUTHFAIL(3)');

-- Make the context a valid one
create or replace
view veil2.accessor_contexts (
  accessor_id, context_type_id, context_id
) as
select accessor_id, 1, 0
  from veil2.accessors
 union all select -2, -3, -31  -- Give Eve two authentication contexts
 union all select -2, -3, -3;

-- Now we should have connect privilege.  Authentication should succeed.
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext', -3, -31) c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select null
  from session s
 where test.expect(s.success, true, 'Authentication should not have failed');


\echo ...become_user()...

-- Modify user -2 (eve) to have role 7 (almost superuser) and connect
delete from veil2.accessor_roles where accessor_id = -2 and role_id = 1;
insert into veil2.accessor_roles
       (accessor_id, role_id, context_type_id, context_id)
values (-2, 7, 1, 0);

-- Check that Bob (-5) authenticates and has some expected privileges
with session as
  (
    select o.*
      from veil2.create_session('bob', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password5') o
  )
select null
  from session s
 where test.expect(s.success, true, 'Bob should be authenticated');

select null
 where test.expect(veil2.i_have_priv_in_scope(20, -5, -51), true,
       'Bob should have priv 20 in context -5,-51')
    or test.expect(veil2.i_have_priv_in_scope(21, -5, -51), true,
       'Bob should have priv 21 in context -5,-51')
    or test.expect(veil2.i_have_priv_in_scope(23, -5, -51), true,
       'Bob should have priv 23 in context -5,-51')
    or test.expect(veil2.i_have_priv_in_scope(24, -5, -51), true,
       'Bob should have priv 24 in context -5,-51')
     or test.expect(veil2.i_have_priv_in_scope(25, -4, -41), true,
       'Bob should have priv 25 in context -4,-41');

-- connect as eve
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext') c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select null
  from session s
 where test.expect(s.success, true, 'Eve should be authenticated');

--select 'EVE:';
--select session_id, scope_type_id, scope_id,
--       to_array(roles), to_array(privs)
--  from session_privileges
-- order by 1, 2, 3;


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
    --select * from veil2.become_accessor(-5, 1, 0)
  )
insert into session_tt select * from session;

select null
  from session_tt s
 where test.expect(s.success, true, 'Eve should now be Bob');
 
select null
  from session_parameters
 where test.expect(accessor_id, -5, 'Eve should now have Bob'' accessor_id');
 
-- Check Eve-as-Bob's privs: should be mostly the same but without
-- priv 20 which Eve did not have.

select null
 where test.expect(veil2.i_have_priv_in_scope(20, -5, -51), false,
       'Bob should not have priv 20 in context -5,-51')
    or test.expect(veil2.i_have_priv_in_scope(21, -5, -51), true,
       'Bob should have priv 21 in context -5,-51 (2)')
    or test.expect(veil2.i_have_priv_in_scope(23, -5, -51), true,
       'Bob should have priv 23 in context -5,-51 (2)')
    or test.expect(veil2.i_have_priv_in_scope(24, -5, -51), true,
       'Bob should have priv 24 in context -5,-51 (2)')
     or test.expect(veil2.i_have_priv_in_scope(25, -4, -41), true,
       'Bob should have priv 25 in context -4,-41 (2)');

\echo ......continuation...
select o.errmsg
  from session_tt
 cross join veil2.open_connection(session_id, 2,
              encode(digest(session_token || to_hex(2), 'sha1'),
	             'base64')) o
 where test.expect(o.success, true, 'Bob''s session should have continued');

\echo ...contextual role mapppings...

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
   set parameter_value = '3'
 where parameter_name = 'mapping context target scope type';

-- connect as eve for scope -3,-3
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext', -3, -3) c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select null
  from session s
 where test.expect(s.success, true, 'Eve should be authenticated (2)');

-- Ensure Eve has roles for scope -3, -3 but not -3, -31
select null
  from session_privileges
 where scope_type_id = -3
   and (   test.expect(scope_id, -3,
               'Eve should only have corp assignments in scope -3')
	or test.expect(roles ? 5, true,
	       'Eve should have role 5')
	or test.expect(roles ? 6, true,
	       'Eve should have role 6')
	or test.expect(roles ? 8, true,
	       'Eve should have role 6')
	or test.expect(roles ? 9, false,
	       'Eve should not have role 9'));
 
/*
select 'EVE: -3, -3';
select session_id, scope_type_id, scope_id,
       to_array(roles), to_array(privs)
  from session_privileges
 order by 1, 2, 3;
*/
-- connect as eve for scope -3,-31
with session as
  (
    select o.*
      from veil2.create_session('eve', 'plaintext', -3, -31) c
     cross join veil2.open_connection(c.session_id, 1, 'password2') o
  )
select null
  from session s
 where test.expect(s.success, true, 'Eve should be authenticated (3)');

-- Ensure Eve has roles for scope -3, -31 but not -3, -3
select null
  from session_privileges
 where scope_type_id = -3
   and (   test.expect(scope_id, -31,
               'Eve should only have corp assignments in scope -31')
	or test.expect(roles ? 5, false,
	       'Eve should not have role 5')
	or test.expect(roles ? 6, true,
	       'Eve should have role 6')
	or test.expect(roles ? 7, true,
	       'Eve should have role 7')
	or test.expect(roles ? 9, true,
	       'Eve should have role 7'));


/*
\pset format aligned
\pset tuples_only false

select 'EVE: -3, -31';
select session_id, scope_type_id, scope_id,
       to_array(roles), to_array(privs)
  from session_privileges
 order by 1, 2, 3;
select *
  from veil2.privilege_assignments
 where accessor_id = -2;
*/
