-- Deterministic synthetic fixtures; rerunning never overwrites existing rows.
BEGIN;
INSERT INTO operational.product
SELECT 100+i, 'SKU'||lpad(i::text,3,'0'), CASE WHEN i<=30 THEN 'Device ' ELSE 'Apparel ' END||lpad(i::text,3,'0'),
 CASE WHEN i<=30 THEN 'Electronics' ELSE 'Clothing' END, CASE WHEN i=1 THEN 100 ELSE 20+i*3 END
FROM generate_series(1,60) i ON CONFLICT DO NOTHING;
INSERT INTO operational.store
SELECT i,'NextGen Store '||i, (ARRAY['Sydney','Melbourne','Brisbane','Perth'])[1+(i-1)%4],
 (ARRAY['NSW','VIC','QLD','WA'])[1+(i-1)%4] FROM generate_series(1,12)i ON CONFLICT DO NOTHING;
INSERT INTO operational.sale
SELECT i,1+(i-1)%12, timestamp '2026-07-01 09:00'+((i-1)%92)*interval '1 day'+(i%9)*interval '1 hour',0
FROM generate_series(1,1200)i ON CONFLICT DO NOTHING;
INSERT INTO operational.sale_item
SELECT (s.sale_id-1)*2+j, s.sale_id,101+(s.sale_id*7+j-1)%60,1+(s.sale_id+j)%3,p.list_price
FROM operational.sale s CROSS JOIN generate_series(1,2)j
JOIN operational.product p ON p.product_id=101+(s.sale_id*7+j-1)%60 ON CONFLICT DO NOTHING;
UPDATE operational.sale s SET total_amount=t.total FROM
 (SELECT sale_id,sum(quantity*unit_price) total FROM operational.sale_item GROUP BY sale_id)t
WHERE s.sale_id=t.sale_id AND s.total_amount IS DISTINCT FROM t.total;
-- Most completed transfers are received; every 18th completed transfer is missing,
-- every 15th has a short receipt. Transfer 3 is a known successful receipt.
INSERT INTO operational.transfer_receipt
SELECT i,1+(i-1)%12,101+(i-1)%60,
 10+i%20-CASE WHEN i%15=0 THEN 2 ELSE 0 END,
 timestamp '2026-09-01 10:00'+(i%20)*interval '1 day'+interval '2 days'
FROM generate_series(1,180)i WHERE i%3=0 AND i%18<>0 ON CONFLICT DO NOTHING;
COMMIT;
