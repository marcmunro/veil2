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
grant all on veil2.scope_types to demouser;


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
controls are placed in project scopes, there will be one scopes
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
'This, in conjunction with the scope_type_id fully identifies a scope
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
must apply in a superior scope (ie as if they has been assigned in a
superior context).

For example a hypothetical ''select lookup'' privilege may be assigned
in a team context (via a hypothetical ''team member'' role).  But if the
lookups table is not in any way team-specific it makes no sense to apply
that privilege in that scope.  Instead, we will promote that privilege
to a scope where it does make sense.  See the veil docs for more on
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
for determining access rights.  Idealy this will be the id of the user
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
  supplemental_fn		text
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
to it must be as thoroughly locked down as possibe.';

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
    parameter_value		text not null
);

alter table veil2.system_parameters add constraint system_parameter__pk
  primary key(parameter_name);

comment on table veil2.system_parameters is
'Provides values for various parameters.';

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
