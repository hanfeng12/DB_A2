-- Conformed dimensions and facts; source identifiers preserve lineage.
BEGIN;
CREATE SCHEMA IF NOT EXISTS dw;
CREATE SCHEMA IF NOT EXISTS etl;
CREATE SCHEMA IF NOT EXISTS reporting;
CREATE TABLE IF NOT EXISTS etl.batch (
 batch_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 started_at timestamptz NOT NULL DEFAULT clock_timestamp(), finished_at timestamptz,
 snapshot_date date NOT NULL, product_count integer, sales_count integer, inventory_count integer, transfer_count integer
);
CREATE TABLE IF NOT EXISTS dw.dim_product (
 product_key integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, sku text NOT NULL UNIQUE,
 product_name text NOT NULL, category text NOT NULL
);
CREATE TABLE IF NOT EXISTS dw.product_xref (
 source_system text NOT NULL, source_product_id integer NOT NULL,
 product_key integer NOT NULL REFERENCES dw.dim_product, raw_sku text NOT NULL,
 PRIMARY KEY(source_system,source_product_id)
);
CREATE TABLE IF NOT EXISTS dw.dim_date (
 date_key integer PRIMARY KEY, full_date date NOT NULL UNIQUE,
 year integer NOT NULL, month integer NOT NULL, quarter integer NOT NULL, day integer NOT NULL
);
CREATE TABLE IF NOT EXISTS dw.dim_channel (
 channel_key integer PRIMARY KEY, channel_name text NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS dw.dim_location (
 location_key integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, location_code text NOT NULL UNIQUE,
 location_name text NOT NULL, location_type text NOT NULL, city text NOT NULL, online_fulfilment boolean NOT NULL DEFAULT false
);
ALTER TABLE dw.dim_location ADD COLUMN IF NOT EXISTS online_fulfilment boolean NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS dw.fact_sales (
 sales_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 source_system text NOT NULL, source_line_id integer NOT NULL,
 product_key integer NOT NULL REFERENCES dw.dim_product, date_key integer NOT NULL REFERENCES dw.dim_date,
 channel_key integer NOT NULL REFERENCES dw.dim_channel, location_key integer NOT NULL REFERENCES dw.dim_location,
 quantity integer NOT NULL CHECK(quantity>0), unit_price numeric(12,2) NOT NULL CHECK(unit_price>=0),
 sales_amount numeric(14,2) GENERATED ALWAYS AS (quantity*unit_price) STORED,
 batch_id bigint NOT NULL REFERENCES etl.batch, UNIQUE(source_system,source_line_id)
);
CREATE TABLE IF NOT EXISTS dw.fact_price (
 product_key integer NOT NULL REFERENCES dw.dim_product, date_key integer NOT NULL REFERENCES dw.dim_date,
 channel_key integer NOT NULL REFERENCES dw.dim_channel, list_price numeric(12,2) NOT NULL CHECK(list_price>=0),
 batch_id bigint NOT NULL REFERENCES etl.batch, PRIMARY KEY(product_key,date_key,channel_key)
);
CREATE TABLE IF NOT EXISTS dw.fact_inventory (
 product_key integer NOT NULL REFERENCES dw.dim_product, date_key integer NOT NULL REFERENCES dw.dim_date,
 channel_key integer NOT NULL REFERENCES dw.dim_channel, location_key integer NOT NULL REFERENCES dw.dim_location,
 available_quantity integer CHECK(available_quantity>=0), batch_id bigint NOT NULL REFERENCES etl.batch,
 PRIMARY KEY(product_key,date_key,channel_key,location_key)
);
CREATE TABLE IF NOT EXISTS dw.fact_transfer (
 transfer_id integer PRIMARY KEY, product_key integer NOT NULL REFERENCES dw.dim_product,
 date_key integer NOT NULL REFERENCES dw.dim_date,
 source_location_key integer NOT NULL REFERENCES dw.dim_location,
 destination_location_key integer NOT NULL REFERENCES dw.dim_location,
 quantity integer NOT NULL CHECK(quantity>0), transfer_status text NOT NULL,
 dispatched_at timestamp NOT NULL, expected_date date NOT NULL, completed_at timestamp,
 received_quantity integer, received_at timestamp, receipt_matches boolean,
 batch_id bigint NOT NULL REFERENCES etl.batch
);
CREATE INDEX IF NOT EXISTS ix_sales_date_channel ON dw.fact_sales(date_key,channel_key);
CREATE INDEX IF NOT EXISTS ix_transfer_status ON dw.fact_transfer(transfer_status,expected_date);
COMMIT;
