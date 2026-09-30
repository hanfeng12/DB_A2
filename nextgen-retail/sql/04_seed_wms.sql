-- Deterministic synthetic fixtures; rerunning never overwrites existing rows.
BEGIN;
INSERT INTO operational.product
SELECT 2000+i, 'Sku'||lpad(i::text,3,'0'), CASE WHEN i<=30 THEN 'Device ' ELSE 'Apparel ' END||lpad(i::text,3,'0'),
 CASE WHEN i<=30 THEN 'Electronics' ELSE 'Clothing' END, CASE WHEN i=1 THEN 100 ELSE 20+i*3 END
FROM generate_series(1,60) i ON CONFLICT DO NOTHING;
INSERT INTO operational.warehouse VALUES
(1,'Sydney Fulfilment','Sydney',true),(2,'Melbourne Fulfilment','Melbourne',true) ON CONFLICT DO NOTHING;
INSERT INTO operational.inventory
SELECT 2000+i,w,CASE WHEN i=1 THEN 13 ELSE 17+i END,2,date '2026-09-30'
FROM generate_series(1,60)i CROSS JOIN generate_series(1,2)w ON CONFLICT DO NOTHING;
INSERT INTO operational.transfer
SELECT i,2001+(i-1)%60,1+i%2,1+(i-1)%12,10+i%20,
 CASE WHEN i%3=0 THEN 'Completed' WHEN i%3=1 THEN 'In Transit' ELSE 'Pending' END,
 timestamp '2026-09-01 10:00'+(i%20)*interval '1 day',date '2026-09-04'+i%20,
 CASE WHEN i%3=0 THEN timestamp '2026-09-01 10:00'+(i%20)*interval '1 day'+interval '2 days' END
FROM generate_series(1,180)i ON CONFLICT DO NOTHING;
COMMIT;
