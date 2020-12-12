\set show_rows 0
\unset ECHO
\set QUIET 1
\pset format unaligned
\pset tuples_only true
\pset pager off

create extension if not exists pgtap;

\c vpd demouser

\echo Unconnected user tests...
begin;
select plan(6);

select is(cnt, 0,
          'Unconnected user sees no users')
  from (select count(*)::integer as cnt from users) x;

-- Insert not allowed
select throws_like(
           $$insert into users values (12, 'user12', 'passwd12')$$,
	   '%violates row-level%',
	   'Unconnected used cannot create users');

select is(cnt, 0,
          'Unconnected user sees no follower_types')
  from (select count(*)::integer as cnt from follower_types) x;

select is(cnt, 0,
          'Unconnected user sees no followers')
  from (select count(*)::integer as cnt from followers) x;

select is(cnt, 0,
          'Unconnected user sees no post_types')
  from (select count(*)::integer as cnt from post_types) x;

/*
select is(cnt, 0,
          'Unconnected user sees no posts')
  from (select count(*)::integer as cnt from posts) x;
*/
select * from finish();
rollback;

\echo admin/superuser user tests...
begin;
select plan(12);

with login as
  (
    select *
      from veil2.create_session('Alice', 'bcrypt') c
     cross join veil2.open_connection(c.session_id, 1, 'passwd_alice')
  )
select is(success, true,
          'Alice successfully logs in (with admin role')
  from login;

select is(cnt, 7,
          'Alice sees all users')
  from (select count(*)::integer as cnt from users) x;

with ins as
  (
    insert into users values (12, 'user12', 'passwd12')
    returning accessor_id
  )
select is(accessor_id, 12, 'Alice can insert new user')
  from ins;

select is(password, 'xxxx', 'New user password is hidden')
  from users
 where accessor_id = 12;

select is(cnt, 0, 'Alice cannot see new accessor record')
  from (select count(*)::integer as cnt
          from veil2.accessors
	 where accessor_id = 12) x;

select is(cnt, 0, 'Alice cannot see authentication details record')
  from (select count(*)::integer as cnt
          from veil2.authentication_details
	 where accessor_id = 12) x;

select is(cnt, 3,
          'Alice sees  follower_types')
  from (select count(*)::integer as cnt from follower_types) x;

select is(cnt, 2,
          'Alice sees  followers')
  from (select count(*)::integer as cnt from followers) x;

with login as
  (
    select *
      from veil2.create_session('Carol', 'bcrypt') c
     cross join veil2.open_connection(c.session_id, 1, 'passwd_carol')
  )
select is(success, true,
          'Carol successfully logs in (with superuser role')
  from login;

select is(cnt, 8,   -- One more user than before
          'Carol sees all users')
  from (select count(*)::integer as cnt from users) x;

select is(cnt, 1, 'Carol can see new accessor record')
  from (select count(*)::integer as cnt
          from veil2.accessors
	 where accessor_id = 12) x;

select is(cnt, 1, 'Carol can see authentication details record')
  from (select count(*)::integer as cnt
          from veil2.authentication_details
	 where accessor_id = 12) x;


select * from finish();
rollback;

\echo ordinary user tests...
begin;
select plan(3);

with login as
  (
    select *
      from veil2.create_session('Bob', 'bcrypt') c
     cross join veil2.open_connection(c.session_id, 1, 'passwd_bob')
  )
select is(success, true,
          'Bob successfully logs in (with only connect role')
  from login;

select is(cnt, 1,   -- Bob only sees himself
          'Bob sees only himself')
  from (select count(*)::integer as cnt from users) x;

with upd as
  (
    update users
       set password = 'wibble'
     where accessor_id = (
        select accessor_id
	  from veil2.session_context())
    returning accessor_id
  )
select is(cnt, 1, 
          'Bob updates password')
  from (select count(*)::integer cnt from upd) x;

with login as
  (
    select *
      from veil2.create_session('Bob', 'bcrypt') c
     cross join veil2.open_connection(c.session_id, 1, 'passwd_bob')
  )
select is(success, false,
          'Bob cannot log in with old password')
  from login;

with login as
  (
    select *
      from veil2.create_session('Bob', 'bcrypt') c
     cross join veil2.open_connection(c.session_id, 1, 'wibble')
  )
select is(success, true,
          'Bob logs in with new password')
  from login;

select is(cnt, 3,
          'Bob sees follower_types')
  from (select count(*)::integer as cnt from follower_types) x;

select is(cnt, 2,
          'Bob sees followers')
  from (select count(*)::integer as cnt from followers) x;

with ins as
  (
    insert
      into followers
           (follower_type_id, follower, follows)
    values (1, 2, 5)
    returning follower
  )
select is(cnt, 1,
          'Bob can follow others')
  from (select count(*)::integer as cnt from ins) x;

select throws_like(
           $$insert into followers (follower_type_id, follower, follows)
    	     values (1, 3, 2) $$,
	   '%violates row-level%',
	   'Bob cannot insert a follower for himself.');

with login as
  (
    select *
      from veil2.create_session('Eve', 'bcrypt') c
     cross join veil2.open_connection(c.session_id, 1, 'passwd_eve')
  )
select is(success, true,
          'Eve successfully logs in (with only connect role')
  from login;

select is(cnt, 1,
          'Eve sees single follower (Bob)')
  from (select count(*)::integer as cnt from followers) x;

with ins as
  (
    insert
      into followers
           (follower_type_id, follower, follows)
    values (2, 5, 2)
    returning follower
  )
select is(cnt, 1,
          'Eve can follow Bob')
  from (select count(*)::integer as cnt from ins) x;


select * from finish();
rollback;

\pset tuples_only false
\pset format aligned
