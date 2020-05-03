/* ----------
 * veil2.sql
 *
 *      Create veil2 schema and contents.
 *
 *      Copyright (c) 2020 Marc Munro
 *      Author:  Marc Munro
 *	License: GPL V3
 *
 * ----------
 */


-- Create the Veil2 schema



\echo ...veil2 roles...
create role veil_user;
comment on role veil_user is
'This role will have read access to all veil2 tables.  That is not to
say that an assignee of the role will be able to see the data in those
tables, but that they will be allowed to try.  If, in addition to this
role, they are (in veil2 terms) an accessor and have been assigned (in
veil2 terms) the veil2_user role, they will be able to see all veil2
relations and their contents.'; 

\echo ...veil2 schema...
create schema veil2;

comment on schema veil2 is
'Schema into which veil2 database objects will be placed.';

-- Limit access to the vpd schema
revoke all on schema veil2 from public;
grant usage on schema veil2 to veil_user;


\echo ...creating veil2 tables...
\i sql/veil2/tables.sql

\echo ...creating veil2 views...
\i sql/veil2/views.sql

\i sql/veil2/functions.sql

\echo ...setting up veil2 base data...
\i sql/veil2/data.sql

\echo ...setting up veil2 security policies...
\i sql/veil2/security.sql
