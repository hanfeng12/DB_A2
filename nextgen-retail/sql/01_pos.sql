-- POS operational model: one sale has many lines; receipts acknowledge WMS transfers.
BEGIN;
CREATE SCHEMA IF NOT EXISTS operational;
CREATE TABLE IF NOT EXISTS operational.product (
 product_id integer PRIMARY KEY, sku text NOT NULL UNIQUE,
 product_name text NOT NULL, category text,
 list_price numeric(12,2) NOT NULL CHECK (list_price >= 0)
);
CREATE TABLE IF NOT EXISTS operational.store (
 store_id integer PRIMARY KEY, store_name text NOT NULL, city text NOT NULL, state text NOT NULL
);
CREATE TABLE IF NOT EXISTS operational.sale (
 sale_id integer PRIMARY KEY, store_id integer NOT NULL REFERENCES operational.store,
 sold_at timestamp NOT NULL, total_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK(total_amount>=0)
);
CREATE TABLE IF NOT EXISTS operational.sale_item (
 line_id integer PRIMARY KEY, sale_id integer NOT NULL REFERENCES operational.sale,
 product_id integer NOT NULL REFERENCES operational.product,
 quantity integer NOT NULL CHECK(quantity>0), unit_price numeric(12,2) NOT NULL CHECK(unit_price>=0)
);
CREATE TABLE IF NOT EXISTS operational.transfer_receipt (
 transfer_id integer PRIMARY KEY, store_id integer NOT NULL REFERENCES operational.store,
 product_id integer NOT NULL REFERENCES operational.product, received_quantity integer NOT NULL CHECK(received_quantity>=0),
 received_at timestamp NOT NULL
);
COMMIT;
