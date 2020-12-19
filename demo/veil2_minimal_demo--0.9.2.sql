/* ----------
 * minimal_demo.sql
 *
 *      A minimal demo of veil2, build using ../sql/veil2_template.sql
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

-- This is a simple database that allows users to post stuff, that
-- other users may or may not be able to see.

-- Trigger function usable by various triggers.
create or replace
function nocando() returns trigger as
$$
begin
  -- Prevent whatever was being attempted.  This should really take a
  -- parameter for an error message and cause the transaction to fail,
  -- but this is good enough for now.
  return null;
end;
$$
language plpgsql security definer volatile;


create table users (
  accessor_id integer not null primary key,
  username    text not null unique,
  password    text not null
);

insert
  into users
       (accessor_id, username, password)
values (1, 'Alice', 'passwd_alice'),
       (2, 'Bob', 'passwd_bob'),
       (3, 'Carol', 'passwd_carol'),
       (4, 'Dave', 'passwd_dave'),
       (5, 'Eve', 'passwd_eve'),
       (6, 'Sue', 'passwd_sue'),
       (7, 'Simon', 'passwd_simon');

create table follower_types (
  follower_type_id	    integer not null primary key,
  follower_type_name	    text not null unique,
  description		    text
);

insert
  into follower_types
       (follower_type_id, follower_type_name, description)
values (1, 'friend_request',
        'This requests that follows becomes a friend to follower'),
       (2, 'friend_acceptance',
        'This identifies that follower has become a friend to follows'),
       (3, 'follower',
        'This identifies that follower anonymously follows follows');

create table followers (
  follower_type_id     integer not null,
  follower	       integer not null,
  follows	       integer not null
);

alter table followers add constraint follower__pk
  primary key(follower, follows, follower_type_id);

alter table followers add constraint follower__type_fk
  foreign key(follower_type_id)
  references follower_types(follower_type_id);

alter table followers add constraint follower__follower_fk
  foreign key(follower)
  references users(accessor_id);

alter table followers add constraint follower__follows_fk
  foreign key(follows)
  references users(accessor_id);

create or replace
function follower_friend_check() returns trigger as
$$
declare
  _ok boolean;
begin
  -- Ensure that there is a friend request matching the friend
  -- acceptance.
  select true
    into _ok
    from followers f
   where f.follower_type_id = 1
     and f.follower = new.follows
     and f.follows = new.follower;
  if found then
    return new;
  else
    -- We could maybe raise an error here but the important thing is
    -- that the friend request fails.
    return null;
  end if;
end;
$$
language plpgsql security definer volatile;

create trigger follower__bi_trg
  before insert on followers
  for each row
  when (new.follower_type_id = 2)
  execute procedure follower_friend_check();

-- Prevent updates, even by db owner.
create trigger follower__bu_trg
  before update on followers
  for each row
  execute procedure nocando();

create or replace
function follower__bd() returns trigger as
$$
begin
  -- Deleting the friend request, means that the friendship gets
  -- cancelled.  All other deletions need no action
  delete
    from followers f
   where f.follower_type_id = 2
     and f.follower = old.follows
     and f.follows = old.follower;
  return old;
end;
$$
language plpgsql security definer volatile;

create trigger follower__bd_trg
  before delete on followers
  for each row
  when (old.follower_type_id = 1)
  execute procedure follower__bd();

-- TODO: we ought to have a constraint that you can't create a friend
-- without first having a friend request.

insert
  into followers
       (follower_type_id, follower, follows)
values (1, 4, 2),
       (2, 2, 4);

create table post_types (
  post_type_id		    integer not null primary key,
  post_type_name	    text not null unique,
  description		    text
);

insert
  into post_types
       (post_type_id, post_type_name, description)
values (11, 'public',
        'Anyone can view this'),
       (12, 'private',
        'Only poster can view this'),
       (13, 'for-friends',
        'Only friends can view this');

create sequence post_id_seq start with 900;
grant all on sequence post_id_seq to veil_user;
create table posts (
  post_id	       integer not null primary key
  		           default nextval('post_id_seq'),
  post_type_id	       integer not null,
  poster	       integer not null,
  post		       text not null
);

alter table posts add constraint post__type_fk
  foreign key(post_type_id)
  references post_types(post_type_id);

alter table posts add constraint post__poster_fk
  foreign key(poster)
  references users(accessor_id);


-- STEP 1: Install Veil2

-- If you haven't installed the extension on your server, and have the
-- pgxn client installed:
-- $ pgxn install veil2

create extension if not exists veil2 cascade; 


-- STEP 2:
-- Define scopes

-- 2.1 Create new scopes by inserting records into veil2.scope_types.
-- 
 
insert 
  into veil2.scope_types
       (scope_type_id, scope_type_name,
        description)
values (3, 'friend', 'Friends get to see more than anonymous followers');


-- STEP 3:
-- Authentication stuff.

-- The Veil2 system defaults work for authentication.

-- Define this just to stop veil2.implementation_status() from
-- complaining that it is not done.  This is just the same as the
-- system-supplied version.

create or replace
view veil2.my_accessor_contexts (
  accessor_id, context_type_id, context_id
) as
select accessor_id, 1, 0
  from veil2.accessors;

-- 3.3 get_accessor()
-- Create a my_get_accessor() function that will take a username and
-- context, and return an accessor_id

create or replace
function veil2.my_get_accessor(
    username in text,
    context_type_id in integer,
    context_id in integer)
  returns integer as
$$
declare
  result integer;
  _username text;
begin
  _username = username;
  select accessor_id
    into result
    from users u
   where u.username = _username;
  return result;
end;
$$
language 'plpgsql' security definer stable leakproof;


-- STEP 4:
-- Link Veil2 accessors to your database's users.

-- 4.1 Create a mapping table
-- Note that you may have multiple users tables and so you may need 
-- multiple FK fields back to your database.  If so, you may want to
-- add a check constraint to ensure that only 1 of them is not null.


create table veil2.accessor_users_map (
  accessor_id		integer not null
);

alter table veil2.accessor_users_map add constraint accessor_users__pk 
  primary key (accessor_id);

alter table veil2.accessor_users_map add constraint accessor__accessor_fk
  foreign key (accessor_id)
  references veil2.accessors(accessor_id);

-- And you must create FKs
alter table veil2.accessor_users_map add constraint accessor__user_fk
  foreign key (accessor_id)
  references users(accessor_id);

-- 4.2 Copy Existing User Records
-- 

insert
  into veil2.accessors
      (accessor_id, notes)
select accessor_id, 'Created as part of initial migration'
  from users;

-- 4.3 Copy existing authentication records
-- This is going to be tricky as it is unlikely that the
-- authentication tokens in your database are going to match those
-- exepected by Veil2.  See the Veil2 documentation for Step 4 for
-- more information.

insert
  into veil2.authentication_details
      (accessor_id, authentication_type, authent_token)
select accessor_id, 'bcrypt', veil2.bcrypt(password)
  from users;

-- Clear out the original password fields, as we don't need them anymore.
update users
  set password = 'xxxx';

-- 4.4 Create Referential Integrity Triggers
-- On insert and on delete triggers are needed as a minimum.  If
-- updates are allowed to change the user id fields, then we will also
-- need to deal with updates.  Far better though to simply have an
-- on-update trigger that fails if such an attempt is made. 

-- Can't do a before insert here as we need the users record to
-- exist before we can create the map table entry.
--
create or replace
function user__ai() returns trigger as
$$
begin
  -- A new users record has been created.  Create the
  -- appropriate records in veil2
  insert 
    into veil2.accessors
         (accessor_id)
  values (new.accessor_id);
  insert
    into veil2.accessor_users_map
         (accessor_id)
  values (new.accessor_id);

  insert
   into veil2.authentication_details
        (accessor_id, authentication_type, authent_token)
  select new.accessor_id, 'bcrypt', veil2.bcrypt(new.password);

  update users
     set password = 'xxxx'
   where accessor_id = new.accessor_id;
  return new;
end;
$$
language plpgsql security definer volatile;

create trigger user__ai_trg
  after insert on users
  for each row
  execute procedure user__ai();


create or replace
function user__bu() returns trigger as
$$
begin
  if new.accessor_id != old.accessor_id or
     new.username != old.username then
    -- You can't do that.
    return null;
  end if;
  if new.password != 'xxxx' then
      update veil2.authentication_details
         set authent_token = veil2.bcrypt(new.password)
       where accessor_id = new.accessor_id;
  
  end if;
  new.password = 'xxxx';
  return new;
end;
$$
language plpgsql security definer volatile;

create trigger user__bu_trg
  before update on users
  for each row
  execute procedure user__bu();

-- Do not allow deletions.  Ours is not to reason why.
create trigger user__bd_trg
  before delete on users
  for each row
  execute procedure nocando();


-- STEP 5: Link your scopes

-- 5.1 Extend the veil2.scopes table to link to the tables that define
-- your scopes.

-- No need to link scopes as all of our relational scopes are based on
-- accessor_id.  This means that we do not need to map between Veil2's
-- scope_ids and the ids used in our demo.  So, we can completely
-- ignore the veil2.scopes table.  Yay!

-- Insert a dummy record to quiten veil2.implementation_status();
insert into veil2.scopes values (3, -1);

-- 5.5 Update the all_accessor_roles view

-- Having a friend gives us an implied 'friend' role in the friend's
-- context.

create or replace
view veil2.my_all_accessor_roles (
  accessor_id, role_id, context_type_id, context_id
) as
select accessor_id, role_id,
       context_type_id, context_id
  from veil2.accessor_roles
 union all
select follows, 5,   -- The friend role
       3, follower   -- follows has friend role in friend context of follower
  from followers
 where follower_type_id = 2
 union all
select follower, 5,
       3, follows   -- follower has friend role in friend context of follows
  from followers
 where follower_type_id = 2;
  
-- 5.6 Create triggers on updates to accessor roles
-- There is no need to do this on the veil2.accessor_roles table as
-- this is already done.

-- For each table providing data to my_all_accessor_roles...

-- Clearing the accessor_privileges_cache is slightly more complex
-- than the standard clear_accessor_privs_cache_entry can handle, so
-- we have to create our own trigger function.
--
create or replace
function veil2.clear_accessor_privs_for_follower()
  returns trigger as
$$
begin
  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    delete
      from veil2.accessor_privileges_cache
     where accessor_id = new.follower
        or accessor_id = new.follows;
    if (tg_op = 'UPDATE') and
       (old.follower != new.follower) then
      delete
        from veil2.accessor_privileges_cache
       where accessor_id = old.follower
          or accessor_id = old.follows;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    delete
      from veil2.accessor_privileges_cache
     where accessor_id = old.follower
        or accessor_id = old.follows;
    return old;
  end if;
end;
$$
language plpgsql security definer volatile;



create trigger follower__ad_trg
  after delete on followers
  for each row
  when (old.follower_type_id = 2)
  execute procedure veil2.clear_accessor_privs_for_follower();

create trigger follower__ai_trg
  after insert on followers
  for each row
  when (new.follower_type_id = 2)
  execute procedure veil2.clear_accessor_privs_for_follower();

-- STEP 6: Define Scope Hierarchy

-- We have no scope hierarchy, so this is a bit of a no-op.

-- 6.1
-- Define the my_superior_scopes view
create or replace
view veil2.my_superior_scopes (
  scope_type_id, scope_id,
  superior_scope_type_id, superior_scope_id
) as
select 0, 0, 0, 0
 where false;


-- STEP 7:
-- Define privileges.  Note that priv_ids below 20 are reserved for Veil2
-- objects

insert into veil2.privileges
       (privilege_id, privilege_name,
        promotion_scope_type_id, description)
values (20, 'select users',
        null, 'select from the users table'),
       (21, 'insert users',
        null, 'insert into the users table'),
       (22, 'update users',
        null, 'update the users table'),
       (23, 'delete users',
        null, 'delete the users table'),
       (24, 'select follower_types',
        1, 'select from the follower_types table'), -- applies in global scope
       (25, 'select followers',
        null, 'select from the followers table'),
       (26, 'insert followers',
        null, 'insert into the followers table'),
       (27, 'delete followers',
        null, 'delete from the followers table'),
       (28, 'select post_types',
        1, 'select from the post_types table'), -- applies in global scope
       (29, 'select posts',
        null, 'select from the posts table'),
       (30, 'insert posts',
        null, 'insert into the posts table');
	

-- STEP 8:
-- Define/integrate roles

-- We use only veil2's roles so no integration needed.

-- 8.2 Create new roles and mappings
--

-- Use of roles
-- - viewer is assigned implicitly for all of your friends and allows
--   you to view friend posts.
-- - personal_context gives you the ability to post
-- - admin must be assigned explicitly
-- - anonymous is the role assigned to anonymous users


insert
  into veil2.roles
       (role_id, role_type_id, role_name,
        implicit, immutable, description)
values (5, 1, 'viewer', false, true, 'can view all appropriate data'),
       (6, 1, 'admin', true, false, 'can administer the system');

-- The admin role can be assigned through accessor_roles in global
-- context.
-- The user role is implied for all users and applies in personal
-- context.

insert into veil2.role_roles
       (primary_role_id, assigned_role_id,
        context_type_id, context_id)
values (6, 5, 1, 0),
       (6, 6, 1, 0);

insert into veil2.role_privileges
       (role_id, privilege_id)
values -- Viewer role privs
       (5, 20),
       (5, 24),
       (5, 25),
       (5, 29),
       -- Admin role privs
       (6, 20),
       (6, 21),
       (6, 25),
       (6, 29),
          -- Personal context role privs
       (2, 20),
       (2, 22),
       (2, 24),
       (2, 25),
       (2, 26),
       (2, 29),
       (2, 30);


-- STEP 9:
-- Secure Tables
-- For each table

grant veil_user to demouser;

alter table users enable row level security;

create policy users__select
    on users
   for select
 using (veil2.i_have_personal_priv(20, accessor_id) or
        veil2.i_have_priv_in_scope_or_global(20, 3, accessor_id));

create policy users__insert
    on users
   for insert
  with check (veil2.i_have_personal_priv(21, accessor_id) or
              veil2.i_have_global_priv(21));

create policy users__update
    on users
   for update
  using (veil2.i_have_personal_priv(22, accessor_id) or
         veil2.i_have_global_priv(22));

revoke all on users from public;
grant select, insert, update on users to demouser;


alter table follower_types enable row level security;

create policy follower_types__select
    on follower_types
   for select
 using (veil2.i_have_global_priv(24));

revoke all on follower_types from public;
grant select on follower_types to demouser;


alter table followers enable row level security;

create policy followers__select
    on followers
   for select
 using (veil2.i_have_global_priv(25) or
        veil2.i_have_personal_priv(25, follower) or -- Anyone I follow
        veil2.i_have_personal_priv(25, follows));   -- Anyone following me

create policy followers__insert
    on followers
   for insert
  with check (veil2.i_have_personal_priv(26, follower) or
	      veil2.i_have_global_priv(26));

revoke all on followers from public;
grant select, insert, delete on followers to demouser;


alter table post_types enable row level security;

create policy post_types__select
    on post_types
   for select
 using (veil2.i_have_global_priv(28));

revoke all on post_types from public;
grant select, insert, delete on post_types to demouser;


alter table posts enable row level security;

create policy posts__select
    on posts
   for select
 using (veil2.i_have_personal_priv(29, poster) or
        veil2.i_have_global_priv(29) or
        (    post_type_id = 12 -- friend posts
	 and veil2.i_have_priv_in_scope(29, 3, poster)) or
        (    post_type_id = 11  -- Public posts require connect privilege.
	 and veil2.i_have_global_priv(0)));

-- The following checks *only* for personal priv as that will
-- ensure that we are the poster (ie we are not faking the id)
create policy posts__insert
    on posts
   for insert
  with check (veil2.i_have_personal_priv(30, poster));

revoke all on post_types from public;
grant select, insert, delete on post_types to demouser;

revoke all on posts from public;
grant select, insert, delete on posts to demouser;


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


-- Step 11:
-- Assign roles to accessors

-- ...

insert
  into veil2.accessor_roles
       (accessor_id, role_id, context_type_id, context_id)
values (1, 0, 1, 0),    -- Alice gets connect
       (1, 6, 1, 0),	-- Alice gets admin
       (2, 0, 1, 0),    -- Bob gets connect
       (3, 0, 1, 0),    -- Carol gets connect
       (3, 1, 1, 0),	-- Carol gets superuser
       (5, 0, 1, 0);	-- Eve gets connect

update veil2.system_parameters
   set parameter_value = 'false'
 where parameter_name = 'error on uninitialized session';

