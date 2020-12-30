/* ----------
 * veil2_demo--0.9.1.sql
 *
 *      Create the veil2 demo database,
 *
 *      Based on the template file veil_template.sql
 *
 *      Copyright (c) 2020 Marc Munro
 *      Author:  Marc Munro
 *	License: GPL V3
 *
 * ----------
 */


-- STEP 0
-- Define your database objects.  These will intially be entirely
-- independent of Veil2 unless you choose to use some of the Veil2
-- tables, such as roles, directly.

-- Create the veil2 demo database

do
$$
declare
  _result integer;
begin
  select 1 into _result from pg_roles where rolname = 'demouser';
  if not found then
    execute 'create role demouser with login password ''pass''';
  end if;
end;
$$;

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
values (1000, 2, 1000, 1000, 'Veil Corp', null),
       (1010, 2, 1010, 1010, 'Secured Corp', null),
       (1020, 2, 1020, 1020, 'Protected Corp', null),
       (1030, 2, 1010, 1010, 'Secured Top Div', null),
       (1040, 2, 1010, 1010, 'Secured 2nd Div', null),
       (1050, 2, 1010, 1030, 'Department S', null),
       (1060, 2, 1010, 1030, 'Department S2', null),
       (1070, 2, 1010, 1040, 'Department s (lower)', null),
       (1080, 1, 1000, 1000, 'Alice', 'passwd1'),   -- superuser
       (1090, 1, 1010, 1010, 'Bob', 'passwd2'),     -- superuser for Secured Corp
       (1100, 1, 1020, 1020, 'Carol', 'passwd3'),   -- superuser for Protected Corp
       (1110, 1, 1000, 1000, 'Eve', 'passwd4'),     -- superuser for both corps
       (1120, 1, 1010, 1050, 'Sue', 'passwd5'),     -- superuser for dept s
       (1130, 1, 1010, 1050, 'Sharon', 'passwd6'),  -- vp for dept s
       (1140, 1, 1010, 1050, 'Simon', 'passwd7'),   -- pm for project S.1
       (1150, 1, 1010, 1050, 'Sara', 'passwd8'),    -- pm for project S2.1
       (1160, 1, 1010, 1050, 'Stef', 'passwd9'),    -- team member of S.1
       (1170, 1, 1010, 1050, 'Steve', 'passwd10'),  -- team member of both projects
       (1180, 2, 1020, 1020, 'Department P', null),
       (1190, 2, 1020, 1020, 'Department P2', null),       
       (1200, 1, 1020, 1020, 'Paul', 'passwd11'),
       (1210, 1, 1020, 1020, 'Pippa', 'passwd12'),
       (1220, 1, 1020, 1020, 'Phil', 'passwd13'),
       (1230, 1, 1020, 1020, 'Pete', 'passwd14'),
       (1240, 1, 1020, 1020, 'Pam', 'passwd15');

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
values (1, 1010, 1050, 'S.1'),
       (2, 1010, 1060, 'S2.1');


\echo ...project_assignments...
create table demo.project_assignments (
  project_id 	      	integer not null,
  party_id		integer not null,
  role_id		integer not null,
    primary key (project_id, party_id, role_id),
    foreign key (party_id) references demo.parties_tbl(party_id)
);

grant all on table demo.project_assignments to demouser;

-- VPD SETUP
-- Refer to the Veil2 documentation for descriptions of the STEPs
-- below.  The numbered steps below are described in the "Setting Up A
-- Veil2' Virtual Private Database" section.

-- STEP 1 is installing Veil2, then we create the extension in this
-- database.  

-- STEP 1: Install Veil2

-- If you haven't installed the extension on your server, and have the
-- pgxn client installed:
-- $ pgxn install veil2
--
-- Install the Veil2 extension in your database.  We use cascade to
-- ensure that dependencies are also installed.

-- If you installed the veil_demo as an extension, the following
-- statement does nothing.
--create extension if not exists veil2 cascade;

-- STEP 2:
-- Define scopes
-- We create corp, org and project scope types.  Orgs are parts of an
-- organisation in an organisational hierarchy.  Corps are the topmost
-- elements.  Projects are projects, owned by orgs.
--

-- 2.1 Create new scopes by inserting records into veil2.scope_types.
-- 
insert into veil2.scope_types
       (scope_type_id, scope_type_name,
        description)
values (3, 'corp scope',
        'For access to data that is specific to corps.'),
       (4, 'org scope',
        'For access to data that is specific to subdivisions (orgs) of a corp.'),
       (5, 'project scope',
        'For access to data that is specific to to project members.');

-- 2.2 Define your role_mapping context.  If you intend to map all
-- roles in global_context then you don't need to do anything.  If you
-- are not sure about this, just skip it.  If you need it, it will
-- become obvious later

update veil2.system_parameters
   set parameter_value = 3
 where parameter_name = 'mapping context target scope type';


-- STEP 3:
-- Authentication stuff.

-- For the purpose of this demo, we will be using only plaintext and
-- bcrypt so no new authentication methods have to be defined and
-- implemented. 
-- Furthermore as this demo is only for use in psql, we are doing no
-- proper session authentication.  Instead we just call open_connection()
-- and create_session() manually and in a contrived manner.  This is
-- not good practice.  Keep your create_session() and open_connection()
-- calls separate.  Your client should use the result of
-- create_session() to determine the parameters for subsequent
-- open_connection() calls.

-- Enable plaintext authentication.  DO NOT DO THIS IN REAL LIFE!!!!

update veil2.authentication_types
   set enabled = true
 where shortname = 'plaintext';

-- 3.1 Create new authentication methods.

-- Nothing done here.

-- 3.2 Associate accessors and authentication contexts
-- This associates each accessor with an authentication context.
-- Typically each authentication context allows their own set of
-- usernames, so that Bob at ProtectedCorp is a different person from
-- Bob at SecuredCorp.

-- Set up accessor contexts.  All authentication will be in org context.
create or replace
view veil2.my_accessor_contexts (
  accessor_id, context_type_id, context_id
) as
select party_id, 4, org_id
  from demo.parties_tbl where party_type_id = 1;

-- 3.3 get_accessor()
-- Create a my_get_accessor() function that will take a username and
-- context, and return an accessor_id

-- Create get_accessor so that we can map from usernames in context to
-- accessor_ids.  This is used by create_session().
create or replace
function veil2.my_get_accessor(
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
   where p.party_name = username
     and p.org_id = context_id
     and context_type_id = 4;  -- Logins are in org context
   return _result;
end;
$$
language plpgsql security definer stable leakproof;

-- 3.4 Session Management Customizations
-- You may need to extend the set of Veil2 session management
-- functions, or provide mechanisms to invoke them from SQL if your
-- application is not flexible enough to use the built-in mechanisms
-- as they stand.  What this will look like will depend on what you
-- are trying to achieve.  It may be additional functions for managing
-- extra round-trips between the user and the database for some
-- imagined exotic authentication system, or it may be the tables and
-- triggers so that authentication can be performed solely using
-- simple insert and select statements.

-- Nothing to do here.


-- STEP 4:
-- Link Veil2 accessors to your database's users.

-- Create FK links for veil2.accessors to the demo database tables.
-- These ensure that veil2.accessors and veil2.authentication_details
-- are kept in step with the demo parties_tbl table.

-- We cannot add the FK directly to the accessors table as the new fk
-- would not be preserved by a restore from pg_dump.  Instead we have
-- to create a new table.  Note that since we use the same accessor_id
-- value in our demo tables as Veil2 uses itself, the mapping is
-- trivial (accessor_id to itself).  If your application is unable to
-- use Veil's accessor_id, the mapping table would have to map from
-- the Veil accessor_id to your user_id (ie it would contain 2
-- columns) and each foreign key below would be on a different column.

-- 4.1 Create a mapping table
-- Note that you may have multiple users tables and so you may need 
-- multiple FK fields back to your database.  If so, you may want to
-- add a check constraint to ensure that only 1 of them is not null.

create table veil2.accessor_party_map (
  accessor_id		integer not null
);

alter table veil2.accessor_party_map
  add constraint accessor_party_map__pk
  primary key(accessor_id);
  
alter table veil2.accessor_party_map
  add constraint accessor_party_map__accessor_fk
  foreign key(accessor_id)
  references veil2.accessors(accessor_id)
  on delete cascade;

alter table veil2.accessor_party_map
  add constraint accessor_party_map__party_fk
  foreign key(accessor_id)
  references demo.parties_tbl (party_id);
  
-- You should probably index the other FK columns
-- No, need: there are no other FK columns.


-- 4.2 Copy Existing User Records
-- 

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


-- 4.3 Copy existing authentication records
-- This is going to be tricky as it is unlikely that the
-- authentication tokens in your database are going to match those
-- exepected by Veil2.  See the Veil2 documentation for Step 4 for
-- more information.

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


-- 4.4 Create Referential Integrity Triggers
-- On insert and on delete triggers are needed as a minimum.  If
-- updates are allowed to change the user id fields, then we will also
-- need to deal with updates.  Far better though to simply have an
-- on-update trigger that fails if such an attempt is made. 

-- Create triggers on demo.parties_tbl to keep veil2.accessors in step.
create or replace
function demo.parties_tbl_ai () returns trigger as
$$
begin
  insert
    into veil2.accessors
        (accessor_id, username)
  select new.party_id, new.party_name
   where new.party_type_id = 1;

  insert
    into veil2.accessor_party_map
        (accessor_id)
  select new.party_id
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

-- WE SHOULD ALSO HANDLE UPDATES TO THE PARTY_ID AND DELETIONS.  THIS
-- IS LEFT AS AN EXERCISE FOR THE READER.


-- 4.5 Authentication Token Handling Triggers
-- Ideally, we will stop recording authentication tokens in the old
-- database tables and instead record them in
-- veil2.authentication_details.

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




-- STEP 5: Link your scopes

-- 5.1 Extend the veil2.scopes table to link to the tables that define
-- your scopes.

-- Extend veil2.scopes using inheritence
create table veil2.scope_links (
  party_id 	integer,
  project_id	integer
) inherits (veil2.scopes);

-- Define Keys for the extended table - these do not get created
-- automatically.
alter table veil2.scope_links add constraint scope_link__pk
  primary key(scope_type_id, scope_id);

alter table veil2.scope_links add constraint scope_link__type_fk
  foreign key(scope_type_id)
  references veil2.scope_types;

-- Define FKs for each <newcolumns>
alter table veil2.scope_links
  add constraint scope_link__party_fk
  foreign key (party_id)
  references demo.parties_tbl(party_id)
  on delete cascade;

-- ditto
alter table veil2.scope_links
  add constraint scope_link__project_fk
  foreign key (project_id)
  references demo.projects(project_id)
  on delete cascade;

comment on column veil2.scope_links.party_id is
'Foreign key column to parties_tbl for use in corp and org contexts.';

comment on column veil2.scope_links.project_id is
'Foreign key column to projects for use in project context.';

-- You may also want to define a check constraint to ensure that only
-- one of the <newcolumn> columns is null.  We might also check that
-- the scope_type_id (an inherited column) is apprpriate for the
-- <newcolumn> that is not null.

alter table veil2.scope_links
  add constraint scope_link__check_fk_type
  check (case
         when scope_type_id in (3, 4) then
              party_id is not null
	 when scope_type_id = 5 then
	      project_id is not null
	 else true end);

comment on constraint scope_link__check_fk_type
  on veil2.scope_links is
'Ensure that party or project-specific contexts have an appropriate FK.';

-- 5.2 Create on-insert triggers to handle new scopes
-- Add a trigger for *each* scope type.

-- 5.3 Create on update triggers
-- Add a trigger for *each* scope type.

-- READER EXERCISE: create triggers on parties_tbl and projects for
-- to automatically propagate inserts updates and deletes back to the
-- scope_links tables.

-- 5.4 Copy existing scope data into the links table.

-- Create initial security contexts...
-- ...for corps...
insert
  into veil2.scope_links
      (scope_type_id, scope_id, party_id)
select 3, party_id, party_id  -- These are all corp scopes
  from demo.parties_tbl
 where party_type_id = 2    -- organisation
   and party_id = corp_id;  -- This is a corp

-- ...for orgs...
insert
  into veil2.scope_links
      (scope_type_id, scope_id, party_id)
select 4, party_id, party_id  -- These are all org scopes
  from demo.parties_tbl
 where party_type_id = 2;  -- This includes corps which are also orgs

-- ...for projects...
insert
  into veil2.scope_links
      (scope_type_id, scope_id, project_id)
select 5, project_id, project_id
  from demo.projects;


-- 5.5 Update the all_accessor_roles view

-- Now we modify all_accessor_roles to include project assignments.
-- With this done, the veil2.load_session_privs() function will see
-- the project_assignments and add these to the set of privileges seen
-- for a connected user.

create or replace
view veil2.my_all_accessor_roles (
  accessor_id, role_id, context_type_id, context_id
) as
select accessor_id, role_id,
       context_type_id, context_id
  from veil2.accessor_roles
 union all
select party_id, role_id, 5, project_id
  from demo.project_assignments ;


-- 5.6 Create triggers on updates to accessor roles
-- There is no need to do this on the veil2.accessor_roles table as
-- this is already done.

-- ADDING THESE TRIGGERS IS ANOTHER READER EXERCISE.


-- STEP 6: Define Scope Hierarchy

-- 6.1
-- Define the my_superior_scopes view

-- Note that the second part of the union below allows scope promotion
-- within the organizational hierarchy.
create or replace
view veil2.my_superior_scopes (
  scope_type_id, scope_id,
  superior_scope_type_id, superior_scope_id
) as
select 4, party_id,  -- Promote org to corp scope
       3, corp_id
  from demo.parties_tbl 
 where party_type_id = 2
union all
select 4, party_id,  -- Promotion of org to higher org
       4, org_id
  from demo.parties_tbl
 where party_type_id = 2
   and party_id != org_id  -- Cannot promote to self
union all
select 5, s.scope_id,   -- Project to corp promotions
       3, p.corp_id
  from demo.projects p
 inner join veil2.scope_links s
    on s.project_id = p.project_id
union all
select 5, s.scope_id,   -- Project to org promotions
       4, p.org_id
  from demo.projects p
 inner join veil2.scope_links s
    on s.project_id = p.project_id;

-- 6.2 
-- Refresh matviews if scope hierarchy changes
-- Create triggers on modification of the scope hierarchy

-- MORE READER EXERCISES HERE


-- STEP 7:
-- Define privileges.  Note that priv_ids below 20 are used for veil2
-- objects.

insert into veil2.privileges
       (privilege_id, privilege_name,
        promotion_scope_type_id, description)
values (20, 'select party_types',
        1, 'Allow select on demo.party_types'),
       (21, 'select parties',
        null, 'Allow select on demo.parties'),
       (22, 'select roles',
        null, 'Allow select on the roles view'),
       (23, 'select role_roles',
        null, 'Allow select on the role_roles view'),
       (24, 'select party_roles',
        null, 'Allow select on the party_roles view'),
       (25, 'select projects',
        null, 'Allow select on the projects table'),
       (26, 'select project_assignments',
        null, 'Allow select on the project_assignments table'),
       (27, 'select orgs',
        4, 'Allow select on parties that are orgs');

-- Priv 27 is intended to allow project members to see the org that
-- owns the project even if they have not been given select-party
-- privilege in any other context.


-- STEP 8:
-- Define/integrate roles

-- Create some new role_types.  These allow us to differentiate
-- between user and function-level roles and could be used, for
-- example, in views to differentiate between roles that can be
-- renamed within a spcecific context, and those that cannot.

insert
  into veil2.role_types
       (role_type_id, role_type_name, description)
values (3, 'Function-level role',
        'Demo App Role for access control to specific functions/data'),
       (4, 'User-level role',
        'Demo App Role that will be assigned to accessors');

-- 8.1 Integrate veil2 roles with your system's equivalent, if it has
-- one.

-- Link project_assignments to roles.  Your assignment to a project
-- comes with one or more roles that define what you can do on/with
-- the project.
alter table demo.project_assignments
  add constraint project_assignments__role_fk
  foreign key (role_id) references veil2.roles(role_id);

-- 8.2 Create new roles and mappings
--
insert
  into veil2.roles
       (role_id, role_type_id, role_name,
        implicit, immutable, description)
values (5, 3, 'party viewer',
        false, true, 'can view party information'),
       (6, 3, 'role viewer',
        false, true, 'can view roles and assignments'),
       (7, 4, 'employee',
        false, false, 'can perform minimal employee duties'),
       (8, 4, 'administration auditor',
        false, false, 'can view administration data'),
       (9, 4, 'administrator',
        false, false, 'can manage administration data'),
       (10, 4, 'project manager',
        false, false, 'manages projects'),
       (11, 4, 'project viewer',
        false, true, 'can view project data'),
       (12, 4, 'project manipulator',
        false, true, 'can manipulate project data'),
       (13, 3, 'dummy fn role 1',
        false, true, 'For demo purposes'),
       (14, 3, 'dummy fn role 2',
        false, true, 'For demo purposes'),
       (15, 3, 'dummy fn role 3',
        false, true, 'For demo purposes'),
       (16, 4, 'dummy user role 1',
        false, false, 'For demo purposes');

insert into veil2.role_privileges
       (role_id, privilege_id)
values (5, 20),  -- party viewer -> select_party_types
       (5, 21),  -- party viewer -> select_parties
       (6, 22),  -- role viewer -> select_roles
       (6, 23),  -- role viewer -> select role_roles
       (6, 24),  -- role viewer -> select party_roles
       (11, 20), -- project viewer -> select_party_types
       (11, 27), -- project viewer -> select_orgs
       (11, 25), -- project viewer -> select_projects
       (12, 25), -- project manipulator -> select projects
       (12, 26), -- project manipulator -> select project assignments
       (2, 13),  -- personal context -> select accessor_roles
       (2, 21),  -- personal context -> select parties
       (2, 26);  -- personal context -> select project_assignments

-- We define a base set of role->role mappings in global context,
-- though these are not actually used.  Then we create copies in the
-- contexts of each of our corps along with some corp-specific
-- mappings so that we can test and demonstrate the mechanism.
--
insert into veil2.role_roles
       (primary_role_id, assigned_role_id,
        context_type_id, context_id)
values (7, 5, 1, 0),  -- In global context
       (8, 5, 1, 0),
       (8, 6, 1, 0),
       (9, 5, 1, 0),
       (9, 6, 1, 0),
       (7, 11, 1, 0),
       (10, 11, 1, 0),
       (10, 12, 1, 0),
       (7, 5, 3, 1010),   -- The same in context of Secured Corp
       (8, 5, 3, 1010),
       (8, 6, 3, 1010),
       (9, 5, 3, 1010),
       (9, 6, 3, 1010),
       (7, 11, 3, 1010),
       (10, 11, 3, 1010),
       (10, 12, 3, 1010),
       (7, 5, 3, 1020),-- Ditto in context of Protected Corp
       (8, 5, 3, 1020),
       (8, 6, 3, 1020),
       (9, 5, 3, 1020),
       (9, 6, 3, 1020),
       (7, 11, 3, 1020),
       (10, 11, 3, 1020),
       (10, 12, 3, 1020),
       (16, 13, 3, 1010),  -- user role 1 gets fn roles 1 & 2 in Secured Corp
       (16, 14, 3, 1010),
       (16, 14, 3, 1020),  -- user role 1 gets fn roles 2 & 3 in Protected Corp
       (16, 15, 3, 1020);


-- STEP 9:
-- Secure Tables

alter table demo.party_types enable row level security;

create policy party_type__select
    on demo.party_types
   for select
 using (veil2.i_have_global_priv(20));


alter table demo.parties_tbl enable row level security;

create policy parties_tbl__select
    on demo.parties_tbl
   for select
 using (   veil2.i_have_priv_in_scope_or_global(21, 3, corp_id)
        or veil2.i_have_priv_in_scope(21, 4, org_id)
        or veil2.i_have_priv_in_scope(21, 4, party_id) -- View the org itself
        or veil2.i_have_personal_priv(21, party_id)
	or (    party_type_id = 2    -- View an org that owns a project
	    and veil2.i_have_priv_in_scope(27, 4, party_id)));


-- READER EXERCISE: secure inserts, updates and deletes

alter table demo.projects enable row level security;

create policy projects__select
    on demo.projects
   for select
 using (   veil2.i_have_priv_in_scope_or_global(25, 3, corp_id)
        or veil2.i_have_priv_in_scope(25, 4, org_id)
        or veil2.i_have_priv_in_scope(25, 5, project_id));

alter table demo.project_assignments enable row level security;

create policy project_assignments__select
    on demo.project_assignments
   for select
 using (   veil2.i_have_priv_in_scope_or_global(26, 5, project_id)
	or veil2.i_have_priv_in_superior_scope(26, 5, project_id)
        or veil2.i_have_personal_priv(26, party_id));

-- No access to scope_links except through triggers, etc
create policy scope_links__all
    on veil2.scope_links
   for all;

alter table veil2.scope_links enable row level security;

-- Ditto accessor_party_map
create policy accessor_party_map__all
    on veil2.accessor_party_map
   for all;

alter table veil2.accessor_party_map enable row level security;

-- STEP 10:
-- Secure Views

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
 where veil2.i_have_global_priv(22);

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
 where veil2.i_have_priv_in_scope_or_global(23, 3, context_id)
    or veil2.i_have_priv_in_scope(23, 4, context_id);

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
 where veil2.i_have_priv_in_scope_or_global(24, 3, context_id)
    or veil2.i_have_priv_in_scope(24, 4, context_id);


-- Check how we are doing.
-- WE CANNOT DO THIS IN THE EXTENSION AS IT CAUSES OUR USER-SUPPLIED
-- VEIL FUNCTIONS TO ATTEMPT TO TAKE THE PLACE OF THE SYSTEM-PROVIDED
-- ONES.  THAT MUST BE DONE OUTSIDE OF THE EXTENSION INSTALLATION.
--select * from veil2.implementation_status();


-- Step 11:
-- Assign roles to accessors

-- Give all persons except Eve the connect role globally
insert
  into veil2.accessor_roles
      (accessor_id, role_id, context_type_id, context_id)
select party_id, 0, 1, 0 
  from demo.parties_tbl
 where party_type_id = 1
   and party_id != 1110;

-- Give Specific roles to users
insert
  into veil2.accessor_roles
       (accessor_id, role_id, context_type_id, context_id)
values (1080, 1, 1, 0),     -- Alice is global superuser
       (1090, 1, 3, 1010),   -- Bob is superuser for Secured Corp
       (1100, 1, 3, 1020),   -- Carol is superuser for Protected Corp
       (1110, 1, 3, 1010),   -- Eve is superuser for Secured Corp
       (1110, 1, 3, 1020),   --  and for Protected Corp
       (1110, 0, 3, 1000),   -- Eve has connect for Veil Corp
       (1110, 0, 3, 1010),   -- Eve has connect for Secured Corp
       (1110, 16, 3, 1010),  --  and has dummy user role 1
       (1110, 16, 3, 1020),  --   for each corp.
       (1140, 16, 3, 1010),  -- Simon has dummy user role 1
       (1140, 16, 3, 1020),  --   for each corp.
       (1120, 1, 4, 1050);   -- Sue is superuser for dept S.

-- Assign project roles
insert
  into demo.project_assignments
       (project_id, party_id, role_id)
values (1, 1140, 10),  -- S.1 Simon, pm
       (2, 1150, 10),  -- S2.1 Sara, pm
       (1, 1160, 7),   -- S.1 Stef, member (employee)
       (1, 1170, 7),   -- S.1 Steve, member (employee)
       (2, 1170, 7);   -- S2.1 Steve, member (employee)

select veil2.reset_session();

-- Convert Alice to use bcrypt - this is mostly for test purposes.
update veil2.authentication_details
   set authent_token = veil2.bcrypt(authent_token),
       authentication_type = 'bcrypt'
 where accessor_id = 1080;


