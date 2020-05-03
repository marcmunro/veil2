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


