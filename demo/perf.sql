/* ----------
 * perf.sql
 *
 *      Perform a timed performance test run on the demo database.  
 *
 *	It is assumed that the database has been loaded with
 *	a suitable amount of data.
 *
 *      Copyright (c) 2020 Marc Munro
 *      Author:  Marc Munro
 *	License: GPL V3
 *
 * ----------
 */
\unset ECHO
\set QUIET 1
\pset format unaligned
\pset tuples_only true
\pset pager off

--delete from veil2.sessions;

insert
  into veil2.accessor_roles
      (accessor_id, role_id, context_type_id, context_id)
select 1110, 0, 4, 1020
 where not exists (
     select null
       from veil2.accessor_roles
      where accessor_id = 1110
        and role_id = 0
	and context_id = 1020);
	
-- Allow plaintext authentication for Alice as bcrypt slows everything
-- down.

insert
  into veil2.authentication_details
      (accessor_id, authentication_type, authent_token)
select 1080, 'plaintext', 'passwd1'
 where not exists (
    select null
      from veil2.authentication_details
     where accessor_id = 1080
       and authentication_type = 'plaintext');

\c vpd demouser

create or replace
function reopen_connection(_name text) returns integer as
$$
declare
  _session integer;
  _nonce integer;
  _token text;
  _token2 text;
  _success boolean;
  _errmsg text;
begin
  update perf_sessions
     set next_nonce = next_nonce + 1
   where name = _name
   returning session_id, next_nonce, session_token
        into _session, _nonce, _token;
  _token2 := encode(digest(_token || to_hex(_nonce), 'sha1'), 'base64');

  --raise notice 'Session: %, Nonce: %, Token: %, token2: %', _session, _nonce, _token, _token2;
  select *
    into _success, _errmsg
    from veil2.open_connection(_session, _nonce, _token2);

  if found and _success then
    return _nonce;
  else
    return null;
  end if;
end;
$$
language plpgsql volatile;

-- Record the start time
create temporary table start_time as select current_timestamp;

-- Create our sessions table and start a session for Alice
create temporary table perf_sessions as
  select 'Alice' as name, 1 as next_nonce, *
    from veil2.create_session('Alice', 'plaintext', 4, 1000);

-- Start session for Bob and the others.
insert into perf_sessions
select 'Bob', 1, *
  from veil2.create_session('Bob', 'plaintext', 4, 1010)
union all
select 'Carol', 1, *
  from veil2.create_session('Carol', 'plaintext', 4, 1020)
union all
select 'Eve1', 1, *
  from veil2.create_session('Eve', 'plaintext', 4, 1000, 4, 1010)
union all
select 'Eve2', 1, *
  from veil2.create_session('Eve', 'plaintext', 4, 1000, 4, 1020)
union all
select 'Sue', 1, *
  from veil2.create_session('Sue', 'plaintext', 4, 1050)
union all
select 'Simon', 1, *
  from veil2.create_session('Simon', 'plaintext', 4, 1050);

select 'Creating sessions: elapsed = ' ||
       floor(extract(seconds from current_timestamp -
                     st.current_timestamp) * 1000) ||
       ' milliseconds.'
  from start_time st;

-- Now we open the sessions.  This will mean that we have to load all
-- privileges.

with open_connections as
  (
select veil2.open_connection(ps.session_id, 1, 'passwd1')
  from perf_sessions ps
 where name = 'Alice'
union all
select veil2.open_connection(ps.session_id, 1, 'passwd2')
  from perf_sessions ps
 where name = 'Bob'
union all
select veil2.open_connection(ps.session_id, 1, 'passwd3')
  from perf_sessions ps
 where name = 'Carol'
union all
select veil2.open_connection(ps.session_id, 1, 'passwd4')
  from perf_sessions ps
 where name = 'Eve1'
union all
select veil2.open_connection(ps.session_id, 1, 'passwd4')
  from perf_sessions ps
 where name = 'Eve2'
union all
select veil2.open_connection(ps.session_id, 1, 'passwd5')
  from perf_sessions ps
 where name = 'Sue'
union all
select veil2.open_connection(ps.session_id, 1, 'passwd7')
  from perf_sessions ps
 where name = 'Simon'
 )
select -- Query constructed to not return rows - keeps output clean
       null
  from open_connections oc
 where open_connection is null;

select 'Opening sessions: elapsed = ' ||
       floor(extract(seconds from current_timestamp -
                     st.current_timestamp) * 1000) ||
       ' milliseconds.'
  from start_time st;

-- Now we re-open those connections
with reopen as (
select reopen_connection('Alice')
union all
select reopen_connection('Bob')
union all
select reopen_connection('Carol')
union all
select reopen_connection('Eve1')
union all
select reopen_connection('Eve2')
union all
select reopen_connection('Sue')
union all
select reopen_connection('Simon'))
select reopen_connection from reopen where reopen_connection = 1;

select 'Re-opening sessions: elapsed = ' ||
       floor(extract(seconds from current_timestamp -
                     st.current_timestamp) * 1000) ||
       ' milliseconds.'
  from start_time st;

drop table start_time;
drop table perf_sessions;
