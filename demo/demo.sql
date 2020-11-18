/* ----------
 * demo.sql
 *
 *      Create and test the veil2 demo database,
 *
 *      Copyright (c) 2020 Marc Munro
 *      Author:  Marc Munro
 *	License: GPL V3
 *
 * ----------
 */

create extension if not exists veil2_demo cascade;

select * from veil2.implementation_status();
select veil2.init();

\ir demo_test.sql

