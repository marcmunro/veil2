\echo ...removing test objects and data...


-- Reset veil2 views to original definitions
create or replace
view veil2.all_accessor_roles (
  accessor_id, role_id, context_type_id, context_id
) as
select accessor_id, role_id,
       context_type_id, context_id
  from veil2.accessor_roles;

select veil2.restore_system_views();
select veil2.restore_system_functions();

drop view veil2.my_superior_scopes;
drop table org_hierarchy;
delete from veil2.accessor_roles where accessor_id < 0;
delete from veil2.authentication_details where accessor_id < 0;;
delete from veil2.accessors where accessor_id < 0;

drop table project_assignments;
drop table projects;
drop table persons;

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
 where role_name like 'test_role%'
    or role_name = 'test_super';

delete
  from veil2.privileges
 where privilege_name like 'test_privilege%';

-- Remove test accessors
delete from veil2.authentication_details where accessor_id in (-1, -2, -3);
delete from veil2.accessor_roles where accessor_id in (-1, -2, -3);
delete from veil2.accessors where accessor_id in (-1, -2, -3);

-- Remove test context
delete from veil2.scopes where scope_type_id < 0;
delete from veil2.scope_types where scope_type_id < 0;


-- Ensure plaintext auth is not enabled.
update veil2.authentication_types
   set enabled = false
 where shortname = 'plaintext';
 

drop user veil2_alice;
drop user veil2_bob;
drop role db_accessor;
