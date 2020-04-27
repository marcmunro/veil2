\set QUIET
\set ON_ERROR_STOP

\echo Creating VPD database
create database vpd;


\c vpd

comment on database vpd is 'Database for baseline VPD implementation.';


\echo creating extensions...
\echo ...extension pgcrypto...
create extension pgcrypto;

\echo ...extension bitmap...
create extension pgbitmap;

\echo creating schemata...
\i sql/veil2.sql


\echo
\echo VPD database created successfully
\echo
