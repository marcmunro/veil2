\echo ...removing test objects and data...

-- Reset veil2 views to original definitions
create or replace
view veil2.all_accessor_roles (
  accessor_id, role_id, context_type_id, context_id
) as
select accessor_id, role_id,
       context_type_id, context_id
  from veil2.accessor_roles;

create or replace
view veil2.scope_promotions (
  scope_type_id, scope_id,
  promoted_scope_type_id, promoted_scope_id
) as
select null::integer, null::integer,
       null::integer, null::integer
where false;

drop table org_hierarchy;
delete from veil2.accessor_roles where accessor_id < 0;
delete from veil2.authentication_details where accessor_id < 0;;
delete from veil2.accessors where accessor_id < 0;

drop table project_assignments;
drop table projects;

-- Remove test roles
delete
  from veil2.context_roles
 where context_type_id in (-3, -4);

delete
  from veil2.role_roles
 where (   primary_role_id in (
           select role_id from veil2.roles where role_name like 'test_role%')
        or assigned_role_id in (
           select role_id from veil2.roles where role_name like 'test_role%'));
   
delete
  from veil2.role_privileges
 where role_id in (
        select role_id from veil2.roles where role_name like 'test_role%');

delete
  from veil2.roles
 where role_name like 'test_role%';

delete
  from veil2.privileges
 where privilege_name like 'test_privilege%';

-- Remove test accessors
delete from veil2.authentication_details where accessor_id in (-1, -2, -3);
delete from veil2.accessor_roles where accessor_id in (-1, -2, -3);
delete from veil2.accessors where accessor_id in (-1, -2, -3);

-- Remove test context
delete from veil2.security_contexts where context_type_id < 0;
delete from veil2.security_context_types where context_type_id < 0;


-- Ensure plaintext auth is not enabled.
update veil2.authentication_types
   set enabled = false
 where shortname = 'plaintext';
 


drop function test.expect(text, integer, text);
drop function test.expect(text, boolean, text);
drop function test.expect(integer, integer, text);
drop function test.expect(boolean, boolean, text);
drop function test.expect(text, text, text);

drop schema test;
drop user veil2_nopriv;
drop user veil2_alice;
drop user veil2_bob;
drop role db_accessor;
