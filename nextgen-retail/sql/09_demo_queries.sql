-- Connect CloudBeaver to nextgen_dw. Execute each block separately for a readable demo.
-- 1. Show three real databases, not three renamed tables.
SELECT datname FROM pg_database WHERE datname LIKE 'nextgen_%' ORDER BY datname;
-- 2. Show inconsistent source identifiers that integrate through SKU.
SELECT 'POS' source,product_id,sku,list_price FROM src_pos.product WHERE product_id=101
UNION ALL SELECT 'ONLINE',product_id,sku,list_price FROM src_ecom.product WHERE product_id=1001
UNION ALL SELECT 'WMS',product_id,sku,list_price FROM src_wms.product WHERE product_id=2001;
-- 3. Execute the integration pipeline.
SELECT etl.run(DATE '2026-09-30');
-- 4. Inspect source lineage and loaded row counts.
SELECT p.sku,x.source_system,x.source_product_id,x.raw_sku,p.product_key
FROM dw.product_xref x JOIN dw.dim_product p USING(product_key) WHERE p.sku='SKU001';
SELECT * FROM etl.batch ORDER BY batch_id DESC LIMIT 3;
-- 5. Demonstrate the three Assignment 1 business problems and additional sales analysis.
SELECT * FROM reporting.price_comparison WHERE status<>'MATCH' ORDER BY sku;
SELECT * FROM reporting.inventory_comparison WHERE status<>'MATCH' ORDER BY sku;
SELECT * FROM reporting.transfer_monitor WHERE transfer_id IN(1,3,15,18) ORDER BY transfer_id;
SELECT * FROM reporting.sales_by_month ORDER BY month,channel;
-- 6. Revenue independently reconciles against both source systems.
SELECT (SELECT sum(sales_amount) FROM dw.fact_sales) warehouse_revenue,
 (SELECT sum(quantity*unit_price) FROM src_pos.sale_item)+
 (SELECT sum(quantity*unit_price) FROM src_ecom.order_item JOIN src_ecom.customer_order USING(order_id) WHERE order_status='Completed') source_revenue;
