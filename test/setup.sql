/* ----------
 * setup.sql
 *
 *      Set up the unit test data for running unit tests.
 *
 *      Copyright (c) 2020 Marc Munro
 *      Author:  Marc Munro
 *	License: GPL V3
 *
 * ----------
 */

create role db_accessor;
create user veil2_alice password 'xyzzy';
create role veil2_bob;
grant db_accessor to veil2_alice;
grant veil_user to veil2_alice;
grant db_accessor to veil2_bob;
grant veil_user to veil2_bob;


-- Create some context types
--\echo ......creating corp context type...
insert into veil2.scope_types
       (scope_type_id, scope_type_name, description)
values (-3, 'corp', 'corporate context'),
       (-4, 'div', 'divisional context'),
       (-5, 'dept', 'department context'),
       (-6, 'proj', 'project context');

-- and a test corp
--\echo ......creating test corp...
insert into veil2.scopes
       (scope_type_id, scope_id)
values (-3, -3),
       (-3, -31);

-- and some test divisions
--\echo ......creating test corp...
insert into veil2.scopes
       (scope_type_id, scope_id)
values (-4, -41),
       (-4, -42),
       (-4, -43),
       (-4, -44);

-- and some test departments
--\echo ......creating test corp...
insert into veil2.scopes
       (scope_type_id, scope_id)
values (-5, -51),
       (-5, -52),
       (-5, -53),
       (-5, -54);

-- and some some projects
--\echo ......creating test corp...
insert into veil2.scopes
       (scope_type_id, scope_id)
values (-6, -61),
       (-6, -62),
       (-6, -63),
       (-6, -64);

-- And some mappings of depts to divs to corps
-- This is a non-veil2 table, ie the sort of data that veil2 is
-- protecting. 
create table org_hierarchy (
  corp_id         integer not null,
  org_id          integer not null,
  superior_org_id integer not null
);

grant all on org_hierarchy to db_accessor;
--TODO: SET-UP ACCESS CONTROLS ON THIS TABLE

-- Define some projects, within some depts
create table projects (
  project_id 	  integer not null,
  corp_id         integer not null,
  dept_id         integer not null,
  project_name	  text
);

-- create my_superior_scopes view to show above org hierarchy and
-- proj->dept mapping
create or replace
view veil2.my_superior_scopes (
  scope_type_id, scope_id,
  superior_scope_type_id, superior_scope_id
) as
select s1.scope_type_id, oh.org_id,
       s2.scope_type_id, oh.superior_org_id
  from org_hierarchy oh
 inner join veil2.scopes s1
    on s1.scope_id = oh.org_id
 inner join veil2.scopes s2
    on s2.scope_id = oh.superior_org_id
union all
select -6, p.project_id,
       -5, p.dept_id
  from projects p;

select veil2.install_user_views();

create trigger org_hierarchy__aiudt
  after insert or update or delete or truncate
  on org_hierarchy
  for each statement
  execute procedure veil2.refresh_scopes_matviews();

create trigger projects__aiudt
  after insert or update or delete or truncate
  on projects
  for each statement
  execute procedure veil2.refresh_scopes_matviews();

--\echo ...creating test parties...
insert into veil2.accessors
       (accessor_id, username)
values (-1, null),
       (-2, null),
       (-3, null),
       (-4, null),
       (-5, null),
       (-6, 'veil2_alice');

create table persons (accessor_id integer, username text);
insert
  into persons
       (accessor_id, username)
values (-6, 'alice'),
       (-5, 'bob'),
       (-4, 'carol'),
       (-3, 'dave'),
       (-2, 'eve'),
       (-1, 'fred');

create or replace
function veil2.my_get_accessor(
    username in text,
    context_type_id in integer,
    context_id in integer)
  returns integer as
$$
declare
  _result integer;
  _username text := username;
begin
  select accessor_id
    into _result
    from persons p
   where p.username = _username;
   return _result;
end;
$$
language plpgsql security definer stable leakproof;


insert into veil2.authentication_details
       (accessor_id, authentication_type, authent_token)
values (-1, 'plaintext', 'password'),
       (-2, 'plaintext', 'password2'),
       (-3, 'plaintext', 'password3'),
       (-4, 'plaintext', 'password4'),
       (-5, 'plaintext', 'password5'),
       (-6, 'plaintext', 'password6'),
       (-1, 'bcrypt', crypt('bassword', gen_salt('bf'))),
       (-2, 'bcrypt', crypt('bassword2', gen_salt('bf')));

insert into org_hierarchy
       (corp_id, org_id, superior_org_id)
values (-3, -51, -41),
       (-3, -52, -41),
       (-3, -53, -42),
       (-3, -41, -3),
       (-3, -42, -3),
       (-3, -43, -3),
       (-31, -44, -31),
       (-31, -54, -44);

insert
  into projects
       (project_id, corp_id, dept_id, project_name)
values (-61, -3, -52, 'Corp -3, dept -52, div -41'),
       (-62, -31, -54, 'Corp -31, dept -54, div -44');

create table project_assignments (
  project_id 	  integer not null,
  corp_id         integer not null,
  accessor_id     integer not null,
  role_id         integer not null
);

-- Add an understanding of project context role assignments to the veil2
-- view, all_accessor_roles.
create or replace
view veil2.all_accessor_roles (
  accessor_id, role_id, context_type_id, context_id
) as
select accessor_id, role_id,
       context_type_id, context_id
  from veil2.accessor_roles
 union
select accessor_id, role_id,
       -6, project_id
  from project_assignments;



--\echo ......creating test roles...
-- Insert some more test roles
insert into veil2.roles
      (role_id, role_name)
with m(id) as (select max(role_id) from veil2.roles)
select m.id + r.role_id, r.role_name
  from m
 cross join 
   (select 1 as role_id, 'test_role_1' as role_name
    union
    select 2, 'test_role_2'
    union
    select 3, 'test_role_3'
    union
    select 4, 'test_role_4'
    union
    select 5, 'test_role_5'
    union
    select 6, 'test_role_6'
    union
    select 7, 'test_super') r;  -- test_super will be almost superuser

--\echo ......creating test context_roles...
insert into veil2.context_roles
      (role_id, role_name, context_type_id, context_id)
select role_id, 'corp_' || role_name, -3, -3
  from veil2.roles
 where role_name in ('test_role_5', 'test_role_6');

insert into veil2.context_roles
      (role_id, role_name, context_type_id, context_id)
select role_id, 'dept_' || role_name, -4, -41
  from veil2.roles
 where role_name in ('test_role_5', 'test_role_6');


-- 1->2
insert into veil2.role_roles
      (primary_role_id, assigned_role_id, context_type_id, context_id)
select p.role_id, a.role_id, 1, 0
  from veil2.roles p, veil2.roles a
 where p.role_name = 'test_role_1'
   and a.role_name = 'test_role_2';

-- 2->3
insert into veil2.role_roles
      (primary_role_id, assigned_role_id, context_type_id, context_id)
select p.role_id, a.role_id, 1, 0
  from veil2.roles p, veil2.roles a
 where p.role_name = 'test_role_2'
   and a.role_name = 'test_role_3';

-- 2->4
insert into veil2.role_roles
      (primary_role_id, assigned_role_id, context_type_id, context_id)
select p.role_id, a.role_id, 1, 0
  from veil2.roles p, veil2.roles a
 where p.role_name = 'test_role_2'
   and a.role_name = 'test_role_4';

-- 1->5
insert into veil2.role_roles
      (primary_role_id, assigned_role_id, context_type_id, context_id)
select p.role_id, a.role_id, 1, 0
  from veil2.roles p, veil2.roles a
 where p.role_name = 'test_role_1'
   and a.role_name = 'test_role_5';

-- 5->6
insert into veil2.role_roles
      (primary_role_id, assigned_role_id, context_type_id, context_id)
select p.role_id, a.role_id, 1, 0
  from veil2.roles p, veil2.roles a
 where p.role_name = 'test_role_5'
   and a.role_name = 'test_role_6';

-- 6->5 (ensuring cyclic assignments cause no problem)
insert into veil2.role_roles
      (primary_role_id, assigned_role_id, context_type_id, context_id)
select p.role_id, a.role_id, 1, 0
  from veil2.roles p, veil2.roles a
 where p.role_name = 'test_role_6'
   and a.role_name = 'test_role_5';

-- 6->5 in corp context of -3
insert into veil2.role_roles
      (primary_role_id, assigned_role_id, context_id, context_type_id)
select p.role_id, a.role_id, -3, -3
  from veil2.roles p, veil2.roles a
 where p.role_name = 'test_role_6'
   and a.role_name = 'test_role_5';

--\echo ...creating test privileges...
insert into veil2.privileges
      (privilege_id, privilege_name)
with m(id) as (select max(privilege_id) from veil2.privileges)
select m.id + p.privilege_id, p.privilege_name
  from m
 cross join 
   (select 1 as privilege_id, 'test_privilege_1' as privilege_name
    union
    select 2, 'test_privilege_2'
    union
    select 3, 'test_privilege_3'
    union
    select 4, 'test_privilege_4'
    union
    select 5, 'test_privilege_5'
    union
    select 6, 'test_privilege_6') p;

-- Create some privileges requiring promotion which we will map to role
-- 5

with mp as (
    select max(privilege_id) + 1 maxpriv from veil2.privileges
  ),
  rows as
    (
       select mp.maxpriv + 1, 'test_privilege_5glob', 1
         from mp
       union
       select mp.maxpriv + 2, 'test_privilege_5corp', -3
         from mp
       union
       select mp.maxpriv + 3, 'test_privilege_5div', -4
         from mp
       union
       select mp.maxpriv + 4, 'test_privilege_5dept', -5
         from mp
    )
insert
  into veil2.privileges
       (privilege_id, privilege_name,
        promotion_scope_type_id)
select * from rows;

-- And role_privileges: assign test_priv_n* to test_role_n
insert into veil2.role_privileges
      (role_id, privilege_id)
with n (n) as (select * from generate_series(1, 6))
select r.role_id, p.privilege_id
  from n
 inner join veil2.roles r
         on r.role_name = 'test_role_' || n::text
 inner join veil2.privileges p
         on p.privilege_name like 'test_privilege_' || n::text || '%';

-- Almost superuser role: test_super (role 7)
-- has all privs except connect and priv 20
insert into veil2.role_privileges
      (role_id, privilege_id)
select 7, p.privilege_id
  from veil2.privileges p
 where p.privilege_id not in (0, 20)
   and not exists (
    select null
      from veil2.role_privileges rp
     where rp.role_id = 7
       and rp.privilege_id = p.privilege_id);

--\echo ...setting access rights for parties...
-- party -1 has no rights
-- party -2 has connect and global superuser
-- party -3 has connect and test_role_5 in corp context -3


-- Create connect and superuser rights for party -3 in global context
-- and for party -3 connect in global context and SOMETHING ELSE IN
-- ANOTHER CONTEXT TODO: COMMENT THIS PROPERLY

with named_values(accessor_id, role_name, context_type_id, context_id) as
  (
     values (-2, 'connect', 1, 0),
       	    (-2, 'superuser', 1, 0),
	    (-3, 'connect', 1, 0),
     	    (-3, 'test_role_5', -3, -3),
       	    (-4, 'test_role_5', -4, -41),
            (-5, 'test_role_5', -5, -51),
            (-5, 'test_role_5', -5, -54),
            (-6, 'connect', 1, 0),
            (-6, 'veil2_viewer', 1, 0)
	    
  ),
role_values(accessor_id, role_id, context_type_id, context_id) as
  (
    select nv.accessor_id, r.role_id,
           nv.context_type_id, nv.context_id
      from named_values nv
     inner join veil2.roles r
        on r.role_name = nv.role_name
  )
insert
  into veil2.accessor_roles
       (accessor_id, role_id, context_type_id, context_id)
select *
  from role_values;

-- Assign user -6 to a project.
insert
  into project_assignments
       (project_id, corp_id, accessor_id, role_id)
select -61, -3, -6, role_id
  from veil2.roles
 where role_name = 'test_role_5';
       

