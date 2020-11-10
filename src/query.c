/**
 * @file   query.c
 * \code
 *     Author:       Marc Munro
 *     Copyright (c) 2020 Marc Munro
 *     License:      GPL V3
 * 
 * \endcode
 * @brief  
 * Functions to simplify SPI-based queries.
 * 
 */


#include <stdio.h>
#include "postgres.h"
#include "catalog/pg_type.h"
#include "executor/spi.h"
#include "access/xact.h"
#include "veil2.h"


/**
 * If already connected in this session, push the current connection,
 * and get a new one.
 * We are already connected, if:
 * - are within a query
 * - and the current transaction id matches the saved transaction id
 * @param p_pushed Pointer to a boolean into which we will record
 * whether we have saved a presiously active SPI connection.  This
 * allows recursive queries, which is probably overkill for our needs,
 * but since the overhead is low...
 * @result integer giving an SPI error code or success.
 */
int
veil2_spi_connect(bool *p_pushed)
{
	int result = SPI_connect();
	if (result == SPI_ERROR_CONNECT) {
		SPI_push();
		*p_pushed = true;
		return SPI_connect();
	}
	*p_pushed = false;
	return result;
}

/**
 * Reciprocal function for veil2_spi_connect()
 * @param pushed  Boolean as set up by veil2_spi_connect().  This
 * tells us whether to revert to a previously active SPI connection. 
 * @result integer giving an SPI error code or success.
 */
int
veil2_spi_finish(bool pushed)
{
	int spi_result = SPI_finish();
	if (pushed) {
		SPI_pop();
	}
	return spi_result;
}

/** 
 * Prepare a query for veil2_query().  This creates and executes a
 * plan.  The caller must have established an SPI connection.  It is
 * assumed that no parameters to the query will be null.
 * @param qry The text of the SQL query to be performed.
 * @param nargs The number of input parameters ($1, $2, etc) to the query
 * @param argtypes Pointer to an array containing the OIDs of the data
 * @param args Actual parameters
 * types of the parameters 
 * @param read_only Whether the query should be read-only or not
 * @param saved_plan Adress of void pointer into which the query plan
 * will be saved.  Passing the same void pointer on a subsequent call
 * will cause the saved query plan to be re-used.  This may be NULL,
 * in which case the query plan will not be saved.
 */
static void
prepare_query(const char *qry,
			  int nargs,
			  Oid *argtypes,
			  Datum *args,
			  bool read_only,
			  void **saved_plan)
{
    void   *plan;
    int     exec_result;
	
    if (saved_plan && *saved_plan) {
		/* A previously prepared plan is available, so use it */
		plan = *saved_plan;
    }
    else {
		if (!(plan = SPI_prepare(qry, nargs, argtypes))) {
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("prepare_query fails"),
					 errdetail("SPI_prepare('%s') returns NULL "
							   "(SPI_result = %d)", 
							   qry, SPI_result)));
		}

		if (saved_plan) {
			/* We have somewhere to put the saved plan, so save  it. */
			*saved_plan = SPI_saveplan(plan);
		}
    }
	
	exec_result = SPI_execute_plan(plan, args, NULL, read_only, 0);
	if (exec_result < 0) {
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("prepare_query fails"),
				 errdetail("SPI_execute_plan('%s') returns error %d",
						   qry, exec_result)));
    }
}

/** 
 * Execute a query and process the results.
 * @param qry The text of the SQL query to be performed.
 * @param nargs The number of input parameters ($1, $2, etc) to the query
 * @param argtypes Pointer to an array containing the OIDs of the data
 * @param args Actual parameters types of the parameters 
 * @param read_only Whether the query should be read-only or not.
 * @param saved_plan Adress of void pointer into which the query plan
 * will be saved.  Passing the same void pointer on a subsequent call
 * will cause the saved query plan to be re-used.  This may be NULL,
 * in which case the query plan will not be saved.
 * @param process_row  A Fetch_fn() to process each tuple retruned by
 * the query.
 * @param fn_param  A parameter to pass to process_row.
 */
int
veil2_query(const char *qry,
			int nargs,
			Oid *argtypes,
			Datum *args,
			bool  read_only,
			void **saved_plan,
			Fetch_fn process_row,
			void *fn_param)
{
    int  row;
	int  fetched;
	int  processed = 0;
	bool cntinue;
	SPITupleTable *tuptab;

    prepare_query(qry, nargs, argtypes, args, read_only, saved_plan);
	fetched = SPI_processed;
	tuptab = SPI_tuptable;
	if (process_row) {
		for(row = 0; row < fetched; row++) {
			processed++;
			/* Process a row using the processor function */
			cntinue = process_row(tuptab->vals[row], 
								  tuptab->tupdesc,
								  fn_param);
			if (!cntinue) {
				break;
			}
		}
	}
    return processed;
}

/** 
 * ::Fetch_fn function for processing a single row of a single integer for 
 * ::query.
 * \param tuple The row to be processed
 * \param tupdesc Descriptor for the types of the fields in the tuple.
 * \param p_result Pointer to an int4 variable into which the value
 * returned from the query will be placed.
 * \return false.  This causes ::query to terminate after processing a
 * single row.
 */
static bool
fetch_one_bool(HeapTuple tuple, TupleDesc tupdesc, void *p_result)
{
	static bool ignore_this = false;
    bool col = DatumGetBool(SPI_getbinval(tuple, tupdesc, 1, &ignore_this));
    *((bool *) p_result) = col;
	
    return false;
}

/** 
 * Executes a query that returns a single bool value.
 * 
 * @param qry The text of the query to be performed.
 * @param result Variable into which the result of the query will be placed.
 * 
 * @return true if the query returned a record, false otherwise.
 */
bool
veil2_bool_from_query(const char *qry,
					  int nargs,
					  Oid *argtypes,
					  Datum *args,
					  void **saved_plan,
					  bool *result)
{
	int     rows;
	rows = veil2_query(qry, nargs, argtypes, args, false, saved_plan, 
					   fetch_one_bool, (void *) result);
	return (rows > 0);
}

