\set show_rows 0
\unset ECHO
\set QUIET 1
\pset format unaligned
\pset tuples_only true
\pset pager off

\echo Setting up tables...
create table x as select * from veil2.privileges;
create table y as select * from veil2.privileges;
create table z as select * from veil2.privileges;
alter table y enable row level security;
alter table z enable row level security;
create policy x__select on y for select using (veil2.always_true(4));
create policy y__select on z for select using (veil2.i_have_global_priv(4));
grant select on x to demouser;
grant select on y to demouser;
grant select on z to demouser;
grant execute on function veil2.result_counts() to demouser;

\timing

\c vpd demouser
\echo connecting as Alice...
select *
      from veil2.create_session('Alice', 'bcrypt', 4, 1000) c
     cross join veil2.open_connection(c.session_id, 1, 'passwd1');
     
\echo running tests...
\echo ...on x (3 times)...
select count(*) from x;
select count(*) from x;
select count(*) from x;

\echo ...on y (3 times)...
select count(*) from y;
select count(*) from y;
select count(*) from y;

\echo result_counts (to keep us honest):
select * from veil2.result_counts();

\echo ...on z (3 times)...
select count(*) from z;
select count(*) from z;
select count(*) from z;

\echo result_counts again:
select * from veil2.result_counts();
