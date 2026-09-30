-- Atomic, repeatable batch integration. PostgreSQL FDW extracts three independent DBs.
-- Call with SELECT etl.run(DATE '2026-09-30'); the historical fixture date is explicit.
CREATE OR REPLACE FUNCTION etl.run(p_snapshot_date date DEFAULT DATE '2026-09-30')
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE b bigint; dk integer;
BEGIN
 PERFORM pg_advisory_xact_lock(32113,2); -- serialize concurrent warehouse refreshes
 IF p_snapshot_date IS NULL THEN RAISE EXCEPTION 'snapshot_date is required'; END IF;
 dk := to_char(p_snapshot_date,'YYYYMMDD')::integer;
 INSERT INTO etl.batch(snapshot_date) VALUES(p_snapshot_date) RETURNING batch_id INTO b;
 -- Staging is transaction-local. Duplicate canonical SKUs within one system are rejected,
 -- not silently collapsed. Cross-system product IDs may overlap and remain namespaced.
 DROP TABLE IF EXISTS pg_temp.stage_product;
 CREATE TEMP TABLE stage_product ON COMMIT DROP AS
 SELECT 'POS'::text source_system,product_id,sku raw_sku,upper(trim(sku)) sku,
 trim(product_name) product_name,coalesce(nullif(initcap(trim(category)),''),'Unknown') category,list_price,1 priority FROM src_pos.product
 UNION ALL SELECT 'ONLINE',product_id,sku,upper(trim(sku)),trim(product_name),coalesce(nullif(initcap(trim(category)),''),'Unknown'),list_price,2 FROM src_ecom.product
 UNION ALL SELECT 'WMS',product_id,sku,upper(trim(sku)),trim(product_name),coalesce(nullif(initcap(trim(category)),''),'Unknown'),list_price,3 FROM src_wms.product;
 IF EXISTS(SELECT FROM stage_product GROUP BY source_system,sku HAVING count(*)>1) THEN
  RAISE EXCEPTION 'Ambiguous canonical SKU within source; resolve master mapping before load'; END IF;
 IF EXISTS(SELECT FROM stage_product WHERE sku !~ '^SKU[0-9]{3}$') THEN
  RAISE EXCEPTION 'Invalid canonical SKU'; END IF;
 IF (SELECT count(DISTINCT source_system) FROM stage_product)<>3 THEN RAISE EXCEPTION 'All three product sources must be populated'; END IF;
 -- POS is the documented master for descriptive attributes. Channel prices stay separate.
 INSERT INTO dw.dim_product(sku,product_name,category)
 SELECT DISTINCT ON(sku) sku,product_name,category FROM stage_product ORDER BY sku,priority
 ON CONFLICT(sku) DO UPDATE SET product_name=excluded.product_name,category=excluded.category;
 INSERT INTO dw.product_xref(source_system,source_product_id,product_key,raw_sku)
 SELECT s.source_system,s.product_id,p.product_key,s.raw_sku FROM stage_product s JOIN dw.dim_product p USING(sku)
 ON CONFLICT(source_system,source_product_id) DO UPDATE SET product_key=excluded.product_key,raw_sku=excluded.raw_sku;
 INSERT INTO dw.dim_channel VALUES(1,'POS'),(2,'ONLINE'),(3,'WMS') ON CONFLICT DO NOTHING;
 -- Calendar includes every event date and every inventory snapshot, including future input.
 INSERT INTO dw.dim_date
 SELECT to_char(d,'YYYYMMDD')::integer,d,extract(year FROM d),extract(month FROM d),extract(quarter FROM d),extract(day FROM d)
 FROM (SELECT p_snapshot_date d UNION SELECT sold_at::date FROM src_pos.sale
 UNION SELECT ordered_at::date FROM src_ecom.customer_order UNION SELECT dispatched_at::date FROM src_wms.transfer
 UNION SELECT snapshot_date FROM src_ecom.online_stock UNION SELECT snapshot_date FROM src_wms.inventory) dates
 ON CONFLICT DO NOTHING;
 UPDATE dw.dim_location SET online_fulfilment=false WHERE online_fulfilment;
 INSERT INTO dw.dim_location(location_code,location_name,location_type,city,online_fulfilment)
 SELECT 'STORE-'||store_id,store_name,'STORE',city,false FROM src_pos.store
 UNION ALL SELECT 'WH-'||warehouse_id,warehouse_name,'WAREHOUSE',city,online_fulfilment FROM src_wms.warehouse
 UNION ALL SELECT 'ONLINE','Online fulfilment pool','ONLINE','Australia',false
 ON CONFLICT(location_code) DO UPDATE SET location_name=excluded.location_name,city=excluded.city,online_fulfilment=excluded.online_fulfilment;
 -- Full refresh of mutable transaction facts: captures cancellations, updates and deletes.
 -- Surrogate fact row IDs are implementation identifiers, not stable external references.
 DELETE FROM dw.fact_sales;
 INSERT INTO dw.fact_sales(source_system,source_line_id,product_key,date_key,channel_key,location_key,quantity,unit_price,batch_id)
 SELECT 'POS',i.line_id,x.product_key,to_char(s.sold_at,'YYYYMMDD')::integer,1,l.location_key,i.quantity,i.unit_price,b
 FROM src_pos.sale_item i JOIN src_pos.sale s USING(sale_id)
 JOIN dw.product_xref x ON x.source_system='POS' AND x.source_product_id=i.product_id
 JOIN dw.dim_location l ON l.location_code='STORE-'||s.store_id
 UNION ALL
 SELECT 'ONLINE',i.line_id,x.product_key,to_char(o.ordered_at,'YYYYMMDD')::integer,2,l.location_key,i.quantity,i.unit_price,b
 FROM src_ecom.order_item i JOIN src_ecom.customer_order o USING(order_id)
 JOIN dw.product_xref x ON x.source_system='ONLINE' AND x.source_product_id=i.product_id
 JOIN dw.dim_location l ON l.location_code='ONLINE' WHERE o.order_status='Completed';
 IF (SELECT count(*) FROM dw.fact_sales)<>(SELECT count(*) FROM src_pos.sale_item)+
 (SELECT count(*) FROM src_ecom.order_item JOIN src_ecom.customer_order USING(order_id) WHERE order_status='Completed')
 THEN RAISE EXCEPTION 'Sales reconciliation failed: unmapped source rows'; END IF;
 -- Preserve prior daily snapshots; same-date reruns replace that date atomically.
 DELETE FROM dw.fact_price WHERE date_key=dk;
 INSERT INTO dw.fact_price
 SELECT x.product_key,dk,CASE WHEN s.source_system='POS' THEN 1 ELSE 2 END,s.list_price,b
 FROM stage_product s JOIN dw.product_xref x ON x.source_system=s.source_system AND x.source_product_id=s.product_id
 WHERE s.source_system IN ('POS','ONLINE');
 DELETE FROM dw.fact_inventory WHERE date_key=dk;
 INSERT INTO dw.fact_inventory
 SELECT x.product_key,dk,2,l.location_key,s.available_quantity,b
 FROM src_ecom.online_stock s JOIN dw.product_xref x ON x.source_system='ONLINE' AND x.source_product_id=s.product_id
 JOIN dw.dim_location l ON l.location_code='ONLINE' WHERE s.snapshot_date=p_snapshot_date
 UNION ALL
 SELECT x.product_key,dk,3,l.location_key,s.quantity_on_hand-s.reserved_quantity,b
 FROM src_wms.inventory s JOIN src_wms.warehouse w USING(warehouse_id)
 JOIN dw.product_xref x ON x.source_system='WMS' AND x.source_product_id=s.product_id
 JOIN dw.dim_location l ON l.location_code='WH-'||s.warehouse_id
 WHERE s.snapshot_date=p_snapshot_date AND w.online_fulfilment;
 DELETE FROM dw.fact_transfer;
 INSERT INTO dw.fact_transfer
 SELECT t.transfer_id,x.product_key,to_char(t.dispatched_at,'YYYYMMDD')::integer,a.location_key,z.location_key,
 t.quantity,t.transfer_status,t.dispatched_at,t.expected_date,t.completed_at,r.received_quantity,r.received_at,
 CASE WHEN r.transfer_id IS NULL THEN NULL ELSE rx.product_key=x.product_key AND r.store_id=t.destination_store_id END,b
 FROM src_wms.transfer t JOIN dw.product_xref x ON x.source_system='WMS' AND x.source_product_id=t.product_id
 JOIN dw.dim_location a ON a.location_code='WH-'||t.warehouse_id
 JOIN dw.dim_location z ON z.location_code='STORE-'||t.destination_store_id
 LEFT JOIN src_pos.transfer_receipt r USING(transfer_id)
 LEFT JOIN dw.product_xref rx ON rx.source_system='POS' AND rx.source_product_id=r.product_id;
 IF (SELECT count(*) FROM dw.fact_transfer)<>(SELECT count(*) FROM src_wms.transfer)
 THEN RAISE EXCEPTION 'Transfer reconciliation failed: unmapped location/product'; END IF;
 UPDATE etl.batch SET finished_at=clock_timestamp(),product_count=(SELECT count(*) FROM dw.dim_product),
 sales_count=(SELECT count(*) FROM dw.fact_sales),inventory_count=(SELECT count(*) FROM dw.fact_inventory WHERE date_key=dk),
 transfer_count=(SELECT count(*) FROM dw.fact_transfer) WHERE batch_id=b;
 RETURN b;
END $$;
