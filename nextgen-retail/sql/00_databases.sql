-- Run with psql against lab; CREATE DATABASE cannot run inside a transaction.
-- Dedicated databases leave existing coursework in lab untouched.
SELECT 'CREATE DATABASE ' || quote_ident(name)
FROM (VALUES ('nextgen_pos'), ('nextgen_ecom'), ('nextgen_wms'), ('nextgen_dw')) AS d(name)
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = name)
\gexec
