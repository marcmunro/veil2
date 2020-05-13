-- Create the veil2 demo app

-- TODO:
-- Need view to identify allowed login contexts
-- Check whether role->role in global context is included in other
-- role->role mappings.  It should not be.
-- NEED UNIT TESTS FOR ROLE MAPPING IN DIFFERENT CONTEXTS

-- PROBLEM: The context-based role->role mapping stuff does not work.
-- DETAILS:
--  - all accessor_privs is not showing project role privs.
--    This is because there is an assumption that the context of any
--    role->role assignments matches the context of whatever test we
--    are doing, but they are different things.
--




--
-- Continue checking different users' access to parties
-- Provide a how-do-I-have priv function
-- supplement superior_scope thingy with privilege inheritence (with
-- filtering)


create role demouser with login password 'pass';
grant veil_user to demouser;

create schema demo;
comment on schema demo is
'The schema where the underlying objects that Veil2 is protecting will
be defined.'; 

grant usage on schema demo to demouser;

\echo ...party_types...
create table demo.party_types (
  party_type_id         integer not null primary key,
  party_type_name       text not null
);

comment on table demo.party_types is
'Lookup table identifying various classifications of party.';

grant all on table demo.party_types to demouser;

insert into demo.party_types
       (party_type_id, party_type_name)
values (1, 'person'),
       (2, 'organisation');

\echo ...parties_tbl...
create table demo.parties_tbl (
  party_id              integer not null primary key,
  party_type_id         integer not null,
  corp_id               integer not null,
  org_id                integer not null,
  party_name            text not null,
  password              text,
    foreign key (party_type_id)
      references demo.party_types (party_type_id),
    foreign key (corp_id)
      references demo.parties_tbl (party_id),
    foreign key (org_id)
      references demo.parties_tbl (party_id)
);

comment on column demo.parties_tbl.corp_id is
'This is the id of the corp that owns the record.  If you are an
employee of corp X, your party record will have the party_id of corp X
as its corp_id.  This is a data denormalisation for performance
reasons, allowing faster tests for permissions in corp context.  Note
that the corp_id could be determined by ascending the org hierarchy
from org_id.  The top-most parent of org will be the corp.';

comment on column demo.parties_tbl.org_id is
'This is the org that owns the record.  If you as a party work for a
department, the org_id will be the party_id of that department.

It would probably be better data modelling to identify orgs for
thparties using other relations, but placing the org_id directly in the
party record will improve the performance of access controls.';

comment on table demo.parties_tbl is
'Describes a party, and which org it belongs to.  Note that this is
named with a _tbl suffix so that a view called parties can be used in
its place.  This view simply hides the password field.';

insert into demo.parties_tbl
       (party_id, party_type_id, corp_id, 
        org_id, party_name, password)
values (100, 2, 100, 100, 'Veil Corp', null),
       (101, 2, 100, 100, 'Secured Corp', null),
       (102, 2, 100, 100, 'Protected Corp', null),
       (103, 2, 100, 101, 'Secured Top Div', null),
       (104, 2, 100, 101, 'Secured 2nd Div', null),
       (105, 2, 101, 103, 'Department S', null),
       (106, 2, 101, 103, 'Department S2', null),
       (107, 2, 101, 104, 'Department s (lower)', null),
       (108, 1, 100, 100, 'Alice', 'passwd1'),   -- superuser
       (109, 1, 101, 101, 'Bob', 'passwd2'),     -- superuser for Secured Corp
       (110, 1, 102, 102, 'Carol', 'passwd3'),   -- superuser for Protected Corp
       (111, 1, 100, 100, 'Eve', 'passwd4'),     -- superuser for both corps
       (112, 1, 101, 105, 'Sue', 'passwd5'),     -- superuser for dept s
       (113, 1, 101, 105, 'Sharon', 'passwd6'),  -- vp for dept s
       (114, 1, 101, 105, 'Simon', 'passwd7'),   -- pm for project S.1
       (115, 1, 101, 105, 'Sara', 'passwd8'),    -- pm for project S2.1
       (116, 1, 101, 105, 'Stef', 'passwd9'),    -- team member of S.1
       (117, 1, 101, 105, 'Steve', 'passwd10'),  -- team member of both projects
       (118, 2, 102, 102, 'Department P', null),
       (119, 2, 102, 102, 'Department P2', null),       
       (120, 1, 102, 102, 'Paul', 'passwd11'),
       (121, 1, 102, 102, 'Pippa', 'passwd12'),
       (122, 1, 102, 102, 'Phil', 'passwd13'),
       (123, 1, 102, 102, 'Pete', 'passwd14'),
       (124, 1, 102, 102, 'Pam', 'passwd15');

grant all on demo.parties_tbl to demouser;

\echo ...parties...
-- Views must be created by an unprivileged user so that they do not
-- bypass our row-level security!!
-- An alternative to this is to build the view in under the privileged
-- user, creating it as a secured view.

grant create on schema demo to demouser;
set session authorization demouser;

create view demo.parties (
       party_id, party_type_id,
       corp_id, org_id, party_name,
       password) as
select party_id, party_type_id,
       corp_id, org_id, party_name,
       -- This view is a special case, as we don't want to show
       -- passwords, so a little extra massaging of the select clause
       -- is required.
       case when password is not null then
            'xxxxxxxxxxxx'
       else null
       end
  from demo.parties_tbl;

-- TODO: Instead-of triggers to manage inserts, updates and deletes.
-- This is an exercise for the reader.

grant all on demo.parties to demouser;

reset session authorization;
revoke create on schema demo from demouser;


\echo ...projects...
create table demo.projects (
  project_id 	      	integer not null primary key,
  corp_id		integer not null,
  org_id		integer not null,
  project_name		text not null,
    foreign key (corp_id) references demo.parties_tbl(party_id),
    unique (project_name, org_id),
    foreign key (org_id) references demo.parties_tbl(party_id)
);

grant all on table demo.projects to demouser;

insert
  into demo.projects
       (project_id, corp_id, org_id, project_name)
values (1, 101, 105, 'S.1'),
       (2, 101, 106, 'S2.1');


\echo ...project_assignments...
create table demo.project_assignments (
  project_id 	      	integer not null,
  party_id		integer not null,
  role_id		integer not null,
    primary key (project_id, party_id, role_id),
    foreign key (party_id) references demo.parties_tbl(party_id),
    foreign key (role_id) references veil2.roles(role_id)
);

grant all on table demo.project_assignments to demouser;


-- VPD SETUP
-- Refer to the Veil2 documentation for descriptions of the STEPs
-- below.  The numbered steps below are described in the "Setting Up A
-- Veil2' Virtual Private Database" section.

-- STEP 1 is installing Veil2

-- STEP 2 is defining authentication data and functions (and session
-- management)
-- For the purpose of this demo, we will be using only plaintext and
-- bcrypt so no new authentication methods have to be defined and
-- implemented. 
-- Furthermore as this demo is only for use in psql, we are doing no
-- proper session authentication.  Instead we just call open_session()
-- and create_session() manually and in a contrived manner.  This is
-- not good practice.  Keep your create_session() and open_session()
-- calls separate.  Your client should use the result of
-- create_session() to determine the parameters for subsequent
-- open_session() calls.

-- Enable plaintext authentication.  DO NOT DO THIS IN REAL LIFE!!!!

update veil2.authentication_types
   set enabled = true
 where shortname = 'plaintext';

-- Create get_accessor so that we can map from usernames in context to
-- accessor_ids.  This is used by create_session().
create or replace
function veil2.get_accessor(
    username in text,
    context_type_id in integer,
    context_id in integer)
  returns integer as
$$
declare
  _result integer;
begin
  select party_id
    into _result
    from demo.parties_tbl p
   where p.party_name = get_accessor.username
     and p.org_id = context_id
     and context_type_id = 4;  -- Logins are in org context
   return _result;
end;
$$
language plpgsql security definer stable leakproof;


create or replace
view veil2.accessor_contexts (
  accessor_id, context_type_id, context_id
) as
select party_id, 4, org_id
  from demo.parties_tbl where party_type_id = 1;


-- STEP 3:
-- Define scopes
-- We create corp, org and project scope types.  Orgs are parts of an
-- organisation in an organisational hierarchy.  Corps are the topmost
-- elements.  Projects are projects, owned by orgs.

insert into veil2.scope_types
       (scope_type_id, scope_type_name,
        description)
values (3, 'corp scope',
        'For access to data that is specific to corps.'),
       (4, 'org scope',
        'For access to data that is specific to subdivisions (orgs) of a corp.'),
       (5, 'project scope',
        'For access to data that is specific to to project members.');





-- STEP 4:
-- Define initial privileges - TODO: provide the scopes

insert into veil2.privileges
       (privilege_id, privilege_name,
        promotion_scope_type_id, description)
values (16, 'select party_types',
        null, 'Allow select on demo.party_types'),
       (17, 'select parties',
        null, 'Allow select on demo.parties'),
       (18, 'select roles',
        null, 'Allow select on the roles view'),
       (19, 'select role_roles',
        null, 'Allow select on the role_roles view'),
       (20, 'select party_roles',
        null, 'Allow select on the party_roles view'),
       (21, 'select projects',
        null, 'Allow select on the projects table'),
       (22, 'select project_assignments',
        null, 'Allow select on the project_assignments table');

-- STEP 5:
-- Link to/create initial roles

insert
  into veil2.roles
       (role_id, role_type_id, role_name,
        implicit, immutable, description)
values (5, 1, 'party viewer',
        false, true, 'can view party information'),
       (6, 1, 'role viewer',
        false, true, 'can view roles and assignments'),
       (7, 1, 'employee',
        false, false, 'can perform minimal employee duties'),
       (8, 1, 'administration auditor',
        false, false, 'can view administration data'),
       (9, 1, 'administrator',
        false, false, 'can manage administration data'),
       (10, 1, 'project manager',
        false, false, 'manages projects'),
       (11, 1, 'project viewer',
        false, true, 'can view project data'),
       (12, 1, 'project manipulator',
        false, true, 'can manipulate project data');

insert into veil2.role_privileges
       (role_id, privilege_id)
values (5, 16),  -- party viewer -> select_party_types
       (5, 17),  -- party viewer -> select_parties
       (6, 18),  -- role viewer -> select_roles
       (6, 19),  -- role viewer -> select role_roles
       (6, 20),  -- role viewer -> select party_roles
       (11, 21), -- project viewer -> select_projects
       (12, 21), -- project manipulator -> select projects
       (12, 22), -- project manipulator -> select project assignments
       (2, 13),  -- personal context -> select accessor_roles
       (2, 17),  -- personal context -> select parties
       (2, 22);  -- personal context -> select project_assignments

-- All of these are going to be assigned globally.  What this means is
-- that everyone's role->role mappings are the same.  If we had
-- context-specific role mappings, then each corp (or whatever) could
-- define their roles differently.  Only do this if you need to: it
-- makes things very confusing for an administrator.
insert into veil2.role_roles
       (primary_role_id, assigned_role_id,
        context_type_id, context_id)
values (7, 5, 1, 0),
       (8, 5, 1, 0),
       (8, 6, 1, 0),
       (9, 5, 1, 0),
       (9, 6, 1, 0),
       (7, 11, 1, 0),
       (10, 11, 1, 0),
       (10, 12, 1, 0);

-- STEP 6:
-- Create FK links for veil2.accessors to the demo database tables.
-- These ensure that veil2.accessors and veil2.authentication_details
-- are kept in step with the demo parties_tbl table.
--
alter table veil2.accessors add constraint accessor__party_fk
  foreign key (accessor_id) references demo.parties_tbl (party_id)
  on delete cascade on update cascade;

comment on constraint accessor__party_fk on veil2.accessors is
'FK to parties_tbl.  This ensures that updates and deletes in parties_tbl are
propagated to veil2.accessors.  This is to ensure that all users in
parties_tbl are known to veil2 for the purpose of authentication, etc.';

-- Create triggers on demo.parties_tbl to populate veil2.accessors
create or replace
function demo.parties_tbl_ai () returns trigger as
$$
begin
  insert
    into veil2.accessors
        (accessor_id, username)
  select new.party_id, new.party_name
   where new.party_type_id = 1;

  -- All authentication is currently done using plaintext.  This is
  -- quite inadequate and *NOT* something you should do in a real
  -- environment.
  insert
    into veil2.authentication_details
        (accessor_id, authentication_type, authent_token)
  select new.party_id, 'plaintext', new.password
   where new.party_type_id = 1;
   return new;
end;
$$
language plpgsql volatile security definer;

comment on function demo.parties_tbl_ai () is
'Propagate inserts, of people, into demo.parties_tbl to veil2.accessors';

create trigger parties_tbl_ait after insert on demo.parties_tbl
  for each row
  execute procedure demo.parties_tbl_ai();
  
comment on trigger parties_tbl_ait on demo.parties_tbl is
'Ensure inserts into demo.parties_tbl, get propagated to veil2.accessors';
  
-- Create initial accessor records from current parties_tbl records
insert into veil2.accessors
      (accessor_id, username)
select party_id, party_name
  from demo.parties_tbl p
 where p.party_type_id = 1
   and not exists (
   select null
     from veil2.accessors a
    where a.accessor_id = p.party_id);

-- Create initial authentication_detail records from current parties_tbl records
insert
  into veil2.authentication_details
      (accessor_id, authentication_type, authent_token)
select party_id, 'plaintext', password
  from demo.parties_tbl p
 where p.party_type_id = 1
   and not exists (
   select null
     from veil2.authentication_details a
    where a.accessor_id = p.party_id);

-- Deal with changes to passwords
create or replace
function demo.parties_tbl_au () returns trigger as
$$
begin
  update veil2.authentication_details
     set authent_token = new.password
   where new.party_type_id = 1
     and new.password != old.password
     and accessor_id = new.party_id;
   return new;
end;
$$
language plpgsql volatile security definer;

comment on function demo.parties_tbl_au () is
'Propagate updates of passwords to veil2.authentication_details';

create trigger parties_tbl_aut after update on demo.parties_tbl
  for each row
  when (new.password != old.password)
  execute procedure demo.parties_tbl_au();
  
comment on trigger parties_tbl_aut on demo.parties_tbl is
'Ensure password changes get propagated to veil2.authentication_details';

-- STEP7:
-- Link scopes back to the database being secured.
-- THIS SHOULD ALSO HANDLE UPDATES TO SOME OF THE CONTEXT VIEWS???


-- 5.1 Parties:
--     this handles corp and org contexts

alter table veil2.scopes
  add column party_id integer;

comment on column veil2.scopes.party_id is
'Foreign key column to parties_tbl for use in corp and org contexts.';

alter table veil2.scopes
  add constraint scope__party_fk
  foreign key (party_id)
  references demo.parties_tbl(party_id)
  on update cascade on delete cascade;

comment on constraint scope__party_fk on veil2.scopes is
'FK to parties_tbl for contexts that are party-specific.';

alter table veil2.scopes
  add constraint scope__check_fk_type
  check (case when scope_type_id in (3, 4) then
              party_id is not null
	 else true end);

comment on constraint scope__check_fk_type
  on veil2.scopes is
'Ensure that party-specific contexts have an FK.';



-- Create initial security contexts
insert
  into veil2.scopes
      (scope_type_id, scope_id, party_id)
select 3, party_id, party_id  -- These are all corp scopes
  from demo.parties_tbl
 where party_type_id = 2  -- organisation
   and org_id = 100;     -- root corp or first level below root

insert
  into veil2.scopes
      (scope_type_id, scope_id, party_id)
select 4, party_id, party_id  -- These are all org scopes
  from demo.parties_tbl
 where party_type_id = 2;  -- This includes corps which are also orgs

-- READER EXERCISE: create insert triggers on parties_tbl for new corps
-- and orgs. 

-- 5.2 Projects:
--     this handles project context
alter table veil2.scopes
  add column project_id integer;

comment on column veil2.scopes.project_id is
'Foreign key column to projects for use in project context.';

alter table veil2.scopes
  add constraint scope__project_fk
  foreign key (project_id)
  references demo.projects(project_id)
  on update cascade on delete cascade;

insert
  into veil2.scopes
      (scope_type_id, scope_id, project_id)
select 5, project_id, project_id
  from demo.projects;

-- Now we redefine all_accessor_roles to include project assignments.
-- With this done, the veil2.load_session_privs() function will see
-- the project_assignments and add these to the set of privileges seen
-- for a connected user.

create or replace
view veil2.all_accessor_roles (
  accessor_id, role_id, context_type_id, context_id
) as
select accessor_id, role_id,
       context_type_id, context_id
  from veil2.accessor_roles
 union
select party_id, role_id, 5, project_id
  from demo.project_assignments ;

-- Ensure updates to project_assignments are reflected in the
-- all_accessor_privs materialized view.

create trigger project_assignment__aiudt
  after insert or update or delete or truncate
  on demo.project_assignments
  for each statement
  execute procedure veil2.refresh_accessor_privs();

-- And update the matview now.
refresh materialized view veil2.all_accessor_privs;

-- READER EXERCISE: create insert triggers on projects table for new
-- projects. 



-- STEP 8:
-- Deal with scope promotions
-- Note that the second part of the union below allows scope promotion
-- within the organizational hierarchy.

create or replace
view veil2.scope_promotions (
  scope_type_id, scope_id,
  promoted_scope_type_id, promoted_scope_id
) as
select 4, party_id,  -- Promote org to corp scope
       3, corp_id
  from demo.parties_tbl -- No join needed to scopes as party_id == scope_id
 where party_type_id = 2
union all
select 3, party_id,  -- Promotion of org to higher org
       3, org_id
  from demo.parties_tbl -- No join needed to scopes as party_id == scope_id
 where party_type_id = 2
union all
select 5, s.scope_id,   -- Project to corp promotions
       3, p.corp_id
  from demo.projects p
 inner join veil2.scopes s
    on s.project_id = p.project_id
union all
select 5, s.scope_id,   -- Project to org promotions
       4, p.org_id
  from demo.projects p
 inner join veil2.scopes s
    on s.project_id = p.project_id;

refresh materialized view veil2.all_scope_promotions;

-- STEP 9:
-- Add row level security on our objects.

alter table demo.party_types enable row level security;

create policy party_type__select
    on demo.party_types
   for select
 using (veil2.i_have_global_priv(16));


alter table demo.parties_tbl enable row level security;

create policy parties_tbl__select
    on demo.parties_tbl
   for select
 using (   veil2.i_have_global_priv(17)
        or veil2.i_have_priv_in_scope(17, 3, corp_id)
        or veil2.i_have_priv_in_scope(17, 4, org_id)
        or veil2.i_have_priv_in_scope(17, 4, party_id) -- View the org itself
        or veil2.i_have_personal_priv(17, party_id));

-- READER EXERCISE: secure inserts, updates and deletes

alter table demo.projects enable row level security;

create policy projects__select
    on demo.projects
   for select
 using (   veil2.i_have_global_priv(21)
        or veil2.i_have_priv_in_scope(21, 3, corp_id)
        or veil2.i_have_priv_in_scope(21, 4, org_id)
        or veil2.i_have_priv_in_scope(21, 5, project_id));

alter table demo.project_assignments enable row level security;

create policy project_assignments__select
    on demo.project_assignments
   for select
 using (   veil2.i_have_global_priv(22)
        or veil2.i_have_priv_in_scope(22, 2, party_id)
        or veil2.i_have_priv_in_scope(21, 5, project_id)
	or veil2.i_have_priv_in_superior_scope(21, 5, project_id));


-- STEP 10:
-- Create secured views into user-facing parts of Veil2
-- ??????????
-- These are:
--   - roles
--   - role_roles
--   - accessor_roles
-- If we were using context_roles, they would be incorporated into all
-- of the views below to provide aliases for role names based upon our
-- own context.  An exercise for the reader.

create or replace
view roles (
    role_type,
    role_name,
    implicit,
    immutable,
    description) as
select rt.role_type_name, r.role_name,
       r.implicit, r.immutable,
       r.description
  from veil2.roles r
 inner join veil2.role_types rt
         on rt.role_type_id = r.role_type_id
 where veil2.i_have_global_priv(18);

-- WE SHOULD ALSO CREATE INSTEAD-OF TRIGGERS FOR THIS.  THAT IS LEFT
-- AS AN EXERCISE FOR THE READER.

create or replace
view role_roles (
    primary_role,
    assigned_role,
    context_type,
    corp_context_id,
    org_context_id) as
select pr.role_name, ar.role_name,
       st.scope_type_name,
       case when rr.context_type_id = 3
       then rr.context_id
       else null
       end,
       case when rr.context_type_id = 4
       then rr.context_id
       else null
       end 
  from veil2.role_roles rr
 inner join veil2.roles pr
         on pr.role_id = rr.primary_role_id
 inner join veil2.roles ar
         on ar.role_id = rr.assigned_role_id
 inner join veil2.scope_types st
         on st.scope_type_id = rr.context_type_id
 where veil2.i_have_global_priv(19)
    or veil2.i_have_priv_in_scope(19, 3, context_id)
    or veil2.i_have_priv_in_scope(19, 4, context_id);

-- WE SHOULD ALSO CREATE INSTEAD-OF TRIGGERS FOR THIS.  THAT IS LEFT
-- AS AN EXERCISE FOR THE READER.

create or replace
view party_roles (
    party_id,
    role_name,
    context_type,
    corp_context_id,
    org_context_id) as
select ar.accessor_id, r.role_name,
       st.scope_type_name,
       case when ar.context_type_id = 3
       then ar.context_id
       else null
       end,
       case when ar.context_type_id = 4
       then ar.context_id
       else null
       end 
  from veil2.accessor_roles ar
 inner join veil2.roles r
         on r.role_id = ar.role_id
 inner join veil2.scope_types st
         on st.scope_type_id = ar.context_type_id
 where veil2.i_have_global_priv(20)
    or veil2.i_have_priv_in_scope(20, 3, context_id)
    or veil2.i_have_priv_in_scope(20, 4, context_id);


-- Step 11
-- Assigning roles.

-- Give all persons the connect role
insert
  into veil2.accessor_roles
      (accessor_id, role_id, context_type_id, context_id)
select party_id, 0, 1, 0 
  from demo.parties_tbl
 where party_type_id = 1;

-- Give Specific roles to users
insert
  into veil2.accessor_roles
       (accessor_id, role_id, context_type_id, context_id)
values (108, 1, 1, 0),     -- Alice is global superuser
       (109, 1, 3, 101),   -- Bob is superuser for Secured Corp
       (110, 1, 3, 102),   -- Carol is superuser for Protected Corp
       (111, 1, 3, 101),   -- Eve is superuser for Secured Corp
       (111, 1, 3, 102),   -- and for Protected Corp
       (112, 1, 4, 105);   -- Sue is superuser for dept S.

-- Assign project roles
insert
  into demo.project_assignments
       (project_id, party_id, role_id)
values (1, 114, 10),  -- S.1 Simon, pm
       (2, 115, 10),  -- S2.1 Sara, pm
       (1, 116, 7),   -- S.1 Stef, member (employee)
       (1, 117, 7),   -- S.1 Steve, member (employee)
       (2, 117, 7);   -- S2.1 Steve, member (employee)


-- TESTS

-- TODO:
-- Check interleaving of sessions.
-- Check sessions using multiple connections.
-- Check sessions using database users.

select veil2.reset_session();

select * from demo.parties;

-- Convert Alice to use bcrypt.
update veil2.authentication_details
   set authent_token = veil2.bcrypt(authent_token),
       authentication_type = 'bcrypt'
 where accessor_id = 108;

\c vpd demouser

-- Log Alice in.
select *
  from veil2.create_session('Alice', 'bcrypt', 4, 100) c
 cross join veil2.open_session(c.session_id, 1, 'passwd1');

select 'Alice sees: ', * from demo.parties;

-- Log Bob in.
select *
  from veil2.create_session('Bob', 'plaintext', 4, 101) c
 cross join veil2.open_session(c.session_id, 1, 'passwd2') o1
 cross join veil2.open_session(c.session_id, 2,
             encode(digest(c.session_token || to_hex(2), 'sha1'),
	     	    'base64')) o2;
 
select 'Bob sees: ', * from demo.parties;


-- Log Carol in.
select *
  from veil2.create_session('Carol', 'plaintext', 4, 102) c
 cross join veil2.open_session(c.session_id, 1, 'passwd3') o1;

select 'Carol sees: ', * from demo.parties;

-- Log Eve in.
select *
  from veil2.create_session('Eve', 'plaintext', 4, 100) c
 cross join veil2.open_session(c.session_id, 1, 'passwd4') o1;

select 'Eve sees: ', * from demo.parties;


-- Log Sue in.
select *
  from veil2.create_session('Sue', 'plaintext', 4, 105) c
 cross join veil2.open_session(c.session_id, 1, 'passwd5') o1;

select 'Sue sees: ', * from demo.parties;

-- Log Simon in.
select *
  from veil2.create_session('Simon', 'plaintext', 4, 105) c
 cross join veil2.open_session(c.session_id, 1, 'passwd7') o1;

select 'Simon sees: ', * from demo.parties;
select 'Simon sees: ', * from demo.projects;




/*


How do I have a certain privilege?

i_have_priv_how(priv)

check in which contexts I have that priv.
For each context
  for each role assigned
    


*/
