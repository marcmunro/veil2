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
arising from role to role assignments';

create or replace
view veil2.direct_role_privileges_vv as
select * from veil2.direct_role_privileges_v;

comment on view veil2.direct_role_privileges_v is
'Exactly as veil2.direct_role_privileges_v.  The _vv suffix indicates
that this is a true view, not relying on any materialized views.
As it happens, direct_role_privileges_v also does not rely on any
materialized views, so this view exists only to be consistent with other
such sets of views.';

create 
materialized view veil2.direct_role_privileges
as select * from veil2.direct_role_privileges_v;

comment on materialized view veil2.direct_role_privileges is
'Returns all privileges, along with some basic privilege promotion data,
 that are assigned directly to each role, including the implied
 privileges for the superuser role.  This does not show privileges
 arising from role to role assignments';

revoke all on veil2.direct_role_privileges from public;
grant select on veil2.direct_role_privileges to veil_user;
revoke all on veil2.direct_role_privileges_v from public;
grant select on veil2.direct_role_privileges_v to veil_user;
revoke all on veil2.direct_role_privileges_vv from public;
grant select on veil2.direct_role_privileges_vv to veil_user;


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
 1 - the superuser role is assigned all non-implicit roles except
     connect;
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

create 
materialized view veil2.all_role_privs
as select * from veil2.all_role_privs_v;

comment on materialized view veil2.all_role_privs is
'This is simply the aggregation of all role->role mappings as provided
by veil2.all_role_roles and the role_privileges as provided by
veil2.direct_role_privileges.  See the comments on those views for more
information.';

revoke all on veil2.all_role_privs from public;
grant select on veil2.all_role_privs to veil_user;
revoke all on veil2.all_role_privs_v from public;
grant select on veil2.all_role_privs_v to veil_user;
revoke all on veil2.all_role_privs_vv from public;
grant select on veil2.all_role_privs_vv to veil_user;


\echo ......accessor_contexts...
create or replace
view veil2.accessor_contexts (
  accessor_id, context_type_id, context_id
) as
select accessor_id, 1, 0
  from veil2.accessors;

comment on view veil2.accessor_contexts is
'This view lists the allowed session contexts for accessors.  When an
accessor opens a session, they choose a session context.  This session
context determines which set of role->role mappings are in play.
Typically, there will only be one such set, as provided by the default
implementation of this view.  If however, your application requires
separate contexts to have different role->role mappings, you should
modify this role to map your accessors with that context.

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
in the context of the client that they work for.';


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
'This view lists all possible context promotions.  It is used for
privilege promotion when a role that is assigned in a restricted
security context has privileges that must be applied in a less
restricted context.  Note that promotion to global context is always
possible and is not managed through this view.

VPD Implementation Notes:
If you have restricted contexts which are sub-contexts of less
restricted ones, and you need privilege promotion for privileges
assigned in the restricted context to the less restricted one, you
should redefine this view to show which contexts may be promoted to
which other contexts.  For example if you have a corp context and a dept
context which is a subcontext of it, you would redefine your view
something like this:

create or replace
view veil2.scope_promotions (
  scope_type_id, scope_id,
  promoted_scope_type_id, promoted_scope_id
) as
select 96, -- dept context type id
       department_id,
       95, -- corp context type id
       corp_id
  from departments;

Note that any multi-level context promotions will be handled by
veil2.all_scope_promotions which you should have no need to modify.';

revoke all on veil2.scope_promotions from public;
grant select on veil2.scope_promotions to veil_user;


\echo ......all_scope_promotions...
create or replace
view veil2.all_scope_promotions_v (
  scope_type_id, scope_id,
  promoted_scope_type_id, promoted_scope_id
) as
with recursive recursive_scope_promotions as
  (
    select scope_type_id, scope_id,
           promoted_scope_type_id, promoted_scope_id
      from veil2.scope_promotions
     union all
    select sp.scope_type_id, sp.scope_id,
           rsp.promoted_scope_type_id, rsp.promoted_scope_id
      from veil2.scope_promotions sp
     inner join recursive_scope_promotions rsp
        on rsp.scope_type_id = sp.promoted_scope_type_id
       and rsp.scope_id = sp.promoted_scope_id
  )
select *
  from recursive_scope_promotions;

comment on view veil2.all_scope_promotions_v is
'This takes the simple custom view veil2.scope_promotions and makes it
recursive so that if context a contains scope b and scope b contains
scope c, then this view will return rows for scope c promoting to
both scope b and scope a.  You should not need to modify this view
when creating your custom VPD implementation.';

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
both context b and context a.  You should not need to modify this view
when creating your custom VPD implementation.';

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
promotions tree.  This is simply an aid to data visualisation and is not
used elsewhere in Veil2.';

revoke all on veil2.scope_tree from public;
grant select on veil2.scope_tree to veil_user;


\echo ......promotable_privileges...
create view veil2.promotable_privileges(
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

revoke all on veil2.promotable_privileges from public;
grant select on veil2.promotable_privileges to veil_user;


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

VPD Implementation Notes:
If you have any explicitly assigned roles that are not granted through
accessor_role, you will want to redefine this view.  For example if you
have a project context that is dependent on an accessor being assigned
to a project you might redefine the view as follows:

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

create
materialized view veil2.all_accessor_privs
  as select * from veil2.all_accessor_privs_v;

comment on materialized view veil2.all_accessor_privs is
'Show all roles and privileges assigned to all accessors in all
contexts, excepting the implied personal context.';

revoke all on veil2.all_accessor_privs from public;
grant select on veil2.all_accessor_privs to veil_user;
revoke all on veil2.all_accessor_privs_v from public;
grant select on veil2.all_accessor_privs_v to veil_user;


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
complete way.  Try it, is should immediately make sense.';



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


\echo ......privilege_assignments...
create or replace
view veil2.privilege_assignments as
select aar.accessor_id, rp.privilege_id,
       aar.context_type_id as assigned_context_type_id,
       aar.context_id as assigned_context_id,
       rp.role_id as assigned_role_id,
       rc.assigned_role_id as priv_bearing_role_id,
       rc.id_chain as role_id_mapping,
       rc.name_chain as role_name_mapping,
       rc.context_type_id as mapping_context_type_id,
       rc.context_id as mapping_context_id
  from veil2.role_privileges rp
 inner join veil2.role_chains rc
    on rc.assigned_role_id = rp.role_id
 inner join veil2.all_accessor_roles_plus aar
    on aar.role_id = rc.primary_role_id;

comment on view veil2.privilege_assignments is
'Developer view that shows how accessors get privileges.  It shows the
roles that the user is assigned, and the context in which they are
assigned, as well as the mappings from role to role to privilege which
give that resulting privilege to the accessor.

If you are uncertain how accessor 999 has privilege 333, then simply
run:

select * from veil2.privilege_assignments where accessor_id = 999 and
privilege_id = 333;';


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
views.  Note that this will mean that the materialzed views will not
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
views.  Note that this will mean that the materialzed views will not
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
views.  Note that this will mean that the materialzed views will not
always be up to date, so this is a trade-off that must be evaluated.';

