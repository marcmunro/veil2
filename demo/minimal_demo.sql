/* ----------
 * minimal_demo.sql
 *
 *      A minimal demo of veil2, build using ../sql/veil2_template.sql
 *
 *      Copyright (c) 2020 Marc Munro
 *      Author:  Marc Munro
 *	License: GPL V3
 *
 * ----------
 */

create extension if not exists veil2_minimal_demo cascade;

select * from veil2.implementation_status();

\ir minimal_demo_test.sql
