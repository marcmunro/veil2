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
'Authentication predicate for plaintext authentication.  Return true iff
the supplied token matches the stored authentication token for the
accessor.  This authentication mechanism exists primarily for demo
purposes.  Do not use it in a real application!';


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
'Authentication predicate for bcrypt authentication.  Return true iff
running bcrypt on the supplied token, using the salt from the
stored authentication token for the accessor, matches that stored
authentication token.';


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
'For the given ACCESSOR_ID and AUTHENTICATION_TYPE check whether TOKEN
is an appropriate authentication.';



\echo ...creating veil2 session functions...

\echo ......reset_session()...
create or replace
function veil2.reset_session()
  returns bool as
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
  return true;
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


\echo ......create_session()...
create or replace
function veil2.create_session(
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
  supplemental_fn text;
begin
  ignore := veil2.reset_session();  -- ignore result
  -- Generate session_id and session_token and establish whether
  -- accessor_id was valid.
  select nextval('veil2.session_id_seq'),
         encode(digest(random()::text || now()::text,
	               'sha256'),
		'base64'),
	 coalesce((select true
	  	     from veil2.accessors a
		    where a.accessor_id = create_session.accessor_id), false),
	 (select t.supplemental_fn
	    from veil2.authentication_types t
	   where shortname = authent_type)
    into session_id,
         session_token,
	 valid,
	 supplemental_fn;
  if supplemental_fn is not null then
    execute format('select * from %s(%s, %L)',
                   supplemental_fn, accessor_id, session_token)
       into session_token, session_supplemental;
  end if;
  if valid then
    insert
      into veil2.sessions
          (accessor_id, session_id,
	   context_type_id, context_id,
	   authent_type, has_authenticated,
	   session_supplemental, expires,
	   token)
    select accessor_id, session_id, 
    	   context_type_id, context_id,
	   authent_type, false,
	   session_supplemental, now() + sp.parameter_value::interval,
	   session_token
      from veil2.system_parameters sp
     where sp.parameter_name = 'timeout';
  end if;
    

  -- Do this regardless of success - there should be no clues to
  -- indicate whether _accessor_id was valid;
  insert
    into session_parameters
         (accessor_id, session_id, context_type_id,
	  context_id, is_open)
  values (accessor_id, session_id, context_type_id,
          context_id, false);
end;
$$
language 'plpgsql' security definer volatile
set client_min_messages = 'error';

comment on function veil2.create_session(integer, text, integer, integer) is
'Get session credentials for a new session.  If _accessor_id is not
valid the function will appear to work but subsequent attempts to open
the session will fail and no privileges will be loaded.  This makes it
harder to fish for valid accessor_ids.

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


\echo ......load_session_privs()...
create or replace
function veil2.load_session_privs(
    session_id in integer,
    _accessor_id in integer)
  returns bool as
$$
declare
  ignore boolean;
begin
  ignore := veil2.reset_session();
  with session_context as
    (
      select context_type_id, context_id
        from veil2.sessions s
       where s.session_id = load_session_privs.session_id
    ), all_session_privs as
    (
      select session_id,
      	     asp.scope_type_id, asp.scope_id,
	     union_of(asp.roles) as roles,
	     union_of(asp.privs) as privs
        from session_context c
       inner join veil2.all_accessor_privs asp
          on /*asp.assignment_context_type_id = c.context_type_id
	 and asp.assignment_context_id = c.context_id
	 and */(   asp.mapping_context_type_id is null
              or (    asp.mapping_context_type_id = c.context_type_id
	          and asp.mapping_context_id = c.context_id))
       where asp.accessor_id = _accessor_id
       group by asp.scope_type_id, asp.scope_id
    ),
  global_privs as
    (
      select privs
        from all_session_privs
       where scope_type_id = 1
    )
  insert
    into session_privileges
        (session_id, context_type_id, context_id,
  	 roles, privs)
  select *
    from all_session_privs
   where (select privs from global_privs) ? 0; -- Test connect priv
  
  if found then
    insert
      into session_parameters
          (accessor_id, session_id, context_type_id,
	   context_id, is_open)
    select _accessor_id, load_session_privs.session_id, context_type_id,
           context_id, true
      from veil2.sessions s
     where s.session_id = load_session_privs.session_id;
    return true;
  else
    return false;
  end if;
end;
$$
language 'plpgsql' security definer volatile;

comment on function veil2.load_session_privs(integer, integer) is
'Load the temporary table session_privileges for SESSION_ID, with the
privileges for _ACCESSOR_ID.  The temporary table is queried by
security functions in order to determine what access rights the
connected user has.';

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


\echo ......open_session()...
create or replace
function veil2.open_session(
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
  authent_type text;
  expired bool;
  can_connect bool;
begin
  success = false;
  update session_parameters  -- If anything goes wrong from here on, 
  	 		     -- the session will be have no access
			     -- rights.
     set is_open = false;
  select s.accessor_id, s.expires < now(),
         s.nonces, s.authent_type,
	 ac.context_type_id,
	 s.has_authenticated, s.token
    into _accessor_id, expired,
         _nonces, authent_type,
	 _context_type_id,
	 _has_authenticated, _session_token
    from veil2.sessions s
    left outer join veil2.accessor_contexts ac
      on ac.accessor_id = s.accessor_id
     and ac.context_type_id = s.context_type_id
     and ac.context_id = s.context_id
   where s.session_id = open_session.session_id;

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
	-- use different authentication tokens for each open_session()
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
       where s.session_id = open_session.session_id
         and sp.parameter_name = 'timeout'
    returning nonces into _nonces;
  end if;
end;
$$
language 'plpgsql' security definer volatile
set client_min_messages = 'error';

comment on function veil2.open_session(integer, integer, text) is
'Attempt to open or re-open a session.  This is used to authenticate
or re-authenticate a connection, and until this is done a session
cannot be used.  

TODO: MORE HELPFUL (AND CORRECT) COMMENT

Failures may be for several reasons with errmsg as described below:
 - non-existence of session [errmsg: ''AUTHFAIL''];
 - expiry of session (while session record still exists - has not been
   cleaned away) [errmsg: ''EXPIRED''];
 - incorrect credentials being used [errmsg: ''AUTHFAIL''];
 - invalid nonce being provided [errmsg: ''NONCEFAIL''];
 - the user has no connect privilege [errmsg: ''AUTHFAIL''].

The _nonce is a number that may only be used once per session, and is
used to prevent replay attacks.  Each open_session() call should provide
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


\echo ......close_session()...
create or replace
function veil2.close_session() returns boolean as
$$
begin
  update session_parameters
     set is_open = false;
  return true;
end;
$$
language 'plpgsql' security definer volatile;

comment on function veil2.close_session() is
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
  ignore bool;
  _accessor_id integer;
  _session_id integer;
  success bool;
begin
  success := false;
  ignore := veil2.reset_session();  -- ignore result
  
  select accessor_id
    into _accessor_id
    from veil2.accessors
   where username = session_user;
  if found then
    _session_id := nextval('veil2.session_id_seq');

    -- Need to create context information for session before we can
    -- call load_session_privs().
    insert
       into veil2.sessions
             (session_id, accessor_id,
	      context_type_id, context_id,
	      authent_type, expires,
	      token, has_authenticated)
      values (_session_id, _accessor_id,
      	      hello.context_type_id, hello.context_id,
      	     'dbuser', now(),
	     'dbsession', false);

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
     and v.context_type_id = 1), false);
$$
language 'sql' security definer stable leakproof;

comment on function veil2.i_have_global_priv(integer) is
'Predicate to determine whether the connected user has the given
privilege in the global context.  This always returns a record.';


\echo ......i_have_priv_in_scope()...
create or replace
function veil2.i_have_priv_in_scope(
    priv integer,
    _context_type_id integer,
    _context_id integer)
  returns bool as
$$
  select privs ? priv
    from session_privileges v
   cross join session_parameters p
   where p.is_open
     and v.context_type_id = _context_type_id
     and v.context_id = _context_id;
$$
language 'sql' security definer stable leakproof;

comment on function veil2.i_have_priv_in_scope(integer, integer, integer) is
'Predicate to determine whether the connected user has the given
privilege in the given scope.';


\echo ......i_have_priv_in_superior_scope()...
create or replace
function veil2.i_have_priv_in_superior_scope(
    priv integer,
    _context_type_id integer,
    _context_id integer)
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
      on sp.context_type_id = asp.promoted_context_type_id
     and sp.context_id = asp.promoted_context_id
   where p.is_open
     and asp.context_type_id = _context_type_id
     and asp.context_id = _context_id
     and sp.privs ? priv;
  return found;
end
$$
language 'plpgsql' security definer stable leakproof;

comment on
function veil2.i_have_priv_in_superior_scope(integer, integer, integer) is
'Predicate to determine whether the connected user has the given
privilege a scope that is superior to the given scope.  This does not
check for the privilege in a global scope as it is assumed that such a
test will have already been performed.   As this function necessarily
performs a recursive query, it may add considerable overhead.  Whenever
possible, alternative mechanisms should be used for determining access
rights.

VPD Implementation Notes:
You may want to rewrite this function for your application, making use
of application-specific data structures in order to reduce its
overhead.';


\echo ......i_have_personal_priv()...
create or replace
function veil2.i_have_personal_priv(
    priv integer,
    _accessor_id integer)
  returns bool as
$$
  select (sp.accessor_id = _accessor_id) and (arp.privileges ? priv)
    from veil2.all_role_privs arp
   cross join session_parameters sp
   where arp.role_id = 2
     and sp.is_open;
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



