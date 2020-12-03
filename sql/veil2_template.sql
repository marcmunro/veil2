/* ----------
 * veil_template
 *
 *      Template for bringing Veil2 security to your database
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

-- STEP 1: Install Veil2

-- If you haven't installed the extension on your server, and have the
-- pgxn client installed:
-- $ pgxn install veil2
--
-- Install the Veil2 extension in your database.  We use cascade to
-- ensure that dependencies are also installed.
create extension if not exists veil2 cascade;


-- STEP 2:
-- Define scopes

-- 2.1 Create new scopes by inserting records into veil2.scope_types.
-- 
/* 
insert 
  into veil2.scope_types
       (scope_type_id, scope_type_name,
        description)
values (,,),
       (,,),
       (,,);
*/

-- 2.2 Define your role_mapping context.  If you intend to map all
-- roles in global_context then you don't need to do anything.  If you
-- are not sure about this, just skip it.  If you need it, it will
-- become obvious later
/*
update veil2.system_parameters
   set parameter_value = 
 where parameter_name = 'mapping context target scope type';
*/


-- STEP 3:
-- Authentication stuff.

-- Create new authentication types if you need them.

-- 3.1 Create new authentication methods.
/*
insert
  into veil2.authentication_types
       (shortname, enabled, description,
        authent_fn, supplemental_fn)
values (,,,,),
       (,,,,),
       (,,,,);

create or replace
function veil2.authenticate_xxxxxx()
    accessor_id integer,
    token text)
  returns bool as
$$
$$
language 'whatever' security definer stable leakproof;

-- 3.2 Associate accessors and authentication contexts
-- This associates each accessor with an authentication context.
-- Typically each authentication context allows their own set of
-- usernames, so that Bob at ProtectedCorp is a different person from
-- Bob at SecuredCorp.

/*
create or replace
view veil2.my_accessor_contexts (
  accessor_id, context_type_id, context_id
) as
select ,,
  from some-of-my-tables-and-views;
*/

-- 3.3 get_accessor()
-- Create a my_get_accessor() function that will take a username and
-- context, and return an accessor_id

/*
create or replace
function veil2.my_get_accessor(
    username in text,
    context_type_id in integer,
    context_id in integer)
  returns integer as
$$
$$
language 'whatever' security definer stable leakproof;
*/

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

/* ?? */


-- STEP 4:
-- Link Veil2 accessors to your database's users.

-- 4.1 Create a mapping table
-- Note that you may have multiple users tables and so you may need 
-- multiple FK fields back to your database.  If so, you may want to
-- add a check constraint to ensure that only 1 of them is not null.

/*
create table veil2.accessor_users_map (
  accessor_id		integer not null,
  . . .
);

alter table veil2.accessor_users_map add constraint accessor_users__pk 
  primary key (accessor_id);

alter table veil2.accessor_users_map add constraint accessor__accessor_fk
  foreign key (accessor_id)
  references veil2.accessors(accessor_id);

-- You should probably index the other FK columns
create index accessor__user_idx
  on veil2.accessor_users_map(??);

-- And you must create FKs
alter table veil2.accessor_users_map add constraint accessor__user_fk
  foreign key (??)
  references ??.??(??);

*/

-- 4.2 Copy Existing User Records
-- 

/*
-- We will probably want to create new accessor_ids using a sequence...

create sequence veil2.accessor_id_seq;

-- Do this in plpgsql as we need to insert into 2 target tables for
-- each source record.
do
$$
declare
  rec record;
begin
  for rec in
    select <id fields>, 
    	   nextval('veil2.accessor_id_seq') as accessor_id
      from <user_tables>
  loop
    insert 
      into veil2.accessors
           (accessor_id, username)
    values (rec.accessor_id,
            rec.<username field>);
    insert
      into veil2.accessor_users_map
           (accessor_id, <user id fields>)
    values (rec.accessor_id,
            rec.<user id fields>);
  end loop;
end;
$$
language plpgsql;
 */

-- 4.3 Copy existing authentication records
-- This is going to be tricky as it is unlikely that the
-- authentication tokens in your database are going to match those
-- exepected by Veil2.  See the Veil2 documentation for Step 4 for
-- more information.

/*
insert
  into veil2.authentication_details
      (accessor_id, authentication_type, authent_token)
select a.accessor_id, 'bcrypt', u.<token>
  from <user_table> u
 inner join veil2.accessors a
    on a.<user id> = u.<user id>;
*/

-- 4.4 Create Referential Integrity Triggers
-- On insert and on delete triggers are needed as a minimum.  If
-- updates are allowed to change the user id fields, then we will also
-- need to deal with updates.  Far better though to simply have an
-- on-update trigger that fails if such an attempt is made. 

/*
create or replace
function <user_insert_trigger_fn_name>() returns trigger as
$$
declare
  _accessor_id integer;
begin
  -- A new <user table> record has been created.  Create the
  -- appropriate records in veil2
  _accesor_id := nextval('veil2.accessor_id_seq');
  insert 
    into veil2.accessors
         (accessor_id, username)
  values (_accessor_id,
          new.<username field>);
  insert
    into veil2.accessor_users_map
         (accessor_id, <user id fields>)
  values (_accessor_id,
          rec.<user id fields>);
  -- Note that you may also need to deal with authentication details
  -- here if the current token is created in the <users> table.
  return new;
end;
$$
language plpgsql security definer volatile;

create trigger <user_table>_bi_trg
  before insert on <user table name>
  for each row
  execute procedure <user_insert_trigger_fn_name>();


create or replace
function <user_delete_trigger_fn_name>() returns trigger as
$$
declare
  _accessor_id integer;
begin
  delete from veil2.accessor_users_map
   where <user id> = old.<user id>
  returning accessor_id into _accessor_id;

  delete
    from veil2.authentication_details
   where accessor_id = _accessor_id;

  delete
    from veil2.accessor_roles
   where accessor_id = _accessor_id;

  delete
    from veil2.accessor_privileges_cache
   where accessor_id = _accessor_id;

  delete
    from veil2.accessors
   where accessor_id = _accessor_id;
  return old;
end;
$$
language plpgsql security definer volatile;

create trigger <user_table>_bd_trg
  before delete on <user table name>
  for each row
  execute procedure <user_delete_trigger_fn_name>();

-- Also do something for updates.  See comments above
*/

-- 4.5 Authentication Token Handling Triggers
-- Ideally, we will stop recording authentication tokens in the old
-- database tables and instead record them in
-- veil2.authentication_details.

/*
-- This assumes that the authentication details in our protected
-- database are not stored in the same table as the basic user data.
-- If it is then this functionaloty must be handled in the referential
-- integrity triggers - see above.

create or replace
function <authent_insert_trigger_fn_name>() returns trigger as
$$
begin
  insert
    into veil2.authentication_details  
        (accessor_id, authentication_type, authent_token)
  select m.accessor_id, 'whatever',
         <some translation of the incoming token?>
    from accessor_users_map
   where <user id> = new.<user id>;

   -- Hide the authentication token from the old table.
   new.<incoming_token> := 'xxxxxxxxxxx';
  return new;
end;
$$
language plpgsql security definer volatile;

-- Check how we are doing.
select * from veil2.implementation_status();

create trigger <authent>_bi_trg
  before insert on <authent table name>
  for each row
  execute procedure <authent_insert_trigger_fn_name>();

create or replace
function <authent_update_trigger_fn_name>() returns trigger as
$$
begin
  update veil2.authentication_details  
     set authent_token = <some translation of the incoming token?>
   where accessor_id = (
       select accessor_id         
        from accessor_users_map
       where <user id> = new.<user id>);

   -- Hide the authentication token from the old table.
   new.<incoming_token> := 'xxxxxxxxxxx';
  return new;
end;
$$
language plpgsql security definer volatile;

create trigger <authent>_bu_trg
  before update on <authent table name>
  for each row
  execute procedure <authent_update_trigger_fn_name>();

-- Deletion trigger should not be needed, as deleting the user will
-- generally do the job.  However, YMMV.

*/


-- STEP 5: Link your scopes

-- 5.1 Extend the veil2.scopes table to link to the tables that define
-- your scopes.

/*
-- Extend veil2.scopes using inheritence
create table veil2.scope_links (
  <new id column definition>,
  <new id column definition>
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
  foreign key (<new id column>)
  references <source table for new id column>(<new id column>)
  on update cascade on delete cascade;

-- You may also want to define a check constraint to ensure that only
-- one of the <newcolumn> columns is null.  We might also check that
-- the scope_type_id (an inherited column) is apprpriate for the
-- <newcolumn> that is not null.

*/

-- 5.2 Create on-insert triggers to handle new scopes

/*
-- Add a trigger for *each* scope type.
create or replace
function <scope_insert_trigger_fn_name>() returns trigger as
$$
begin
  insert
    into veil2.scope_types
         (scope_type_id, scope_id,
          <new id column>)
  values (<appropriate scope_type for new id colum>, <new id column>,
          <new id column>;
  return new;
end;
$$
language plpgsql security definer volatile;

create trigger <scope>_bi_trg
  before insert on <scope table name>
  for each row
  execute procedure <scope_insert_trigger_fn_name>();
*/

-- 5.3 Create on update triggers

/*
-- Add a trigger for *each* scope type.
create or replace
function <scope_update_trigger_fn_name>() returns trigger as
$$
begin
  if new.<key fields> != old.<key fields> then
    raise exception 'NOCANDO: You cannot change the PK field of <table>';
  end if;
  return new;
end;
$$
language plpgsql security definer volatile;

create trigger <scope>_bu_trg
  before update on <scope table name>
  for each row
  execute procedure <scope_update_trigger_fn_name>();
*/

-- 5.4 Copy existing scope data into the links table.

/*
-- Copy existing scopes for *each* scope type.
insert
  into veil2.scope_links
      (scope_type_id, scope_id, <new id column>)
select <appropriate scope type>, <id column>,
       <id column>
  from <source table for new id column>
 where <?????>;
*/

-- 5.5 Update the all_accessor_roles view

/*
create or replace
view veil2.my_all_accessor_roles (
  accessor_id, role_id, context_type_id, context_id
) as
select accessor_id, role_id,
       context_type_id, context_id
  from veil2.accessor_roles
 union all
select party_id, role_id, 
       <appropriate scope type id>, <foreign key column>
  from <foreign scope table>
 union all
select party_id, role_id, 
       <appropriate scope type id>, <foreign key column>
  from <foreign scope table>;
*/

-- 5.6 Create triggers on updates to accessor roles
-- There is no need to do this on the veil2.accessor_roles table as
-- this is already done.

/*
-- For each table providing data to my_all_accessor_roles...

create trigger <tablename>_biud_trg
  before insert or update or delete on <role assignment table>
  for each row
  execute procedure veil2.clear_accessor_privs_cache_entry();

-- You should probably ensure that truncation of the above table does
-- not happen.  If, for some reason you need to allow it, create a
-- trigger for truncation that calls veil2.clear_accessor_privs_cache();

*/


-- STEP 6: Define Scope Hierarchy

/*
-- 6.1
-- Define the my_superior_scopes view

create or replace
view veil2.my_superior_scopes (
  scope_type_id, scope_id,
  superior_scope_type_id, superior_scope_id
) as
select <scope_type_id>, <scope_id>
       <superior_scope_type_id>, <superior_scope_id>
  from <??>
 where <??>
union all
select <scope_type_id>, <scope_id>
       <superior_scope_type_id>, <superior_scope_id>
  from <??>
 where <??>
union all
 . . .';

-- 6.2 
-- Refresh matviews if scope hierarchy changes
-- Create triggers on modification of the scope hierarchy

create trigger privileges__aiud
  after insert or update or delete or truncate
  on <source table>
  for each statement
  execute procedure veil2.refresh_scopes_matviews();

-- Alternatively, if you need your trigger function to determine
-- whether a change is significant enough to warrant clearing the
-- matviews, you can call the function veil2.refresh_all_matviews()
-- from your custom trigger function.
 */


-- STEP 7:
-- Define privileges.  Note that priv_ids below 20 are reserved for Veil2
-- objects

/*
insert into veil2.privileges
       (privilege_id, privilege_name,
        promotion_scope_type_id, description)
values (20, <privname>
        <null or ??>, <priv description>,
       (21, <privname>
        <null or ??>, <priv description>,
       (22, <privname>
        <null or ??>, <priv description>,
       . . .;
*/

-- STEP 8:
-- Define/integrate roles

-- 8.1 Integrate veil2 roles with your system's equivalent, if it has
-- one.

/* 
-- We will assume that your existing objects are going to use veil2's
-- roles.  If not, you will have to figure all of this out for
-- yourself.

-- For each protected table that needs to reference veil2.roles:
alter table <protected table>
  add constraint <protected_tablename>__role_fk
  foreign key (role_id) references veil2.roles(role_id);
*/

-- 8.2 Create new roles and mappings
--
/*
insert
  into veil2.roles
       (role_id, role_type_id, role_name,
        implicit, immutable, description)
values (,,,,,),
       (,,,,,),
       ...;

insert into veil2.role_privileges
       (role_id, privilege_id)
values (,)
       (,), 
       ...;

insert into veil2.role_roles
       (primary_role_id, assigned_role_id,
        context_type_id, context_id)
values (,,,),
       (,,,),
       ...;
*/

-- STEP 9:
-- Secure Tables

/*
-- For each table

alter table <table name> enable row level security;

-- For each operation (insert, update, select, delete) that you need
-- to secure:
create policy <table name>_select
    on <table name>
   for select
 using veil2.i_have_xxxx(<priv>,??);

revoke all on <table name> from public;
greant <appropriate operations> on table_name to <your access role>;

*/

-- STEP 10:
-- Secure Views

/*
-- For each view

create or replace
view view_name as
select ....
 where veil2.i_have_xxxx(<priv>,??);

-- Create appropriate instead-of triggers if the view is to be
-- updatable.

*/

-- Check how we are doing.
select * from veil2.implementation_status();

create trigger <authent>_bi_trg
  before insert on <authent table name>
  for each row
  execute procedure <authent_insert_trigger_fn_name>();


-- Step 11:
-- Assign roles to accessors

-- ...


