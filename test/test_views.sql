--  test_views.sql
--
--     Unit tests for views.  Primarily this is about views that
--     aggregate privileges to ensure aggregation and promotion is all
--     correct. 
--
--     Copyright (c) 2020 Marc Munro
--     Author:  Marc Munro
--     License: GPL V3
--
-- Usage:  Called from test_veil2.sql
--

begin;
select '...test Veil2 views...';
select plan(13);
refresh materialized view veil2.all_role_privileges;

select is(array_length(to_array(privileges), 1), 1,
          'Expecting connect role to have only 1 privilege')
  from veil2.all_role_privileges 
 where role_id = 0;

select is(bitmin(privileges), 0,
       'Expecting connect role to have connect privilege') 
  from veil2.all_role_privileges
 where role_id = 0;

select is(0, cnt,
       'Expecting no other roles to have connect privilege') 
  from (select count(*)::integer as cnt
          from veil2.all_role_privileges
         where role_id != 0
	   and privileges ? 0) x;

select is(array_length(to_array(drp.privileges), 1), x.cnt,
          'Expecting superuser role to have all but connect privilege')
  from veil2.all_role_privileges drp
 cross join (select count(*)::integer as cnt
               from veil2.privileges
	      where privilege_id != 0) x
  where drp.role_id = 1;


-- Ensure that each test role is assigned to one test privilege and that
-- is all.

with n (n) as (select * from generate_series(1, 6)),
target_role_privs as (
     select r.role_id, p.privilege_id
      from n
     inner join veil2.roles r
             on r.role_name = 'test_role_' || n::text
     inner join veil2.privileges p
             on p.privilege_name = 'test_privilege_' || n::text
  ),
direct_role_privs as (
    select role_id, privileges
      from veil2.all_role_privileges
     where role_id in (select role_id from target_role_privs)
           -- Ignore role_privs for mappings other than global
       and coalesce(mapping_context_type_id, 1) = 1  
  ),
all_role_privs as (
    select role_id, bits(privileges) as privilege_id
      from direct_role_privs
  ),
matching_role_privs as (
    select count(*) as cnt
      from target_role_privs t
     inner join all_role_privs a
        on a.role_id = t.role_id
       and a.privilege_id = t.privilege_id
  )
select is(
         (select count(*) from target_role_privs)::integer,
         (select count(*) from direct_role_privs)::integer,
	 'Target role privs count must match direct_role_privs count')
union all
select is(
         (select count(*) from target_role_privs)::integer,
	 (select cnt from matching_role_privs)::integer,
	 'Each direct_role_privs should match target');

-- Accessor -2 has connect and superuser only, in global context
select is((select count(*)
	     from veil2.all_accessor_roles
	    where accessor_id = -2
	      and context_type_id = 1)::integer,
	  2,  'Accessor -2 has 2 global roles')
union all
select is((select count(*)
	     from veil2.all_accessor_roles
	    where accessor_id = -2
	      and context_type_id != 1)::integer,
	  0, 'Accessor -2 has 0 non-global roles')
union all
select is((select count(*)
	     from veil2.all_accessor_roles
	    where accessor_id = -2
	      and role_id = 0
	      and context_type_id = 1)::integer,
	  1,  'Accessor -2 has global connect role')
union all
select is((select count(*)
	     from veil2.all_accessor_roles
	    where accessor_id = -2
	      and role_id = 1
	      and context_type_id = 1)::integer,
	  1, 'Accessor -2 has global superuser role');

-- Accessor -3 has connect only in global context and test_role_5 in
-- corp context for corp -2
select is((select count(*)
	     from veil2.all_accessor_roles
	    where accessor_id = -3
	      and context_type_id = 1)::integer,
	  1, 'Accessor -3 should have 1 global role')
union all
select is((select count(*)
	     from veil2.all_accessor_roles
	    where accessor_id = -3
	      and role_id = 0
	      and context_type_id = 1)::integer,
	  1, 'Accessor -3 should have global connect role')
union all
select is((select count(*)
	     from veil2.all_accessor_roles aar
	    inner join veil2.roles r
	       on r.role_id = aar.role_id
	    where aar.accessor_id = -3
	      and r.role_name = 'test_role_5'
	      and aar.context_type_id = -3
	      and aar.context_id = -3)::integer,
	  1, 'Accessor -3 should have role 8 in corp context -3');

/* OLD TESTS FROM PREVIOUS INCARMATION OF VIEWS 
-- Accessor -6 has been granted role 8 for project -61
-- Check that role and priv assignments happen in the appropriate
-- contexts, with proper handling of privilege promotion
with all_roles as
  (
    select mapping_context_type_id as context_type_id,
           mapping_context_id as context_id,
    	   bits(roles) role_id
      from veil2.all_accessor_privs
     where accessor_id = -6
       and roles is not null
  ),
expand_privs as
  (
    select mapping_context_type_id as context_type_id,
           mapping_context_id as context_id,
	   scope_type_id, scope_id, 
           bits(privileges) priv_id
      from veil2.all_accessor_privs
     where accessor_id = -6
  ),
all_privs as
  (
    select distinct
           ep.context_type_id, ep.context_id, 
	   ep.scope_type_id, ep.scope_id, 
           ep.priv_id, p.privilege_name
      from expand_privs ep
     inner join veil2.privileges p
        on p.privilege_id = ep.priv_id
  ),
min_test_priv as
  (
    select min(privilege_id) as priv
      from veil2.privileges
     where privilege_name like 'test_priv%'
  )
select is((select count(*)
	     from all_roles
	    where context_type_id = -6)::integer, -- project_context
	  2, 'Expect 2 roles in project context')
union all
select is((select count(*)
	     from all_roles
	    where context_type_id != -6)::integer, -- not project_context
	  2, 'Expect 2 roles in non-project contexts')
union all
select is((select true
	     from all_roles ar
	    inner join veil2.roles r
	       on r.role_id = ar.role_id
	    where ar.context_type_id = -6
	      and r.role_name = 'test_role_5'),
	  true, 'Expect test_role_5 in project context')
union all
select is((select true
	     from all_roles ar
	    inner join veil2.roles r
	       on r.role_id = ar.role_id
	    where ar.context_type_id = -6
	      and r.role_name = 'test_role_6'),
	  true, 'Expect test_role_6 in project context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = 1
	      and privilege_name = 'test_privilege_5glob')::integer, 
	  1, 'Expect priv5glob to be promoted to global context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = 1
	      and priv_id >= (select priv from min_test_priv)
                  -- ignore non-test privileges
	  )::integer,
	  1, 'Expect only priv5glob to be promoted to global context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -3
	      and scope_id = -3 -- The owning corp of the project
	      and privilege_name = 'test_privilege_5corp')::integer, 
	  1, 'Expect priv5corp to be promoted to corporate context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -3
	      and priv_id != 0)::integer, 
	  1, 'Expect only priv5corp to be promoted to corporate context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -4
	      and scope_id = -41 -- The owning div of the project
	      and privilege_name = 'test_privilege_5div')::integer, 
	  1, 'Expect priv5div to be promoted to div context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -4)::integer, 
	  1, 'Expect only priv5div to be promoted to div context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -5
	      and scope_id = -52 -- The owning dept of the project
	      and privilege_name = 'test_privilege_5dept')::integer, 
	  1, 'Expect priv5dept to be promoted to dept context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -5)::integer, 
	  1, 'Expect only priv5dept to be promoted to dept context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -6
	      and scope_id = -61 
	      and privilege_name = 'test_privilege_5')::integer, 
	  1, 'Expect priv5 to exist in proj context');

-- Accessor -5 has been granted test_role_5 for departments -51 and -54
-- Check that role and priv assignments happen in the appropriate
-- contexts, with proper handling of privilege promotion
with all_roles as
  (
    select assignment_context_type_id as context_type_id,
           assignment_context_id as context_id,
	   bits(roles) role_id
      from veil2.all_accessor_privs
     where accessor_id = -5
       and roles is not null
  ),
expand_privs as
  (
    select assignment_context_type_id as context_type_id,
           assignment_context_id as context_id,
	   scope_type_id, scope_id, 
           bits(privs) priv_id
      from veil2.all_accessor_privs
     where accessor_id = -5
  ),
all_privs as
  (
    select distinct
           ep.context_type_id, ep.context_id,
	   ep.scope_type_id, ep.scope_id, 
           ep.priv_id, p.privilege_name
      from expand_privs ep
     inner join veil2.privileges p
        on p.privilege_id = ep.priv_id
  )
select is((select count(*)
	     from all_roles
	    where context_type_id = -5  -- dept_context
	      and context_id = -51)::integer,
	  2, 'Expect 2 roles in context of dept -51')
union all
select is((select count(*)
 	     from all_roles
	    where context_type_id = -5  -- dept_context
	      and context_id = -54)::integer,
	  2, 'Expect 2 roles in context of dept -54')
union all
select is((select count(*)
	     from all_roles
	    where context_type_id != -5)::integer, -- not dept context
	  0, 'Expect 0 roles in non-dept contexts')	  
union all
select is((select count(*)
 	     from all_roles ar
	    inner join veil2.roles r
	       on r.role_id = ar.role_id
	    where ar.context_type_id = -5
	      and r.role_name in ('test_role_5', 'test_role_6')
	      and ar.context_id = -51)::integer,
	  2, 'Expect roles 8 and 9 for dept -51')
union all
select is((select count(*)
	     from all_roles ar
	    inner join veil2.roles r
	       on r.role_id = ar.role_id
	    where ar.context_type_id = -5
	      and r.role_name in ('test_role_5', 'test_role_6')
	      and context_id = -54)::integer,
	  2, 'Expect roles 8 and 9 for dept -54')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = 1
	      and privilege_name = 'test_privilege_5glob')::integer, 
	  2, 'Expect priv5glob to be promoted to global context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = 1)::integer, 
	  2, 'Expect only priv 18 to be promoted to global context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -3
	      and scope_id = -3 -- The owning corp of the project
	      and privilege_name = 'test_privilege_5corp')::integer, 
	  1, 'Expect priv5corp to be promoted to corporate context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -3
	      and scope_id = -3)::integer, 
	  1, 'Expect only priv5corp to be promoted for corporation -3')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -3
	      and scope_id = -31 -- The owning corp of the project
	      and privilege_name = 'test_privilege_5corp')::integer, 
	  1, 'Expect priv5corp to be promoted to corporate context')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -3
	      and scope_id = -31)::integer, 
	  1, 'Expect only priv5corp to be promoted for corporation -3')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -4
	      and scope_id = -41 -- The owning div of the project
	      and privilege_name = 'test_privilege_5div')::integer, 
	  1, 'Expect priv5div to be promoted to div context for div -41')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -4
	      and scope_id = -41)::integer, 
	  1, 'Expect only priv5div to be promoted to div context for div -41')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -4
	      and scope_id = -44 -- The owning div of the project
	      and privilege_name = 'test_privilege_5div')::integer, 
	  1, 'Expect priv5div to be promoted to div context for div -44')
union all
select is((select count(*)
	     from all_privs
	    where scope_type_id = -4
	      and scope_id = -44)::integer, 
	  1, 'Expect only priv5div to be promoted to div context for div -44')
union all
select is((select count(*)
 	     from all_privs
	    where context_type_id = -5
	      and context_id = -51
	      and privilege_name = 'test_privilege_5dept')::integer, 
	  1, 'Expect priv5dept to exist in dept context for dept -51')
union all
select is((select count(*)
	     from all_privs
	    where context_type_id = -5
	      and context_id = -54
	      and privilege_name = 'test_privilege_5dept')::integer, 
	  1, 'Expect priv5dept to exist in dept context for dept -54')
union all
select is((select count(*)
	     from all_privs
	    where context_type_id = -5
	      and privilege_name = 'test_privilege_5')::integer, 
	  2, 'Expect priv5 to exist in dept contexts');	  
*/
select * from finish();


/*
\set QUIET 0
\pset format aligned
\pset tuples_only false
*/


rollback;
