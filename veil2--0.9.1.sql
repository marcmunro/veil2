/* ----------
 * veil2.sql
 *
 *      Create the veil2 extension
 *
 *      Copyright (c) 2020 Marc Munro
 *      Author:  Marc Munro
 *	License: GPL V3
 *
 * ----------
 */


-- Although technically it is evil to create roles within extensions,
-- the veil_user role is so intrinsic to veil2 that it is a necessity.
-- Please don't hate me for it.

\echo ...veil2 roles...
do
$$
declare
  _result integer;
begin
  select 1 into _result from pg_roles where rolname = 'veil_user';
  if not found then
    execute 'create role veil_user';
  end if;
end;
$$;

comment on role veil_user is
'This role will have read access to all veil2 tables.  That is not to
say that an assignee of the role will be able to see the data in those
tables, but that they will be allowed to try.  If, in addition to this
role, they are (in veil2 terms) an accessor and have been assigned (in
veil2 terms) the veil2_user role, they will be able to see all veil2
relations and their contents.';

\echo ...veil2 schema...
create schema if not exists veil2;

comment on schema veil2 is
'Schema containing veil2 database objects.';

revoke all on schema veil2 from public;
grant usage on schema veil2 to veil_user;

-- Create the VEIL2 schema tables

\echo ......scope_types...
create table veil2.scope_types (
  scope_type_id	       		integer not null,
  scope_type_name		text not null,
  description			text not null
);

alter table veil2.scope_types
  add constraint scope_type__pk
  primary key(scope_type_id);

alter table veil2.scope_types
  add constraint scope__name_uq
  unique(scope_type_name);

comment on table veil2.scope_types is
'Identifies the types of security scope for your VPD.  This can be
thought of as the ''level'' of a scope.

Insert one record into this table for each type of scope that you wish
to implement.  Veil2 comes with 2 built-in scope types: for global and
personal contexts.';

revoke all on veil2.scope_types from public;
grant select on veil2.scope_types to veil_user;
--grant all on veil2.scope_types to demouser;


\echo ......scopes...
create table veil2.scopes (
  scope_type_id	       		integer not null,
  scope_id			integer not null
);

alter table veil2.scopes
  add constraint scope__pk
  primary key(scope_type_id, scope_id);

alter table veil2.scopes
  add constraint scope__type_fk
  foreign key(scope_type_id)
  references veil2.scope_types(scope_type_id);

comment on table veil2.scopes is
'A scope, or context, identifies a limit to access.  It is a
scope_type applied to a specific instance.  For example, if access
controls are placed in project scopes, there will be one scope
record for each project that we wish to manage access to.  So for
three projects A, B and C, there would be 3 scopes with scope_types of
project.  This table as created by the Veil2 database creation scripts
is incomplete.  It needs additional columns to link itself with the
scopes it is protecting.

For each relational scope type that you create, you should create
foreign key relationships from this table back to your protected
database.  There are a number of ways to do this.  Probably the
simplest is to add nullable columns to this table for each type of
relational context key and then add appropriate foreign key and check
constraints.

For example to implement a corp context with a foreign key back to your
corporations table:

    alter table veil2.scopes 
      add column corp_id integer;

    alter table veil2.scopes 
      add constraint scope__corp_fk
      foreign key (corp_id)
      references my_schema.corporations(corp_id);

    -- Ensure that for corp context types we have a corp_id
    -- (assume corp_context has scope_type_id = 3)
    alter table veil2.scopes 
      add constraint scope__corp_chk
      check ((scope_type_id != 3) 
          or ((scope_type_id = 3) and (corp_id is not null)));

You will, of course, also need to ensure that the corp_id field is
populated.

Note that global scope uses scope_id 0.  Ideally it would be null,
since it does not relate directly to any other entity but that makes
defining foreign key relationships (to this table) difficult.  Using a 
reserved value of zero is just simpler (though suckier).';

comment on column veil2.scopes.scope_type_id is
'Identifies the type of scope that we are describing.';

comment on column veil2.scopes.scope_id is
'This, in conjunction with the scope_type_id, fully identifies a scope
or context.  For global scope, this id is 0: ideally it would be null
but as it needs to be part of the primary key of this table, that is
not possible.

The scope_id provides a link back to the database we are protecting,
and will usually be the key to some entity that can be said to ''own''
data.  This might be a party, or a project, or a department.';

revoke all on veil2.scopes from public;
grant select on veil2.scopes to veil_user;


\echo ......privileges...
create table veil2.privileges (
  privilege_id			integer not null,
  privilege_name		text not null,
  promotion_scope_type_id	integer,
  description			text
);

comment on table veil2.privileges is
'This provides all privileges used by our VPD.  There should be no
need for anyone other than administrators to have any access to this
table.

A privilege is the lowest level of access control.  It should be used to
allow the holder of that privilege to do exactly one thing, for example
''select privileges'' should be used to allow the privilege holder to
select from the privileges table.  It should not be used for any other
purpose.

Note that the name of the privilege is only a clue to its usage.  We
use the privilege ids and not the names to manage access.  It is the
responsibility of the implementor to ensure that a privilege''s name
matches the purpose to which it is put.';

comment on column veil2.privileges.privilege_id is
'Primary key for privilege.  This is the integer that will be used as a
key into our privilege bitmaps.  It is not generated from a sequence as
we want to have very tight control of the privilege_ids.

The range of privilege_ids in use should be kept as small as
possible.  If privileges become deprecated, you should (once you have
ensured that the old privilege_id is not in use *anywhere*) try to
re-use the old privilege_ids rather than extending the range of
privilege_ids by allocating new ones.

This will keep your privilege bitmaps smaller, which should in turn
improve performance.';

comment on column veil2.privileges.privilege_name is
'A descriptive name for a privilege.  This should generally be enough to 
figure out the purpose of the privilege.';

comment on column veil2.privileges.promotion_scope_type_id is
'Identfies a security scope type to which this privileges scope should
be promoted if possible.  This allows roles which will be assigned in
a restricted security context to contain privileges which necessarily
must apply in a superior scope (ie as if they had been assigned in a
superior context).

For example a hypothetical ''select lookup'' privilege may be assigned
in a team context (via a hypothetical ''team member'' role).  But if the
lookups table is not in any way team-specific it makes no sense to apply
that privilege in that scope.  Instead, we will promote that privilege
to a scope where it does make sense.  See the Veil2 docs for more on
privilege promotion and on the use of the terms scope and context.';

comment on column veil2.privileges.description is
'For any privilege whose purpose cannot easily be determined from the
name, a description of the privilege should appear here.';

alter table veil2.privileges add constraint privilege__pk
  primary key(privilege_id);

alter table veil2.privileges add constraint privilege__promotion_scope_type_fk
  foreign key(promotion_scope_type_id)
  references veil2.scope_types(scope_type_id);

revoke all on veil2.privileges from public;
grant select on veil2.privileges to veil_user;


\echo ......role_types...
create table veil2.role_types (
  role_type_id		      integer not null,
  role_type_name	      text not null,
  description		      text
);

comment on table veil2.role_types is
'A role type is used to classify roles so that they may be shown and
used in different ways.   This is mostly a VPD implementation choice.

For instance you may choose to distinguish between user and
function-level roles so that you can prevent role assignments to
user-level roles.  In such a case you might add columns to this table
to identify specific properties of specific role_types.';

alter table veil2.role_types add constraint role_type__pk
  primary key(role_type_id);

alter table veil2.role_types add constraint role_type__name_uk
  unique(role_type_name);

revoke all on veil2.role_types  from public;
grant select on veil2.role_types to veil_user;


\echo ......roles...
create sequence veil2.role_id_seq;

create table veil2.roles (
  role_id			integer not null,
  role_type_id			integer not null default(1),
  role_name			text not null,
  implicit 			boolean not null default false,
  immutable			boolean not null default false,
  description			text
);

comment on table veil2.roles is
'A role is a way of collecting privileges (and other roles) into groups
for easier management.';

comment on column veil2.roles.role_id is
'Primary key for role.';

comment on column veil2.roles.role_name is
'A descriptive name for a role.  This should generally be enough to 
figure out the purpose of the role.';

comment on column veil2.roles.implicit is
'Whether this role is implicitly assigned to all accessors.  Such roles
may not be explicitly assigned.';

comment on column veil2.roles.immutable is
'Whether this role is considered unmodifiable.  Such roles may not be
the primary role in a role_role assignment.';

comment on column veil2.roles.description is
'For any role whose purpose cannot easily be determined from the
name, a description of the role should appear here.';

alter table veil2.roles add constraint role__pk
  primary key(role_id);

alter table veil2.roles add constraint role__name_uk
  unique(role_name);

alter table veil2.roles add constraint role__type_fk
  foreign key(role_type_id)
  references veil2.role_types(role_type_id);

revoke all on veil2.roles  from public;
grant select on veil2.roles to veil_user;


\echo ......context_roles...
create table veil2.context_roles (
  role_id			integer not null,
  role_name			text not null,
  context_type_id	       	integer not null,
  context_id			integer not null
);

comment on table veil2.context_roles is
'This provides a context-based role-name for a role.  The purpose of
this is to allow certain security contexts to name their own roles.
This, coupled with role_roles, allows for role definitions to be
different in different contexts.  It is primarily aimed at VPDs where
there are completely independent sets of accessors.  For example in a
SaaS implementation where each corporate customer gets their virtual
private database and no customer can see any data for any other
customer.  In such a case it is likely that roles will be different,
will have different names, and different sets of roles will exist.

If this makes no sense to you, you probably have no need for it, so
don''t use it.  If do choose to use, do so sparingly as it could lead to
great confusion.';

alter table veil2.context_roles add constraint context_role__pk
  primary key(role_id, context_type_id, context_id);

alter table veil2.context_roles add constraint context_role__name_uk
  unique(role_name, context_type_id, context_id);

alter table veil2.context_roles add constraint context_role__role_fk
  foreign key(role_id)
  references veil2.roles(role_id);

alter table veil2.context_roles add constraint context_role__context_fk
  foreign key(context_type_id, context_id)
  references veil2.scopes(scope_type_id, scope_id)
  on delete cascade on update cascade;

comment on constraint context_role__context_fk
  on veil2.context_roles is
'Since contexts may be updated or deleted as a result of transactions
in our secured database, we must allow such updates or deletions to
cascade to this table as well.  The point of this is that the
application need not know about fk relationships that are internal to
Veil2.';

revoke all on veil2.context_roles  from public;
grant select on veil2.context_roles to veil_user;


\echo ......role_privileges...
create table veil2.role_privileges (
  role_id			integer not null,
  privilege_id			integer not null
);

comment on table veil2.role_privileges is
'Records the mapping of privileges to roles.  Roles will be assigned to
parties in various contexts; privileges are only assigned indirectly
through roles.  Note that role privileges should not be managed by
anyone other than a developer or administrator that understands the 
requirements of system access controls.  Getting this wrong is the best
route to your system having poor database security.  There should be no
need for anyone other than administrators to have any access to this
table.

User management of roles should be done through user visible role->role
mappings.  While this may seem an odd concept, the use of roles in
databases provides a good model for how this can work.

Note that the assignment of role to role may be something that is done
within a specific security context: consider that the database may be
storing data for separate groups of parties (eg companies) and the
role->role assignment may therefore need to be specific to those groups
(eg a customer liaison role in one company may need different privileges
from a similar role in another company).

You should not normally query this table directly; instead use the
direct_role_privilges view which deals with implied assignments for the
superuser role.';

alter table veil2.role_privileges add constraint role_privilege__pk
  primary key(role_id, privilege_id);

alter table veil2.role_privileges
  add constraint role_privilege__role_fk
  foreign key(role_id)
  references veil2.roles(role_id);

alter table veil2.role_privileges
  add constraint role_privilege__privilege_fk
  foreign key(privilege_id)
  references veil2.privileges(privilege_id);

revoke all on veil2.role_privileges from public;
grant select on veil2.role_privileges to veil_user;


\echo ......role_roles...
create table veil2.role_roles (
  primary_role_id		integer not null,
  assigned_role_id		integer not null,
  context_type_id	       	integer not null,
  context_id		       	integer not null
);

comment on table veil2.role_roles is
'This table shows the mapping of roles to roles in various contexts.

The purpose of context-specific role mappings is to enable custom role
mappings in different situations.  An example of when this may be useful
is when creating a SaaS application for multiple corporate customers.
Each corporation can have their own role mappings, unaffected and unseen
by other corporations.  This means that a CSR role at one corporation
may have different privileges from a CSR at another.';

alter table veil2.role_roles add constraint role_role__pk
  primary key(primary_role_id, assigned_role_id, context_type_id, context_id);

alter table veil2.role_roles
  add constraint role_role__primary_role_fk
  foreign key(primary_role_id)
  references veil2.roles(role_id);

alter table veil2.role_roles
  add constraint role_role__assigned_role_fk
  foreign key(assigned_role_id)
  references veil2.roles(role_id);

alter table veil2.role_roles
  add constraint role_role__context_fk
  foreign key(context_type_id, context_id)
  references veil2.scopes(scope_type_id, scope_id);

revoke all on veil2.role_roles from public;
grant select on veil2.role_roles to veil_user;


\echo .....accessors...
create table veil2.accessors (
  accessor_id			integer not null,
  username			text,
  notes				text
);

comment on table veil2.accessors is
'Identifies parties that may access our database.  If this is a party
that should have direct database access (ie they are a database user),
we record their username here.  This allows our security functions to
associate the connected database user with their assigned privileges.

VPD Implementation Notes:
You are likely to want to implement a foreign-key relationship back to
your users table in your protected database (each accessor is a user).
It is likely that your accessor_id can simply be the same as the user_id
(or party_id, or person_id...).  If this is not the case, you can add 
columns to this table as needed and define FKs as needed.

In the simple case you will do something like this:

alter table veil2.accessors
  add constraint accessor__user_fk
  foreign key(accessor_id)
  references my_schema.users(user_id);

In the event that you have multiple types of accessors, with overlapping
ranges of keys, you may have to extend this table to add an
accessor_type, and other columns to provide the actual foreign-key
values.  As accessor_id is heavily used by Veil2 you *must* ensure that
this value is truly unique.';

comment on column veil2.accessors.username is
'If this is provided, it should match a database username.  This
allows a database user to be associated with the accessor_id, and for
their privileges to be determined.'; 

comment on column veil2.accessors.accessor_id is
'The id of the database accessor.  This is the id used throughout Veil2
for determining access rights.  Ideally this will be the id of the user
from the protected database';

alter table veil2.accessors add constraint accessor__pk
  primary key(accessor_id);

alter table veil2.accessors add constraint accessor__username_uk
  unique (username);

revoke all on veil2.accessors from public;
grant select on veil2.accessors to veil_user;


\echo ......authentication_types...
create table veil2.authentication_types (
  shortname			text not null,
  enabled			boolean not null,
  description			text not null,
  authent_fn			text not null,
  supplemental_fn		text,
  user_defined			boolean
);

comment on table veil2.authentication_types is
'Types of authentication supported by this VPD.';

comment on column veil2.authentication_types.shortname is
'A short textual identifier for this type of authentication.  This acts
as the primary key.';

comment on column veil2.authentication_types.enabled is
'Whether this authentication type is currently enabled.  If it is not,
you will not be able to authenticate using this method.';

comment on column veil2.authentication_types.description is
'A description of this authentication type.';

comment on column veil2.authentication_types.authent_fn is
'The name of a function that will determine whether a supplied
authentication token is correct.

The signature for this function is:
      fn(accessor_id integer, token text) returns bool;
It will return true if the supplied token is what is expected.';

comment on column veil2.authentication_types.supplemental_fn is
'The name of a function that will return session_supplemental values
for create_session.

The signature for this function is:
    fn(accessor_id in integer, 
       session_token in out text,
       session_supplemental out text) 
    returns record;

The provided session_token is a random value, that may be returned
untouched or may be modified.  The session_supplemental result is
supplemental data for the chosen authentication protocol.  This is where
you might return the base and modulus selection for a Diffie-Hellman
exchange, should you wish to implement such a thing.';

comment on column veil2.authentication_types.user_defined is
'Whether this parameter value was modified by the user.  This is
needed for exports using pg_dump.';

alter table veil2.authentication_types add constraint authentication_type__pk
  primary key(shortname);

revoke all on veil2.authentication_types from public;
grant select on veil2.authentication_types to veil_user;


\echo ......authentication_details...
create table veil2.authentication_details (
  accessor_id			integer not null,
  authentication_type		text not null,
  authent_token			text not null
);

comment on table veil2.authentication_details is
'Types of auhentication available for individual parties, along with
whatever authentication tokens are needed for that form of
authentication.  Because this table stores authentication tables, access
to it must be as thoroughly locked down as possible.';

comment on column veil2.authentication_details.authentication_type is
'Identifies a specific authentication type.  More than 1 authentication
type may be available to some parties.';

comment on column veil2.authentication_details.authent_token is
'An authentication token for the party for the given authentication
type.  If we were using plaintext passwords (do not do this), this would
be where the password would be stored.';

alter table veil2.authentication_details
  add constraint authentication_detail__pk
  primary key(accessor_id, authentication_type);

alter table veil2.authentication_details
  add constraint authentication_detail__authent_type_fk
  foreign  key(authentication_type)
  references veil2.authentication_types(shortname);

 alter table veil2.authentication_details
   add constraint authentication_detail__accessor_fk
   foreign key(accessor_id)
   references veil2.accessors(accessor_id)
   on delete cascade on update cascade;

comment on constraint authentication_detail__accessor_fk
  on veil2.authentication_details is
'Since accessors may be updated or deleted as a result of transactions
in our secured database, we must allow such updates or deletions to
cascade to this table as well.  The point of this is that the
application need not know about fk relationships that are internal to
Veil2.';


revoke all on veil2.authentication_details from public;
grant select on veil2.authentication_details to veil_user;


\echo ......accessor_roles...
create table veil2.accessor_roles (
  accessor_id			integer not null,
  role_id			integer not null,
  context_type_id	       	integer not null,
  context_id		       	integer not null
);

comment on table veil2.accessor_roles is
'This records the assignment of roles to accessors in various contexts.
A role assigned to a party here, grants that accessor all of the privileges
that that role has been assigned, whether directly or indirectly.';

alter table veil2.accessor_roles add constraint accessor_role__pk
  primary key(accessor_id, role_id, context_type_id, context_id);

alter table veil2.accessor_roles
  add constraint accessor_role__accessor_fk
  foreign key(accessor_id)
   references veil2.accessors(accessor_id)
   on delete cascade on update cascade;

comment on constraint accessor_role__accessor_fk
  on veil2.accessor_roles is
'Since accessors may be updated or deleted as a result of transactions
in our secured database, we must allow such updates or deletions to
cascade to this table as well.  The point of this is that the
application need not know about fk relationships that are internal to
Veil2.';

alter table veil2.accessor_roles
  add constraint accessor_role__context_fk
  foreign key(context_type_id, context_id)
   references veil2.scopes(scope_type_id, scope_id)
   on delete cascade on update cascade;

comment on constraint accessor_role__context_fk
  on veil2.accessor_roles is
'Since contexts may be updated or deleted as a result of transactions
in our secured database, we must allow such updates or deletions to
cascade to this table as well.  The point of this is that the
application need not know about fk relationships that are internal to
Veil2.';

revoke all on veil2.accessor_roles from public;
grant select on veil2.accessor_roles to veil_user;


\echo ......sessions...
create sequence veil2.session_id_seq;

create unlogged table veil2.sessions (
  session_id			integer not null
  				  default nextval('veil2.session_id_seq'),
  accessor_id			integer not null,
  login_context_type_id		integer not null,
  login_context_id		integer not null,
  mapping_context_type_id	integer not null,
  mapping_context_id		integer not null,
  authent_type			text not null,
  expires			timestamp with time zone,
  token				text not null,
  has_authenticated		boolean not null,
  session_supplemental		text,
  nonces			bitmap
);

comment on table veil2.sessions is
'Records active sessions.  There should be a background task to delete
expired sessions and keep this table vacuumed.  Note that for
performance reasons we may want to disable any foreign key constraints
on this table.

Note that access to this table should not be granted to normal users.
This table can be used to determine whether a create_session() call
successfully created a session, and so can aid in username fishing.';

comment on column veil2.sessions.login_context_type_id is
'This, along with the login_context_id column describes the context
used for authentication of this session.  This allows users to log in
in specific contexts (eg for dept a, rather than dept b), within which
role mappings may differ.  This context information allows the session
to determine which role mappings to apply.';

comment on column veil2.sessions.login_context_id is
'See comment on veil2.sessions.login_context_type_id';

comment on column veil2.sessions.mapping_context_type_id is
'This, along with the mapping_context_id column describes the context
used for role->role mapping by this session.';

comment on column veil2.sessions.mapping_context_id is
'See comment on veil2.sessions.mapping_context_type_id';

alter table veil2.sessions add constraint session__pk
  primary key(session_id);

/*
 * For performance reasons we will not create FK constraints on this
 * table. 

alter table veil2.sessions add constraint session__accessor_fk
  foreign key(accessor_id)
  references veil2.accessors(accessor_id);

*/

revoke all on veil2.sessions from public;
grant select on veil2.sessions to veil_user;



\echo ......system_parameters...
create table veil2.system_parameters (
    parameter_name		text not null,
    parameter_value		text not null,
    user_defined		boolean
);

alter table veil2.system_parameters add constraint system_parameter__pk
  primary key(parameter_name);

comment on table veil2.system_parameters is
'Provides values for various parameters.';

comment on column veil2.system_parameters.user_defined is
'Whether this parameter value was modified by the user.  This is
needed for exports using pg_dump.';

revoke all on veil2.system_parameters from public;
grant select on veil2.system_parameters to veil_user;


\echo ......session_privileges_t...
create type veil2.session_privileges_t as (
  session_id			integer,
  scope_type_id			integer,
  scope_id			integer,
  roles                         bitmap,
  privs				bitmap
);

comment on type veil2.session_privileges_t is
'Records the privileges for active sessions in each assigned context.

This type is used for the generation of a session_privileges temporary
table which is populated by Veil2''s session management functions.';
 
\echo ......session_params_t(type)...
create type veil2.session_params_t as (
  accessor_id			integer,
  session_id                    integer,
  login_context_type_id		integer,
  login_context_id		integer,
  mapping_context_type_id	integer,
  mapping_context_id		integer,
  is_open			boolean
);

-- Create the VEIL2 schema views, including matviews
-- 
-- Note that there are often multiple versions of equivalent views
-- defined below.   Where a user facing view xxx is a materialized
-- view, there may also be definitions for:
--  - xxx_v
--    This will be the view from which the materialized view is
--    constructed.  Sometimes this will itself depend on materialized
--    views.
--  - xxx_vv
--    This is an equivelent to xxx_v, which uses no materialised views
--    itself.  This view exists as a development/debug tool.
--


\echo ......direct_role_privileges...
create or replace
view veil2.direct_role_privileges_v (
    role_id, privileges, global_privileges,
    promotable_privileges) as
with all_role_privileges (role_id, privilege_id) as
  (
    select 1, privilege_id    -- implied privs for superuser role
      from veil2.privileges
     where privilege_id != 0  -- [all privs except connect]
     union
    select role_id, privilege_id
      from veil2.role_privileges
  )
select arp.role_id, bitmap_of(p.privilege_id),
       bitmap_of(case when p.promotion_scope_type_id = 1
       		 then p.privilege_id else null end),
       bitmap_of(case
                 when p.promotion_scope_type_id is null then null
                 when p.promotion_scope_type_id = 1 then null
                 else p.privilege_id end)
  from all_role_privileges arp
 inner join veil2.privileges p
    on p.privilege_id = arp.privilege_id
 group by arp.role_id;

comment on view veil2.direct_role_privileges_v is
'Returns all privileges, along with some basic privilege promotion data,
that are assigned directly to each role, including the implied
privileges for the superuser role.  This does not show privileges
arising from role to role assignments.

Note the use of bitmap_of() to aggregate privilege_ids.';

create or replace
view veil2.direct_role_privileges_v_info (
    role_id, privileges, global_privileges,
    promotable_privileges) as
select role_id, to_array(privileges),
       to_array(global_privileges), to_array(promotable_privileges)
  from veil2.direct_role_privileges_v;

comment on view veil2.direct_role_privileges_v_info is
'As veil2.direct_role_privileges_v with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';

create or replace
view veil2.direct_role_privileges_vv as
select * from veil2.direct_role_privileges_v;

comment on view veil2.direct_role_privileges_vv is
'Exactly as veil2.direct_role_privileges_v.  The _vv suffix indicates
that this is a true view, not relying on any materialized views.
As it happens, direct_role_privileges_v also does not rely on any
materialized views, so this view exists only to be consistent with other
such sets of views.';

create or replace
view veil2.direct_role_privileges_vv_info (
    role_id, privileges, global_privileges,
    promotable_privileges) as
select role_id, to_array(privileges),
       to_array(global_privileges), to_array(promotable_privileges)
  from veil2.direct_role_privileges_vv;

comment on view veil2.direct_role_privileges_vv_info is
'As veil2.direct_role_privileges_vv with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';

create 
materialized view veil2.direct_role_privileges
as select * from veil2.direct_role_privileges_v;

comment on materialized view veil2.direct_role_privileges is
'Returns all privileges, along with some basic privilege promotion data,
 that are assigned directly to each role, including the implied
 privileges for the superuser role.  This does not show privileges
 arising from role to role assignments';

create or replace
view veil2.direct_role_privileges_info (
    role_id, privileges, global_privileges,
    promotable_privileges) as
select role_id, to_array(privileges),
       to_array(global_privileges), to_array(promotable_privileges)
  from veil2.direct_role_privileges;

comment on view veil2.direct_role_privileges_info is
'As veil2.direct_role_privileges with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';


revoke all on veil2.direct_role_privileges from public;
grant select on veil2.direct_role_privileges to veil_user;
revoke all on veil2.direct_role_privileges_info from public;
grant select on veil2.direct_role_privileges_info to veil_user;
revoke all on veil2.direct_role_privileges_v from public;
grant select on veil2.direct_role_privileges_v to veil_user;
revoke all on veil2.direct_role_privileges_v_info from public;
grant select on veil2.direct_role_privileges_v_info to veil_user;
revoke all on veil2.direct_role_privileges_vv from public;
grant select on veil2.direct_role_privileges_vv to veil_user;
revoke all on veil2.direct_role_privileges_vv_info from public;
grant select on veil2.direct_role_privileges_vv_info to veil_user;

\echo ......all_role_roles...
create or replace
view veil2.all_role_roles (
    primary_role_id, assigned_role_id,
    context_type_id, context_id) as
with recursive assigned_roles (
    primary_role_id, assigned_role_id,
    context_type_id, context_id) as
  (
    -- get all role->role assignments, both direct and indirect, in all contexts
    select primary_role_id, assigned_role_id,
           context_type_id, context_id,
	   bitmap(primary_role_id) + assigned_role_id as roles_encountered
      from veil2.role_roles
     union all
    select rr.primary_role_id, ar.assigned_role_id,
           rr.context_type_id, rr.context_id,
	   roles_encountered + ar.assigned_role_id
      from veil2.role_roles rr
     inner join assigned_roles ar
             on ar.primary_role_id = rr.assigned_role_id
	    and (   ar.context_type_id = 1
	         or (    ar.context_type_id = rr.context_type_id
	             and ar.context_id = rr.context_id))
     where not ar.roles_encountered ?  ar.assigned_role_id
  ),
  all_assigned_roles (
    primary_role_id, assigned_role_id,
    context_type_id, context_id) as
  (
    -- to above query, add assignment of each role to itself
    -- Since this applies in all mapping contexts, we provide null as
    -- the context ids
    select primary_role_id, assigned_role_id,
           context_type_id, context_id
      from assigned_roles
     union all
    select role_id, role_id, null, null
      from veil2.roles
  ),
  superuser_roles (primary_role_id, assigned_role_id) as
  (
    select 1, role_id
      from veil2.roles
     where role_id not in (1, 0)  -- not connect and not superuser
       and not implicit           -- and not implicitly assigned roles
  )
select primary_role_id, assigned_role_id,
       context_type_id, context_id
  from all_assigned_roles
 union all
select primary_role_id, assigned_role_id,
       1, 0
  from superuser_roles;

comment on view veil2.all_role_roles is
'Show all role->role mappings in all contexts, including mappings that
are implied and those that are indirect.

Implied mappings are:

 1 - the superuser role is assigned all non-implicit roles except connect;

 2 - all roles implicitly map to themselves.

Indirect mappings occur through other mappings (ie mappings are
transitive).  Eg if a is assigned to b and b to c, then by transitivity
a is assigned (indirectly) to c.'; 

revoke all on veil2.all_role_roles from public;
grant select on veil2.all_role_roles to veil_user;


\echo ......all_role_privs...
create or replace
view veil2.all_role_privs_v (
  role_id, roles,
  privileges, global_privileges, 
  promotable_privileges, context_type_id,
  context_id
) as
select arr.primary_role_id,
       bitmap_of(arr.assigned_role_id),
       union_of(drp.privileges),
       union_of(drp.global_privileges),
       union_of(drp.promotable_privileges),
       arr.context_type_id,
       arr.context_id
  from veil2.all_role_roles arr
  left outer join veil2.direct_role_privileges drp
    on (   drp.role_id = arr.assigned_role_id
        or drp.role_id = arr.primary_role_id)
 group by arr.primary_role_id, arr.context_type_id, arr.context_id;

comment on view veil2.all_role_privs_v is
'This is simply the aggregation of all role->role mappings as provided
by veil2.all_role_roles and the role_privileges as provided by
veil2.direct_role_privileges.  See the comments on those views for more
information.';

create or replace
view veil2.all_role_privs_v_info (
  role_id, roles,
  privileges, global_privileges, 
  promotable_privileges, context_type_id,
  context_id
) as
select role_id, to_array(roles),
  to_array(privileges), to_array(global_privileges), 
  to_array(promotable_privileges), context_type_id,
  context_id
from veil2.all_role_privs_v;

comment on view veil2.all_role_privs_v_info is
'As veil2.all_role_privs_v with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';


create or replace
view veil2.all_role_privs_vv (
  role_id, roles,
  privileges, global_privileges, 
  promotable_privileges, context_type_id,
  context_id
) as
select arr.primary_role_id,
       bitmap_of(arr.assigned_role_id),
       union_of(drp.privileges),
       union_of(drp.global_privileges),
       union_of(drp.promotable_privileges),
       arr.context_type_id,
       arr.context_id
  from veil2.all_role_roles arr
  left outer join veil2.direct_role_privileges_vv drp
    on (   drp.role_id = arr.assigned_role_id
        or drp.role_id = arr.primary_role_id)
 group by arr.primary_role_id, arr.context_type_id, arr.context_id;

comment on view veil2.all_role_privs_vv is
'Exactly as veil2.all_role_privs_v.  The _vv suffix indicates
that this is a true view, not relying on any materialized views.';

create or replace
view veil2.all_role_privs_vv_info (
  role_id, roles,
  privileges, global_privileges, 
  promotable_privileges, context_type_id,
  context_id
) as
select role_id, to_array(roles),
  to_array(privileges), to_array(global_privileges), 
  to_array(promotable_privileges), context_type_id,
  context_id
from veil2.all_role_privs_vv;

comment on view veil2.all_role_privs_vv_info is
'As veil2.all_role_privs_vv with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';

create 
materialized view veil2.all_role_privs
as select * from veil2.all_role_privs_v;

comment on materialized view veil2.all_role_privs is
'Materialized version of veil2.all_role_privs_v.';

create or replace
view veil2.all_role_privs_info (
  role_id, roles,
  privileges, global_privileges, 
  promotable_privileges, context_type_id,
  context_id
) as
select role_id, to_array(roles),
  to_array(privileges), to_array(global_privileges), 
  to_array(promotable_privileges), context_type_id,
  context_id
from veil2.all_role_privs;

comment on view veil2.all_role_privs_info is
'As veil2.all_role_privs with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';

revoke all on veil2.all_role_privs from public;
grant select on veil2.all_role_privs to veil_user;
revoke all on veil2.all_role_privs_info from public;
grant select on veil2.all_role_privs_info to veil_user;
revoke all on veil2.all_role_privs_v from public;
grant select on veil2.all_role_privs_v to veil_user;
revoke all on veil2.all_role_privs_v_info from public;
grant select on veil2.all_role_privs_v_info to veil_user;
revoke all on veil2.all_role_privs_vv from public;
grant select on veil2.all_role_privs_vv to veil_user;
revoke all on veil2.all_role_privs_vv_info from public;
grant select on veil2.all_role_privs_vv_info to veil_user;


\echo ......accessor_contexts (kinda) ...
create or replace
view veil2.accessor_contexts_template (
  accessor_id, context_type_id, context_id
) as
select accessor_id, 1, 0
  from veil2.accessors;


\echo ......scope_promotions...
create or replace
view veil2.scope_promotions (
  scope_type_id, scope_id,
  promoted_scope_type_id, promoted_scope_id
) as
select null::integer, null::integer,
       null::integer, null::integer
where false;

comment on view veil2.scope_promotions is
'This view lists all possible direct scope promotions.  It is used
for privilege promotion when a role that is assigned in a restricted
security context has privileges that must be applied in a less
restricted scope.  Note that promotion to global scope is always
possible and is not managed through this view.

VPD Implementation Notes:
If you have restricted scopes which are sub-scopes of less
restricted ones, and you need privilege promotion for privileges
assigned in the restricted context to the less restricted one, you
should redefine this view to show which scopes may be promoted to
which other scopes.  For example if you have a corp scope type and a
dept scope type which is a sub-scope of it, and your departments table
identifies the corp_id for each deprtment, you would redefine your
view something like this:

    create or replace
    view veil2.scope_promotions (
      scope_type_id, scope_id,
      promoted_scope_type_id, promoted_scope_id
    ) as
    select 96, -- dept scope type id
           department_id,
           95, -- corp scope type id 
           corp_id
      from departments;

Note that any multi-level context promotions will be handled by
veil2.all_scope_promotions which you should have no need to modify.';

revoke all on veil2.scope_promotions from public;
grant select on veil2.scope_promotions to veil_user;


\echo ......scope_promotions_template...
create or replace
view veil2.scope_promotions_template (
  scope_type_id, scope_id,
  promoted_scope_type_id, promoted_scope_id
) as
select null::integer, null::integer,
       null::integer, null::integer
where false;


\echo ......all_scope_promotions...
create or replace
view veil2.all_scope_promotions_v (
  scope_type_id, scope_id,
  promoted_scope_type_id, promoted_scope_id,
  is_type_promotion
) as
with recursive recursive_scope_promotions as
  (
    select scope_type_id, scope_id,
           promoted_scope_type_id, promoted_scope_id,
	   scope_type_id != promoted_scope_type_id
      from veil2.scope_promotions
     union
    select rsp.scope_type_id, rsp.scope_id,
           sp.promoted_scope_type_id, sp.promoted_scope_id,
	   sp.scope_type_id != sp.promoted_scope_type_id
      from recursive_scope_promotions rsp
     inner join veil2.scope_promotions sp
        on sp.scope_type_id = rsp.promoted_scope_type_id
       and sp.scope_id = rsp.promoted_scope_id
     where not (    sp.promoted_scope_type_id = rsp.promoted_scope_type_id
                and sp.promoted_scope_id = rsp.promoted_scope_id)
  )
select *
  from recursive_scope_promotions;

comment on view veil2.all_scope_promotions_v is
'This takes the simple custom view veil2.scope_promotions and makes it
recursive so that if context a contains scope b and scope b contains
scope c, then this view will return rows for scope c promoting to
both scope b and scope a.  


You should not need to modify this view when creating your custom VPD
implementation.';

create or replace
view veil2.all_scope_promotions_vv as
select * from veil2.all_scope_promotions_v;

comment on view veil2.all_scope_promotions_vv is
'Exactly as veil2.all_scope_promotions_v.  The _vv suffix indicates
that this is a true view, not relying on any materialized views.';

create 
materialized view veil2.all_scope_promotions
as select * from veil2.all_scope_promotions_v;

comment on materialized view veil2.all_scope_promotions is
'This takes the simple custom view veil2.scope_promotions and makes it
recursive so that if context a contains context b and context b contains
context c, then this view will return rows for context c promoting to
both context b and context a.  

It is automatically refreshed when the veil2.scopes table is modified.

You should not need to modify this view when creating your custom VPD
implementation.'; 

revoke all on veil2.all_scope_promotions from public;
grant select on veil2.all_scope_promotions to veil_user;
revoke all on veil2.all_scope_promotions_v from public;
grant select on veil2.all_scope_promotions_v to veil_user;
revoke all on veil2.all_scope_promotions_vv from public;
grant select on veil2.all_scope_promotions_vv to veil_user;


\echo ......scope_tree...
create or replace
view veil2.scope_tree (scope_tree) as
with recursive
  top_scopes as
  (
    select distinct
           promoted_scope_id as root_scope_id,
	   promoted_scope_type_id as root_scope_type_id
      from veil2.scope_promotions
     where promoted_scope_id not in (
        select scope_id
	  from veil2.scope_promotions)
  ),
  recursive_scope_tree as
  (    
    select 1 as depth, 
           '(' || sp.promoted_scope_id::text || '.' ||
	   sp.scope_id || ').(' || sp.promoted_scope_type_id ||
	   '.' || sp.scope_type_id || ')' as path,
           sp.promoted_scope_id, sp.scope_id,
	   sp.promoted_scope_type_id, sp.scope_type_id
      from top_scopes ts
     inner join veil2.scope_promotions sp
        on sp.promoted_scope_id = ts.root_scope_id
       and sp.promoted_scope_type_id = ts.root_scope_type_id
     union all
    select depth + 1, 
    	   rst.path || '(' || sp.promoted_scope_id ||
	   '.' || sp.scope_id || ')',
           sp.promoted_scope_id, sp.scope_id,
	   sp.promoted_scope_type_id, sp.scope_type_id
      from recursive_scope_tree rst
     inner join veil2.scope_promotions sp
        on sp.promoted_scope_id = rst.scope_id
       and sp.promoted_scope_type_id = rst.scope_type_id
  ),
  format1 as
  (
    select st1.scope_type_name || ':' ||
    	    promoted_scope_id::text as parent,
           st2.scope_type_name || ':' || scope_id::text as child,
	   depth
      from recursive_scope_tree rst
     inner join veil2.scope_types st1
        on st1.scope_type_id = rst.promoted_scope_type_id
     inner join veil2.scope_types st2
        on st2.scope_type_id = rst.scope_type_id
    order by path
  )
select format('%' || ((depth)*16 - 14) || 's', '+-') ||
       substr('------------', length(parent)) || parent ||
       '-+' || substr('-------------', length(child)) ||
       child 
  from format1;

comment on view veil2.scope_tree is
'Provides a simple ascii-formatted tree representation of our scope
promotions tree.  This is an aid to data visualisation for data
designers and administrators and is not used elsewhere in Veil2.';

revoke all on veil2.scope_tree from public;
grant select on veil2.scope_tree to veil_user;


\echo ......promotable_privileges...
create view veil2.promotable_privileges (
  scope_type_id, privilege_ids)
as
select st.scope_type_id, bitmap_of(p.privilege_id)
  from veil2.scope_types st
 inner join veil2.privileges p
    on p.promotion_scope_type_id = st.scope_type_id
group by st.scope_type_id;

comment on view veil2.promotable_privileges is
'Provide bitmaps of those privileges that may be promoted, mapped to the
context types to which they should promote.  This is not used elsewhere
in veil2 but may be useful for visualising data.';

create view veil2.promotable_privileges_info (
  scope_type_id, privilege_ids)
as
select scope_type_id, to_array(privilege_ids)
  from veil2.promotable_privileges;

comment on view veil2.promotable_privileges_info is
'As veil2.promotable_privileges with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';

revoke all on veil2.promotable_privileges from public;
grant select on veil2.promotable_privileges to veil_user;
revoke all on veil2.promotable_privileges_info from public;
grant select on veil2.promotable_privileges_info to veil_user;


\echo ......all_accessor_roles...
create or replace
view veil2.all_accessor_roles (
  accessor_id, role_id, context_type_id, context_id
) as
select accessor_id, role_id,
       context_type_id, context_id
  from veil2.accessor_roles;

comment on view veil2.all_accessor_roles is
'Provides all of an accessor''s explicit role assignments, ie it does
not provide the personal_context role.  This view is used by the veil2
access control functions, and when adding new security context types,
this view is all that should usually need to be modified.

VPD Implementation Notes: If you have any explicitly assigned roles
that are not granted through the veil2.accessor_role table, you will
need to redefine this view.  For example if you have a project context
that is dependent on an accessor being assigned to a project you might
redefine the view as follows:

    create or replace
    view veil2.all_accessor_roles (
      accessor_id, role_id, context_type_id, context_id
    ) as
    select accessor_id, role_id,
           context_type_id, context_id
      from veil2.accessor_roles
     union all
    select party_id, role_id,
           99,  -- id for project context_type
           project_id
      from project_parties;';

revoke all on veil2.all_accessor_roles from public;
grant select on veil2.all_accessor_roles to veil_user;


\echo ......all_context_privs...
create or replace
view veil2.all_context_privs as
    -- We retrieve 2 distinct pairs of context keys: one for the
    -- scope within which the privilge applies (which for directly
    -- assigned roles and privileges is the context of the
    -- assignment), and one for the role->role mappings, which may be
    -- in a different context.  Note that global_privs below are those
    -- privs which automatically promote to global scope regardless of
    -- the context in which they are assigned.
with direct_privs(
    accessor_id, assignment_context_type_id,
    assignment_context_id, mapping_context_type_id,
    mapping_context_id, roles,
    privs, global_privs, promotable_privs) as
  (
    -- Provides all accessor roles and privs in all contexts, without
    -- privilege promotion, identifying the context of the original
    -- role assignment, and the context of role->role mappings.  Note
    -- that a null mapping context should be interpreted as meaning
    -- that the role mapping applies in all contexts.
    select aar.accessor_id, aar.context_type_id,
           aar.context_id, arp.context_type_id,
           arp.context_id, union_of(arp.roles),
           union_of(arp.privileges),
           union_of(arp.global_privileges),
           union_of(arp.promotable_privileges)
      from veil2.all_accessor_roles aar
     inner join veil2.all_role_privs arp
        on arp.role_id = aar.role_id
     group by aar.accessor_id, aar.context_type_id, aar.context_id,
              arp.context_type_id, arp.context_id
  ),
promotable_privs as
  (
    -- Provides a row for each promotable privilege (ie privilege that
    -- may be promoted).
    select dp.accessor_id, dp.assignment_context_type_id,
           dp.assignment_context_id, dp.mapping_context_type_id,
           dp.mapping_context_id, 
           bits(dp.promotable_privs) as privilege_id
      from direct_privs dp
     where promotable_privs is not null
  ),
promoted_privs as
  (
    -- Provides bitmaps of promoted privileges, identifying the scope
    -- to which they have been promoted as well as the assignment and
    -- mapping contexts.
    select pp.accessor_id, pp.assignment_context_type_id,
           pp.assignment_context_id, pp.mapping_context_type_id,
	   pp.mapping_context_id, pp.privilege_id,
	   asp.promoted_scope_type_id as promoted_scope_type_id,
	   asp.promoted_scope_id as promoted_scope_id,
	   bitmap_of(pp.privilege_id) as promoted_privs
      from promotable_privs pp
     inner join veil2.privileges p
        on p.privilege_id = pp.privilege_id
     inner join veil2.all_scope_promotions asp
       on asp.scope_type_id = pp.assignment_context_type_id
      and asp.scope_id = pp.assignment_context_id
      and asp.promoted_scope_type_id = p.promotion_scope_type_id
      and asp.is_type_promotion
    group by pp.accessor_id, pp.assignment_context_type_id,
             pp.assignment_context_id, pp.mapping_context_type_id,
	     pp.mapping_context_id, pp.privilege_id,
	     asp.promoted_scope_type_id, asp.promoted_scope_id
)
select accessor_id,
       -- The assignment fields give the context of the role
       -- assignment from which the privs are derived.
       assignment_context_type_id,
       assignment_context_id,
       -- The mapping fields give the scope of role->role mappings
       -- which must map the context of the session.  If these are
       -- null, they match all session contexts.
       mapping_context_type_id,
       mapping_context_id,
       -- The scope fields give the scope within which the privilege
       -- applies.  For direct privileges, this is the same as the
       -- assignment context.
       assignment_context_type_id as scope_type_id,
       assignment_context_id as scope_id,
       roles, privs,'direct' as source
  from direct_privs
 union all
       -- The following gives those privileges that have been
       -- promoted to global scope regardless of how they were
       -- assigned  .
select accessor_id,
       assignment_context_type_id, assignment_context_id,
       mapping_context_type_id, mapping_context_id,
       1, 0, -- Global scope
       null, global_privs, 'global'
  from direct_privs
 union all
select accessor_id,
       assignment_context_type_id, assignment_context_id,
       mapping_context_type_id, mapping_context_id, 
       promoted_scope_type_id, promoted_scope_id,
       null, promoted_privs, 'promoted'
  from promoted_privs;

comment on view veil2.all_context_privs is
'This is an internal view aimed to help development and debugging.
There should be no need to give anyone other than developers any
access to this.';

create or replace
view veil2.all_context_privs_info (
  accessor_id, assignment_context_type_id,
  assignment_context_id, mapping_context_type_id,
  mapping_context_id, scope_type_id,
  scope_id, roles,
  privs, source) as
select accessor_id, assignment_context_type_id,
       assignment_context_id, mapping_context_type_id,
       mapping_context_id, scope_type_id,
       scope_id, to_array(roles),
       to_array(privs), source
  from veil2.all_context_privs;
  
comment on view veil2.all_context_privs_info is
'As veil2.direct_role_privileges_v with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';

revoke all on veil2.all_context_privs from public;
grant select on veil2.all_context_privs to veil_user;
revoke all on veil2.all_context_privs_info from public;
grant select on veil2.all_context_privs_info to veil_user;


\echo ......all_accessor_privs...
create or replace
view veil2.all_accessor_privs_v (
  accessor_id,
  assignment_context_type_id, assignment_context_id,
  mapping_context_type_id, mapping_context_id,
  scope_type_id, scope_id,
  roles,  privs) as
select accessor_id,
       assignment_context_type_id, assignment_context_id,
       mapping_context_type_id, mapping_context_id,
       scope_type_id, scope_id,
       union_of(roles),  union_of(privs)
  from veil2.all_context_privs
 group by accessor_id, assignment_context_type_id, assignment_context_id,
  mapping_context_type_id, mapping_context_id,
  scope_type_id, scope_id;

comment on view veil2.all_accessor_privs_v is
'Show all roles and privileges assigned to all accessors in all
contexts, excepting the implied personal context.';

create or replace
view veil2.all_accessor_privs_v_info (
  accessor_id,
  assignment_context_type_id, assignment_context_id,
  mapping_context_type_id, mapping_context_id,
  scope_type_id, scope_id,
  roles,  privs) as
select accessor_id,
       assignment_context_type_id, assignment_context_id,
       mapping_context_type_id, mapping_context_id,
       scope_type_id, scope_id,
       to_array(roles),  to_array(privs)
  from veil2.all_accessor_privs_v;

comment on view veil2.all_accessor_privs_v_info is
'As veil2.all_accessor_privs_v with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';

create or replace 
view veil2.all_accessor_privs_vv as
select * from veil2.all_accessor_privs_v;

comment on view veil2.all_accessor_privs_vv is
'As veil2.all_accessor_privs_v';

create or replace
view veil2.all_accessor_privs_vv_info (
  accessor_id,
  assignment_context_type_id, assignment_context_id,
  mapping_context_type_id, mapping_context_id,
  scope_type_id, scope_id,
  roles,  privs) as
select accessor_id,
       assignment_context_type_id, assignment_context_id,
       mapping_context_type_id, mapping_context_id,
       scope_type_id, scope_id,
       to_array(roles),  to_array(privs)
  from veil2.all_accessor_privs_vv;

comment on view veil2.all_accessor_privs_vv_info is
'As veil2.all_accessor_privs_vv with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';

create
materialized view veil2.all_accessor_privs
  as select * from veil2.all_accessor_privs_v;

comment on materialized view veil2.all_accessor_privs is
'Show all roles and privileges assigned to all accessors in all
contexts, excepting the implied personal context.';

create or replace
view veil2.all_accessor_privs_info (
  accessor_id,
  assignment_context_type_id, assignment_context_id,
  mapping_context_type_id, mapping_context_id,
  scope_type_id, scope_id,
  roles,  privs) as
select accessor_id,
       assignment_context_type_id, assignment_context_id,
       mapping_context_type_id, mapping_context_id,
       scope_type_id, scope_id,
       to_array(roles),  to_array(privs)
  from veil2.all_accessor_privs;

comment on view veil2.all_accessor_privs_info is
'As veil2.all_accessor_privs with bitmaps shown as arrays.  Info
views are intended as developer-readable versions of the non-info
views.';

revoke all on veil2.all_accessor_privs from public;
grant select on veil2.all_accessor_privs to veil_user;
revoke all on veil2.all_accessor_privs_info from public;
grant select on veil2.all_accessor_privs_info to veil_user;
revoke all on veil2.all_accessor_privs_v from public;
grant select on veil2.all_accessor_privs_v to veil_user;
revoke all on veil2.all_accessor_privs_v_info from public;
grant select on veil2.all_accessor_privs_v_info to veil_user;
revoke all on veil2.all_accessor_privs_vv from public;
grant select on veil2.all_accessor_privs_vv to veil_user;
revoke all on veil2.all_accessor_privs_vv_info from public;
grant select on veil2.all_accessor_privs_vv_info to veil_user;


\echo ......role_chains...
create or replace
view veil2.role_chains as
with recursive role_chains
as
  (
    select rr.primary_role_id, rr.assigned_role_id,
    	   rr.primary_role_id::text || '->' ||
	       rr.assigned_role_id::text as id_chain,
	   r1.role_name || '->' || r2.role_name as name_chain,
	   rr.context_type_id,
	   rr.context_id,
	   bitmap(rr.primary_role_id) + rr.assigned_role_id as roles_bitmap
      from veil2.role_roles rr
     inner join veil2.roles r1
        on r1.role_id = rr.primary_role_id
     inner join veil2.roles r2
        on r2.role_id = rr.assigned_role_id
     union all
    select rc.primary_role_id, rr.assigned_role_id,
           rc.id_chain || '->' || rr.assigned_role_id::text,
	   rc.name_chain || '->' || r.role_name,
	   rc.context_type_id,
	   rc.context_id,
	   rc.roles_bitmap + rr.assigned_role_id
      from role_chains rc
     inner join veil2.role_roles rr
        on rr.primary_role_id = rc.assigned_role_id
       and rr.context_type_id = rc.context_type_id
       and rr.context_id = rc.context_id
     inner join veil2.roles r
        on r.role_id = rr.assigned_role_id
     where not rc.roles_bitmap ? rr.assigned_role_id
   ),
  all_contexts as
   (
     select distinct context_type_id, context_id
       from role_chains
   ),
  base_roles as
   (
     select r.role_id as primary_role_id, 
            r.role_id as assigned_role_id, 
            r.role_id::text as id_chain,
            r.role_name as name_chain,
            ac.context_type_id,
            ac.context_id
       from veil2.roles r
      cross join all_contexts ac
   )  
select primary_role_id, assigned_role_id,
       context_type_id,
       context_id, id_chain, name_chain
  from role_chains
 union all
select primary_role_id, assigned_role_id,
       context_type_id,
       context_id, id_chain, name_chain
  from base_roles
order by 3, 4, 1, 2;

comment on view veil2.role_chains is
'This is a developer view.  It is intended for development and
debugging, and provides a way to view role mappings in a simple but
complete way.  Try it, it should immediately make sense.';

revoke all on veil2.role_chains from public;
grant select on veil2.role_chains to veil_user;


\echo ......all_accessor_roles_plus...
create or replace
view veil2.all_accessor_roles_plus as
select accessor_id, role_id,
       context_type_id, context_id
  from veil2.all_accessor_roles
 union all
select accessor_id, 2, 1, accessor_id
  from veil2.accessors;

comment on view veil2.all_accessor_roles_plus is
'As all_accessor_roles but also showing personal_context role for each
accessor.  This is a developer view, aimed at development and
debugging.';

revoke all on veil2.all_accessor_roles_plus from public;
grant select on veil2.all_accessor_roles_plus to veil_user;


\echo ......privilege_assignments...
create or replace
view veil2.privilege_assignments as
select aar.accessor_id, rp.privilege_id,
       aar.context_type_id as ass_cntxt_type_id,
       aar.context_id as ass_cntxt_id,
       coalesce(p.promotion_scope_type_id,
                aar.context_type_id) as scope_type_id,
       coalesce(asp.promoted_scope_id,
	        aar.context_id) as scope_id,
       rc.primary_role_id as ass_role_id,
       rc.assigned_role_id as priv_bearing_role_id,
       rc.id_chain as role_id_mapping,
       rc.name_chain as role_name_mapping,
       rc.context_type_id as map_cntxt_type_id,
       rc.context_id as map_cntxt_id
  from (
    select role_id, privilege_id
      from veil2.role_privileges
    union all
    select 1, privilege_id
      from veil2.privileges
       ) rp
 inner join veil2.privileges p
    on p.privilege_id = rp.privilege_id
 inner join veil2.role_chains rc
    on rc.assigned_role_id = rp.role_id
 inner join veil2.all_accessor_roles_plus aar
    on aar.role_id = rc.primary_role_id
  left outer join veil2.all_scope_promotions asp
    on asp.scope_type_id = aar.context_type_id
   and asp.scope_id = aar.context_id
   and asp.promoted_scope_type_id = p.promotion_scope_type_id
   and asp.is_type_promotion;

comment on view veil2.privilege_assignments is
'Developer view that shows how accessors get privileges.  It shows the
roles that the user is assigned, and the context in which they are
assigned, as well as the mappings from role to role to privilege which
give that resulting privilege to the accessor.

If you are uncertain how accessor 999 has privilege 333, then simply
run:

    select * 
      from veil2.privilege_assignments 
     where accessor_id = 999 
       and privilege_id = 333;';


revoke all on veil2.privilege_assignments from public;
grant select on veil2.privilege_assignments to veil_user;


\echo ...creating materialized view refresh functions...

\echo ...refresh_accessor_privs()...
create or replace
function veil2.refresh_accessor_privs()
  returns trigger
as
$$
begin
  refresh materialized view veil2.all_accessor_privs;
  return new;
end;
$$
language 'plpgsql' security definer volatile leakproof;

comment on function veil2.refresh_accessor_privs() is
'Trigger function to refresh materialized views based on accessor_role
data.';


\echo ...refresh_scope_promotions()...
create or replace
function veil2.refresh_scope_promotions()
  returns trigger
as
$$
begin
  refresh materialized view veil2.all_scope_promotions;
  refresh materialized view veil2.all_accessor_privs;
  return new;
end;
$$
language 'plpgsql' security definer volatile leakproof;

comment on function veil2.refresh_scope_promotions() is
'Trigger function to refresh materialized views that provide or use
privilege promotion data.';


\echo ...refresh_role_privileges()...
create or replace
function veil2.refresh_role_privileges()
  returns trigger
as
$$
begin
  refresh materialized view veil2.direct_role_privileges;
  refresh materialized view veil2.all_role_privs;
  refresh materialized view veil2.all_accessor_privs;
  return new;
end;
$$
language 'plpgsql' security definer volatile leakproof;

comment on function veil2.refresh_role_privileges() is
'Trigger function to refresh dependant materialized views
when role->role or role->privilege mappings are changed.';


\echo ...creating materialized view refresh triggers...

\echo ......on role_privileges...
create trigger role_privileges__aiudt
  after insert or update or delete or truncate
  on veil2.role_privileges
  for each statement
  execute procedure veil2.refresh_role_privileges();

comment on trigger role_privileges__aiudt on veil2.role_privileges is
'Refresh materialized views that are constructed from the
role_privileges table.  We should not be concerned with the overhead of
this, as the role_privileges table should be mostly static.';


\echo ......on role_roles...
create trigger role_roles__aiudt
  after insert or update or delete or truncate
  on veil2.role_roles
  for each statement
  execute procedure veil2.refresh_role_privileges();

comment on trigger role_roles__aiudt on veil2.role_roles is
'Refresh materialized views that are constructed from the
role_privileges table.  

VPD Implementation Notes:
Although we expect that role->role mappings will be modified relatively
infrequently, this may not be the case in your application.  If the
overhead of this trigger proves to be too significant it should be
dropped, and other mechanisms used to refresh the affected materialized
views.  Note that this will mean that the materialized views will not
always be up to date, so this is a trade-off that must be evaluated.';


\echo ......on scopes...
create trigger scopes__aiudt
  after insert or update or delete or truncate
  on veil2.scopes
  for each statement
  execute procedure veil2.refresh_scope_promotions();

comment on trigger scopes__aiudt on veil2.scopes is
'Refresh materialized views that are constructed from the
scopes table.

VPD Implementation Notes:
Although we expect that scopes will be modified relatively
infrequently, this may not be the case in your application.  If the
overhead of this trigger proves to be too significant it should be
dropped, and other mechanisms used to refresh the affected materialized
views.  Note that this will mean that the materialized views will not
always be up to date, so this is a trade-off that must be evaluated.';


\echo ......on accessor_roles...
create trigger accessor_roles__aiudt
  after insert or update or delete or truncate
  on veil2.accessor_roles
  for each statement
  execute procedure veil2.refresh_accessor_privs();

comment on trigger accessor_roles__aiudt on veil2.accessor_roles is
'Refresh materialized views that are constructed from the
accessor_roles table.

VPD Implementation Notes:
As accessor_roles may be updated moderately frequently, the overhead of
this trigger may prove to be significant.  If so, you may choose to
drop it and use other mechanisms to refresh the affected materialized
views.  Note that this will mean that the materialized views will not
always be up to date, so this is a trade-off that must be evaluated.';

-- Create the VEIL2 base functions


\echo ...creating veil2 authentication functions...
\echo ......authenticate_false()...
create or replace
function veil2.authenticate_false(
    accessor_id integer,
    token text)
  returns bool as
$$
select false;
$$
language 'sql' security definer stable leakproof;

comment on function veil2.authenticate_false(integer, text) is
'Authentication predicate for unimplemented or disabled authentication
types.  This function always returns false, causing authentication to
fail.';


\echo ......authenticate_plaintext()...
create or replace
function veil2.authenticate_plaintext(
    accessor_id integer,
    token text)
  returns bool as
$$
select coalesce(
    (select authent_token = authenticate_plaintext.token
       from veil2.authentication_details
      where accessor_id = authenticate_plaintext.accessor_id
        and authentication_type = 'plaintext'),
    false);
$$
language 'sql' security definer stable leakproof;

comment on function veil2.authenticate_plaintext(integer, text) is
'Authentication predicate for plaintext authentication.  Return true if
the supplied token matches the stored authentication token for the
accessor.  This authentication mechanism exists primarily for demo
purposes.  DO NOT USE IT IN A REAL APPLICATION!';


\echo ......authenticate_bcrypt()...
create or replace
function veil2.authenticate_bcrypt(
    accessor_id integer,
    token text)
  returns bool as
$$
select coalesce(
    (select authent_token = crypt(token, authent_token)
       from veil2.authentication_details
      where accessor_id = authenticate_bcrypt.accessor_id
        and authentication_type = 'bcrypt'),
    false);
$$
language 'sql' security definer stable leakproof;

comment on function veil2.authenticate_bcrypt(integer, text) is
'Authentication predicate for bcrypt authentication.  Return true if
running bcrypt on the supplied token, using the salt from the
stored authentication token for the accessor, matches that stored
authentication token.

Bcrypt is generally considered a step up from traditional hash-based
password authentication, though it is essentially the same thing.  In
a hash-based authentication system, a user''s password is stored as a,
possibly salted, hash on the plaintext.  Since hashes are one-way
algorithms it is impossible to retrieve the original password from the
hash.  However, as computers have become more powerful, brute-force
approaches have become more feasible.  With a simple hash, it is is
now possible to try every possible password until one matches the
hash, whether salted or not in a matter of hours.  Bcrypt makes
brute-forcing difficult by using a compuatationally inefficient hash
algorithm, which makes brute force attacks a very expensive
proposition.  Note that in attacks on hash-based passwords it is
assumed that the hashed password has been compromised.  Whether this
is likely in database protected by Veil2 is moot, however there may be
more likely avenues for attack as the hashed passwords can be pretty
well locked down.

The current bcrypt implementation''s biggest down-side, in common with
traditional hash-based approaches, is that the user''s password is
sent to the server in plaintext before it is tested by bcrypting it.
A better authentication method would avoid this.';


\echo ......authenticate()...
create or replace
function veil2.authenticate(
    accessor_id integer,
    authent_type text,
    token text)
  returns bool as
$$
declare
  success bool;
  authent_fn text;
  enabled bool;
begin
  select t.enabled, t.authent_fn
    into enabled, authent_fn
    from veil2.authentication_types t
   where t.shortname = authent_type;
  if found and enabled then
    execute format('select * from %s(%s, %L)',
                   authent_fn, accessor_id, token)
       into success;
    return success;
  end if;
  return false;
end;
$$
language 'plpgsql' security definer stable leakproof;

comment on function veil2.authenticate(integer, text, text) is
'For the given accessor_id and authentication_type check whether token
is an appropriate authentication.';


\echo ...creating veil2 session functions...

\echo ......reset_session()...
create or replace
function veil2.reset_session()
  returns void as
$$
begin
  create temporary table if not exists session_parameters
    of veil2.session_params_t;
  truncate table session_parameters;
  create temporary table if not exists session_privileges
    of veil2.session_privileges_t;
  truncate table session_privileges;

  execute 'grant select on session_privileges to veil_user;';
  execute 'grant select on session_parameters to veil_user;';
end;
$$
language 'plpgsql' security definer
set client_min_messages = 'error';

comment on function veil2.reset_session() is
'Ensure our session_parameters temp table has been created, and then
clear it.  Note that notices about session_parameters already existing
are not sent to the client.

Note that the return type is not relevant but using bool rather than
void makes formatting tests results easier as it makes it easier to
write queries that call the function that return no rows';

/*
create or replace
function veil2.get_accessor(
    username in text,
    context_type_id in integer,
    context_id in integer)
  returns integer as
$$
begin
  return 0;
end;
$$
language plpgsql security definer stable leakproof;

comment on function veil2.get_accessor(text, integer, integer) is
'Retrieve accessor_id based on username and context.  This function
must be customized specifically for your application.';
*/

\echo ......create_accessor_session()...
create or replace
function veil2.create_accessor_session(
    accessor_id in integer,
    authent_type in text,
    context_type_id in integer default 1,
    context_id in integer default 0,
    session_id out integer,
    session_token out text,
    session_supplemental out text)
  returns record as
$$
declare
  valid bool;
  ignore bool;
  _mapping_context_type_id integer;
  _mapping_context_id integer;
  supplemental_fn text;
begin
  execute veil2.reset_session();  -- ignore result

  -- Regardless of validity of accessor_id, we create a
  -- session_parameters record to prevent fishing for valid
  -- accessor_ids.
  insert
    into session_parameters
        (accessor_id, session_id,
	 login_context_type_id, login_context_id,
	 mapping_context_type_id, mapping_context_id,
	 is_open)
  select create_accessor_session.accessor_id,
         nextval('veil2.session_id_seq'),
	 create_accessor_session.context_type_id,
	 create_accessor_session.context_id,
         case when sp.parameter_value = '1' then 1
         else coalesce(asp.promoted_scope_type_id,
	               create_accessor_session.context_type_id) end,
         case when sp.parameter_value = '1' then 0
         else coalesce(asp.promoted_scope_id,
	               create_accessor_session.context_id) end,
	 false
    from veil2.system_parameters sp
    left outer join veil2.all_scope_promotions asp
      on asp.scope_type_id = create_accessor_session.context_type_id
     and asp.scope_id = create_accessor_session.context_id
     and asp.promoted_scope_type_id = sp.parameter_value::integer
     and asp.is_type_promotion
   where sp.parameter_name = 'mapping context target scope type'
  returning session_parameters.session_id,
            session_parameters.mapping_context_type_id,
            session_parameters.mapping_context_id
       into create_accessor_session.session_id,
            _mapping_context_type_id,
	    _mapping_context_id;

  -- Figure out the session tokens.  As above this must succeed
  -- regardless of the validity of our parameters.
  select t.supplemental_fn
    into supplemental_fn
    from veil2.authentication_types t
   where shortname = authent_type;

  if supplemental_fn is not null then
    execute format('select * from %s(%s, %L)',
                   supplemental_fn, _accessor_id, session_token)
       into session_token, session_supplemental;
  else
    session_token := encode(digest(random()::text || now()::text, 'sha256'),
		            'base64');
  end if;

  select true
    into ignore
    from veil2.accessors a
   inner join veil2.accessor_contexts ac
      on ac.accessor_id = a.accessor_id
   where a.accessor_id = create_accessor_session.accessor_id
     and ac.context_type_id = create_accessor_session.context_type_id
     and ac.context_id = create_accessor_session.context_id;
     
  if found then
    -- The combination of accessor_id and context is valid.
    -- Generate session_supplemental if authentication method supports it.
  
    insert
      into veil2.sessions
          (accessor_id, session_id,
	   login_context_type_id, login_context_id,
	   mapping_context_type_id, mapping_context_id,
	   authent_type, has_authenticated,
	   session_supplemental, expires,
	   token)
    select create_accessor_session.accessor_id,
    	   create_accessor_session.session_id, 
    	   create_accessor_session.context_type_id,
	   create_accessor_session.context_id,
    	   _mapping_context_type_id,
	   _mapping_context_id,
	   authent_type, false,
	   session_supplemental, now() + sp.parameter_value::interval,
	   session_token
      from veil2.system_parameters sp
     where sp.parameter_name = 'shared session timeout';
  end if;
end;
$$
language 'plpgsql' security definer volatile
set client_min_messages = 'error';

comment on function veil2.create_accessor_session(
integer, text, integer, integer) is
'Create a new session based on an accessor_id rather than username.
This is an internal function to veil2.  It does the hard work for
create_session().';


\echo ......create_session()...
create or replace
function veil2.create_session(
    username in text,
    authent_type in text,
    context_type_id in integer default 1,
    context_id in integer default 0,
    session_id out integer,
    session_token out text,
    session_supplemental out text)
  returns record as
$$
declare
  _accessor_id integer;
begin
  execute veil2.reset_session();
  -- Generate session_id and session_token and establish whether
  -- username was valid.
  _accessor_id := veil2.get_accessor(username, context_type_id, context_id);

  select cas.session_id, cas.session_token,
         cas.session_supplemental
    into create_session.session_id, create_session.session_token,
         create_session.session_supplemental
    from veil2.create_accessor_session(
             _accessor_id, authent_type,
	     context_type_id, context_id) cas;
end;
$$
language 'plpgsql' security definer volatile
set client_min_messages = 'error';

comment on function veil2.create_session(text, text, integer, integer) is
'Get session credentials for a new session.  

Returns session_id, authent_token and session_supplemental.

session_id is used to uniquely identify this user''s session.  It will
be needed for subsequent open_connection() calls.

session_token is randomly generated.  Depending on the authentication
method chosen, the client may need to use this when generating their
authentication token for the subsequent open_connection() call.
session_supplemental is an authentication method specific set of
data.  Depending upon the authentication method, the client may need
to use this in generating subsequent authentication tokens,

If username is not valid the function will appear to work but
subsequent attempts to open the session will fail and no privileges
will be loaded.  This makes it harder to fish for valid usernames.

The authent_type parameter identifies what type of authentication will
be used, and therefore determines the authentication protocol.  All
authentication types will make use of a session_id and session_token,
some may also require additional fields.  These will be provided in
session_supplemental.  For example, if we were to define a
Diffie-Hellman key exchange protocol, the session_supplemental field
would provide modulus, base and public transport values.';


\echo ......check_nonce()...
create or replace
function veil2.check_nonce(
    nonce integer,
    nonces bitmap)
  returns bool as
$$
  select case
         when nonces is null then true
         when (nonces ? nonce) then false
	 when nonce < bitmin(nonces) then false
	 when nonce > (bitmax(nonces) + 64) then false
	 else true end;
$$
language 'sql' security definer stable leakproof;

comment on function veil2.check_nonce(integer, bitmap) is
'Check that nonce has not already been used and is within the range of
acceptable values, returning true if all is well.';


\echo ......update_nonces()...
create or replace
function veil2.update_nonces(
    nonce integer,
    nonces bitmap)
  returns bitmap as
$$
declare
  reslt bitmap;
  i integer;
target_bitmin integer;
begin
  reslt := coalesce(nonces, bitmap()) + nonce;
  if (bitmax(reslt) - bitmin(reslt)) > 192 then
    -- If there are 3 64-bit groups in the bitmap, let's lose the
    -- lowest one.  We keep 2 groups active, allowing for some slop in
    -- the arrival of consecutive integers without allowing the bitmaps
    -- to become unreasonably large.  I don't see any attack vector
    -- here as it should be impossible to get past the checks in
    -- check_nonce() by attempting to re-use (in a replay attack) a
    -- nonce from a group that we have dropped.
    target_bitmin = (bitmin(reslt) + 64) & ~63;
    reslt := bitmap_setmin(reslt, target_bitmin);
  end if;
  return reslt;
end;
$$
language 'plpgsql' security definer stable leakproof;

comment on function veil2.update_nonces(integer, bitmap) is
'Add nonce to the list of used nonces, slimming the bitmap down when it
gets too large.'; 


\echo ......filter_privs()...
create or replace
function veil2.filter_privs()
  returns void as
$$
begin
  -- We are going to update session_privileges to remove any roles and
  -- privileges that do not exist in orig_privileges.  This is part of
  -- the become user process, to ensure that become user cannot lead
  -- to privilege escalation.
  with new_privs as
    (
      select sp.scope_type_id, sp.scope_id
        from session_privileges sp
    ),
  superior_scopes as
    (
      select np.scope_type_id, np.scope_id,
             asp.promoted_scope_type_id, asp.promoted_scope_id
        from new_privs np
       inner join veil2.all_scope_promotions asp
          on asp.scope_type_id = np.scope_type_id
         and asp.scope_id = np.scope_id
       union
       select scope_type_id, scope_id, scope_type_id, scope_id
        from new_privs
       union
       select scope_type_id, scope_id, 1, 0  -- global scope is superior
        from new_privs
    ),
  allowable_privs as
    (
      select ss.scope_type_id, ss.scope_id,
             union_of(op.roles) as roles,
  	   union_of(op.privs) as privs
        from superior_scopes ss
       inner join orig_privileges op
          on op.scope_type_id = ss.promoted_scope_type_id
         and (   op.scope_id = ss.promoted_scope_id
              or op.scope_type_id = 2)  -- Personal scope: do not test scope_id
      group by ss.scope_type_id, ss.scope_id
    ),
  final_privs as
    (
      select sp.session_id, sp.scope_type_id, sp.scope_id,
             sp.roles * ap.roles as roles,
             sp.privs * ap.privs as privs
        from session_privileges sp
       inner join allowable_privs ap
          on ap.scope_type_id = sp.scope_type_id
         and ap.scope_id = sp.scope_id
    )
  update session_privileges sp
     set roles = fp.roles,
         privs = fp.privs
    from final_privs fp
   where sp.scope_type_id = fp.scope_type_id
     and sp.scope_id = fp.scope_id;
end;
$$
language 'plpgsql' security definer volatile;

comment on function veil2.filter_privs() is
'Remove any privileges from session_privileges that would not be
provided by orig_privileges.  This is part of the become user
functionality.  We perform this filtering in order to ensure that a
user cannot increase their privileges using become user.';


\echo ......save_privs_as_orig()...
create or replace
function veil2.save_privs_as_orig () returns void as
$$
begin
  create temporary table if not exists orig_privileges as
  select * from session_privileges where false;
  truncate table orig_privileges;
  insert into orig_privileges select * from session_privileges;
end;
$$
language 'plpgsql' security definer volatile;

comment on function veil2.save_privs_as_orig() is
'Save the current contents of the session_privileges table to
orig_privileges.  This is part of the become user process.';


\echo ......load_session_privs()...
create or replace
function veil2.load_session_privs(
    session_id in integer,
    _accessor_id in integer,
    _prev_session_id in integer default null)
  returns bool as
$$
declare
  _prev_accessor_id integer;
  _prevprev_accessor_id integer;
  _need_filter boolean := false;
begin
  execute veil2.reset_session();

  if _prev_session_id is not null then
    select accessor_id,
      	   case when s.authent_type = 'become'
	        then s.session_supplemental::integer
	        else null
	   end
      into _prev_accessor_id,
      	   _prevprev_accessor_id
      from veil2.sessions
     where session_id = _prev_session_id;
    -- Recurse to load privs of originating session.
    if veil2.load_session_privs(
           _prev_session_id, _prev_accessor_id,
	   _prevprev_accessor_id)
    then
      -- Save originating session privs for later filtering.
      execute veil2.save_privs_as_orig();
      _need_filter := true;
    else
      return false;
    end if;
  end if;

  with session_context as
    (
      select mapping_context_type_id, mapping_context_id
        from veil2.sessions s
       where s.session_id = load_session_privs.session_id
    ), 
  valid_scopes as
    (
      -- This query is used to restrict the role assignments we use,
      -- to those that apply in scopes superior, inferior or equal to
      -- our mapping context.  This eliminates roles assigned in
      -- scopes that have no bearing on our mapping scope, ie from
      -- parallel parts of the scope tree.  We *must* do this because
      -- those roles, assigned in an irrelevant context,could contain
      -- privileges that will be promoted to a relevant one.
      select asp.promoted_scope_type_id as scope_type_id,
             asp.promoted_scope_id as scope_id
        from session_context sc
       inner join veil2.all_scope_promotions asp
          on asp.scope_type_id = sc.mapping_context_type_id
         and asp.scope_id = sc.mapping_context_id
       union all
       select 1, 0
       union all
       select mapping_context_type_id, mapping_context_id
         from session_context
       union all
       select asp.scope_type_id,
             asp.scope_id as scope_id
         from session_context sc
       inner join veil2.all_scope_promotions asp
          on (    asp.promoted_scope_type_id = sc.mapping_context_type_id
              and asp.promoted_scope_id = sc.mapping_context_id)
	  or sc.mapping_context_type_id = 1
    ),
  all_session_privs as
    (
      select session_id,
      	     aap.scope_type_id, aap.scope_id,
  	     union_of(aap.roles) as roles,
  	     union_of(aap.privs) as privs
        from session_context c
       inner join veil2.all_accessor_privs aap
          on (   aap.mapping_context_type_id is null
              or (    aap.mapping_context_type_id = c.mapping_context_type_id
  	          and aap.mapping_context_id = c.mapping_context_id))
       where aap.accessor_id = _accessor_id
         and (aap.scope_type_id, aap.scope_id) in (
           select scope_type_id, scope_id
  	   from valid_scopes)
       group by aap.scope_type_id, aap.scope_id
    ),
  global_privs as
    (
      select privs
        from all_session_privs
       where scope_type_id = 1
    ),
  personal_privs as
    (
      select session_id,
      	     2, _accessor_id,  -- Personal context scope type
	     roles,
	     privileges
        from veil2.all_role_privs
       where role_id = 2      -- Personal context role
    )
  insert
    into session_privileges
        (session_id, scope_type_id, scope_id,
  	 roles, privs)
  select *
    from all_session_privs
  union all
  select * from personal_privs
   where (select privs from global_privs) ? 0; -- Tests for connect priv
  
  if found then
    insert
      into session_parameters
          (accessor_id, session_id,
	   login_context_type_id, login_context_id,
	   mapping_context_type_id, mapping_context_id,
	   is_open)
    select _accessor_id, load_session_privs.session_id,
           login_context_type_id, login_context_id,
           mapping_context_type_id, mapping_context_id,
	   true
      from veil2.sessions s
     where s.session_id = load_session_privs.session_id;
    if _need_filter then
      -- We are in a become-user session.  We need to filter the privs
      -- of the user we became with the privs of the session we came
      -- from so that we do not gain privileges the originating
      -- session did not have.
      execute veil2.filter_privs();
    end if;
    return true;
  else
    return false;
  end if;
end;
$$
language 'plpgsql' security definer volatile;

comment on function veil2.load_session_privs(integer, integer, integer) is
'Load the temporary table session_privileges for session_id, with the
privileges for _accessor_id.  The temporary table is queried by
security functions in order to determine what access rights the
connected user has.  If the optional 3rd parameter is provided, use
that as the session_id of an originating session - this is part of the
become-user process (see become_user())';


\echo ......check_continuation()...
create or replace
function veil2.check_continuation(
    nonce integer,
    session_token text,
    authent_token text)
  returns boolean as
$$
select encode(digest(session_token || to_hex(nonce), 'sha1'),
              'base64') = authent_token;
$$
language 'sql' security definer stable;

comment on function veil2.check_continuation(integer, text, text) is
'Checks whether the combination of nonce, session_token and
authent_token is valid.  This is used to continue sessions that have
already been authenticated.  It ensures that new tokens are used on
each call, and that the caller has access to the session_token
returned from the original (subsequently authenticated) create
session() call.';

\echo ......open_connection()...
create or replace
function veil2.open_connection(
    session_id in integer,
    nonce in integer,
    authent_token in text,
    success out bool,
    errmsg out text)
  returns record as
$$
declare
  _accessor_id integer;
  _nonces bitmap;
  _has_authenticated boolean;
  _session_token text;
  _context_type_id integer;
  _prev_session_id integer;
  authent_type text;
  expired bool;
  can_connect bool;
begin
  success := false;
  update session_parameters  -- If anything goes wrong from here on, 
  	 		     -- the session will be have no access
			     -- rights.
     set is_open = false;
  select s.accessor_id, s.expires < now(),
         s.nonces, s.authent_type,
	 ac.context_type_id,
	 s.has_authenticated, s.token,
	 case when s.authent_type = 'become'
	      then s.session_supplemental::integer
	      else null
	 end
    into _accessor_id, expired,
         _nonces, authent_type,
	 _context_type_id,
	 _has_authenticated, _session_token,
	 _prev_session_id
    from veil2.sessions s
    left outer join veil2.accessor_contexts ac
      on ac.accessor_id = s.accessor_id
     and ac.context_type_id = s.login_context_type_id
     and ac.context_id = s.login_context_id
   where s.session_id = open_connection.session_id;

  if not found then
    raise warning 'SECURITY: Login attempt with no session: %',  session_id;
    errmsg = 'AUTHFAIL';
  elsif _context_type_id is null then
    raise warning 'SECURITY: Login attempt for invalid context';
    errmsg = 'AUTHFAIL';
  elsif expired then
    errmsg = 'EXPIRED';
  else
    -- We have an unexpired session.
    if veil2.check_nonce(nonce, _nonces) then
      success := true;
    else
      -- Since this could be the result of an attempt to replay a past
      -- authentication token, we log this failure
      raise warning 'SECURITY: Nonce failure.  Nonce %, Nonces %',
                   nonce, to_array(_nonces);
      errmsg = 'NONCEFAIL';
      success := false;
    end if;

    if success then
      if _has_authenticated then
        -- The session has already been opened.  From here on we 
	-- use different authentication tokens for each open_connection()
	-- call in order to avoid replay attacks.
	-- This will be the sha1 of the concatenation of:
	--   - the session token
	--   - the nonce as a lower-case hexadecimal string
	if not veil2.check_continuation(nonce, _session_token,
	       				authent_token) then
          raise warning 'SECURITY: incorrect continuation token for %, %',
                       _accessor_id, session_id;
          errmsg = 'AUTHFAIL';
	  success := false;
	end if;
      else 
        if not veil2.authenticate(_accessor_id, authent_type,
				  authent_token) then
          raise warning 'SECURITY: incorrect % authentication token for %, %',
                       authent_type, _accessor_id, session_id;
          errmsg = 'AUTHFAIL';
	  success := false;
	end if;
      end if;
    end if;
    
    if success then
      if not veil2.load_session_privs(session_id, _accessor_id) then
        raise warning 'SECURITY: Accessor % has no connect privilege.',
                       _accessor_id;
        errmsg = 'AUTHFAIL';
	success := false;
      end if;
    end if;
    
    if not success then
      delete from session_privileges;
      delete from session_parameters;
    end if;
    -- Regardless of the success of the preceding checks we record the
    -- use of the latest nonce.  If all validations succeeded, we
    -- extend the expiry time of the session.
    update veil2.sessions s
       set expires =
           case when success
	   then now() + sp.parameter_value::interval
	   else s.expires
	   end,
           nonces = veil2.update_nonces(nonce, _nonces),
	   has_authenticated = has_authenticated or success
        from veil2.system_parameters sp
       where s.session_id = open_connection.session_id
         and sp.parameter_name = 'shared session timeout'
    returning nonces into _nonces;
  end if;
end;
$$
language 'plpgsql' security definer volatile
set client_min_messages = 'error';

comment on function veil2.open_connection(integer, integer, text) is
'Attempt to open or re-open a session.  This is used to authenticate
or re-authenticate a connection, and until this is done a session
cannot be used.  

Failures may be for several reasons with errmsg as described below:

 - non-existence of session [errmsg: ''AUTHFAIL''];

 - expiry of session (while session record still exists - has not been cleaned away) [errmsg: ''EXPIRED''];

 - incorrect credentials being used [errmsg: ''AUTHFAIL''];

 - invalid nonce being provided [errmsg: ''NONCEFAIL''];

 - the user has no connect privilege [errmsg: ''AUTHFAIL''].

The _nonce is a number that may only be used once per session, and is
used to prevent replay attacks.  Each open_connection() call should provide
a new nonce ascending in value from the last.  As connections may be
asynchronous, we do not require a strictly ascending order but nonces
may not be out of sequence by a value of more than 64.  This allows us
to keep track of used nonces without excess overhead while still
allowing an application to have multiple database connections.

The value of _authent_token depends upon the authentication method
chosen.  See the authentication function for your session''s
authentication method (identified in table veil2.authentication_types)
for details.

Note that warning messages will be sent to the log but not to the
client, even if client_min_messages is modified for the session.  This
is deliberate, for security reasons.';


\echo ......close_connection()...
create or replace
function veil2.close_connection() returns boolean as
$$
begin
  update session_parameters
     set is_open = false;
  return true;
end;
$$
language 'plpgsql' security definer volatile;

comment on function veil2.close_connection() is
'Close the current session.  We use this to ensure that a shared
database connection cannot be used with our privileges once we have
finished with it.  There is no authentication or verification done to
ensure that the session owner is the one doing this, because there is
no perceived need.  If this is a problem then, given that you can
achieve the same thing by deliberately failing a veil2.open() call,
there are other, more complex areas of the session management protocol
that will need to be reconsidered.';


\echo ......hello()...
create or replace
function veil2.hello(
    context_type_id in integer default 1,
    context_id in integer default 0)
  returns bool as
$$
declare
  _accessor_id integer;
  _session_id integer;
  success bool;
begin
  success := false;
  execute veil2.reset_session();
  
  select accessor_id
    into _accessor_id
    from veil2.accessors
   where username = session_user;
  if found then

    select cas.session_id
      into _session_id
    from veil2.create_accessor_session(
             _accessor_id, 'dedicated',
	     context_type_id, context_id) cas;

    success := veil2.load_session_privs(_session_id, _accessor_id);

    if not success then
      raise exception 'SECURITY: user % has no connect privilege.',
      	    	      session_user;
    else
      -- Update the permanent session record to show that we have
      -- authenticated and give a reasonable expiry time.
      update veil2.sessions
         set expires = now() + '1 day'::interval,
 	    has_authenticated = true
       where session_id = _session_id;

       execute 'grant select on session_parameters to veil_user;';
       execute 'grant select on session_privileges to veil_user;';
    end if;
  end if;
  return success;
end;
$$
language 'plpgsql' security definer volatile;

comment on function veil2.hello(integer, integer) is
'This is used to begin a veil2 session for a database user.';


\echo ...creating veil2 privilege testing functions...
-- Ensure the session_parameters and session _privileges temp tables
-- exist as they are needed in order to compile the following functions.
create temporary table if not exists session_parameters
    of veil2.session_params_t;

create temporary table if not exists session_privileges
    of veil2.session_privileges_t;

\echo ......i_have_global_priv()...
create or replace
function veil2.i_have_global_priv(priv integer)
  returns bool as
$$
  select coalesce(
  (select privs ? priv
    from session_privileges v
   cross join session_parameters p
   where p.is_open
     and v.scope_type_id = 1), false);
$$
language 'sql' security definer stable leakproof;

comment on function veil2.i_have_global_priv(integer) is
'Predicate to determine whether the connected user has the given
privilege in the global context.  This always returns a record.';


\echo ......i_have_priv_in_scope()...
create or replace
function veil2.i_have_priv_in_scope(
    priv integer,
    _scope_type_id integer,
    _scope_id integer)
  returns bool as
$$
select coalesce((
  select privs ? priv
    from session_privileges v
   cross join session_parameters p
   where p.is_open
     and v.scope_type_id = _scope_type_id
     and v.scope_id = _scope_id),
   false);
$$
language 'sql' security definer stable leakproof;

comment on function veil2.i_have_priv_in_scope(integer, integer, integer) is
'Predicate to determine whether the connected user has the given
privilege in the given scope.';


\echo ......i_have_priv_in_superior_scope()...
create or replace
function veil2.i_have_priv_in_superior_scope(
    priv integer,
    _scope_type_id integer,
    _scope_id integer)
  returns bool as
$$
declare
  have_priv bool;
begin
  select true
    into have_priv
    from veil2.all_scope_promotions asp
   cross join session_parameters p
   inner join session_privileges sp
      on sp.scope_type_id = asp.promoted_scope_type_id
     and sp.scope_id = asp.promoted_scope_id
   where p.is_open
     and asp.scope_type_id = _scope_type_id
     and asp.scope_id = _scope_id
     and sp.privs ? priv
   limit 1;
  return found;
end
$$
language 'plpgsql' security definer stable leakproof;

comment on function veil2.i_have_priv_in_superior_scope(integer, integer, integer) is
'Predicate to determine whether the connected user has the given
privilege in a scope that is superior to the given scope.  This does not
check for the privilege in a global scope as it is assumed that such a
test will have already been performed.  Note that due to the join on
all_scope_promotions this function may incur some small measurable
overhead.';


\echo ......i_have_personal_priv()...
create or replace
function veil2.i_have_personal_priv(
    priv integer,
    _accessor_id integer)
  returns bool as
$$
select coalesce((
  select privs ? priv
    from session_privileges v
   cross join session_parameters p
   where p.is_open
     and v.scope_type_id = 2
     and v.scope_id = _accessor_id),
   false);
$$
language 'sql' security definer stable leakproof;

comment on function veil2.i_have_personal_priv(integer, integer) is
'Predicate to determine whether the connected user has the given
privilege in the personal scope.';


\echo ...creating veil2 admin and helper functions...
\echo ......delete_expired_sessions()...
create or replace
function veil2.delete_expired_sessions() returns void as
$$
declare
  session_id integer;
begin
  for session_id in
    select s.session_id
      from veil2.sessions s
     where expires <= now()
       for update
  loop
    delete
      from veil2.session_privileges sp
     where sp.session_id = session_id;
    delete from veil2.sessions s
     where p.session_id = session_id;
  end loop;
end;
$$
language 'plpgsql' security definer volatile;

comment on function veil2.delete_expired_sessions() is
'Utility function to clean-up  session data.  This should probably be
run periodically from a batch job.';


\echo ......bcrypt()...
create or replace
function veil2.bcrypt(passwd text) returns text as
$$
select crypt(passwd, gen_salt('bf'));
$$
language 'sql' security definer volatile;

comment on function veil2.bcrypt(text) is
'Create a bcrypted password from plaintext.  It creates a value that can
be stored in veil2.authentication_details for use by the
authenticate_bcrypt() function.';

\echo ......become_accessor()...
create or replace
function veil2.become_accessor(
    accessor_id in integer,
    context_type_id in integer,
    context_id in integer,
    session_id out integer,
    session_token out text,
    success out boolean,
    errmsg out text)
  returns record as
$$
declare
  orig_session_id integer;
  _result boolean;
begin
  select sp.session_id
    into orig_session_id
    from session_parameters sp;
    
  if veil2.i_have_global_priv(1) or
     veil2.i_have_priv_in_superior_scope(1, context_type_id, context_id)
  then
    -- Ensure accessor_id and context are valid
    select true
      into _result
      from veil2.accessor_contexts ac
     where ac.accessor_id = become_accessor.accessor_id
       and ac.context_type_id = become_accessor.context_type_id
       and ac.context_id = become_accessor.context_id;
    if found then
      -- Create local copy of current privileges.  This is used to
      -- ensure that we don't gain more privileges than we started
      -- with by becoming the new user, ie <become user> privilege
      -- should not be a mechanism for privilege escalation.

      execute veil2.save_privs_as_orig();

      -- Now create the session.
      select cas.session_id, cas.session_token
        into become_accessor.session_id, become_accessor.session_token
        from veil2.create_accessor_session(
             become_accessor.accessor_id, 'become',
	     context_type_id, context_id) cas;

      -- Update sessions to show which was our original session.
      update veil2.sessions s
         set session_supplemental = orig_session_id::text,
	     has_authenticated = true
       where s.session_id = become_accessor.session_id;

      -- Update sessions to modify the timeout of our original session
      update veil2.sessions s
         set expires = now() + sp.parameter_value::interval
        from veil2.system_parameters sp
       where s.session_id = orig_session_id
         and sp.parameter_name = 'shared session timeout';

      -- Load the session privs as though we were the new user.
      success := veil2.load_session_privs(session_id, accessor_id);
      if success then
        execute veil2.filter_privs();
      else
        errmsg := 'LOADPRIV';
      end if;
    else
      errmsg := 'INVARGS';
      success := false;
    end if;
  else
    errmsg := 'NOPRIV';
    success := false;
  end if;
end;
$$
language 'plpgsql' security definer volatile
set client_min_messages = 'error';

comment on function veil2.become_accessor(integer, integer, integer) is
'Create a new opened session for the given accessor_id and context.
This allows a suitably privileged accessor to emulate another user.
The intended use-case for this is in testing and debugging access
rights.  Note that the new session will not give the connected user
more privileges than they already have, so the usage of this should
probably be confined to superusers.  Any other user is likely to get a
set of privileges that may be less than the user they have become
would normally get.';


\echo ......become_user()...
create or replace
function veil2.become_user(
    username in text,
    context_type_id in integer,
    context_id in integer,
    session_id out integer,
    session_token out text,
    success out boolean,
    errmsg out text)
  returns record as
$$
declare
  _accessor_id integer;
begin
  _accessor_id := veil2.get_accessor(username, context_type_id, context_id);

  select ba.session_id, ba.session_token,
  	 ba.success, ba.errmsg
    into become_user.session_id, become_user.session_token,
         become_user.success, become_user.errmsg
    from veil2.become_accessor(
             _accessor_id, context_type_id, context_id) ba;
end;
$$
language 'plpgsql' security definer volatile;

comment on function veil2.become_user(text, integer, integer) is
'See comments for become_accessor().  This is the same but takes a
username rather than accessor_id.';

-- NEW FUNCTIONS
create or replace 
function veil2.have_user_defined_scopes()
  returns boolean as
$$
-- Have we defined new scope_types:
select exists (
  select null
    from veil2.scope_types
   where scope_type_id not in (1, 2));
$$
language sql security definer stable;


create or replace
function veil2.have_accessor_contexts()
  returns boolean as
$$
-- Does the accessor_contexts view exist?
select exists (
  select null
    from pg_catalog.pg_class c
   inner join pg_catalog.pg_namespace n
      on n.oid = c.relnamespace
   where n.nspname = 'veil2'
     and c.relname = 'accessor_contexts'
     and c.relkind = 'v');
$$
language sql security definer stable;

create or replace
function veil2.have_accessor_contexts_comment()
  returns boolean as
$$
-- Does the accessor_contexts view exist?
select pg_catalog.obj_description(c.oid) is not null
  from pg_catalog.pg_class c
 inner join pg_catalog.pg_namespace n
    on n.oid = c.relnamespace
 where n.nspname = 'veil2'
   and c.relname = 'accessor_contexts'
   and c.relkind = 'v';
$$
language sql security definer stable;


create or replace
function veil2.define_accessor_contexts()
  returns void as
$$
begin
  if not veil2.have_accessor_contexts() then
    execute('create view veil2.accessor_contexts (
                 accessor_id, context_type_id, context_id
             ) as
	       select accessor_id, 1, 0
	         from veil2.accessors');
  end if;
  if not veil2.have_accessor_contexts_comment() then
    execute($__$
   comment on view veil2.accessor_contexts is
'This view lists the allowed session contexts for accessors.  When an
accessor opens a session, they choose a session context.  This session
context determines which set of role->role mappings are in play.
Typically, there will only be one such set, as provided by the default
implementation of this view.  If however, your application requires
separate contexts to have different role->role mappings, you should
modify this view to map your accessors with that context.

Typically this will be used in a situation where your application
serves a number of different clients, each of which have their own
role definitions.  Each accessor will belong to one of those clients
and this view should be modified to make that mapping apparent.

A typical view definition might be:
  select party_id, 3, client_id
    from app_schema.parties
   union all 
  select party_id, 1, 0
    from mycorp_schema.superusers;

which would allow those defined in the superusers table to connect in
the global context, and those defined in the parties table to connect
in the context of the client that they work for.'
$__$);
  end if;
end;
$$
language plpgsql security definer volatile;

comment on function veil2.define_accessor_contexts() is
'Creates, a dummy version of the accessor_contexts view if it has not
already been defined.  Also creates a comment for the view if there is
not already one in place.  This exists to create and comment the view
which an implementor is supposed to replace.  The view is not created
as part of the extension as this would make it too difficult to
modify.'; 


create or replace
function veil2.accessor_contexts_is_original()
  returns boolean as
$$
select pg_catalog.pg_get_viewdef(cn.oid) =
           pg_catalog.pg_get_viewdef(ct.oid)
  from pg_catalog.pg_class cn  -- Class for New view
 inner join pg_catalog.pg_namespace n
    on n.oid = cn.relnamespace
 inner join pg_catalog.pg_class ct -- Class for Template view
    on n.oid = ct.relnamespace
 where n.nspname = 'veil2'
   and cn.relname = 'accessor_contexts'
   and cn.relkind = 'v'
   and ct.relname = 'accessor_contexts_template'
   and ct.relkind = 'v';
$$
language sql security definer volatile;

create or replace
function veil2.get_accessor_defined()
  returns boolean as
$$
select exists (
  select null
    from pg_proc p
   inner join pg_catalog.pg_namespace n
      on n.oid = p.pronamespace
   where p.proname = 'get_accessor'
     and n.nspname = 'veil2');
$$
language sql security definer volatile;


create or replace
function veil2.have_user_privileges()
  returns boolean as
$$
select exists (
  select null
    from veil2.privileges
   where privilege_id > 15
      or privilege_id < 0);
$$
language sql security definer volatile;


create or replace
function veil2.have_user_roles()
  returns boolean as
$$
select exists (
  select null
    from veil2.roles
   where role_id > 4
      or role_id < 0);
$$
language sql security definer volatile;


create or replace
function veil2.have_role_privileges()
  returns boolean as
$$
select exists (
  select null
    from veil2.role_privileges
   where role_id < 0
      or role_id > 4);
$$
language sql security definer volatile;

create or replace
function veil2.have_role_roles()
  returns boolean as
$$
select exists (
  select null
    from veil2.role_roles);
$$
language sql security definer volatile;

create or replace
function veil2.have_accessors()
  returns boolean as
$$
select exists (
  select null
    from veil2.accessors);
$$
language sql security definer volatile;


create or replace
function veil2.have_user_scopes ()
  returns boolean as
$$
select exists (
  select null
    from veil2.scopes
   where scope_type_id != 1
     and scope_id != 0);
$$
language sql security definer volatile;


create or replace
function veil2.scope_promotions_is_original()
  returns boolean as
$$
select pg_catalog.pg_get_viewdef(cn.oid) =
           pg_catalog.pg_get_viewdef(ct.oid)
  from pg_catalog.pg_class cn  -- Class for New view
 inner join pg_catalog.pg_namespace n
    on n.oid = cn.relnamespace
 inner join pg_catalog.pg_class ct -- Class for Template view
    on n.oid = ct.relnamespace
 where n.nspname = 'veil2'
   and cn.relname = 'scope_promotions'
   and cn.relkind = 'v'
   and ct.relname = 'scope_promotions_template'
   and ct.relkind = 'v';
$$
language sql security definer volatile;

create or replace
function veil2.check_table_security()
  returns setof text as
$$
declare
  tbl text;
  header_returned boolean := false;
begin
  for tbl in
    select n.nspname || '.' || c.relname
      from pg_catalog.pg_class c
     inner join pg_catalog.pg_namespace n
        on n.oid = c.relnamespace
     where c.relkind = 'r'
       and n.nspname not in ('pg_catalog', 'information_schema')
       and c.relpersistence = 'p'
       and not relrowsecurity
  loop
    if not header_returned then
      header_returned := true;
      return next 'The following tables have no security policies:';
    end if;
    return next '    - ' || tbl;
  end loop;
  if not header_returned then
    return next 'All tables appear to have security policies:';
  end if;  
end;
$$
language plpgsql security definer stable;


create or replace
function veil2.my_status()
  returns setof text as
$$
declare
  ok boolean := true;
  line text;
begin
  if not veil2.have_user_defined_scopes() then
    ok := false;
    return next 'You need to define some relational scopes (step 2)';
  end if;
  perform veil2.define_accessor_contexts();
  if veil2.accessor_contexts_is_original() then
    ok := false;
    return next 'You need to redefine the accessor_contexts view (step 3)';
  end if;
  if not veil2.get_accessor_defined() then
    ok := false;
    return next 'You need to define a get_accessor() function (step 3)';
  end if;
  if not veil2.have_user_privileges() then
    ok := false;
    return next 'You need to define some privileges (step 4)';
  end if;
  if not veil2.have_user_roles() then
    ok := false;
    return next 'You need to define some roles (step 5)';
  end if;
  if not veil2.have_role_privileges() then
    ok := false;
    return next 'You need to create entries in role_privileges (step 5)';
  end if;
  if not veil2.have_role_roles() then
    ok := false;
    return next 'You need to create entries in role_roles (step 5)';
  end if;
  if not veil2.have_accessors() then
    ok := false;
    return next 'You need to create accessors (and maybe FK links) (step 6)';
  end if;
  if not veil2.have_user_scopes() then
    ok := false;
    return next 'You need to create user scopes (step 7)';
  end if;
  if veil2.scope_promotions_is_original() then
    ok := false;
    return next 'You need to redefine the scope_promotions view (step 8)';
  else
    execute('refresh materialized view veil2.all_scope_promotions');
  end if;
  if ok then
    return next 'Your Veil2 basic implemementation seems to be complete.';
  end if;
  for line in select * from veil2.check_table_security()
  loop
    return next line;
  end loop;
  if ok then
    return next 'Have you secured your views?.';
  end if;
end;
$$
language plpgsql security definer volatile;



-- END NEW FUNCTIONS

-- Create base meta-data for veil2 schema

insert into veil2.scope_types
       (scope_type_id, scope_type_name, description)
values (1, 'global context',
        'Assignments made in the global context apply globally: that is ' ||
	'there are no limitions based on data ownership applied to ' ||
	'these assignments'),
       (2, 'personal context',
        'Privileges assigned in personal context apply to the personal ' ||
        'data of the user.  If they have the ''select_parties'' ' ||
	'privilege assigned only in personal context, they will be ' ||
	'able to see only their own party record.  All parties are ' || 
	'expected to have the same rights to their own data, so we ' ||
        'do not explicitly assign rights in personal context, instead ' ||
	'we assume that the ''personal_context'' role has been ' ||
	'assigned to every party.  This role is special in that it ' ||
	'should not be assigned in any other context, and so ' ||
       	'is defined as not enabled.');

insert into veil2.scopes
       (scope_type_id, scope_id)
values (1, 0);

insert into veil2.authentication_types
       (shortname, enabled,
        description, authent_fn)
values ('bcrypt', true,
        'Bcrypted password from the user.', 'veil2.authenticate_bcrypt'),
       ('plaintext', false,
        'Plaintext password - enable for development only',
	'veil2.authenticate_plaintext'),
       ('dedicated', false,
        'Dedicated Session.  Authentication by database session username',
        'veil2.authenticate_false'),
       ('become', false,
        'From become_user.  Session supplemental identifies the originating session',
       'veil2.authenticate_false'),
       ('oath2', false,  -- Placeholder.  An exercise for the reader
        'Openid authentication.', 'veil2.authenticate_false');

insert into veil2.privileges
       (privilege_id, privilege_name,
        promotion_scope_type_id, description)
values (0, 'connect', 1,
        'May connect to the database to execute queries.'),
       (1, 'become user', null,
        'May execute the become_user function.  This should only ' ||
	'be available to superusers'),
       (2, 'select scope_types', 1,
        'May select from scope_types.'),
       (3, 'select scopes', null,
        'May select from scopes.'),
       (4, 'select privileges', 1,
        'May select from privileges.'),
       (5, 'select role_types', 1,
        'May select from role_types.'),
       (6, 'select roles', 1,
        'May select from roles.'),
       (7, 'select context_roles', null,
        'May select from context_roles.'),
       (8, 'select role_privileges', 1,
        'May select from role_privileges.'),
       (9, 'select role_roles', null,
        'May select from role_roles.'),
       (10, 'select accessors', null,
        'May select from accessors.'),
       (11, 'select authentication_types', 1,
        'May select from authentication_types.'),
       (12, 'select authentication_details', null,
        'May select from authentication_details.'),
       (13, 'select accessor_roles', null,
        'May select from accessor_roles.'),
       (14, 'select sessions', null,
        'May select from sessions.'),
       (15, 'select system_parameters', null,
        'May select from system_parameters.');

insert
  into veil2.role_types
       (role_type_id, role_type_name, description)
values (1, 'default', 'A general-purpose, unspecific role type'),
       (2, 'veil2',
        'A Veil2-specific role type, used for access to veil2 data');

insert into veil2.roles
       (role_id, role_name, implicit, immutable, description)
values (0, 'connect', false, true, 'Allow minimal access to the system.'),
       (1, 'superuser', false, true, 'An all-encompassing role.'),
       (2, 'personal_context', true, true,
        'An implicitly assigned, to all users, role that allows ' ||
	'access to a user''s own information'),
       (3, 'visitor', true, false,
        'Default role for unauthenticated visitors');

-- Veil-specific roles
insert
  into veil2.roles
       (role_id, role_type_id, role_name, implicit, immutable, description)
values (4, 2, 'veil2_viewer', false, true,
        'Allow read-access to veil data');
	
-- Set up basic access rights.
insert into veil2.role_privileges
       (role_id, privilege_id)
values (0, 0),
       (2, 10)  -- personal_context gives select to accessors table
       ;

-- Set up veil2_viewer rights
insert into veil2.role_privileges
       (role_id, privilege_id)
values (4, 2),
       (4, 3),
       (4, 4),
       (4, 5),
       (4, 6),
       (4, 7),
       (4, 8),
       (4, 9),
       (4, 10),
       (4, 11),
       (4, 12),
       (4, 13),
       (4, 14),
       (4, 15);


-- system parameters
insert into veil2.system_parameters
       (parameter_name, parameter_value)
values ('shared session timeout', '20 mins'),
       ('mapping context target scope type', '1');


-- Create security for vpd tables.
-- This consists of enabling row-level security and only allowing
-- select access to users with the approrpiate veil privileges.

\echo ......scope_types...
alter table veil2.scope_types enable row level security;

-- Prevent modifications to scope_types - the database owner
-- should be the only user doing this.
create policy scope_type__select
    on veil2.scope_types
   for select
 using (veil2.i_have_global_priv(2));


\echo ......scopes...
alter table veil2.scopes enable row level security;

create policy scope__select
    on veil2.scopes
   for select
 using (   veil2.i_have_global_priv(3)
        or veil2.i_have_priv_in_scope(3, scope_type_id, scope_id));

comment on policy scope__select on veil2.scopes is
'Require privilege ''select scopes'' in global scope
(assigned in global context), in order to see the data in this table.';


\echo ......privileges...
alter table veil2.privileges enable row level security;

create policy privilege__select
    on veil2.privileges
   for select
 using (veil2.i_have_global_priv(4));

comment on policy privilege__select on veil2.privileges is
'Require privilege ''select privilege'' in global scope
(assigned in global context), in order to see the data in this table.';


\echo ......role_types...
alter table veil2.role_types enable row level security;

create policy role_type__select
    on veil2.role_types
   for select
 using (veil2.i_have_global_priv(5));

comment on policy role_type__select on veil2.role_types is
'Require privilege ''select role_type'' in global scope
(assigned in global context), in order to see the data in this table.';


\echo ......roles...
alter table veil2.roles enable row level security;

create policy role__select
    on veil2.roles
   for select
 using (veil2.i_have_global_priv(6));

comment on policy role__select on veil2.roles is
'Require privilege ''select roles'' in global scope
(assigned in global context), in order to see the data in this table.';


\echo ......context_roles...
alter table veil2.context_roles enable row level security;

-- We should be able to view this if we have select_context_role
-- privilege in a suitable scope.
create policy context_role__select
    on veil2.context_roles
   for select
 using (   veil2.i_have_global_priv(7)
        or veil2.i_have_priv_in_scope(7, context_type_id, context_id)
        or veil2.i_have_priv_in_superior_scope(7, context_type_id, context_id)
       );

comment on policy context_role__select on veil2.context_roles is
'Require privilege ''select context_roles'' in an appropriate scope in
order to see the data in this table.';


\echo ......role_privileges...
alter table veil2.role_privileges enable row level security;

-- We should be able to view this if we have select_role_privilege
-- privilege in a suitable scope.
create policy role_privilege__select
    on veil2.role_privileges
   for select
 using (veil2.i_have_global_priv(8));

comment on policy role_privilege__select on veil2.role_privileges is
'Require privilege ''select role_privileges'' in global scope
(assigned in global context), in order to see the data in this table.';


\echo ......role_roles...
alter table veil2.role_roles enable row level security;

-- We should be able to view this if we have select_role_role
-- privilege in a suitable scope.
create policy role_role__select
    on veil2.role_roles
 using (   veil2.i_have_global_priv(9)
        or veil2.i_have_priv_in_scope(9, context_type_id, context_id)
        or veil2.i_have_priv_in_superior_scope(9, context_type_id, context_id)
       );

comment on policy role_role__select on veil2.role_roles is
'Require privilege ''select role_roles'' in an appropriate scope in
order to see the data in this table.';


\echo ......accessors...
alter table veil2.accessors enable row level security;

-- We should be able to view this if we have select_accessor
-- privilege in a suitable scope.
create policy accessor__select
    on veil2.accessors
   for select
 using (   veil2.i_have_global_priv(10)
        or veil2.i_have_personal_priv(10, accessor_id));

comment on policy accessor__select on veil2.accessors is
'Require privilege ''select accessors'' in global scope
(assigned in global context) or personal scope, in order to see the data
in this table.'; 


\echo ......authentication_types...
alter table veil2.authentication_types enable row level security;

-- We should be able to view this if we have select_authentication_type
-- privilege in a suitable scope.
create policy authentication_type__select
    on veil2.authentication_types
   for select
 using (veil2.i_have_global_priv(11));

comment on policy authentication_type__select on veil2.authentication_types is
'Require privilege ''select authentication_types'' in global scope
(assigned in global context) in order to see the data in this table.'; 


\echo ......authentication_details...
alter table veil2.authentication_details enable row level security;

-- We should be able to view this if we have select_authentication_detail
-- privilege in a suitable scope.
create policy authentication_detail__select
    on veil2.authentication_details
   for select
 using (veil2.i_have_global_priv(12));

comment on policy authentication_detail__select
  on veil2.authentication_details is
'Require privilege ''select authentication_details'' in global scope
(assigned in global context) in order to see the data in this table.'; 


\echo ......accessor_roles...
alter table veil2.accessor_roles enable row level security;

-- We should be able to view this if we have select_accessor_role
-- privilege in a suitable scope.
create policy accessor_role__select
    on veil2.accessor_roles
   for select
 using (veil2.i_have_global_priv(13)
        or veil2.i_have_priv_in_scope(13, context_type_id, context_id));

comment on policy accessor_role__select on veil2.accessor_roles is
'Require privilege ''select accessor_roles'' in global scope
(assigned in global context) in order to see the data in this table.'; 


\echo ......sessions...
alter table veil2.sessions enable row level security;

-- We should be able to view this if we have select_session
-- privilege in a suitable scope.
create policy session__select
    on veil2.sessions
   for select
 using (veil2.i_have_global_priv(14));

comment on policy session__select on veil2.sessions is
'Require privilege ''select sessions'' in global scope
(assigned in global context) or personal scope, in order to see the data
in this table.'; 


\echo ......system_parameters...
alter table veil2.system_parameters enable row level security;

-- We should be able to view this if we have select_system_parameter
-- privilege in a suitable scope.
create policy system_parameter__select
    on veil2.system_parameters
   for select
 using (veil2.i_have_global_priv(15));

comment on policy system_parameter__select on veil2.system_parameters is
'Require privilege ''select system_parameters'' in global scope
(assigned in global context) in order to see the data in this table.'; 


-- Deal with tables that implementors and administrators are expected
-- to update.

\echo ...handling for user-defined data in pg_dump...
\echo ......scope_types...
select pg_catalog.pg_extension_config_dump(
           'veil2.scope_types',
	   'where not scope_type_id in (1,2)');


\echo ......system_parameters...
create or replace
function veil2.system_parameters_check()
  returns trigger
as
$$
begin
  if tg_op = 'INSERT' then
    -- Check that the insert will not result in a key collision.  If
    -- it will, do an update instead.  The insert may come from a
    -- backup from pg_dump which is why we have to handle it like
    -- this.
    if exists (
        select null
	  from veil2.system_parameters
	 where parameter_name = new.parameter_name)
    then
      update veil2.system_parameters
         set parameter_value = new.parameter_value
       where parameter_name = new.parameter_name;
      return null;
    end if;
  end if;
  new.user_defined := true;
  return new;
end;
$$
language 'plpgsql' security definer volatile leakproof;

comment on function veil2.system_parameters_check() is
'Trigger function to allow pg_dump to dump and restore user-defined
system parameters, and to ensure all inserted and updated rows are
identfied as user_defined.';

create trigger system_parameters_biu before insert or update
  on veil2.system_parameters
  for each row execute function veil2.system_parameters_check();

select pg_catalog.pg_extension_config_dump(
           'veil2.system_parameters',
	   'where user_defined');


\echo ......authentication_types...
create or replace
function veil2.make_user_defined()
  returns trigger
as
$$
begin
  if tg_op = 'INSERT' then
    -- Check that the insert will not result in a key collision.  If
    -- it will, do an update instead.  The insert may come from a
    -- backup from pg_dump which is why we have to handle it like
    -- this.
    if exists (
        select null
	  from veil2.authentication_types
	 where shortname = new.shortname)
    then
      update veil2.authentication_types
         set enabled = new.enabled,
	     description = new.description,
	     authent_fn = new.authent_fn,
	     supplemental_fn = new.supplemental_fn
       where shortname = new.shortname;
      return null;
    end if;
  end if;
  new.user_defined := true;
  return new;
end;
$$
language 'plpgsql' security definer volatile leakproof;

create trigger authentication_types_biu before insert or update
  on veil2.authentication_types
  for each row execute function veil2.make_user_defined();

select pg_catalog.pg_extension_config_dump(
           'veil2.authentication_types',
	   'where user_defined');


\echo ......privileges...
select pg_catalog.pg_extension_config_dump(
           'veil2.privileges',
	   'where privilege_id > 15
               or privilege_id < 0');


\echo ......roles...
select pg_catalog.pg_extension_config_dump(
           'veil2.roles',
	   'where role_id > 4
               or role_id < 0');

\echo ......role_privileges...
select pg_catalog.pg_extension_config_dump(
           'veil2.role_privileges',
	   'where role_id > 4
               or role_id < 0');

\echo ......role_roles...
select pg_catalog.pg_extension_config_dump(
           'veil2.role_roles', '');


\echo ......scopes...
select pg_catalog.pg_extension_config_dump(
           'veil2.scopes', 
	   'where scope_type_id != 1
	       or scope_id != 0');


\echo ......accessors...
select pg_catalog.pg_extension_config_dump(
           'veil2.accessors', '');


\echo ......authentication_details...
select pg_catalog.pg_extension_config_dump(
           'veil2.authentication_details', '');
