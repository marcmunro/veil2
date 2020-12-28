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
PG_FUNCTION_INFO_V1(veil2_session_context); 
PG_FUNCTION_INFO_V1(veil2_session_privileges); 
PG_FUNCTION_INFO_V1(veil2_add_session_privileges); 
PG_FUNCTION_INFO_V1(veil2_update_session_privileges); 
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
PG_FUNCTION_INFO_V1(veil2_version);


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
	Bitmap *roles;
	Bitmap *privileges;
} ContextRolePrivs;

/**
 * Used to record the set of ContextPrivs for the current user's session.
 */
typedef struct {
	/** How many ContextPrivs we can currently store.  If we need
	 * more, we have to rebuild this structure. */
	int array_len;
	/** How many ContextPrivs we have for the current session. */
	int active_contexts;
	ContextRolePrivs context_roleprivs[0];
} SessionRolePrivs;


/**
 * Used to record our current session context.  This replaces a
 * temporary table in an attempt to improve both security and
 * performance.
 */
typedef struct {
	bool  loaded;
	int	  accessor_id;
	int64 session_id;
	int	  login_context_type_id;
	int	  login_context_id;
	int	  session_context_type_id;
	int	  session_context_id;
	int	  mapping_context_type_id;
	int	  mapping_context_id;
	/** parent_session_id is nullable.  To indicate null we set it to
	 * the same value as session_id.  */
	int64 parent_session_id;
} SessionContext;

/** 
 * The SessionPrivs object for this session. 
 */
static SessionRolePrivs *session_roleprivs = NULL;

/** 
 * Whether we have loaded our session's ContextPrivs into session memory.
 */
static bool session_roleprivs_loaded = false;

static SessionContext session_context = {false, 0, 0, 0, 0,
										 0, 0, 0, 0};


/**
 * Locate a particular ContextPriv entry in ::session_roleprivs.
 *
 * @param p_idx Pointer to a cached index value for the entry in the
 * ::session_roleprivs->active_contexts that the search should start from.
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
	int upper;
	ContextRolePrivs *this_cp;

	if (!session_roleprivs) {
		*p_idx = -1;
		return;
	}
	upper = session_roleprivs->active_contexts - 1;
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
		this_cp = &(session_roleprivs->context_roleprivs[this]);
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
 * ::session_roleprivs->active_contexts that the search should start from.
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
		session_roleprivs->context_roleprivs[*p_idx].privileges, priv);
}


/**
 * Free a ContextRolePrivs entry.  This just means freeing the privileges
 * Bitmap and zeroing the pointer for it.
 * 
 * @param cp The ContextRolePrivs entry to be cleared out.
 */
static void
freeContextRolePrivs(ContextRolePrivs *cp)
{
	pfree((void *) cp->roles);
	pfree((void *) cp->privileges);
	cp->roles = NULL;
	cp->privileges = NULL;
}


/**
 * Clear all ContextRolePrivs entries in session_roleprivs.
 */
static void
clear_session_roleprivs()
{
	int i;
	MemoryContext old_context;
	old_context = MemoryContextSwitchTo(TopMemoryContext);

	if (session_roleprivs) {
		for (i = session_roleprivs->active_contexts - 1; i >= 0; i--) {
			freeContextRolePrivs(&session_roleprivs->context_roleprivs[i]);
		}
		session_roleprivs->active_contexts = 0;
		session_roleprivs_loaded = false;
	}
	MemoryContextSwitchTo(old_context);
}

/**
 * How many ContextPrivs entries a SessionPrivs structure will be
 * created with or extended by.
 */
#define CONTEXT_ROLEPRIVS_INCREMENT 16

/** Provide the size that we want our SessionRolePrivs structure to be.
 *
 * @param elems the number of ContextRolePrivs entries already in
 * place.  This will be increased by CONTEXT_ROLEPRIVS_INCREMENT.
 */
#define CONTEXT_ROLEPRIVS_SIZE(elems) (					\
	sizeof(SessionRolePrivs) +							\
	(sizeof(ContextRolePrivs) *							\
	 (elems + CONTEXT_ROLEPRIVS_INCREMENT)))

/*
 * Create or extend our SessionRolePrivs structure.
 *
 * @param session_roleprivs, the current version of the struct, or
 * NULL, if it has not yet been created.
 * @result The newly allocated or extended SessionRolePrivs struct.
 */
static SessionRolePrivs *
extendSessionRolePrivs(SessionRolePrivs *session_roleprivs)
{
	size_t size;
	int i;
	if (session_roleprivs) {
		size = CONTEXT_ROLEPRIVS_SIZE(session_roleprivs->array_len);
		session_roleprivs = (SessionRolePrivs *)
			realloc((void *) session_roleprivs, size);
		session_roleprivs->array_len += CONTEXT_ROLEPRIVS_INCREMENT;
		for (i = session_roleprivs->array_len - CONTEXT_ROLEPRIVS_INCREMENT;
			 i < session_roleprivs->array_len; i++)
		{
			session_roleprivs->context_roleprivs[i].privileges = NULL;
		}
	}
	else {
		session_roleprivs = (SessionRolePrivs *)
			calloc(1, CONTEXT_ROLEPRIVS_SIZE(0));
		session_roleprivs->array_len = CONTEXT_ROLEPRIVS_INCREMENT;
	}
	if (!session_roleprivs) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("Unable to create session memory in "
						"extendSessionPrivs()")));
	}
	return session_roleprivs;
}


/**
 * Add a ContextPrivs entry to ::session_privs, from the parameters.
 *
 * @param scope_type The scope_type for the new entry
 * @param the scope scope for the new entry
 * @param roles The roles Bitmap for the new entry
 * @param privs The privileges Bitmap for the new entry
 */
static void
add_scope_roleprivs(int scope_type, int scope, Bitmap *roles, Bitmap *privs)
{
	MemoryContext old_context;
	int idx;
	
	if (!session_roleprivs) {
		session_roleprivs = extendSessionRolePrivs(NULL);
	}
	else if (session_roleprivs->active_contexts >=
			 session_roleprivs->array_len) {
		session_roleprivs = extendSessionRolePrivs(session_roleprivs);
	}
	idx = session_roleprivs->active_contexts;
	session_roleprivs->active_contexts++;
	session_roleprivs->context_roleprivs[idx].scope_type = scope_type;
	session_roleprivs->context_roleprivs[idx].scope = scope;

	/* We copy the bitmaps in TopMemoryContext so they won't be
	 * cleaned-up as transactions come and go. */
	
	old_context = MemoryContextSwitchTo(TopMemoryContext);
	session_roleprivs->context_roleprivs[idx].roles = bitmapCopy(roles);
	session_roleprivs->context_roleprivs[idx].privileges = bitmapCopy(privs);
	MemoryContextSwitchTo(old_context);
}

/**
 * Update a ContextPrivs entry in ::session_privs with new roles and
 * privs.  If there is no matching entry, we do nothing.
 *
 * @param scope_type The scope_type for the entry to be updated.
 * @param the scope scope for the entry to be updated.
 * @param roles The new roles Bitmap for the entry
 * @param privs The new privileges Bitmap for the entry
 */
static void
update_scope_roleprivs(int scope_type, int scope, Bitmap *roles, Bitmap *privs)
{
	int idx;
	MemoryContext old_context;

	findContext(&idx, scope_type, scope);
	if (idx == -1) {
		/* PK fields do not match an existing record, so the update
		 * does nothing. */
		return;
	}
	old_context = MemoryContextSwitchTo(TopMemoryContext);
	freeContextRolePrivs(&session_roleprivs->context_roleprivs[idx]);
	session_roleprivs->context_roleprivs[idx].roles = bitmapCopy(roles);
	session_roleprivs->context_roleprivs[idx].privileges = bitmapCopy(privs);
	MemoryContextSwitchTo(old_context);
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
 * Create a temporary table used for handling privileges in become_user.
 * Originally, more temp tables were used but these have been replaced
 * by in memory structures for performance and security.
 */
static void
create_temp_tables()
{
	(void) veil2_query(
		"create temporary table veil2_ancestor_privileges"
		"    of veil2.session_privileges_t",
		0, NULL, NULL,
		false, NULL,
		NULL, NULL);
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
		" where c.relname = 'veil2_ancestor_privileges'"
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
			/* We have no temp table, so let's create it. */
			create_temp_tables();
			session_ready = true;
		}
		else if (my_tup.f1 == 1) {
			/* We have the expected temp tables - check that access
			 * is properly limited. */
			if (my_tup.f2 != 1) {
				ereport(ERROR,
						(errcode(ERRCODE_INTERNAL_ERROR),
						 errmsg("Unexpected access to temp table in "
								"veil2_reset_session"),
						 errdetail("This indicates an attempt to bypass "
								   "VPD security!")));
			}
			/* Access to temp tables looks kosher.  Truncate the
			 * tables. */
			if (clear_context) {
				session_context.loaded = false;
			}
			clear_session_roleprivs();
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

	veil2_spi_connect(&pushed, "failed to reset session privs (1)");
	do_reset_session(false);
	veil2_spi_finish(pushed, "failed to reset session privs (2)");
 	PG_RETURN_VOID();
}

/** 
 * <code>veil2.session_context(<optional variables>)</code> 
 *
 * Optionally set (if variables are provided), and return the session
 * context.
 *
 * @return record
 */
Datum
veil2_session_context(PG_FUNCTION_ARGS)
{
	Datum results[9];
	static bool allnulls[9] = {true, true, true, true,
							   true, true, true, true, true};
	static bool nonulls[9] = {false, false, false, false,
							  false, false, false, false, false};
	bool *nulls;
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
	
	if (!PG_ARGISNULL(0)) {
		session_context.accessor_id = PG_GETARG_INT32(0);
		session_context.session_id = PG_GETARG_INT64(1);
		session_context.login_context_type_id = PG_GETARG_INT32(2);
		session_context.login_context_id = PG_GETARG_INT32(3);
		session_context.session_context_type_id = PG_GETARG_INT32(4);
		session_context.session_context_id = PG_GETARG_INT32(5);
		session_context.mapping_context_type_id = PG_GETARG_INT32(6);
		session_context.mapping_context_id = PG_GETARG_INT32(7);
		if (PG_ARGISNULL(8)) {
			session_context.parent_session_id = session_context.session_id;
		}
		else {
			session_context.parent_session_id = PG_GETARG_INT64(8);
		}
		session_context.loaded = true;
	}
	if (session_context.loaded) {
		results[0] = Int32GetDatum(session_context.accessor_id);
		results[1] = Int64GetDatum(session_context.session_id);
		results[2] = Int32GetDatum(session_context.login_context_type_id);
		results[3] = Int32GetDatum(session_context.login_context_id);
		results[4] = Int32GetDatum(session_context.session_context_type_id);
		results[5] = Int32GetDatum(session_context.session_context_id);
		results[6] = Int32GetDatum(session_context.mapping_context_type_id);
		results[7] = Int32GetDatum(session_context.mapping_context_id);
		nulls = nonulls;
		if (session_context.parent_session_id ==
			session_context.session_id)
		{
			nulls[8] = true;
		}
		else {
			results[8] = Int64GetDatum(session_context.parent_session_id);
			nulls[8] = false;
		}
	}
	else {
		nulls = allnulls;
	}
	tuple = heap_form_tuple(tuple_desc, results, nulls);
	tuple_desc = BlessTupleDesc(tuple_desc);
	return HeapTupleGetDatum(tuple);
}


/** 
 * <code>veil2.session_privileges()</code> 
 *
 * Return the current in-memory session_privileges as though they were
 * a SQL table.
 *
 * @return setof record
 */
Datum
veil2_session_privileges(PG_FUNCTION_ARGS)
{
    FuncCallContext *funcctx;
    AttInMetadata *attinmeta;
	MemoryContext oldcontext;
    TupleDesc tupdesc;
	long idx;
	bool nulls[4] = {false, false, false, false};
	
    if (SRF_IS_FIRSTCALL()) {
		funcctx = SRF_FIRSTCALL_INIT();
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

        tupdesc = RelationNameGetTupleDesc("veil2.session_privileges_t");
        funcctx->tuple_desc = tupdesc;
        attinmeta = TupleDescGetAttInMetadata(tupdesc);
        funcctx->attinmeta = attinmeta;

        MemoryContextSwitchTo(oldcontext);
		/* We use the user function context to store an index into
 		 * session_roleprivs. */
		funcctx->user_fctx = (void *) 0;
	}
	
	funcctx = SRF_PERCALL_SETUP();
	idx = (long) funcctx->user_fctx;

	if (session_roleprivs &&
		(idx < session_roleprivs->active_contexts)) {
		Datum results[4];
		HeapTuple tuple;
		Datum datum;
		Bitmap *bitmap;
		results[0] = Int32GetDatum(session_roleprivs->
								   context_roleprivs[idx].scope_type);
		results[1] = Int32GetDatum(session_roleprivs->
								   context_roleprivs[idx].scope);
		bitmap = session_roleprivs->context_roleprivs[idx].roles;
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
		if (bitmap) {
			results[2] = (Datum) bitmapCopy(bitmap);
		}
		else {
			nulls[2] = true;
		}
		bitmap = session_roleprivs->context_roleprivs[idx].privileges;
		if (bitmap) {
			results[3] = (Datum) bitmapCopy(bitmap);
		}
		else {
			nulls[3] = true;
		}
        MemoryContextSwitchTo(oldcontext);
        tupdesc = funcctx->tuple_desc;
		tuple = heap_form_tuple(tupdesc, results, nulls);
		tupdesc = BlessTupleDesc(tupdesc);
        datum = TupleGetDatum(tupdesc, tuple);
		funcctx->user_fctx = (void *) (idx + 1);
        SRF_RETURN_NEXT(funcctx, datum);
	}
	else {
		SRF_RETURN_DONE(funcctx);
	}
}

/** 
 * <code>veil2.add_session_privileges(scope_type_id, scope_id,
 *                              roles, privileges)</code> 
 *
 * Create a new in-memory session_privileges record.  Note that this
 * *must* be called with records ordered by scope_type_id, and
 * scope_id.  This is because we use a binary search to match the
 * relevant scope when "querying" this structure internally.
 * @param integer scope_type_id The type of scope
 * @param integer scope_id The id of the actual scope
 * @param Bitmap roles The roles assigned in the context for this scope
 * @param Bitmap privs The privileges that apply in this scope
 * @return void
 */
Datum veil2_add_session_privileges(PG_FUNCTION_ARGS)
{
	int scope_type_id = PG_GETARG_INT32(0);
	int scope_id = PG_GETARG_INT32(1);
	Bitmap *roles = PG_GETARG_BITMAP(2);
	Bitmap *privs = PG_GETARG_BITMAP(3);

	add_scope_roleprivs(scope_type_id, scope_id, roles, privs);
	PG_RETURN_VOID();
}


/** 
 * <code>veil2.update_session_privileges(scope_type_id, scope_id,
 *                                 roles, privileges)</code> 
 *
 * Update an in-memory session_privileges record, with new roles and
 * prvs bitmaps.
 * @param integer scope_type_id The type of scope
 * @param integer scope_id The id of the actual scope
 * @param Bitmap roles The roles assigned in the context for this scope
 * @param Bitmap privs The privileges that apply in this scope
 * @return void
 */
Datum veil2_update_session_privileges(PG_FUNCTION_ARGS)
{
	int scope_type_id = PG_GETARG_INT32(0);
	int scope_id = PG_GETARG_INT32(1);
	Bitmap *roles = PG_GETARG_BITMAP(2);
	Bitmap *privs = PG_GETARG_BITMAP(3);

	update_scope_roleprivs(scope_type_id, scope_id, roles, privs);
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
			" inner join veil2.session_privileges() sp"
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
				" inner join veil2.session_privileges() sp"
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
				" inner join veil2.session_privileges() sp"
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


/** 
 * Provide the veil2 version as a string.
 * 
 * @return Text value containing the version.
 */
Datum
veil2_version(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(textfromstr(VEIL2_VERSION));
}


