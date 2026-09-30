-- Deterministic synthetic fixtures; rerunning never overwrites existing rows.
BEGIN;
INSERT INTO operational.product
SELECT 1000+i, ' sku'||lpad(i::text,3,'0')||' ', CASE WHEN i<=30 THEN 'Device ' ELSE 'Apparel ' END||lpad(i::text,3,'0'),
 CASE WHEN i=60 THEN NULL WHEN i<=30 THEN ' electronics ' ELSE 'CLOTHING' END, CASE WHEN i=1 THEN 100 ELSE 20+i*3 END - CASE WHEN i=1 THEN 5 WHEN i%5=0 THEN 4 ELSE 0 END
FROM generate_series(1,60) i ON CONFLICT DO NOTHING;
INSERT INTO operational.customer_order
SELECT i,timestamp '2026-07-01 08:00'+((i-1)%92)*interval '1 day',
 (ARRAY['NSW','VIC','QLD','WA'])[1+i%4],
 CASE WHEN i%10=0 THEN 'Cancelled' WHEN i%13=0 THEN 'Pending' ELSE 'Completed' END
FROM generate_series(1,900)i ON CONFLICT DO NOTHING;
INSERT INTO operational.order_item
SELECT (o.order_id-1)*2+j,o.order_id,1001+(o.order_id*11+j-1)%60,1+(o.order_id+j)%2,p.list_price
FROM operational.customer_order o CROSS JOIN generate_series(1,2)j
JOIN operational.product p ON p.product_id=1001+(o.order_id*11+j-1)%60 ON CONFLICT DO NOTHING;
INSERT INTO operational.online_stock
SELECT 1000+i,CASE WHEN i=60 THEN NULL WHEN i=1 THEN 30 ELSE 30+2*i+CASE WHEN i%7=0 THEN 5 ELSE 0 END END,
 date '2026-09-30' FROM generate_series(1,60)i ON CONFLICT DO NOTHING;
COMMIT;
