/**
 * A Fetch_fn is a function that processes records, one at a time,
 * returned from a query.
 */
typedef bool (Fetch_fn)(HeapTuple, TupleDesc, void *);



typedef struct {
	int f1;
	int f2;
} tuple_2ints;



/* query.c */
extern int veil2_spi_connect(bool *p_pushed);
extern int veil2_spi_finish(bool pushed);
extern int veil2_spi_finish(bool pushed);
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
Datum veil2_ok(PG_FUNCTION_ARGS);
Datum veil2_reset_session(PG_FUNCTION_ARGS);
Datum veil2_i_have_global_priv(PG_FUNCTION_ARGS);
Datum veil2_i_have_personal_priv(PG_FUNCTION_ARGS);
Datum veil2_i_have_priv_in_scope(PG_FUNCTION_ARGS);
Datum veil2_i_have_priv_in_superior_scope(PG_FUNCTION_ARGS);

