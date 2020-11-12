\set show_rows 0
\unset ECHO
\set QUIET 1
\pset format unaligned
\pset tuples_only true
\pset pager off

\c vpd demouser

begin;

do
$$
begin
  if not exists (
      select null
        from pg_catalog.pg_extension
       where extname = 'pgtap')
  then
    execute 'create extension pgtap';
  end if;
end;
$$;

select plan(14);

-- Log Alice in.
\timing on
with login as
  (
    select *
      from veil2.create_session('Alice', 'bcrypt', 4, 1000) c
     cross join veil2.open_connection(c.session_id, 1, 'passwd1')
  )
select is(success, true,
          'Alice successfully logs in as a global superuser')
  from login;
\timing off

select is(cnt, 25,
          'Alice sees all parties')
  from (select count(*)::integer as cnt from demo.parties) x;

\if :show_rows
    \pset tuples_only false
    \pset format aligned
    select session_id, scope_type_id, scope_id,
           to_array(roles) as roles, to_array(privs) as privs
      from session_privileges ;

    select 'Alice sees: ', * from demo.parties;

    \pset format unaligned
    \pset tuples_only true
\endif


-- Log Bob in and continue his session with 2nd open_connection call
\timing on
with login as
  (
    select o2.success -- *
      from veil2.create_session('Bob', 'plaintext', 4, 1010) c
     cross join veil2.open_connection(c.session_id, 1, 'passwd2') o1
     cross join veil2.open_connection(c.session_id, 2,
                 encode(digest(c.session_token || to_hex(2), 'sha1'),
    	     	    'base64')) o2
  )
select is(success, true,
          'Bob successfully logs in as a superuser for secured corp')
  from login;
\timing off

select is(cnt, 13,
          'Bob sees all parties for secured corp')
  from (select count(*)::integer as cnt from demo.parties) x;

\if :show_rows
    \pset tuples_only false
    \pset format aligned
    select session_id, scope_type_id, scope_id,
           to_array(roles) as roles, to_array(privs) as privs
      from session_privileges ;

    select 'Bob sees: ', * from demo.parties;

    \pset format unaligned
    \pset tuples_only true
\endif


-- Log Carol in.
\timing on
with login as
  (
    select *
      from veil2.create_session('Carol', 'plaintext', 4, 1020) c
     cross join veil2.open_connection(c.session_id, 1, 'passwd3') o1
  )
select is(success, true,
          'Carol successfully logs in as a superuser for protected corp')
  from login;
\timing off

select is(cnt, 9,
          'Carol sees all parties for protected corp')
  from (select count(*)::integer as cnt from demo.parties) x;

\if :show_rows
    \pset tuples_only false
    \pset format aligned
    select session_id, scope_type_id, scope_id,
           to_array(roles) as roles, to_array(privs) as privs
      from session_privileges ;

    select 'Carol sees: ', * from demo.parties;

    \pset format unaligned
    \pset tuples_only true
\endif


-- Log Eve in.
\timing on
with login as
  (
    select *
      from veil2.create_session('Eve', 'plaintext', 4, 1000) c
     cross join veil2.open_connection(c.session_id, 1, 'passwd4') o1
   )
select is(success, true,
          'Eve successfully logs in as a superuser for both Corps')
  from login;
\timing off

select is(cnt, 23,
          'Eve sees all parties for both Corps')
  from (select count(*)::integer as cnt from demo.parties) x;


\if :show_rows
    \pset tuples_only false
    \pset format aligned
    select session_id, scope_type_id, scope_id,
           to_array(roles) as roles, to_array(privs) as privs
      from session_privileges ;

    select 'Eve sees: ', * from demo.parties;

    \pset format unaligned
    \pset tuples_only true
\endif

-- Log Sue in.
\timing on
with login as
  (
    select *
      from veil2.create_session('Sue', 'plaintext', 4, 1050) c
     cross join veil2.open_connection(c.session_id, 1, 'passwd5') o1
  )
select is(success, true,
          'Sue successfully logs in as a superuser for Dept S')
  from login;
\timing off

select is(cnt, 7,
          'Sue sees all parties for Dept S')
  from (select count(*)::integer as cnt from demo.parties) x;

\if :show_rows
    \pset tuples_only false
    \pset format aligned
    select session_id, scope_type_id, scope_id,
           to_array(roles) as roles, to_array(privs) as privs
      from session_privileges ;

    select 'Sue sees: ', * from demo.parties;

    \pset format unaligned
    \pset tuples_only true
\endif


-- Log Simon in.
\timing on
with login as
  (
    select *
      from veil2.create_session('Simon', 'plaintext', 4, 1050) c
     cross join veil2.open_connection(c.session_id, 1, 'passwd7') o1
  )
select is(success, true,
          'Sue successfully logs in as a Project Manager for Project S.1')
  from login;
\timing off
  
select is(cnt, 2,
          'Simon sees only himself and the org in parties')
  from (select count(*)::integer as cnt from demo.parties) x;

select is(cnt, 1,
          'Simon sees only the project he manages')
  from (select count(*)::integer as cnt from demo.projects) x;

select is(cnt, 3,
          'Simon sees only project_assignments for the project he manages')
  from (select count(*)::integer as cnt from demo.project_assignments) x;

\if :show_rows
    \pset tuples_only false
    \pset format aligned
    select session_id, scope_type_id, scope_id,
           to_array(roles) as roles, to_array(privs) as privs
      from session_privileges ;

    \echo ...Simon should see his own party record, and that of the org...
    select 'Simon sees: ', * from demo.parties;

    \echo ...Simon should see only the project he manages...
    select 'Simon sees: ', * from demo.projects;

    \echo ...Simon should see only assignments for the project he manages...
    select 'Simon sees: ', * from demo.project_assignments;

    \pset format unaligned
    \pset tuples_only true
\endif


select * from finish();

rollback;
\pset tuples_only false
\pset format aligned

