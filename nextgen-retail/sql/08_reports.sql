-- R1: like-for-like list prices at a single batch snapshot. Difference = POS minus online.
CREATE OR REPLACE VIEW reporting.price_comparison AS
WITH latest AS (SELECT to_char(snapshot_date,'YYYYMMDD')::integer d FROM etl.batch WHERE finished_at IS NOT NULL ORDER BY batch_id DESC LIMIT 1), prices AS (
 SELECT product_key,max(list_price) FILTER(WHERE channel_key=1) pos_price,
 max(list_price) FILTER(WHERE channel_key=2) online_price
 FROM dw.fact_price,latest WHERE date_key=latest.d GROUP BY product_key)
SELECT p.sku,p.product_name,p.category,q.pos_price,q.online_price,
 q.pos_price-q.online_price difference,
 round(100*(q.pos_price-q.online_price)/nullif(q.pos_price,0),2) difference_pct,
 CASE WHEN q.pos_price IS NULL OR q.online_price IS NULL THEN 'MISSING_PRICE'
 WHEN q.pos_price<>q.online_price THEN 'MISMATCH' ELSE 'MATCH' END status
FROM dw.dim_product p LEFT JOIN prices q USING(product_key);
-- R2: WMS available = on-hand minus reserved, aggregated only for online fulfilment warehouses.
-- Missing feeds, incomplete warehouse coverage and NULL stock never become zero stock.
CREATE OR REPLACE VIEW reporting.inventory_comparison AS
WITH latest AS (SELECT to_char(snapshot_date,'YYYYMMDD')::integer d FROM etl.batch WHERE finished_at IS NOT NULL ORDER BY batch_id DESC LIMIT 1), inv AS (
 SELECT product_key,max(available_quantity) FILTER(WHERE channel_key=2) online_available,
 sum(available_quantity) FILTER(WHERE channel_key=3) warehouse_available,
 count(*) FILTER(WHERE channel_key=3) warehouse_count
 FROM dw.fact_inventory,latest WHERE date_key=latest.d GROUP BY product_key)
SELECT p.sku,p.product_name,q.online_available,q.warehouse_available,
 q.online_available-q.warehouse_available difference,coalesce(q.warehouse_count,0) warehouse_count,
 CASE WHEN q.online_available IS NULL THEN 'UNKNOWN_ONLINE'
 WHEN q.warehouse_available IS NULL THEN 'UNKNOWN_WMS'
 WHEN q.warehouse_count<>(SELECT count(*) FROM dw.dim_location WHERE location_type='WAREHOUSE' AND online_fulfilment) THEN 'INCOMPLETE_WMS'
 WHEN q.online_available<>q.warehouse_available THEN 'MISMATCH' ELSE 'MATCH' END status
FROM dw.dim_product p LEFT JOIN inv q USING(product_key);
-- R3: operational exception, as of fixture/batch date rather than wall-clock date.
CREATE OR REPLACE VIEW reporting.transfer_monitor AS
SELECT t.transfer_id,p.sku,a.location_name source_location,z.location_name destination_location,
 t.quantity,t.transfer_status,t.expected_date,t.received_quantity,
 CASE WHEN t.transfer_status='Cancelled' THEN 'CANCELLED'
 WHEN t.received_at IS NOT NULL AND NOT t.receipt_matches THEN 'RECEIPT_IDENTITY_MISMATCH'
 WHEN t.transfer_status='Completed' AND t.received_at IS NULL THEN 'MISSING_STORE_RECEIPT'
 WHEN t.transfer_status='Completed' AND t.received_quantity<>t.quantity THEN 'QUANTITY_MISMATCH'
 WHEN t.transfer_status='Completed' THEN 'RECONCILED'
 WHEN t.expected_date<b.snapshot_date THEN 'OVERDUE' ELSE 'ON_TRACK' END exception,
 greatest(0,b.snapshot_date-t.expected_date) days_past_due
FROM dw.fact_transfer t JOIN dw.dim_product p USING(product_key)
JOIN dw.dim_location a ON a.location_key=t.source_location_key
JOIN dw.dim_location z ON z.location_key=t.destination_location_key JOIN etl.batch b USING(batch_id);
-- R4: completed sales only, preserving channel and month; revenue uses transaction price.
CREATE OR REPLACE VIEW reporting.sales_by_month AS
SELECT to_char(d.full_date,'YYYY-MM') AS month,c.channel_name channel,
 count(*) line_count,sum(f.quantity) units,sum(f.sales_amount) revenue
FROM dw.fact_sales f JOIN dw.dim_date d USING(date_key) JOIN dw.dim_channel c USING(channel_key)
GROUP BY 1,2;
CREATE OR REPLACE VIEW reporting.sales_by_category AS
SELECT p.category,c.channel_name channel,sum(f.quantity) units,sum(f.sales_amount) revenue
FROM dw.fact_sales f JOIN dw.dim_product p USING(product_key) JOIN dw.dim_channel c USING(channel_key) GROUP BY 1,2;
-- Human-friendly queries for CloudBeaver (connect to nextgen_dw).
-- SELECT * FROM reporting.price_comparison WHERE status <> 'MATCH' ORDER BY abs(difference) DESC;
-- SELECT * FROM reporting.inventory_comparison WHERE status <> 'MATCH' ORDER BY sku;
-- SELECT * FROM reporting.transfer_monitor WHERE exception <> 'RECONCILED' ORDER BY transfer_id;
-- SELECT * FROM reporting.sales_by_month ORDER BY month,channel;
