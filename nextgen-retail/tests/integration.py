"""Integration tests exercise actual PostgreSQL/FDW and restore all source mutations."""
import json, datetime
from prototype import sql,rows,etl,ROOT

def run():
    checks=[]
    def check(name,query,expected=True,db='nextgen_dw'):
        actual=sql(query,db,scalar=True)
        wanted='t' if expected is True else str(expected)
        if actual!=wanted: raise AssertionError(f'{name}: expected {wanted}, got {actual}')
        checks.append({'test':name,'status':'PASS'})
        print('PASS',name,flush=True)
    check('Four independent databases',"SELECT count(*) FROM pg_database WHERE datname IN ('nextgen_pos','nextgen_ecom','nextgen_wms','nextgen_dw');",4)
    check('Master SKU normalization',"SELECT count(*)=60 AND count(DISTINCT sku)=60 FROM dw.dim_product;")
    check('180 product identifiers map to 60 products',"SELECT count(*)=180 AND count(DISTINCT product_key)=60 FROM dw.product_xref;")
    check('Sales counts reconcile; incomplete orders excluded',"SELECT (SELECT count(*) FROM dw.fact_sales)=(SELECT count(*) FROM src_pos.sale_item)+(SELECT count(*) FROM src_ecom.order_item JOIN src_ecom.customer_order USING(order_id) WHERE order_status='Completed');")
    check('Sales monetary totals reconcile exactly',"SELECT (SELECT sum(sales_amount) FROM dw.fact_sales)=(SELECT sum(quantity*unit_price) FROM src_pos.sale_item)+(SELECT sum(quantity*unit_price) FROM src_ecom.order_item JOIN src_ecom.customer_order USING(order_id) WHERE order_status='Completed');")
    check('POS headers reconcile to line totals',"SELECT NOT EXISTS(SELECT FROM src_pos.sale s JOIN (SELECT sale_id,sum(quantity*unit_price) amount FROM src_pos.sale_item GROUP BY sale_id)i USING(sale_id) WHERE s.total_amount<>i.amount);")
    check('Known price difference = AUD 5',"SELECT difference FROM reporting.price_comparison WHERE sku='SKU001';",'5.00')
    check('Known stock difference = 8 (30 vs 22)',"SELECT difference FROM reporting.inventory_comparison WHERE sku='SKU001';",8)
    check('Missing stock is explicitly unknown',"SELECT status FROM reporting.inventory_comparison WHERE sku='SKU060';",'UNKNOWN_ONLINE')
    check('Missing store receipt detected',"SELECT exception FROM reporting.transfer_monitor WHERE transfer_id=18;",'MISSING_STORE_RECEIPT')
    check('Short receipt detected',"SELECT exception FROM reporting.transfer_monitor WHERE transfer_id=15;",'QUANTITY_MISMATCH')
    check('Completed transfer reconciled',"SELECT exception FROM reporting.transfer_monitor WHERE transfer_id=3;",'RECONCILED')
    check('Overdue transfer uses explicit snapshot date',"SELECT exception FROM reporting.transfer_monitor WHERE transfer_id=1;",'OVERDUE')
    def signature():
        return rows("SELECT (SELECT count(*) FROM dw.fact_sales) sales,(SELECT sum(sales_amount) FROM dw.fact_sales) revenue,(SELECT count(*) FROM dw.fact_price) prices,(SELECT count(*) FROM dw.fact_inventory) inventory,(SELECT count(*) FROM dw.fact_transfer) transfers")
    before=signature();etl();after=signature()
    if before!=after: raise AssertionError('ETL rerun changed business totals')
    checks.append({'test':'Idempotent ETL preserves counts and revenue','status':'PASS'});print('PASS Idempotent ETL')
    # Change the live source; verify FDW/ETL propagation and restore original data.
    old=sql('SELECT list_price FROM operational.product WHERE product_id=1001;','nextgen_ecom',True)
    try:
        sql('UPDATE operational.product SET list_price=90 WHERE product_id=1001;','nextgen_ecom');etl()
        check('Source price update propagates to report',"SELECT difference FROM reporting.price_comparison WHERE sku='SKU001';",'10.00')
    finally:
        sql(f'UPDATE operational.product SET list_price={old} WHERE product_id=1001;','nextgen_ecom');etl()
    try:
        sql("UPDATE operational.customer_order SET order_status='Cancelled' WHERE order_id=1;",'nextgen_ecom');etl()
        check('Late cancellation removes prior warehouse facts',"SELECT count(*) FROM dw.fact_sales WHERE source_system='ONLINE' AND source_line_id IN(1,2);",0)
    finally:
        sql("UPDATE operational.customer_order SET order_status='Completed' WHERE order_id=1;",'nextgen_ecom');etl()
    # Preserve prior snapshot history, while flagging a missing new-day inventory feed.
    check('New-day history retained; absent feed is unknown', "BEGIN; DO $$ BEGIN PERFORM etl.run(DATE '2026-10-01'); END $$; SELECT (SELECT count(*) FROM dw.fact_price WHERE date_key=20260930)=120 AND (SELECT count(*) FROM dw.fact_price WHERE date_key=20261001)=120 AND (SELECT count(*) FROM reporting.inventory_comparison WHERE status='UNKNOWN_ONLINE')=60; ROLLBACK;")
    try:
        sql('UPDATE operational.transfer_receipt SET store_id=2 WHERE transfer_id=3;', 'nextgen_pos');etl()
        check('Receipt for wrong store cannot reconcile', "SELECT exception FROM reporting.transfer_monitor WHERE transfer_id=3;", 'RECEIPT_IDENTITY_MISMATCH')
    finally:
        sql('UPDATE operational.transfer_receipt SET store_id=3 WHERE transfer_id=3;', 'nextgen_pos');etl()
    try:
        sql("UPDATE operational.inventory SET snapshot_date=DATE '2026-09-29' WHERE product_id=2001 AND warehouse_id=2;", 'nextgen_wms');etl()
        check('Partial warehouse feed is flagged incomplete', "SELECT status FROM reporting.inventory_comparison WHERE sku='SKU001';", 'INCOMPLETE_WMS')
    finally:
        sql("UPDATE operational.inventory SET snapshot_date=DATE '2026-09-30' WHERE product_id=2001 AND warehouse_id=2;", 'nextgen_wms');etl()
    baseline=signature();batches=sql('SELECT count(*) FROM etl.batch;',scalar=True)
    try:
        sql("INSERT INTO operational.product VALUES(9999,'sku001','Duplicate fixture','Electronics',1);",'nextgen_pos')
        try: etl()
        except RuntimeError as e:
            if 'Ambiguous canonical SKU' not in str(e): raise
        else: raise AssertionError('Ambiguous SKU accepted')
        if signature()!=baseline: raise AssertionError('Failed ETL left partial facts')
        check('Failed ETL rolls back audit and warehouse',"SELECT count(*) FROM etl.batch;",batches)
        checks.append({'test':'Duplicate canonical SKU rejected','status':'PASS'})
    finally: sql('DELETE FROM operational.product WHERE product_id=9999;','nextgen_pos')
    # Test constraints using rolled-back transactions; zero changes persist.
    for name,db,query in [('Negative stock rejected','nextgen_wms','UPDATE operational.inventory SET quantity_on_hand=-1 WHERE product_id=2001'),('Orphan sale line rejected','nextgen_pos','INSERT INTO operational.sale_item VALUES(999999,999999,101,1,10)')]:
        try: sql('BEGIN; '+query+'; ROLLBACK;',db)
        except RuntimeError as e:
            if not ('violates check constraint' in str(e) or 'violates foreign key constraint' in str(e)): raise
        else: raise AssertionError(name)
        checks.append({'test':name,'status':'PASS'});print('PASS',name)
    result={'tested_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'engine':sql('SELECT version();',scalar=True),'passed':len(checks),'failed':0,'checks':checks}
    (ROOT/'evidence'/'test_results.json').write_text(json.dumps(result,indent=2)+'\n')
    print(f'{len(checks)} integration checks passed')
