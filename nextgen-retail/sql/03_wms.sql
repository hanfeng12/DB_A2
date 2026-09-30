-- Warehouse stock distinguishes on-hand from reserved; comparisons use available stock.
BEGIN;
CREATE SCHEMA IF NOT EXISTS operational;
CREATE TABLE IF NOT EXISTS operational.product (
 product_id integer PRIMARY KEY, sku text NOT NULL UNIQUE,
 product_name text NOT NULL, category text,
 list_price numeric(12,2) NOT NULL CHECK (list_price >= 0)
);
CREATE TABLE IF NOT EXISTS operational.warehouse (
 warehouse_id integer PRIMARY KEY, warehouse_name text NOT NULL, city text NOT NULL,
 online_fulfilment boolean NOT NULL DEFAULT true
);
CREATE TABLE IF NOT EXISTS operational.inventory (
 product_id integer NOT NULL REFERENCES operational.product,
 warehouse_id integer NOT NULL REFERENCES operational.warehouse,
 quantity_on_hand integer NOT NULL CHECK(quantity_on_hand>=0),
 reserved_quantity integer NOT NULL CHECK(reserved_quantity BETWEEN 0 AND quantity_on_hand),
 snapshot_date date NOT NULL, PRIMARY KEY(product_id,warehouse_id,snapshot_date)
);
CREATE TABLE IF NOT EXISTS operational.transfer (
 transfer_id integer PRIMARY KEY, product_id integer NOT NULL REFERENCES operational.product,
 warehouse_id integer NOT NULL REFERENCES operational.warehouse,
 destination_store_id integer NOT NULL, quantity integer NOT NULL CHECK(quantity>0),
 transfer_status text NOT NULL CHECK(transfer_status IN ('Pending','In Transit','Completed','Cancelled')),
 dispatched_at timestamp NOT NULL, expected_date date NOT NULL, completed_at timestamp,
 CHECK((transfer_status='Completed')=(completed_at IS NOT NULL)),
 CHECK(expected_date>=dispatched_at::date), CHECK(completed_at IS NULL OR completed_at>=dispatched_at)
);
COMMIT;
