-- E-commerce uses unrelated product IDs and inconsistent SKU/category formatting.
BEGIN;
CREATE SCHEMA IF NOT EXISTS operational;
CREATE TABLE IF NOT EXISTS operational.product (
 product_id integer PRIMARY KEY, sku text NOT NULL UNIQUE,
 product_name text NOT NULL, category text,
 list_price numeric(12,2) NOT NULL CHECK (list_price >= 0)
);
CREATE TABLE IF NOT EXISTS operational.customer_order (
 order_id integer PRIMARY KEY, ordered_at timestamp NOT NULL, customer_region text NOT NULL,
 order_status text NOT NULL CHECK(order_status IN ('Completed','Cancelled','Pending'))
);
CREATE TABLE IF NOT EXISTS operational.order_item (
 line_id integer PRIMARY KEY, order_id integer NOT NULL REFERENCES operational.customer_order,
 product_id integer NOT NULL REFERENCES operational.product,
 quantity integer NOT NULL CHECK(quantity>0), unit_price numeric(12,2) NOT NULL CHECK(unit_price>=0)
);
-- Stock advertised online is for the shared online fulfilment pool, not all stores.
CREATE TABLE IF NOT EXISTS operational.online_stock (
 product_id integer PRIMARY KEY REFERENCES operational.product,
 available_quantity integer CHECK(available_quantity>=0), snapshot_date date NOT NULL
);
COMMIT;
