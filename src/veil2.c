/**
 * @file   veil2.c
 * \code
 *     Author:       Marc Munro
 *     Copyright (c) 2020 Marc Munro
 *     License:      GPL V3
 * 
 * \endcode
 * @brief  
 * Callable veil2 functions.  These are written in C to ensure that
 * they cannot be easily subverted.  Performance is a secondary
 * concern.
 * 
 */

#include "postgres.h"
#include "catalog/pg_type.h"
#include "access/xact.h"
#include "executor/spi.h"
#include "veil2.h"



PG_MODULE_MAGIC;

/**
 * Used to record whether the current session's temporary tables have
 * been properly initialised.  If not the privilege testing functions
 * will always return false.
 */
static bool is_ok = false;

PG_FUNCTION_INFO_V1(veil2_ok);
/** 
 * <code>veil2_ok() returns bool</code>
 * Predicate to indicate whether the current session has been properly
 * set up.
 * 
 * @return <code>bool</code> true if this session has been set up.
 */
Datum
veil2_ok(PG_FUNCTION_ARGS)
{

    PG_RETURN_BOOL(is_ok);
}

static bool
fetch_2ints(HeapTuple tuple, TupleDesc tupdesc, void *p_result)
{
	static bool ignore_this = false;
	tuple_2ints *my_tup = (tuple_2ints *) p_result;
    my_tup->f1 = DatumGetInt32(SPI_getbinval(tuple, tupdesc, 1, &ignore_this));
    my_tup->f2 = DatumGetInt32(SPI_getbinval(tuple, tupdesc, 2, &ignore_this));

	return false;  // No need to continue processing after this
}

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
		"create temporary table veil2_session_parameters"
		"    of veil2.session_params_t",
		0, NULL, NULL,
		false, NULL,
		NULL, NULL);
}

static void
truncate_temp_tables()
{
	(void) veil2_query(
		"truncate table veil2_session_privileges",
		0, NULL, NULL,
		false, 	NULL,
		NULL, NULL);
	(void) veil2_query(
		"truncate table veil2_session_parameters",
		0, NULL, NULL,
		false, 	NULL,
		NULL, NULL);
}

PG_FUNCTION_INFO_V1(veil2_reset_session);
Datum
veil2_reset_session(PG_FUNCTION_ARGS)
{
	tuple_2ints my_tup;
	int ok;
	int processed;
	bool pushed;
	
	ok = veil2_spi_connect(&pushed);
	if (ok != SPI_OK_CONNECT) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("failed to reset session (1)"),
				 errdetail("SPI_connect() failed, returning %d.", ok)));
	}

	processed = veil2_query(
		"select count(*)::integer,"
		"       sum(case when c.relacl is null then 1 else 0 end)"
		"  from pg_catalog.pg_class c"
		" where c.relname in ('veil2_session_privileges',"
		"                     'veil2_session_parameters',"
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
			is_ok = true;
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
			is_ok = true;
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

	ok = veil2_spi_finish(pushed);
	if (ok != SPI_OK_FINISH) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("failed to reset session (2)"),
				 errdetail("SPI_finish() failed, returning %d.", ok)));
	}
	
    PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(veil2_i_have_global_priv);
Datum
veil2_i_have_global_priv(PG_FUNCTION_ARGS)
{
	static void *saved_plan = NULL;
	bool result;
	bool found;
	int ok;
	bool pushed;
	int priv = PG_GETARG_INT32(0);
	Oid argtypes[] = {INT4OID};
	Datum args[] = {Int32GetDatum(priv)};
	
	ok = veil2_spi_connect(&pushed);
	if (ok != SPI_OK_CONNECT) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("SPI connect failed in veil2_i_have_global_priv()"),
				 errdetail("SPI_connect() failed, returning %d.", ok)));
	}

	if (is_ok) {
		found = veil2_bool_from_query(
			"select coalesce("
			" (select privs ? $1"
			"    from veil2_session_privileges v"
			"   where v.scope_type_id = 1), false)",
			1, argtypes, args,
			&saved_plan, &result);

		ok = veil2_spi_finish(pushed);
		if (ok != SPI_OK_FINISH) {
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("SPI finish failed in veil2_i_have_global_priv()"),
					 errdetail("SPI_finish() failed, returning %d.", ok)));
		}
		return found && result;
	}
	ereport(ERROR,
			(errcode(ERRCODE_INTERNAL_ERROR),
			 errmsg("Attempt to check privileges before call to  "
					"veil2_reset_session.")));
	return false;
}


PG_FUNCTION_INFO_V1(veil2_i_have_personal_priv);
Datum
veil2_i_have_personal_priv(PG_FUNCTION_ARGS)
{
	static void *saved_plan = NULL;
	bool result;
	bool found;
	int ok;
	bool pushed;
	int priv = PG_GETARG_INT32(0);
	int accessor_id = PG_GETARG_INT32(1);
	Oid argtypes[] = {INT4OID, INT4OID};
	Datum args[] = {Int32GetDatum(priv), Int32GetDatum(accessor_id)};
	
	ok = veil2_spi_connect(&pushed);
	if (ok != SPI_OK_CONNECT) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("SPI connect failed in veil2_i_have_personal_priv()"),
				 errdetail("SPI_connect() failed, returning %d.", ok)));
	}

	if (is_ok) {
		found = veil2_bool_from_query(
			"select coalesce("
			" (select privs ? $1"
			"    from veil2_session_privileges v"
			"   where v.scope_type_id = 2"
			"     and v.scope_id = $2), false)",
			2, argtypes, args,
			&saved_plan, &result);

		ok = veil2_spi_finish(pushed);
		if (ok != SPI_OK_FINISH) {
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("SPI finish failed in veil2_i_have_personal_priv()"),
					 errdetail("SPI_finish() failed, returning %d.", ok)));
		}
		return found && result;
	}
	ereport(ERROR,
			(errcode(ERRCODE_INTERNAL_ERROR),
			 errmsg("Attempt to check privileges before call to  "
					"veil2_reset_session.")));
	return false;
}


PG_FUNCTION_INFO_V1(veil2_i_have_priv_in_scope);
Datum veil2_i_have_priv_in_scope(PG_FUNCTION_ARGS)
{
	static void *saved_plan = NULL;
	bool result;
	bool found;
	int ok;
	bool pushed;
	int priv = PG_GETARG_INT32(0);
	int scope_type_id = PG_GETARG_INT32(1);
	int scope_id = PG_GETARG_INT32(2);
	Oid argtypes[] = {INT4OID, INT4OID, INT4OID};
	Datum args[] = {Int32GetDatum(priv),
					Int32GetDatum(scope_type_id),
					Int32GetDatum(scope_id)};
	
	ok = veil2_spi_connect(&pushed);
	if (ok != SPI_OK_CONNECT) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("SPI connect failed in veil2_i_have_priv_in_scope()"),
				 errdetail("SPI_connect() failed, returning %d.", ok)));
	}

	if (is_ok) {
		found = veil2_bool_from_query(
			"select coalesce("
			" (select privs ? $1"
			"    from veil2_session_privileges v"
			"   where v.scope_type_id = $2"
			"     and v.scope_id = $3), false)",
			3, argtypes, args,
			&saved_plan, &result);

		ok = veil2_spi_finish(pushed);
		if (ok != SPI_OK_FINISH) {
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("SPI finish failed in "
							"veil2_i_have_priv_in_scope()"),
					 errdetail("SPI_finish() failed, returning %d.", ok)));
		}
		return found && result;
	}
	ereport(ERROR,
			(errcode(ERRCODE_INTERNAL_ERROR),
			 errmsg("Attempt to check privileges before call to  "
					"veil2_reset_session.")));
	return false;
}


PG_FUNCTION_INFO_V1(veil2_i_have_priv_in_superior_scope);
Datum veil2_i_have_priv_in_superior_scope(PG_FUNCTION_ARGS)
{
	static void *saved_plan = NULL;
	bool result;
	bool found;
	int ok;
	bool pushed;
	int priv = PG_GETARG_INT32(0);
	int scope_type_id = PG_GETARG_INT32(1);
	int scope_id = PG_GETARG_INT32(2);
	Oid argtypes[] = {INT4OID, INT4OID, INT4OID};
	Datum args[] = {Int32GetDatum(priv),
					Int32GetDatum(scope_type_id),
					Int32GetDatum(scope_id)};
	
	ok = veil2_spi_connect(&pushed);
	if (ok != SPI_OK_CONNECT) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("SPI connect failed in "
						"veil2_i_have_priv_in_superior_scope()"),
				 errdetail("SPI_connect() failed, returning %d.", ok)));
	}

	if (is_ok) {
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

		ok = veil2_spi_finish(pushed);
		if (ok != SPI_OK_FINISH) {
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("SPI finish failed in "
							"veil2_i_have_priv_in_superior_scope()"),
					 errdetail("SPI_finish() failed, returning %d.", ok)));
		}
		return found && result;
	}
	ereport(ERROR,
			(errcode(ERRCODE_INTERNAL_ERROR),
			 errmsg("Attempt to check privileges before call to  "
					"veil2_reset_session.")));
	return false;
}
