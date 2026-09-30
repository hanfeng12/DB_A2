-- Run with psql inside the provided PostgreSQL container.
-- Password comes from the container environment and is never committed to source.
\getenv source_password POSTGRES_PASSWORD
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE SCHEMA IF NOT EXISTS src_pos;
CREATE SCHEMA IF NOT EXISTS src_ecom;
CREATE SCHEMA IF NOT EXISTS src_wms;
CREATE SERVER IF NOT EXISTS nextgen_pos_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS(host '127.0.0.1',dbname 'nextgen_pos',port '5432', updatable 'false');
CREATE SERVER IF NOT EXISTS nextgen_ecom_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS(host '127.0.0.1',dbname 'nextgen_ecom',port '5432', updatable 'false');
CREATE SERVER IF NOT EXISTS nextgen_wms_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS(host '127.0.0.1',dbname 'nextgen_wms',port '5432', updatable 'false');
CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER SERVER nextgen_pos_server OPTIONS(user 'student',password :'source_password');
CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER SERVER nextgen_ecom_server OPTIONS(user 'student',password :'source_password');
CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER SERVER nextgen_wms_server OPTIONS(user 'student',password :'source_password');
-- Import each source only once; this script does not drop existing objects.
SELECT 'IMPORT FOREIGN SCHEMA operational FROM SERVER '||quote_ident(s)||' INTO '||quote_ident(n)
FROM (VALUES('nextgen_pos_server','src_pos'),('nextgen_ecom_server','src_ecom'),('nextgen_wms_server','src_wms'))v(s,n)
WHERE NOT EXISTS(SELECT FROM pg_class c JOIN pg_namespace ns ON c.relnamespace=ns.oid WHERE ns.nspname=n AND c.relkind='f')
\gexec
