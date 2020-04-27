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
       bitmap_of(case when p.promotion_context_type_id = 1
       		 then p.privilege_id else null end),
       bitmap_of(case
                 when p.promotion_context_type_id is null then null
                 when p.promotion_context_type_id = 1 then null
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
           context_type_id, context_id
      from veil2.role_roles
     union all
    select rr.primary_role_id, ar.assigned_role_id,
           rr.context_type_id, rr.context_id
      from veil2.role_roles rr
     inner join assigned_roles ar
             on ar.primary_role_id = rr.assigned_role_id
	    and (   ar.context_type_id = 1
	         or (    ar.context_type_id = rr.context_type_id
	             and ar.context_id = rr.context_id))
     where rr.primary_role_id != ar.assigned_role_id -- avoid loops
  ),
  all_assigned_roles (
    primary_role_id, assigned_role_id,
    context_type_id, context_id) as
  (
    -- to above query, add assignment of each role to itself
    select primary_role_id, assigned_role_id,
           context_type_id, context_id
      from assigned_roles
     union all
    select role_id, role_id, 1, 0
      from veil2.roles
  ),
  assigned_role_privs (
    primary_role_id, assigned_role_id,
    privileges, global_privileges,
    promotable_privileges, context_type_id,
    context_id) as
  (
    select aar.primary_role_id, aar.assigned_role_id,
    	   drp.privileges, drp.global_privileges,
	   drp.promotable_privileges, aar.context_type_id,
	   aar.context_id
      from all_assigned_roles aar
     inner join veil2.direct_role_privileges drp
        on drp.role_id = aar.assigned_role_id
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
  from assigned_role_privs
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
 inner join veil2.direct_role_privileges drp
    on drp.role_id = arr.primary_role_id
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
 inner join veil2.direct_role_privileges_vv drp
    on drp.role_id = arr.primary_role_id
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


\echo ......context_promotions...
create or replace
view veil2.context_promotions (
  context_type_id, context_id,
  promoted_context_type_id, promoted_context_id
) as
select null::integer, null::integer,
       null::integer, null::integer
where false;

comment on view veil2.context_promotions is
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
view veil2.context_promotions (
  context_type_id, context_id,
  promoted_context_type_id, promoted_context_id
) as
select 96, -- dept context type id
       department_id,
       95, -- corp context type id
       corp_id
  from departments;

Note that any multi-level context promotions will be handled by
veil2.all_context_promotions which you should have no need to modify.';

revoke all on veil2.context_promotions from public;
grant select on veil2.context_promotions to veil_user;


\echo ......all_context_promotions...
create or replace
view veil2.all_context_promotions_v (
  context_type_id, context_id,
  promoted_context_type_id, promoted_context_id
) as
with recursive recursive_context_promotions as
  (
    select context_type_id, context_id,
           promoted_context_type_id, promoted_context_id
      from veil2.context_promotions
     union all
    select cp.context_type_id, cp.context_id,
           rcp.promoted_context_type_id, rcp.promoted_context_id
      from veil2.context_promotions cp
     inner join recursive_context_promotions rcp
        on rcp.context_type_id = cp.promoted_context_type_id
       and rcp.context_id = cp.promoted_context_id
  )
select *
  from recursive_context_promotions;

comment on view veil2.all_context_promotions_v is
'This takes the simple custom view veil2.context_promotions and makes it
recursive so that if context a contains context b and context b contains
context c, then this view will return rows for context c promoting to
both context b and context a.  You should not need to modify this view
when creating your custom VPD implementation.';

create or replace
view veil2.all_context_promotions_vv as
select * from veil2.all_context_promotions_v;

comment on view veil2.all_context_promotions_vv is
'Exactly as veil2.all_context_promotions_v.  The _vv suffix indicates
that this is a true view, not relying on any materialized views.';

create 
materialized view veil2.all_context_promotions
as select * from veil2.all_context_promotions_v;

comment on materialized view veil2.all_context_promotions is
'This takes the simple custom view veil2.context_promotions and makes it
recursive so that if context a contains context b and context b contains
context c, then this view will return rows for context c promoting to
both context b and context a.  You should not need to modify this view
when creating your custom VPD implementation.';

revoke all on veil2.all_context_promotions from public;
grant select on veil2.all_context_promotions to veil_user;
revoke all on veil2.all_context_promotions_v from public;
grant select on veil2.all_context_promotions_v to veil_user;
revoke all on veil2.all_context_promotions_vv from public;
grant select on veil2.all_context_promotions_vv to veil_user;


\echo ......context_tree...
create or replace
view veil2.context_tree (context_tree) as
with recursive
  top_contexts as
  (
    select distinct
           promoted_context_id root_context_id,
	   promoted_context_type_id root_context_type_id
      from veil2.context_promotions
     where promoted_context_id not in (
        select context_id
	  from veil2.context_promotions)
  ),
  recursive_context_tree as
  (    
    select 1 as depth, 
           '(' || cp.promoted_context_id::text || '.' ||
	   cp.context_id || ').(' || cp.promoted_context_type_id ||
	   '.' || cp.context_type_id || ')' as path,
           cp.promoted_context_id, cp.context_id,
	   cp.promoted_context_type_id, cp.context_type_id
      from top_contexts tc
     inner join veil2.context_promotions cp
        on cp.promoted_context_id = tc.root_context_id
       and cp.promoted_context_type_id = tc.root_context_type_id
     union all
    select depth + 1, 
    	   rct.path || '(' || cp.promoted_context_id ||
	   '.' || cp.context_id || ')',
           cp.promoted_context_id, cp.context_id,
	   cp.promoted_context_type_id, cp.context_type_id
      from recursive_context_tree rct
     inner join veil2.context_promotions cp
        on cp.promoted_context_id = rct.context_id
       and cp.promoted_context_type_id = rct.context_type_id
  ),
  format1 as
  (
    select sct1.context_type_name || ':' ||
    	    promoted_context_id::text as parent,
           sct2.context_type_name || ':' || context_id::text as child,
	   depth
      from recursive_context_tree rct
     inner join veil2.security_context_types sct1
        on sct1.context_type_id = rct.promoted_context_type_id
     inner join veil2.security_context_types sct2
        on sct2.context_type_id = rct.context_type_id
    order by path
  )
select format('%' || ((depth)*16 - 14) || 's', '+-') ||
       substr('------------', length(parent)) || parent ||
       '-+' || substr('-------------', length(child)) ||
       child 
  from format1;

comment on view veil2.context_tree is
'Provides a simple ascii-formatted tree representation of our context
promotions tree.  This is simply an aid to data visualisation and is not
used elsewhere in Veil2.';

revoke all on veil2.context_tree from public;
grant select on veil2.context_tree to veil_user;


\echo ......promotable_privileges...
create view veil2.promotable_privileges(
  context_type_id, privilege_ids)
as
select sct.context_type_id, bitmap_of(p.privilege_id)
  from veil2.security_context_types sct
 inner join veil2.privileges p
    on p.promotion_context_type_id = sct.context_type_id
group by sct.context_type_id;

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


\echo ......all_accessor_privs...
create or replace
view veil2.all_accessor_privs_v (
  accessor_id, context_type_id, context_id, roles, privs)
as
with direct_privs(
    accessor_id, context_type_id,
    context_id, roles, privs,
    global_privs, promotable_privs) as
  (
    -- Identfies all accessor roles and privs in all contexts, without
    -- privilege promotion.
    select aar.accessor_id, aar.context_type_id,
           aar.context_id, union_of(arp.roles),
	   union_of(arp.privileges), union_of(arp.global_privileges),
	   union_of(arp.promotable_privileges)
      from veil2.all_accessor_roles aar
     inner join veil2.all_role_privs arp
        on arp.role_id = aar.role_id
           -- Match on both context-specific role mapping and global mapping.
       and (  (     arp.context_type_id = aar.context_type_id
                and arp.context_id = aar.context_id)
	    or (    arp.context_type_id = 1
	        and arp.context_id = 0))
     group by aar.accessor_id, aar.context_type_id, aar.context_id
  ),
promotable_privs as
  (
    select dp.accessor_id, dp.context_type_id, dp.context_id,
           bits(dp.promotable_privs) as privilege_id
      from direct_privs dp
     where promotable_privs is not null
  ),
promoted_privs as
  (
    select pp.accessor_id, acp.promoted_context_type_id,
           acp.promoted_context_id,
	   bitmap_of(pp.privilege_id) as promoted_privs
      from promotable_privs pp
     inner join veil2.privileges p
        on p.privilege_id = pp.privilege_id
     inner join veil2.all_context_promotions acp
       on acp.context_type_id = pp.context_type_id
      and acp.context_id = pp.context_id
      and acp.promoted_context_type_id = p.promotion_context_type_id
      group by pp.accessor_id, acp.promoted_context_type_id,
               acp.promoted_context_id
  ),
all_context_privs as
  (
    select accessor_id, context_type_id,
           context_id, roles, privs,
	   'direct' as source
      from direct_privs
     union all
    select accessor_id, 1, 0,
    	   case when context_type_id = 1 then roles else null end,
           global_privs, 'global'
      from direct_privs
     union all
    select accessor_id, promoted_context_type_id,
           promoted_context_id, null, promoted_privs,
	   'promoted'
      from promoted_privs
  )
select accessor_id, context_type_id,
       context_id, union_of(roles),
       union_of(privs)
  from all_context_privs
 group by accessor_id, context_type_id,
          context_id;

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


\echo ...refresh_context_promotions()...
create or replace
function veil2.refresh_context_promotions()
  returns trigger
as
$$
begin
  refresh materialized view veil2.all_context_promotions;
  refresh materialized view veil2.all_accessor_privs;
  return new;
end;
$$
language 'plpgsql' security definer volatile leakproof;

comment on function veil2.refresh_context_promotions() is
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


\echo ......on security_contexts...
create trigger security_contexts__aiudt
  after insert or update or delete or truncate
  on veil2.security_contexts
  for each statement
  execute procedure veil2.refresh_context_promotions();

comment on trigger security_contexts__aiudt on veil2.security_contexts is
'Refresh materialized views that are constructed from the
security_contexts table.

VPD Implementation Notes:
Although we expect that security_contexts will be modified relatively
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


