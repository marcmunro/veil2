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
       ('oath2', false,
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
