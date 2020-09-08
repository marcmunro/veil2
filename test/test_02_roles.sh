#! /bin/bash

echo "`basename $0 .sh` - Checking role handling -"
result=`psql -d vpd 2>&1 <<EOF 
\set ON_ERROR_STOP
\set QUIET
\pset tuples_only on

\echo ...checking roles and privileges...
-- (where clause is designed to return no rows in order to keep output clean
select 99 where 99 = test.expect_n(
    'select (select count(*) 
               from veil2.all_role_roles 
              where primary_role_id = 1
                and context_id is null) - 
            (select count(*) 
               from veil2.roles 
              where role_id > 1 
                and not implicit)', 0, 
    'Superuser roles count should be all enabled roles (except connect)');

\echo ...check recursive role assignents...
select 99 where 99 = test.expect_n(
    'select count(*)
       from veil2.all_role_roles grr
      inner join veil2.roles rp
         on rp.role_id = grr.primary_role_id
      where rp.role_name = ''test_role_1''', 7, 
    'test_role_1 should have 7 roles');

\echo ...checking superuser privileges...
select 99 where 99 = test.expect_n(
    'select (select count(*) 
               from veil2.direct_role_privileges 
              where role_id = 1) - 
            (select count(*) 
               from veil2.privileges
              where privilege_id != 0)', 0, 
    'Superuser privileges count should be all privileges (except connect)');

-- The same again, this time testing that bitmap operations look sound
select 99 where 99 = test.expect_n(
    'select (with basic_role_privs (
    	            role_id, privs) as (
               select role_id, bitmap_of(privilege_id)
                 from veil2.direct_role_privileges
                group by role_id)
             select array_length(to_array(privs),1) 
               from basic_role_privs 
              where role_id = 1) - 
            (select count(*) 
               from veil2.privileges
              where privilege_id != 0)', 0, 
    'Superuser privileges count should be all privileges(2)');

\echo ...checking test_role privileges...
select 99 where 99 = test.expect_n(
    'select array_length(to_array(arp.privs), 1)
       from veil2.all_role_privs arp
      inner join veil2.roles r
              on r.role_id = arp.role_id
      where r.role_name = ''test_role_6''
        and arp.context_type_id = 1', 1, 
    'test_role_6 should have 1 privilege in global context');

select 99 where 99 = test.expect_n(
    'select array_length(to_array(arp.privs), 1)
       from veil2.all_role_privs arp
      inner join veil2.roles r
              on r.role_id = arp.role_id
      where r.role_name = ''test_role_6''
        and arp.context_type_id = -3', 2, 
    'test_role_6 should have 2 privileges in corp context -3');

select 99 where 99 = test.expect_n(
    'select array_length(to_array(arp.privs), 1)
       from veil2.all_role_privs arp
      inner join veil2.roles r
              on r.role_id = arp.role_id
      where r.role_name = ''test_role_5''
        and arp.context_type_id = 1', 2, 
    'test_role_5 should have 2 privileges in global context');

select 99 where 99 = test.expect_n(
    'select array_length(to_array(arp.privs), 1)
       from veil2.all_role_privs arp
      inner join veil2.roles r
              on r.role_id = arp.role_id
      where r.role_name = ''test_role_5''
        and arp.context_type_id = -3', 1, 
    'test_role_5 should have 1 privilege in corp context -3');

select 99 where 99 = test.expect_n(
    'select array_length(to_array(arp.privs), 1)
       from veil2.all_role_privs arp
      inner join veil2.roles r
              on r.role_id = arp.role_id
      where r.role_name = ''test_role_1''
        and arp.context_type_id = 1', 6, 
    'test_role_1 should have 6 privileges in global context');

select 99 where 99 = test.expect_n(
    'select array_length(to_array(arp.privs), 1)
       from veil2.all_role_privs arp
      inner join veil2.roles r
              on r.role_id = arp.role_id
      where r.role_name = ''test_role_1''
        and arp.context_type_id = -3', 1, 
    'test_role_1 should have 1 privilege in corp context -3');


EOF`
status=$?

# Show output from psql, with any blank lines (empty result sets) removed.
echo "${result}" | grep .


exit ${status}
