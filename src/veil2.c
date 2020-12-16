/**
 * @file   veil2.c
 * \code
 *     Author:       Marc Munro
 *     Copyright (c) 2020 Marc Munro
 *     License:      GPL V3
 * 
 * \endcode
 * @brief  
 * Provides callable veil2 functions.  These are written in C for
 * performance and to ensure that they cannot be easily subverted.
 * 
 */

#include "postgres.h"
#include "funcapi.h"
#include "catalog/pg_type.h"
#include "access/xact.h"
#include "executor/spi.h"
#include "utils/builtins.h"
#include "veil2.h"

PG_MODULE_MAGIC;


/* These definitions are here rather than immediately preceding the
 * function declarations themselves as this code seems to confuse
 * Doxygen's call graph stuff.
 */
PG_FUNCTION_INFO_V1(veil2_session_ready); 
PG_FUNCTION_INFO_V1(veil2_reset_session);
PG_FUNCTION_INFO_V1(veil2_reset_session_privs);
PG_FUNCTION_INFO_V1(veil2_true);
PG_FUNCTION_INFO_V1(veil2_i_have_global_priv);
PG_FUNCTION_INFO_V1(veil2_i_have_personal_priv);
PG_FUNCTION_INFO_V1(veil2_i_have_priv_in_scope);
PG_FUNCTION_INFO_V1(veil2_i_have_priv_in_scope_or_global);
PG_FUNCTION_INFO_V1(veil2_i_have_priv_in_superior_scope);
PG_FUNCTION_INFO_V1(veil2_i_have_priv_in_scope_or_superior);
PG_FUNCTION_INFO_V1(veil2_i_have_priv_in_scope_or_superior_or_global);
PG_FUNCTION_INFO_V1(veil2_result_counts);
PG_FUNCTION_INFO_V1(veil2_docpath);
PG_FUNCTION_INFO_V1(veil2_datapath);


/**
 * Used to record whether the current session's temporary tables have
 * been properly initialised using veil2_reset_session().  If not the
 * privilege testing functions veil2_i_have_global_priv(),
 * veil2_i_have_personal_priv(), veil2_i_have_priv_in_scope() and
 * veil2_i_have_priv_in_superior_scope() will always return false.
 * If you need to implement your own pl/pgsql base privilege testing
 * function, it should call veil2_session_reeady() to ensure that
 * privileges have been correctly set up.
 *
 * The primary reason for this variable to exist is to ensure that a
 * user cannot trick the privileges functions by creating their own
 * session_privileges table.
 */
static bool session_ready = false;


/**
 * Used to record counts of false and true results from the
 * i_have_priv_xxx() functions.
 */
static int result_counts[] = {0, 0};


/**
 * Used to record an in-memory set of privileges associated with a
 * specfic scope (security context).
 */
typedef struct {
	int scope_type;
	int scope;
	Bitmap *privileges;
} ContextPrivs;

/**
 * Used to record the set of ContextPrivs for the current user's session.
 */
typedef struct {
	/** How many ContextPrivs we can currently store.  If we need
	 * more, we have to rebuild this structure. */
	int array_len;
	/** How many ContextPrivs we have for the current session. */
	int active_contexts;
	ContextPrivs context_privs[0];
} SessionPrivs;


/** 
 * The SessionPrivs object for this session. 
 */
static SessionPrivs *session_privs = NULL;

/** 
 * Whether we have loaded our session's ContextPrivs into session memory.
 */
static bool session_privs_loaded = false;


/**
 * Locate a particular ContextPriv entry in ::session_privs.
 *
 * @param p_idx Pointer to a cached index value for the entry in the
 * ::session_privs->active_contexts that the search should start from.
 * This allows the caller to cache the last returned index in the hope
 * that they will be looking for the same entry next time.  If no
 * cached value exists, the caller should provide -1.  The index of
 * the found ContextPrivs entry will be returned through this, or -1
 * if no context can be found.
 * @param scope_type The scope_type_id of the ContextPrivs entry we
 * are looking for.
 * @param scope The scope_id of the ContextPrivs entry we are looking
 * for.
 */
static void
findContext(int *p_idx, int scope_type, int scope)
{
	int this = *p_idx;
	int cmp;
	int lower = 0;
	int upper = session_privs->active_contexts - 1;
	ContextPrivs *this_cp;

	if (upper == 0) {
		*p_idx = -1;
		return;
	}
	else if ((this < 0) || (this >= upper)) {
		/* Create a new start, in the middle of the contexts. */
		this = upper >> 1;
	}
	/* Bsearch until we find a match or realise there is none. */	  
	while (true) {
		this_cp = &(session_privs->context_privs[this]);
		cmp = this_cp->scope_type - scope_type;
		if (!cmp) {
			cmp = this_cp->scope - scope;
		}
		if (!cmp) {
			*p_idx = this;
			return;
		}
		if (cmp > 0) {
			/* We are looking for a lower value. */
			upper = this - 1;
		}
		else {
			lower = this + 1;
		}
		if (upper < lower) {
			*p_idx = -1;
			return;
		}
		this = (upper + lower) >> 1;
	}
}

/**
 * Wrapper for findContext() that finds the context and checks for a
 * privilege in a single operation.
 *
 * @param p_idx Pointer to a cached index value for the entry in the
 * ::session_privs->active_contexts that the search should start from.
 * This allows the caller to cache the last returned index in the hope
 * that they will be looking for the same entry next time.  If no
 * cached value exists, the caller should provide -1.  The index of
 * the found ContextPrivs entry will be returned through this, or -1
 * if no context can be found.
 * @param scope_type The scope_type_id of the ContextPrivs entry we
 * are looking for.
 * @param scope The scope_id of the ContextPrivs entry we are looking
 * for.
 * @param priv The privilege to test for.
 *
 * @return false if no context can be found, otherwise true if the
 * user has priv in the supplied scope.
 */
static bool
checkContext(int *p_idx, int scope_type, int scope, int priv)
{
	findContext(p_idx, scope_type, scope);
	if (*p_idx == -1) {
		return false;
	}
	return bitmapTestbit(
		session_privs->context_privs[*p_idx].privileges, priv);
}


/**
 * Free a ContextPrivs entry.  This just means freeing the privileges
 * Bitmap and zeroing the pointer for it.
 * 
 * @param cp The ContextPrivs entry to be cleared out.
 */
static void
freeContextPrivs(ContextPrivs *cp)
{
	pfree((void *) cp->privileges);
	cp->privileges = NULL;
}


/**
 * Clear all ContextPrivs entries in session_privs.
 */
static void
clear_session_privs()
{
	int i;
	if (session_privs) {
		for (i = session_privs->active_contexts - 1; i >= 0; i--) {
			freeContextPrivs(&session_privs->context_privs[i]);
		}
		session_privs->active_contexts = 0;
		session_privs_loaded = false;
	}
}

/**
 * How many ContextPrivs entries a SessionPrivs structure will be
 * created with/extended by.
 */
#define CONTEXT_PRIVS_INCREMENT 16

/** Provide the size that we want our SessionPrivs structure to be.
 *
 * @param elems the number of ContextPrivs entries already in place.  This
 * will be increased by CONTEXT_PRIVS_INCREMENT.
 */
#define CONTEXT_PRIVS_SIZE(elems) (					\
	sizeof(SessionPrivs) +							\
	(sizeof(ContextPrivs) *							\
	 (elems + CONTEXT_PRIVS_INCREMENT)))

/*
 * Create or extend our SessionPrivs structure.
 *
 * @result The newly allocated SessionPrivs struct.
 */
static SessionPrivs *
extendSessionPrivs(SessionPrivs *session_privs)
{
	size_t size;
	int i;
	if (session_privs) {
		size = CONTEXT_PRIVS_SIZE(session_privs->array_len);
		session_privs = (SessionPrivs *)
			realloc((void *) session_privs, size);
		session_privs->array_len += CONTEXT_PRIVS_INCREMENT;
		for (i = session_privs->array_len - CONTEXT_PRIVS_INCREMENT;
			 i < session_privs->array_len; i++)
		{
			session_privs->context_privs[i].privileges = NULL;
		}
	}
	else {
		session_privs = (SessionPrivs *) calloc(1, CONTEXT_PRIVS_SIZE(0));
		session_privs->array_len = CONTEXT_PRIVS_INCREMENT;
	}
	if (!session_privs) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("Unable to create session memory in "
						"extendSessionPrivs()")));
	}
	return session_privs;
}


/**
 * Add a ContextPrivs entry to ::session_privs, from the parameters.
 *
 * @param scope_type The scope_type for the new entry
 * @param the scope scope for the new entry
 * @param privs The privileges Bitmap for the new entry
 */
static void
add_scope_privs(int scope_type, int scope, Bitmap *privs)
{
	MemoryContext old_context;
	int idx = session_privs->active_contexts;
	if (session_privs->active_contexts >= session_privs->array_len) {
		session_privs = extendSessionPrivs(session_privs);
	}

	session_privs->active_contexts++;
	session_privs->context_privs[idx].scope_type = scope_type;
	session_privs->context_privs[idx].scope = scope;

	/* We copy the bitmap in TopMemoryContext so that it won't be
	 * cleaned-up as transactions come and go. */
	
	old_context = MemoryContextSwitchTo(TopMemoryContext);
	session_privs->context_privs[idx].privileges = bitmapCopy(privs);
	MemoryContextSwitchTo(old_context);
}


/**
 * A ::Fetch_fn for veil2_query() that retrieves the details for a
 * ContextPrivs entry and adds it to ::session_privs using
 * add_scope_privs(). 
 *
 * @param tuple  The ::HeapTuple returned from a Postgres SPI query.
 * This will contain a tuple of 2 integers.
 * @param tupdesc The ::TupleDesc returned from the same Postgres SPI query
 * @param p_result This should be null.
 *
 * @result true, to indicate to veil2_query() that there may be more
 * records to fetch.
 */
static bool
fetch_scope_privs(HeapTuple tuple, TupleDesc tupdesc, void *p_result)
{
	bool isnull;
	int scope_type;
	int scope;
	Bitmap *privs;
	
	scope_type = DatumGetInt32(SPI_getbinval(tuple, tupdesc, 1, &isnull));
    scope = DatumGetInt32(SPI_getbinval(tuple, tupdesc, 2, &isnull));
    privs = DatumGetBitmap(SPI_getbinval(tuple, tupdesc, 3, &isnull));

	add_scope_privs(scope_type, scope, privs);
	return true;
}

/**
 * Does the donkey-work of loading session privileges into session
 * memory.
 */
static void
do_load_session_privs()
{
	bool pushed;
	
	if (session_privs) {
		clear_session_privs();
	}
	else {
		session_privs = extendSessionPrivs(NULL);
	}
	veil2_spi_connect(&pushed,
					  "SPI connect failed in do_load_session_privs() - veil2");

	(void) veil2_query(
		"select scope_type_id, scope_id, privs"
		"  from veil2_session_privileges"
		" order by 1, 2",
		0, NULL, NULL,
		false, 	NULL,
		fetch_scope_privs, NULL);
	
	veil2_spi_finish(pushed,
					 "SPI finish failed in do_load_session_privs() - veil2");
}

/**
 * Manage the conditional loading of session privileges into session
 * memory.  If the session is already loaded, it does nothing.
 */
static void
load_privs()
{
	if (!session_privs_loaded) {
		do_load_session_privs();
		session_privs_loaded = true;
	}
}

/** 
 * Predicate to indicate whether to raise an error if a privilege test
 * function has been called prior to a session being established.  If
 * not, the privilege testing function should return false.  The
 * determination of whether to error or return false is based on the
 * value of the veil2.system_parameter 'error on uninitialized
 * session' at the time that the database session is established.
 *
 * @return boolean, whether or not to raise an error.
 */
static bool
error_if_no_session()
{
	static bool init_done = false;
	static bool error = true;
	bool pushed;
	if (!init_done) {
		veil2_spi_connect(&pushed, "error_if_no_session() (1)");
		(void) veil2_bool_from_query(
			"select parameter_value::boolean"
			"  from veil2.system_parameters"
			" where parameter_name = 'error on uninitialized session'",
			0, NULL, NULL, NULL, &error);
		veil2_spi_finish(pushed, "error_if_no_session (2)");
		init_done = true;
	}
	return error;
}



/** 
 * This is a Fetch_fn() for dealing with tuples containing 2 integers.
 * Its job is to populate the p_result parameter with 2 integers
 * from a Postgres SPI query.
 * 
 * @param tuple  The ::HeapTuple returned from a Postgres SPI query.
 * This will contain a tuple of 2 integers.
 * @param tupdesc The ::TupleDesc returned from the same Postgres SPI query
 * @param p_result Pointer to a ::tuple_2ints struct into which the 2
 * integers from the SPI query will be placed.
 *
 * @return <code>bool</code> false, indicating to veil2_query() that
 * no more rows are expected.
 */
static bool
fetch_2ints(HeapTuple tuple, TupleDesc tupdesc, void *p_result)
{
	bool isnull;
	tuple_2ints *my_tup = (tuple_2ints *) p_result;
    my_tup->f1 = DatumGetInt32(SPI_getbinval(tuple, tupdesc, 1, &isnull));
    my_tup->f2 = DatumGetInt32(SPI_getbinval(tuple, tupdesc, 2, &isnull));

	return false;  // No need to continue processing after this
}


/** 
 * Create the temporary tables used for recording session privileges
 * and context.
 */
static void
create_temp_tables()
{
	(void) veil2_query(
		"create temporary table veil2_session_privileges"
		"    of veil2.session_privileges_t",
		0, NULL, NULL,
		false, NULL,
		NULL, NULL);
	(void) veil2_query(
		"create temporary table veil2_ancestor_privileges"
		"    of veil2.session_privileges_t",
		0, NULL, NULL,
		false, NULL,
		NULL, NULL);
	(void) veil2_query(
		"create temporary table veil2_session_context"
		"    of veil2.session_context_t",
		0, NULL, NULL,
		false, NULL,
		NULL, NULL);
}


/** 
 * Truncate the veil2_session_privileges and veil2_session_context
 * temporary tables (actually we use deletion rather than truncation
 * as it seems faster.
 *
 * @param clear_context  Whether veil2_session_context should be
 * cleared as well as the privileges temp tables.
 */
static void
truncate_temp_tables(bool clear_context)
{
	(void) veil2_query(
		"delete from veil2_session_privileges",
		0, NULL, NULL,
		false, 	NULL,
		NULL, NULL);
	if (clear_context) {
		(void) veil2_query(
			"delete from veil2_session_context",
			0, NULL, NULL,
			false, 	NULL,
			NULL, NULL);
	}
}


/** 
 * <code>veil2_session_ready() returns bool</code>
 * Predicate to indicate whether the current session has been properly
 * initialized by veil2_reset_session().  It tests the static variable
 * ::session_ready.
 * 
 * @return <code>bool</code> true if this session has been set up.
 */
Datum
veil2_session_ready(PG_FUNCTION_ARGS)
{
    PG_RETURN_BOOL(session_ready);
}


/**
 * Does the database donkey-work for veil2_reset_session().
 * 
 * @param clear_context  Whether veil2_session_context should be
 * cleared as well as the privileges temp tables.
 */
static void
do_reset_session(bool clear_context)
{
	tuple_2ints my_tup;
	int processed;

	processed = veil2_query(
		"select count(*)::integer,"
		"       sum(case when c.relacl is null then 1 else 0 end)"
		"  from pg_catalog.pg_class c"
		" where c.relname in ('veil2_session_privileges',"
		"                     'veil2_session_context',"
		"                     'veil2_ancestor_privileges')"
		"   and c.relkind = 'r'"
		"   and c.relpersistence = 't'"
		"   and pg_catalog.pg_table_is_visible(c.oid)",
		0, NULL, NULL,
		false, 	NULL,
		fetch_2ints, (void *) &my_tup);

	if (processed == 0) {
		/* Unexpected error in query. */
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("Temp tables query fails in veil2_reset_session()")));
	}
	else {
		if (processed != 1) {
			/* This should be impossible. */
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("Unexpected processing error in "
							"veil2_reset_session: %d", processed)));
		}
		if (my_tup.f1 == 0) {
			/* We have no temp tables, so let's create them. */
			create_temp_tables();
			session_ready = true;
		}
		else if (my_tup.f1 == 3) {
			/* We have the expected temp tables - check that access
			 * is properly limited. */
			if (my_tup.f2 != 3) {
				ereport(ERROR,
						(errcode(ERRCODE_INTERNAL_ERROR),
						 errmsg("Unexpected access to temp tables in "
								"veil2_reset_session"),
						 errdetail("This indicates an attempt to bypass "
								   "VPD security!")));
			}
			/* Access to temp tables looks kosher.  Truncate the
			 * tables. */
			truncate_temp_tables(clear_context);
			session_ready = true;
		}
		else {
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("Unexpected count of temp tables in "
							"veil2_reset_session: %d", my_tup.f1),
					 errdetail("This indicates an attempt to bypass "
							   "VPD security!")));
		}
	}
}

/** 
 * <code>veil2.reset_session() returns void</code> 
 *
 * Resets a postgres session prior to the recording of session
 * privilege information.  This ensures that the Veil2 temporary
 * tables, on which our security depends, exist and have not been
 * tamperered with.  Unless this function succeeds, the privilege
 * testing functions veil2_i_have_global_priv(),
 * veil2_i_have_personal_priv(), veil2_i_have_priv_in_scope() and
 * veil2_i_have_priv_in_superior_scope() will always return false.
 *
 * @return void
 */
Datum
veil2_reset_session(PG_FUNCTION_ARGS)
{
	bool pushed;
	
	session_ready = false;
	clear_session_privs();
	veil2_spi_connect(&pushed, "failed to reset session (1)");
	do_reset_session(true);
	veil2_spi_finish(pushed, "failed to reset session (2)");
 	PG_RETURN_VOID();
}

/** 
 * <code>veil2.reset_session_privs() returns void</code> 
 *
 * Clears the temp table and cached privileges for a postgres
 * session and reloads them.
 *
 * @return void
 */
Datum
veil2_reset_session_privs(PG_FUNCTION_ARGS)
{
	bool pushed;

	clear_session_privs();
	veil2_spi_connect(&pushed, "failed to reset session privs (1)");
	do_reset_session(false);
	veil2_spi_finish(pushed, "failed to reset session privs (2)");
 	PG_RETURN_VOID();
}

/** 
 * <code>veil2.true(params) returns bool</code> 
 *
 * Always return true, regardless of parameters.  This is used to
 * determine the minimum possible overhead for a privilege testing
 * predicate, for performance measurements.
 *
 * @return boolean true
 */
Datum
veil2_true(PG_FUNCTION_ARGS)
{
	return true;
}

/**
 * Check whether a session has been properly initialized.  If not, and
 * we are supposed to fail in such a situation, fail with an appropriate
 * error message.  Otherwise return true if the session is ready to
 * go.
 *
 * @result boolean True if our session has been properly initialized.
 */
static bool
checkSessionReady()
{
	if (session_ready) {
		return true;
	}
	if (error_if_no_session()) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("Attempt to check privileges before call to "
						"veil2_reset_session.")));
	}
	return false;
}

/** 
 * <code>veil2.i_have_global_priv(priv) returns bool</code> 
 *
 * Predicate to determine whether the current session user has a given
 * privilege, <code>priv</code>, with global scope.
 *
 * @param privilege_id Integer giving privilege to test for
 *
 * @return boolean true if the session has the given privilege
 */
Datum
veil2_i_have_global_priv(PG_FUNCTION_ARGS)
{
	static int context_idx = -1;
	int priv = PG_GETARG_INT32(0);
	bool result;
	
	if ((result = checkSessionReady())) {
		load_privs();
		result = checkContext(&context_idx, 1, 0, priv);
	}
	result_counts[result]++;
	return result;
}


/** 
 * <code>veil2.i_have_personal_priv(priv, accessor_id) returns bool</code> 
 *
 * Predicate to determine whether the current session user has a given
 * privilege, <code>priv</code>, in their personal scope (ie for data
 * pertaining to themselves).
 *
 * @param privilege_id Integer giving privilege to test for
 * @param accessor_id Integer id for a party from the record being
 * checked.
 *
 * @return boolean true if the session has the given privilege in the
 * personal scope of the given accessor_id
 */
Datum
veil2_i_have_personal_priv(PG_FUNCTION_ARGS)
{
	static int context_idx = -1;
	bool result;
	int priv = PG_GETARG_INT32(0);
	int accessor_id = PG_GETARG_INT32(1);
	
	if ((result = checkSessionReady())) {
		load_privs();
		result = checkContext(&context_idx, 2, accessor_id, priv);
	}
	result_counts[result]++;
	return result;
}


/** 
 * <code>veil2.i_have_priv_in_scope(priv, scope_type_id, scope_id) 
 *     returns bool</code> 
 *
 * Predicate to determine whether the current session user has a given
 * privilege, <code>priv</code>, in a specific scope
 * (<code>scope_type_id</code>, <code>scope_id</code>).
 *
 * @param privilege_id Integer giving privilege to test for
 * @param scope_type_id Integer id of the scope type to be checked
 * @param scope_id Integer id of the scop to be checked
 *
 * @return boolean true if the session has the given privilege for the
 * given scope_type_id and scope_id
 */
Datum
veil2_i_have_priv_in_scope(PG_FUNCTION_ARGS)
{
	static int context_idx = -1;
	bool result;
	int priv = PG_GETARG_INT32(0);
	int scope_type_id = PG_GETARG_INT32(1);
	int scope_id = PG_GETARG_INT32(2);
	
	if ((result = checkSessionReady())) {
		load_privs();
		result = checkContext(&context_idx, scope_type_id, scope_id, priv);
	}
	result_counts[result]++;
	return result;
}


/** 
 * <code>veil2.i_have_priv_in_scope_or_global(priv, scope_type_id, scope_id) 
 *     returns bool</code> 
 *
 * Predicate to determine whether the current session user has a given
 * privilege, <code>priv</code>, in a specific scope
 * (<code>scope_type_id</code>, <code>scope_id</code>), or in global scope.
 *
 * @param privilege_id Integer giving privilege to test for
 * @param scope_type_id Integer id of the scope type to be checked
 * @param scope_id Integer id of the scop to be checked
 *
 * @return boolean true if the session has the given privilege for the
 * given scope_type_id and scope_id
 */
Datum
veil2_i_have_priv_in_scope_or_global(PG_FUNCTION_ARGS)
{
	static int global_context_idx = -1;
	static int given_context_idx = -1;
	bool result;
	int priv = PG_GETARG_INT32(0);
	int scope_type_id = PG_GETARG_INT32(1);
	int scope_id = PG_GETARG_INT32(2);
	
	if ((result = checkSessionReady())) {
		load_privs();
		result =
			(checkContext(&global_context_idx, 1, 0, priv) ||
			 checkContext(&given_context_idx, scope_type_id,
						  scope_id, priv));
	}
	result_counts[result]++;
	return result;
}


/** 
 * <code>veil2.i_have_priv_in_superior_scope(priv, scope_type_id, scope_id) 
 *     returns bool</code> 
 *
 * Predicate to determine whether the current session user has a given
 * privilege, <code>priv</code>, in a superior scope to that supplied: 
 * <code>scope_type_id</code>, <code>scope_id</code>.
 *
 * @param privilege_id Integer giving privilege to test for
 * @param scope_type_id Integer id of the scope type to be checked
 * @param scope_id Integer id of the scop to be checked
 *
 * @return boolean true if the session has the given privilege in a
 * scope superior to that given by scope_type_id and scope_id
 */
Datum
veil2_i_have_priv_in_superior_scope(PG_FUNCTION_ARGS)
{
	static void *saved_plan = NULL;
	bool result;
	bool found;
	bool pushed;
	int priv = PG_GETARG_INT32(0);
	int scope_type_id = PG_GETARG_INT32(1);
	int scope_id = PG_GETARG_INT32(2);
	Oid argtypes[] = {INT4OID, INT4OID, INT4OID};
	Datum args[] = {Int32GetDatum(priv),
					Int32GetDatum(scope_type_id),
					Int32GetDatum(scope_id)};
	
	if ((result = checkSessionReady())) {
		veil2_spi_connect(&pushed,
						  "SPI connect failed in "
						  "veil2_i_have_priv_in_superior_scope()");
		found = veil2_bool_from_query(
			"select true"
			"  from veil2.all_superior_scopes asp"
			" inner join veil2_session_privileges sp"
			"    on sp.scope_type_id = asp.superior_scope_type_id"
			"   and sp.scope_id = asp.superior_scope_id"
			" where asp.scope_type_id = $2"
			"   and asp.scope_id = $3"
			"   and sp.privs ? $1",
			3, argtypes, args,
			&saved_plan, &result);

		veil2_spi_finish(pushed,
						 "SPI finish failed in "
						 "veil2_i_have_priv_in_superior_scope()");
		result = found && result;
	}
	result_counts[result]++;
	return result;
}


/** 
 * <code>veil2.i_have_priv_in_scope_or_superior(priv, scope_type_id, scope_id) 
 *     returns bool</code> 
 *
 * Predicate to determine whether the current session user has a given
 * privilege, <code>priv</code>, in the supplied scope or a superior one: 
 * <code>scope_type_id</code>, <code>scope_id</code>.
 *
 * @param privilege_id Integer giving privilege to test for
 * @param scope_type_id Integer id of the scope type to be checked
 * @param scope_id Integer id of the scop to be checked
 *
 * @return boolean true if the session has the given privilege in the
 * scope given by scope_type_id and scope_id or a supeior one.
 */
Datum
veil2_i_have_priv_in_scope_or_superior(PG_FUNCTION_ARGS)
{
	static int context_idx = -1;
	static void *saved_plan = NULL;
	bool result;
	bool found;
	bool pushed;
	int priv = PG_GETARG_INT32(0);
	int scope_type_id = PG_GETARG_INT32(1);
	int scope_id = PG_GETARG_INT32(2);
	Oid argtypes[] = {INT4OID, INT4OID, INT4OID};
	Datum args[] = {Int32GetDatum(priv),
					Int32GetDatum(scope_type_id),
					Int32GetDatum(scope_id)};

	if ((result = checkSessionReady())) {
		load_privs();
		/* Start by checking priv in scope - this can maybe save us a
		 * query. */

		result = checkContext(&context_idx, scope_type_id, scope_id, priv);

		if (!result) {
			veil2_spi_connect(&pushed,
							  "SPI connect failed in "
							  "veil2_i_have_priv_in_scope_or_superior()");
			found = veil2_bool_from_query(
				"select true"
				"  from veil2.all_superior_scopes asp"
				" inner join veil2_session_privileges sp"
				"    on sp.scope_type_id = asp.superior_scope_type_id"
				"   and sp.scope_id = asp.superior_scope_id"
				" where asp.scope_type_id = $2"
				"   and asp.scope_id = $3"
				"   and sp.privs ? $1",
				3, argtypes, args,
				&saved_plan, &result);
			
			veil2_spi_finish(pushed,
							 "SPI finish failed in "
							 "veil2_i_have_priv_in_scope_or_superior()");
			result = found && result;
		}
	}
	result_counts[result]++;
	return result;
}


/** 
 * <code>veil2.i_have_priv_in_scope_or_superior_or_global(priv, scope_type_id, scope_id) 
 *     returns bool</code> 
 *
 * Predicate to determine whether the current session user has a given
 * privilege, <code>priv</code>, in global_scope, or the supplied
 * scope, or a superior one: 
 * <code>scope_type_id</code>, <code>scope_id</code>.
 *
 * @param privilege_id Integer giving privilege to test for
 * @param scope_type_id Integer id of the scope type to be checked
 * @param scope_id Integer id of the scop to be checked
 *
 * @return boolean true if the session has the given privilege in the
 * scope given by scope_type_id and scope_id or a supeior one or
 * global scope.
 */
Datum
veil2_i_have_priv_in_scope_or_superior_or_global(PG_FUNCTION_ARGS)
{
	static int global_context_idx = -1;
	static int given_context_idx = -1;
	static void *saved_plan = NULL;
	bool result;
	bool found;
	bool pushed;
	int priv = PG_GETARG_INT32(0);
	int scope_type_id = PG_GETARG_INT32(1);
	int scope_id = PG_GETARG_INT32(2);
	Oid argtypes[] = {INT4OID, INT4OID, INT4OID};
	Datum args[] = {Int32GetDatum(priv),
					Int32GetDatum(scope_type_id),
					Int32GetDatum(scope_id)};
	
	if ((result = checkSessionReady())) {
		load_privs();
		result =
			(checkContext(&global_context_idx, 1, 0, priv) ||
			 checkContext(&given_context_idx, scope_type_id,
						  scope_id, priv));
		if (!result) {
			veil2_spi_connect(&pushed,
							  "SPI connect failed in "
							  "veil2_i_have_priv_in_scope_or_superior()");
			found = veil2_bool_from_query(
				"select true"
				"  from veil2.all_superior_scopes asp"
				" inner join veil2_session_privileges sp"
				"    on sp.scope_type_id = asp.superior_scope_type_id"
				"   and sp.scope_id = asp.superior_scope_id"
				" where asp.scope_type_id = $2"
				"   and asp.scope_id = $3"
				"   and sp.privs ? $1",
				3, argtypes, args,
				&saved_plan, &result);

			veil2_spi_finish(pushed,
							 "SPI finish failed in "
							 "veil2_i_have_priv_in_scope_or_superior()");
			result = found && result;
		}
	}
	result_counts[result]++;
	return result;
}


/** 
 * Return the number of times one of the i_have_privilege_xxxx()
 * functions has returned false and true.
 * 
 * @return Record: false_count, true_count
 */
Datum
veil2_result_counts(PG_FUNCTION_ARGS)
{
	/* We only return positive integers.  That's just the way it
	 * is. */ 
	Datum results[2] = {Int32GetDatum(result_counts[0] & INT_MAX),
					    Int32GetDatum(result_counts[1] & INT_MAX)};
	bool nulls[2] = {false, false};
	TupleDesc tuple_desc;
	HeapTuple tuple;
	if (get_call_result_type(fcinfo, NULL,
							 &tuple_desc) != TYPEFUNC_COMPOSITE) {
		ereport(ERROR,
                    (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                     errmsg("function returning record called in context "
                            "that cannot accept type record")));
	}
	tuple_desc = BlessTupleDesc(tuple_desc);
	tuple = heap_form_tuple(tuple_desc, results, nulls);
	return HeapTupleGetDatum(tuple);
}
	
/** 
 * Create a dynamically allocated text value as a copy of a C string.
 * 
 * @param in String to be copied
 *
 * @return Dynamically allocated (by palloc()) copy of in.
 */
static text *
textfromstr(char *in)
{
    int   len = strlen(in);
    text *out = palloc(len + VARHDRSZ);
    memcpy(VARDATA(out), in, len);
	SET_VARSIZE(out, (len + VARHDRSZ));

    return out;
}

/** 
 * Provide the path to where documentation should be stored on the server.
 * 
 * @return Text value containing the path.
 */
Datum
veil2_docpath(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(textfromstr(DOCS_PATH));
}

/** 
 * Provide the path to where veil2 sql scripts should be stored on the
 * server.
 * 
 * @return Text value containing the path.
 */
Datum
veil2_datapath(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(textfromstr(DATA_PATH));
}


