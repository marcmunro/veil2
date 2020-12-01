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


/* These definitions are up here rather than immediately preceding the
 * function declarations themselves as this code seems to confuse
 * Doxygen's call graph stuff.
 */
PG_FUNCTION_INFO_V1(veil2_session_ready); 
PG_FUNCTION_INFO_V1(veil2_reset_session);
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
 * Load minimal set of pgbitmap functionality.  Ideally, we'd link to
 * the pgbitmap extension but I haven't figured our how to do that.
 * This is a pretty nasty hack, but I think it's safe.
 */
#include "../../pgbitmap/src/pgbitmap_utils.c"


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
 * Used to record the set of ContextPrivs for the current user's sesion.
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
 * @param start The index for the entry in the
 * ::session_privs->active_contexts that the search should start from.
 * This allows the caller to cache the last returned index in the hope
 * that they will be looking for the same entry next time.  If no
 * cached value exists, the caller should provide -1.
 * @param scope_type The scope_type_id of the ContextPrivs entry we are
 * looking for.
 * @param scope The scope_id of the ContextPrivs entry we are
 * looking for.
 *
 * @result the index into ::session_privs->active_contexts for the given
 * scope_type and scope, and starting at start.  If not found, return
 * -1.
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
 * @param the ContextPrivs entry to be cleared out.
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
 * @param the scope_type for the new entry
 * @param the scope for the new entry
 * @param the privileges Bitmap for the new entry
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
	session_privs->context_privs[idx].privileges = copyBitmap(privs);
	MemoryContextSwitchTo(old_context);
}


/**
 * A ::Fetch_fn for veil2_query() that retrieves the details for a
 * ContextPrivs entry and adds it to ::session_privs using
 * add_scope_privs(). 
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
 *
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
		"create temporary table veil2_orig_privileges"
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
 */
static void
truncate_temp_tables()
{
	(void) veil2_query(
		"delete from veil2_session_privileges",
		0, NULL, NULL,
		false, 	NULL,
		NULL, NULL);
	(void) veil2_query(
		"delete from veil2_session_context",
		0, NULL, NULL,
		false, 	NULL,
		NULL, NULL);
	

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

#define USE_BITMAPS_DIRECTLY



/**
 * Does the database donkey-work for veil2_reset_session().
 */
static void
do_reset_session()
{
	tuple_2ints my_tup;
	int processed;

	processed = veil2_query(
		"select count(*)::integer,"
		"       sum(case when c.relacl is null then 1 else 0 end)"
		"  from pg_catalog.pg_class c"
		" where c.relname in ('veil2_session_privileges',"
		"                     'veil2_session_context',"
		"                     'veil2_orig_privileges')"
		"   and c.relkind = 'r'"
		"   and c.relpersistence = 't'",
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
			truncate_temp_tables();
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
	do_reset_session();
	veil2_spi_finish(pushed, "failed to reset session (2)");
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
 * @param int privilege_id of privilege to test for
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
 * <code>veil2.i_have_personal_priv(priv) returns bool</code> 
 *
 * Predicate to determine whether the current session user has a given
 * privilege, <code>priv</code>, in their personal scope (ie for data
 * pertaining to themselves).
 *
 * @param int privilege_id of privilege to test for
 * @param int accessor_id of the record being checked.
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
 * @param int privilege_id of privilege to test for
 * @param int scope_type_id of the record being checked.
 * @param int scope_id for the record being checked.
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
 * @param int privilege_id of privilege to test for
 * @param int scope_type_id of the record being checked.
 * @param int scope_id for the record being checked.
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
 * @param int privilege_id of privilege to test for
 * @param int scope_type_id of the record being checked.
 * @param int scope_id for the record being checked.
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
	}
	result_counts[found && result]++;
	return found && result;
}


/** 
 * <code>veil2.i_have_priv_in_scope_or_superior(priv, scope_type_id, scope_id) 
 *     returns bool</code> 
 *
 * Predicate to determine whether the current session user has a given
 * privilege, <code>priv</code>, in the supplied scope or a superior one: 
 * <code>scope_type_id</code>, <code>scope_id</code>.
 *
 * @param int privilege_id of privilege to test for
 * @param int scope_type_id of the record being checked.
 * @param int scope_id for the record being checked.
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
 * @param int privilege_id of privilege to test for
 * @param int scope_type_id of the record being checked.
 * @param int scope_id for the record being checked.
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


#ifdef TRIED_WITH_NO_PERFORMANCE_GAIN
PG_FUNCTION_INFO_V1(veil2_create_accessor_session);
typedef struct {
	int accessor_id;
	int authent_accessor_id;
	int session_id;
	int login_context_type_id;
	int login_context_id;
	int session_context_type_id;
	int session_context_id;
	int mapping_context_type_id;
	int mapping_context_id;      
} SessionContext;

static bool
fetch_session_context(HeapTuple tuple, TupleDesc tupdesc, void *args)
{
	SessionContext *session_context = (SessionContext *) args;
	bool is_null;
	int mapping_context_type;
	int mapping_context;
	
	session_context->session_id = 
		DatumGetInt32(SPI_getbinval(tuple, tupdesc, 1, &is_null));
	
	mapping_context_type = 
		DatumGetInt32(SPI_getbinval(tuple, tupdesc, 2, &is_null));

	if (mapping_context_type == 1) {
		/* Mapping is in global_context */
		session_context->mapping_context_type_id = 1;
		session_context->mapping_context_id = 0;
	}
	else {
		mapping_context = 
			DatumGetInt32(SPI_getbinval(tuple, tupdesc, 3, &is_null));
		if (is_null) {
			session_context->mapping_context_type_id =
				session_context->session_context_type_id;
			session_context->mapping_context_id = 
				session_context->session_context_id;
		}
		else {
			session_context->mapping_context_type_id = mapping_context_type;
			session_context->mapping_context_id = mapping_context;
		}
	}

	return false;  // Only want one row: this stopes further processing.
}

// TODO:
// later add a static to indicate whether session is currently reset
// and do nothing in reset_session if so
static void
get_session_context(SessionContext *session_context)
{
	static void *saved_plan = NULL;
	int processed;
	Oid argtypes[] = {INT4OID, INT4OID};
	Datum args[] = {Int32GetDatum(session_context->session_context_type_id),
					Int32GetDatum(session_context->session_context_type_id)};

	processed = veil2_query(
		"select nextval('veil2.session_id_seq')::integer,"
		"       sp.parameter_value::integer,"
		"       asp.superior_scope_id"
		"  from veil2.system_parameters sp"
		"  left outer join veil2.all_superior_scopes asp"
		"    on asp.scope_type_id = $1"
		"   and asp.scope_id = $2"
		"   and asp.superior_scope_type_id = sp.parameter_value::integer"
		"   and asp.is_type_promotion"
		" where sp.parameter_name = 'mapping context target scope type'",
		2, argtypes, args, true, &saved_plan,
		fetch_session_context, (void *) session_context);

	if (!(processed == 1)) {
		ereport(ERROR,
				(errcode(ERRCODE_NO_DATA_FOUND),
				 errmsg("Failed to fetch session context.")));
	}
}

static void
save_session_context(SessionContext *session_context)
{
	static void *saved_plan = NULL;
	Oid argtypes[] = {INT4OID, INT4OID, INT4OID,
	                  INT4OID, INT4OID, INT4OID,
	                  INT4OID, INT4OID, INT4OID};
	Datum args[] = {
		Int32GetDatum(session_context->accessor_id),
		Int32GetDatum(session_context->authent_accessor_id),
		Int32GetDatum(session_context->session_id),
		Int32GetDatum(session_context->login_context_type_id),
		Int32GetDatum(session_context->login_context_id),
		Int32GetDatum(session_context->session_context_type_id),
		Int32GetDatum(session_context->session_context_id),
		Int32GetDatum(session_context->mapping_context_type_id),
		Int32GetDatum(session_context->mapping_context_id)};

	(void) veil2_query(
		"insert"
		"  into veil2_session_context"
        "        (accessor_id, authent_accessor_id, session_id,"
		"         login_context_type_id, login_context_id,"
		"         session_context_type_id, session_context_id,"
		"         mapping_context_type_id, mapping_context_id)"
		" values ($1, $2, $3,"
		"         $4, $5,"
		"         $6, $7,"
		"         $8, $9)",
		9, argtypes, args, false, &saved_plan, NULL, NULL);
}

typedef struct {
	int accessor_id;
	char *authent_type;
	char *supplemental_fn;
	char *session_token;
	char *session_supplemental;
} AuthentDetails;

static bool
fetch_authent_details(HeapTuple tuple, TupleDesc tupdesc, void *args)
{
	AuthentDetails *authent_details = (AuthentDetails *) args;
	Datum val;
	bool is_null;

	if ((val = SPI_getbinval(tuple, tupdesc, 1, &is_null))) {
		authent_details->supplemental_fn = TextDatumGetCString(val);
	}
	else {
		authent_details->supplemental_fn = NULL;
		authent_details->session_supplemental = NULL;
	}
	authent_details->session_token = 
		TextDatumGetCString(SPI_getbinval(tuple, tupdesc, 2, &is_null));

	return false;  // Only want one row: this stopes further processing.
}

static bool
fetch_supplemental_tokens(HeapTuple tuple, TupleDesc tupdesc, void *args)
{
	AuthentDetails *authent_details = (AuthentDetails *) args;
	Datum val;
	bool is_null;

	if ((val = SPI_getbinval(tuple, tupdesc, 1, &is_null))) {
		/* If session_token is null, we leave the original value in
		 * place, otherwise we overwrite it below. */
		authent_details->session_token = TextDatumGetCString(val);
	}

	if ((val = SPI_getbinval(tuple, tupdesc, 2, &is_null))) {
		authent_details->session_supplemental = TextDatumGetCString(val);
	}
	else {
		authent_details->session_supplemental = NULL;
	}

	return false;  // Only want one row: this stopes further processing.
}

#define EXEC_SUPPLEMENTAL_FN_START "select * from %s($1, $2)"

static void
get_authent_details(AuthentDetails *authent_details)
{
	static void *saved_plan = NULL;
	static void *saved_plan2 = NULL;
	int processed;
	Oid argtypes[] = {TEXTOID};
	Datum args[] = {CStringGetTextDatum(authent_details->authent_type)};
	char *qrystr;
	
	/* Query designed to always return a sesion token regardless of
     * whether the authentication type matches a record. */
	processed = veil2_query(
		"select a2.supplemental_fn,"
		"       encode(digest(random()::text || now()::text, 'sha256'),"
		"                     'base64') as session_token"
		"  from (select $1 as auth_type) a1"
		"  left outer join veil2.authentication_types a2"
		"    on a2.shortname = a1.auth_type",
		1, argtypes, args, true, &saved_plan,
		fetch_authent_details, (void *) authent_details);

	if (!(processed == 1)) {
		ereport(ERROR,
				(errcode(ERRCODE_NO_DATA_FOUND),
				 errmsg("Failed to fetch authentication details.")));
	}

	if (authent_details->supplemental_fn) {
		Oid argtypes[] = {INT4OID, TEXTOID};
		Datum args[] = {
			Int32GetDatum(authent_details->accessor_id),
			CStringGetTextDatum(authent_details->session_token)};
		
		qrystr = (char *) palloc(sizeof(char *) *
								 (strlen(EXEC_SUPPLEMENTAL_FN_START) +
								  strlen(authent_details->supplemental_fn)));
		(void) sprintf(qrystr,
					   EXEC_SUPPLEMENTAL_FN_START,
					   authent_details->supplemental_fn);

		processed = veil2_query(
			qrystr,
			1, argtypes, args, true, &saved_plan2,
			fetch_supplemental_tokens, (void *) authent_details);
	}
}

static bool
valid_accessor_context(SessionContext *session_context)
{
	static void *saved_plan = NULL;
	bool found;
	bool is_valid;
	Oid argtypes[] = {INT4OID, INT4OID, INT4OID};
	Datum args[] = {
		Int32GetDatum(session_context->accessor_id),
		Int32GetDatum(session_context->login_context_type_id),
		Int32GetDatum(session_context->login_context_id)};

	found = veil2_bool_from_query(
		"select true"
		"  from veil2.accessors a"
		" inner join veil2.accessor_contexts ac"
		"    on ac.accessor_id = a.accessor_id"
		" where a.accessor_id = $1"
		"   and ac.context_type_id = $2"
		"  and ac.context_id = $3",
		3, argtypes, args, &saved_plan, &is_valid);
	return found;
}

static void
record_session(SessionContext *session_context,
			   AuthentDetails *authent_details)
{
	static void *saved_plan = NULL;
	char *nulls;
	Oid argtypes[] = {INT4OID, INT4OID, INT4OID,
					  INT4OID, INT4OID, INT4OID,
					  INT4OID, INT4OID, INT4OID,
					  TEXTOID, TEXTOID, TEXTOID};
	Datum args[] = {
		Int32GetDatum(session_context->accessor_id),
		Int32GetDatum(session_context->authent_accessor_id),
		Int32GetDatum(session_context->session_id),
		Int32GetDatum(session_context->login_context_type_id),
		Int32GetDatum(session_context->login_context_id),
		Int32GetDatum(session_context->session_context_type_id),
		Int32GetDatum(session_context->session_context_id),
		Int32GetDatum(session_context->mapping_context_type_id),
		Int32GetDatum(session_context->mapping_context_id),
		CStringGetTextDatum(authent_details->authent_type),
		(Datum) NULL,
		CStringGetTextDatum(authent_details->session_token)};

	if (authent_details->session_supplemental) {
		args[10] = CStringGetTextDatum(authent_details->session_supplemental);
		nulls = NULL;  /* No nulls. */
	}
	else {
		/* session_supplemental is null */
		nulls = "          n ";
	}
		
	(void) veil2_query_wn(
		"insert"
		"  into veil2.sessions"
        "      (accessor_id, authent_accessor_id, session_id,"
		"       login_context_type_id, login_context_id,"
		"       session_context_type_id, session_context_id,"
		"       mapping_context_type_id, mapping_context_id,"
		"       authent_type, has_authenticated,"
		"       session_supplemental, expires,"
		"       token) "
		"select $1, $2, $3,"
		"       $4, $5,"
		"       $6, $7,"
		"       $8, $9,"
		"       $10, false,"
		"       $11, now() + sp.parameter_value::interval,"
		"       $12"
		"  from veil2.system_parameters sp"
		" where sp.parameter_name = 'shared session timeout'",
		12, argtypes, args, nulls, false, &saved_plan, NULL, NULL);
}

/** 
 * <code>veil2.create_accessor_session(params) returns record</code> 
 *
 * TODO: explain this
 *
 * @param accessor_id in integer
 * @param authent_type in text
 * @param context_type_id in integer
 * @param context_id in integer
 * @param session_context_type_id in integer
 * @param session_context_id in integer
 * @param authent_accessor_id in integer default null
 * @param session_id out integer
 * @param session_token out text
 * @param session_supplemental out text
 *
 * @return record
 */
Datum
veil2_create_accessor_session(PG_FUNCTION_ARGS)
{
	SessionContext session_context;
	AuthentDetails authent_details;
	TupleDesc tuple_desc;
	HeapTuple tuple;
	Datum results[3];
	bool nulls[3] = {false, false, false};
	bool pushed;
	
	session_context.accessor_id = PG_GETARG_INT32(0);
	session_context.login_context_type_id = PG_GETARG_INT32(2);
	session_context.login_context_id = PG_GETARG_INT32(3);
	session_context.session_context_type_id = PG_GETARG_INT32(4);
	session_context.session_context_id = PG_GETARG_INT32(5);
	if (PG_ARGISNULL(6)) {
		session_context.authent_accessor_id = session_context.accessor_id;
	}
	else {
		session_context.authent_accessor_id = PG_GETARG_INT32(6);
	}
	authent_details.accessor_id = session_context.accessor_id;
	authent_details.authent_type = TextDatumGetCString(PG_GETARG_TEXT_P(1));
	
	veil2_spi_connect(&pushed, "failed to get_session_context (1)");
	do_reset_session();

	get_session_context(&session_context);
	save_session_context(&session_context);
	get_authent_details(&authent_details);
	if (valid_accessor_context(&session_context)) {
		record_session(&session_context, &authent_details);
	}
	
	veil2_spi_finish(pushed, "failed to get_session_context (2)");

	/* Create results record. */
	if (get_call_result_type(fcinfo, NULL,
							 &tuple_desc) != TYPEFUNC_COMPOSITE) {
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context "
						"that cannot accept type record")));
	}

	/* Return the results set. */
	results[0] = Int32GetDatum(session_context.session_id);
	results[1] = CStringGetTextDatum(authent_details.session_token);
	if (authent_details.session_supplemental) {
		results[2] = CStringGetTextDatum(authent_details.session_supplemental);
	}
	else
	{
		nulls[2] = true;
		results[2] = (Datum) NULL;
	}
	tuple_desc = BlessTupleDesc(tuple_desc);
	tuple = heap_form_tuple(tuple_desc, results, nulls);
	return HeapTupleGetDatum(tuple);
}

#endif
