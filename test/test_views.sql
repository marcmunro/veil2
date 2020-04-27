
\echo ...views...
\echo ......checking direct_role_privileges...

\echo .........connect role and privilege...
select null
 where test.expect(
    'select array_length(to_array(privileges), 1) 
       from veil2.direct_role_privileges 
      where role_id = 0',
      1, 'Expecting connect role to have only connect privilege')
or test.expect(
    'select bitmin(privileges) from veil2.direct_role_privileges 
      where role_id = 0',
      0, 'Expecting connect role to have connect privilege')
    or test.expect(
    'select count(*) from veil2.direct_role_privileges 
      where privileges ? 0',
      1, 'Expecting only connect role to have connect privilege');

\echo .........superuser role...
select null
 where test.expect(
    'select array_length(to_array(privileges), 1)
       from veil2.direct_role_privileges 
      where role_id = 1',
      (select count(*) 
        from veil2.privileges where privilege_id != 0)::integer,
      'Expecting superuser role to have all but connect privilege');

\echo .........test roles...
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
      from veil2.direct_role_privileges
     where role_id in (select role_id from target_role_privs)),
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
select null
 where test.expect(
         (select count(*) from target_role_privs)::integer,
         (select count(*) from direct_role_privs)::integer,
	 'Target role privs count must match direct_role_privs count')
    or test.expect(
         (select count(*) from target_role_privs)::integer,
	 (select cnt from matching_role_privs)::integer,
	 'Each direct_role_privs should match target');

\echo ......checking assigned_role_info...
-- Accessor -2 has connect and superuser only, in global context
select null
 where test.expect(
         (select count(*)
	    from veil2.all_accessor_roles
	   where accessor_id = -2
	     and context_type_id = 1)::integer,
	 2, 'Accessor -2 should have 2 global roles')
    or test.expect(
         (select count(*)
	    from veil2.all_accessor_roles
	   where accessor_id = -2
	     and context_type_id != 1)::integer,
	 0, 'Accessor -2 should have 0 non-global roles')
    or test.expect(
         (select count(*)
	    from veil2.all_accessor_roles
	   where accessor_id = -2
	     and role_id = 0
	     and context_type_id = 1)::integer,
	 1, 'Accessor -2 should global connect role')
    or test.expect(
         (select count(*)
	    from veil2.all_accessor_roles
	   where accessor_id = -2
	     and role_id = 1
	     and context_type_id = 1)::integer,
	 1, 'Accessor -2 should global superuser role');
	 
-- Accessor -3 has connect only in global context and test_role_5 in
-- corp context for corp -2
select null
 where test.expect(
         (select count(*)
	    from veil2.all_accessor_roles
	   where accessor_id = -3
	     and context_type_id = 1)::integer,
	 1, 'Accessor -3 should have 1 global role')
    or test.expect(
         (select count(*)
	    from veil2.all_accessor_roles
	   where accessor_id = -3
	     and role_id = 0
	     and context_type_id = 1)::integer,
	 1, 'Accessor -3 should have global connect role')
    or test.expect(
         (select count(*)
	    from veil2.all_accessor_roles aar
	   inner join veil2.roles r
	      on r.role_id = aar.role_id
	   where aar.accessor_id = -3
	     and r.role_name = 'test_role_5'
	     and aar.context_type_id = -3
	     and aar.context_id = -3)::integer,
	 1, 'Accessor -3 should have role 8 in corp context -3');


-- Accessor -6 has been granted role 8 for project -61
-- Check that role and priv assignments happen in the appropriate
-- contexts, with proper handling of privilege promotion
with all_roles as
  (
    select context_type_id, context_id, bits(roles) role_id
      from veil2.all_accessor_privs
     where accessor_id = -6
       and roles is not null
  ),
expand_privs as
  (
    select context_type_id, context_id, bits(privs) priv_id
      from veil2.all_accessor_privs
     where accessor_id = -6
  ),
all_privs as
  (
    select ep.context_type_id, ep.context_id, ep.priv_id,
           p.privilege_name
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
select null
 where -- We should have test roles 5 and 6 in project context and no others
       test.expect(
         (select count(*)
	    from all_roles
	   where context_type_id = -6)::integer, -- project_context
	 2, 'Expect 2 roles in project context')
    or test.expect(
         (select count(*)
	    from all_roles
	   where context_type_id != -6)::integer, -- not project_context
	 2, 'Expect 2 roles in non-project contexts')
	 -- The roles above should be connect and veil2_viewer
    or test.expect(
         (select true
	    from all_roles ar
	   inner join veil2.roles r
	      on r.role_id = ar.role_id
	   where ar.context_type_id = -6
	     and r.role_name = 'test_role_5'),
	 true, 'Expect test_role_5 in project context')
    or test.expect(
         (select true
	    from all_roles ar
	   inner join veil2.roles r
	      on r.role_id = ar.role_id
	   where ar.context_type_id = -6
	     and r.role_name = 'test_role_6'),
	 true, 'Expect test_role_6 in project context')
    -- Check that priv5glob got promoted to global context
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = 1
	     and privilege_name = 'test_privilege_5glob')::integer, 
	 1, 'Expect priv5glob to be promoted to global context')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = 1
	     and priv_id >= (select priv from min_test_priv)
                 -- ignore non-test privileges
	 )::integer,
	 1, 'Expect only priv5glob to be promoted to global context')
    -- Check that priv5corp got promoted to corp context
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -3
	     and context_id = -3 -- The owning corp of the project
	     and privilege_name = 'test_privilege_5corp')::integer, 
	 1, 'Expect priv5corp to be promoted to corporate context')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -3
	     and priv_id != 0)::integer, 
	 1, 'Expect only priv5corp to be promoted to corporate context')
    -- Check that priv5div got promoted to div context
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -4
	     and context_id = -41 -- The owning div of the project
	     and privilege_name = 'test_privilege_5div')::integer, 
	 1, 'Expect priv5div to be promoted to div context')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -4)::integer, 
	 1, 'Expect only priv5div to be promoted to div context')
    -- Check that priv5dept got promoted to dept context
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -5
	     and context_id = -52 -- The owning dept of the project
	     and privilege_name = 'test_privilege_5dept')::integer, 
	 1, 'Expect priv5dept to be promoted to dept context')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -5)::integer, 
	 1, 'Expect only priv5dept to be promoted to dept context')
    -- Finally check that priv5 appears in the appropriate proj context
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -6
	     and context_id = -61 
	     and privilege_name = 'test_privilege_5')::integer, 
	 1, 'Expect priv5 to exist in proj context');

-- Accessor -5 has been granted test_role_5 for departments -51 and -54
-- Check that role and priv assignments happen in the appropriate
-- contexts, with proper handling of privilege promotion
with all_roles as
  (
    select context_type_id, context_id, bits(roles) role_id
      from veil2.all_accessor_privs
     where accessor_id = -5
       and roles is not null
  ),
expand_privs as
  (
    select context_type_id, context_id, bits(privs) priv_id
      from veil2.all_accessor_privs
     where accessor_id = -5
  ),
all_privs as
  (
    select ep.context_type_id, ep.context_id, ep.priv_id,
           p.privilege_name
      from expand_privs ep
     inner join veil2.privileges p
        on p.privilege_id = ep.priv_id
  )
select null
 where -- We should have roles 8 and 9 in dept contexts and no others
       test.expect(
         (select count(*)
	    from all_roles
	   where context_type_id = -5  -- dept_context
	     and context_id = -51)::integer,
	 2, 'Expect 2 roles in context of dept -51')
    or test.expect(
         (select count(*)
	    from all_roles
	   where context_type_id = -5  -- dept_context
	     and context_id = -54)::integer,
	 2, 'Expect 2 roles in context of dept -54')
    or test.expect(
         (select count(*)
	    from all_roles
	   where context_type_id != -5)::integer, -- not dept context
	 0, 'Expect 0 roles in non-dept contexts')
    or test.expect(
         (select count(*)
	    from all_roles ar
	   inner join veil2.roles r
	      on r.role_id = ar.role_id
	   where ar.context_type_id = -5
	     and r.role_name in ('test_role_5', 'test_role_6')
	     and ar.context_id = -51)::integer,
	 2, 'Expect roles 8 and 9 for dept -51')
    or test.expect(
         (select count(*)
	    from all_roles ar
	   inner join veil2.roles r
	      on r.role_id = ar.role_id
	   where ar.context_type_id = -5
	     and r.role_name in ('test_role_5', 'test_role_6')
	     and context_id = -54)::integer,
	 2, 'Expect roles 8 and 9 for dept -54')

    -- Check that priv5glob got promoted to global context
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = 1
	     and privilege_name = 'test_privilege_5glob')::integer, 
	 1, 'Expect priv5glob to be promoted to global context')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = 1)::integer, 
	 1, 'Expect only priv 18 to be promoted to global context')
    -- Check that priv5corp got promoted to corp context
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -3
	     and context_id = -3 -- The owning corp of the project
	     and privilege_name = 'test_privilege_5corp')::integer, 
	 1, 'Expect priv5corp to be promoted to corporate context')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -3
	     and context_id = -3)::integer, 
	 1, 'Expect only priv5corp to be promoted for corporation -3')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -3
	     and context_id = -31 -- The owning corp of the project
	     and privilege_name = 'test_privilege_5corp')::integer, 
	 1, 'Expect priv5corp to be promoted to corporate context')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -3
	     and context_id = -31)::integer, 
	 1, 'Expect only priv5corp to be promoted for corporation -3')
    -- Check that priv5div got promoted to div context
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -4
	     and context_id = -41 -- The owning div of the project
	     and privilege_name = 'test_privilege_5div')::integer, 
	 1, 'Expect priv5div to be promoted to div context for div -41')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -4
	     and context_id = -41)::integer, 
	 1, 'Expect only priv5div to be promoted to div context for div -41')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -4
	     and context_id = -44 -- The owning div of the project
	     and privilege_name = 'test_privilege_5div')::integer, 
	 1, 'Expect priv5div to be promoted to div context for div -44')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -4
	     and context_id = -44)::integer, 
	 1, 'Expect only priv5div to be promoted to div context for div -44')
    -- Ensure we have priv5dept in to dept context
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -5
	     and context_id = -51
	     and privilege_name = 'test_privilege_5dept')::integer, 
	 1, 'Expect priv5dept to exist in dept context for dept -51')
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -5
	     and context_id = -54
	     and privilege_name = 'test_privilege_5dept')::integer, 
	 1, 'Expect priv5dept to exist in dept context for dept -54')
    -- Finally check that priv5 appears in the appropriate dept contexts
    or test.expect(
         (select count(*)
	    from all_privs
	   where context_type_id = -5
	     and privilege_name = 'test_privilege_5')::integer, 
	 2, 'Expect priv5 to exist in dept contexts');
                  
-- The following query is useful if you need to debug any of the above
-- tests:
/*
select accessor_id, context_type_id, context_id, to_array(roles),
       to_array(privs)
  from veil2.all_accessor_privs
 where accessor_id = -5;
*/


