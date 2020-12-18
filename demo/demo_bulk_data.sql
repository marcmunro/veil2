\echo Creating  dataset for performance testing...

grant execute on function veil2.result_counts() to demouser;

begin; 
\echo ...parties...
-- Close to 10,000 parties
with new_ids as
  (
    select id
      from (
        select generate_series as id
          from generate_series(1001, 9999)) x
     where id % 10 != 0
  ),
orgs as
  (
    select corp_id, org_id, row_number() over() as rownum
      from (
        select distinct corp_id, org_id
          from demo.parties_tbl) x
  )
insert
  into demo.parties_tbl
      (party_id, party_type_id, corp_id,
       org_id, party_name, password)
select n.id, 1, o.corp_id,
       o.org_id, 'party_' || n.id, 'passwd_' || n.id
  from (
    select n.id, floor(random() * 6) + 1 as rownum
      from new_ids n) n
 inner join orgs o
    on o.rownum = n.rownum;

\echo ...privileges...
-- Close to 2000 privileges, approx 10% of which promote
insert
  into veil2.privileges
      (privilege_id, privilege_name,
       promotion_scope_type_id,
       description)
select generate_series, 'priv ' || generate_series,
       case floor(random() * 40)
       when 1 then 1
       when 2 then 2
       when 3 then 3
       when 4 then 4
       else null end,
       'Long text to make the table larger than it would otherwise be'
  from generate_series(30, 2000);

\echo ...function-level roles...
-- Around 200 function-level roles, each with random privileges
insert
  into veil2.roles
      (role_id, role_type_id,
       role_name, implicit,
       immutable, description)
select generate_series, 3,
       'role_' || generate_series, false,
       true, 'Long text to make the table larger than it would otherwise be'
  from generate_series(20, 200);

-- Random role_privs assignments
insert
  into veil2.role_privileges
      (role_id, privilege_id)
select distinct floor(random() * 180) + 20,
       floor(random() * 1970) + 30
  from generate_series(1, 2000);

\echo ...user-level roles...
-- Around 100 user-level roles, each with ~ 5 random roles

insert
  into veil2.roles
      (role_id, role_type_id,
       role_name, implicit,
       immutable, description)
select generate_series, 3,
       'role_' || generate_series, false,
       false, 'Long text to make the table larger than it would otherwise be'
  from generate_series(201, 300);

with contexts as
  (
    select 1 as rownum, 1 as context_type_id, 0 as context_id
    union
    values (2, 3, 1010),
           (3, 3, 1020)
  )
insert
  into veil2.role_roles
      (primary_role_id, assigned_role_id,
       context_type_id, context_id)
select distinct
       floor(random() * 100) + 101,
       floor(random() * 180) + 20,
       c.context_type_id,
       c.context_id
  from (
    select floor(random() * 3) + 1 as rownum
      from generate_series(1,500)) n
 inner join contexts c
    on c.rownum = n.rownum;
 

-- assign the various roles to our accessors
\echo ...accessor_roles...
-- Give each accessor an average of 5 roles.
with contexts as
  (
    select 1 as rownum, 1 as context_type_id, 0 as context_id
    union
    values (2, 3, 1010),
           (3, 3, 1020)
  )
insert
  into veil2.accessor_roles
      (accessor_id, role_id,
       context_type_id, context_id)
select distinct
       a.accessor_id, a.role_id,
       c.context_type_id, c.context_id
  from (
    select floor(random() * 8999)::integer + 1001 as accessor_id,
           floor(random() * 100) + 201 as role_id,
	   floor(random() * 3) + 1 as rownum
      from generate_series(1, 50000)) a
 inner join contexts c
    on c.rownum = a.rownum
 where a.accessor_id % 10 != 0;

\echo ...projects...
-- Let's create 50 projects

with orgs as
  (
    select corp_id, org_id, row_number() over() as rownum
      from (
        select distinct corp_id, org_id
          from demo.parties_tbl) x
  )
insert
  into demo.projects
      (project_id, corp_id, org_id, project_name)
select n.id, o.corp_id,
       o.org_id, 'project_' || n.id
  from (
    select generate_series as id, floor(random() * 6) + 1 as rownum
      from generate_series(3, 52)) n
 inner join orgs o
    on o.rownum = n.rownum;

\echo ...project_assignments...
-- Let's have 300 project assignments

insert
  into demo.project_assignments
      (project_id, party_id, role_id)
select distinct *
  from (
    select floor(random() * 50)::integer + 3 as project_id,
           floor(random() * 8999)::integer + 1000 as party_id,
	   floor(random() * 100)::integer + 200 as role_id
      from generate_series(1, 330)) n
 where party_id % 10 != 0;
       

commit;
