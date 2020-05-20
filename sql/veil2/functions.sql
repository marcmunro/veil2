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
to use this in generating subsequent authetntication tokens,

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
become-user process (see become_user()';


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
