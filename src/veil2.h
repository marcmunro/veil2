/**
 * @file   veil2.h
 * \code
 *     Author:       Marc Munro
 *     Copyright (c) 2020 Marc Munro
 *     License:      GPL v3
 * 
 * \endcode
 * @brief  
 * Main header file for veil2.
 * 
 */

#include "extension/pgbitmap/pgbitmap.h"
#include "veil2_version.h"

/**
 * A Fetch_fn is a function that processes records, one at a time,
 * returned from a query.
 */
typedef bool (Fetch_fn)(HeapTuple, TupleDesc, void *);


/**
 * This is for queries that return tuples containing a pair of
 * integers.  It is passed as a fn_param value to veil2_query() and
 * processed by a Fetch_fn().
 */
typedef struct {
	/** Unnamed integer field */
	int f1;   
    /** Unnamed, integer field */
	int f2;   
} tuple_2ints;



/* query.c */
extern void veil2_spi_connect(bool *p_pushed, const char *msg);
extern void veil2_spi_finish(bool pushed, const char *msg);
extern int veil2_query_wn(const char *qry,
						  int nargs,
						  Oid *argtypes,
						  Datum *args,
						  const char *nulls,
						  bool  read_only,
						  void **saved_plan,
						  Fetch_fn process_row,
						  void *fn_param);
extern int veil2_query(const char *qry,
					   int nargs,
					   Oid *argtypes,
					   Datum *args,
					   bool  read_only,
					   void **saved_plan,
					   Fetch_fn process_row,
					   void *fn_param);

extern bool veil2_bool_from_query(const char *qry,
								  int nargs,
								  Oid *argtypes,
								  Datum *args,
								  void **saved_plan,
								  bool *result);


/* veil2.c */
Datum veil2_session_ready(PG_FUNCTION_ARGS);
Datum veil2_reset_session(PG_FUNCTION_ARGS);
Datum veil2_reset_session_privs(PG_FUNCTION_ARGS);
Datum veil2_session_context(PG_FUNCTION_ARGS);
Datum veil2_session_privileges(PG_FUNCTION_ARGS);
Datum veil2_add_session_privileges(PG_FUNCTION_ARGS);
Datum veil2_update_session_privileges(PG_FUNCTION_ARGS);
Datum veil2_true(PG_FUNCTION_ARGS);
Datum veil2_i_have_global_priv(PG_FUNCTION_ARGS);
Datum veil2_i_have_personal_priv(PG_FUNCTION_ARGS);
Datum veil2_i_have_priv_in_scope(PG_FUNCTION_ARGS);
Datum veil2_i_have_priv_in_scope_or_global(PG_FUNCTION_ARGS);
Datum veil2_i_have_priv_in_superior_scope(PG_FUNCTION_ARGS);
Datum veil2_i_have_priv_in_scope_or_superior(PG_FUNCTION_ARGS);
Datum veil2_i_have_priv_in_scope_or_superior_or_global(PG_FUNCTION_ARGS);
Datum veil2_result_counts(PG_FUNCTION_ARGS);
Datum veil2_docpath(PG_FUNCTION_ARGS);
Datum veil2_datapath(PG_FUNCTION_ARGS);
Datum veil2_version(PG_FUNCTION_ARGS);


#ifndef DOCS_PATH
#define DOCS_PATH "<path to postgres extension docs>"
#endif

#ifndef DATA_PATH
#define DATA_PATH "<path to postgres extension data files>"
#endif

