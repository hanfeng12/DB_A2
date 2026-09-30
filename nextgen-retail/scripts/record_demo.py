#!/usr/bin/env python3
"""Capture real commands and PostgreSQL output as an asciinema v2 terminal recording."""
import datetime,json,pathlib,subprocess,sys,time
from prototype import ROOT,DOCKER,CONTAINER,USER
out=ROOT/'evidence'/'end_to_end.cast'
transcript=[];started=time.monotonic()
with out.open('w') as f:
    f.write(json.dumps({'version':2,'width':130,'height':38,'timestamp':int(time.time()),'title':'NextGen Retail — real PostgreSQL end-to-end demonstration','env':{'TERM':'xterm-256color','SHELL':'bash'}})+'\n')
    def emit(text):
        f.write(json.dumps([round(time.monotonic()-started,3),'o',text.replace('\n','\r\n')])+'\n');f.flush();transcript.append(text);print(text,end='',flush=True)
    def run(title,args,input_text=None):
        emit('\n=== '+title+' ===\n')
        if input_text:emit('SQL> '+input_text+'\n')
        else:emit('$ python3 scripts/prototype.py all\n')
        p=subprocess.Popen(args,stdin=subprocess.PIPE if input_text else subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
        if input_text:p.stdin.write(input_text);p.stdin.close()
        for line in p.stdout:emit(line)
        if p.wait(): raise RuntimeError('Recorded command failed: '+title)
        emit('[command completed successfully]\n')
    emit('NEXTGEN RETAIL | ASSIGNMENT 2\nActual execution against the provided PostgreSQL lab. Synthetic data.\nRecorded UTC: '+datetime.datetime.now(datetime.timezone.utc).isoformat()+'\n')
    run('1. BUILD SOURCES, LOAD WAREHOUSE, TEST, EXPORT',[sys.executable,'-u',str(ROOT/'scripts'/'prototype.py'),'all'])
    base=[DOCKER,'exec','-i',CONTAINER,'psql','-X','-P','pager=off','-v','ON_ERROR_STOP=1','-U',USER,'-d','nextgen_dw']
    for title,query in [
      ('2. THREE SOURCE DATABASES + ONE WAREHOUSE',"SELECT datname FROM pg_database WHERE datname LIKE 'nextgen_%' ORDER BY datname;"),
      ('3. CANONICAL PRODUCT MAPPING',"SELECT p.sku,x.source_system,x.source_product_id,x.raw_sku,p.product_key FROM dw.product_xref x JOIN dw.dim_product p USING(product_key) WHERE p.sku='SKU001';"),
      ('4. PRICE CONSISTENCY',"SELECT sku,pos_price,online_price,difference,status FROM reporting.price_comparison WHERE sku IN ('SKU001','SKU002');"),
      ('5. INVENTORY ALIGNMENT',"SELECT sku,online_available,warehouse_available,difference,status FROM reporting.inventory_comparison WHERE sku IN ('SKU001','SKU002','SKU060');"),
      ('6. TRANSFER EXCEPTIONS',"SELECT transfer_id,sku,quantity,received_quantity,exception FROM reporting.transfer_monitor WHERE transfer_id IN (1,3,15,18) ORDER BY transfer_id;"),
      ('7. CHANNEL SALES',"SELECT * FROM reporting.sales_by_month ORDER BY month,channel;"),
      ('8. FINAL RECONCILIATION',"SELECT sum(sales_amount) AS total_revenue,count(*) AS sales_lines FROM dw.fact_sales; SELECT product_count,sales_count,inventory_count,transfer_count FROM etl.batch ORDER BY batch_id DESC LIMIT 1;")]:run(title,base,query)
    emit('\nDEMONSTRATION COMPLETE\nOpen dashboard/index.html or http://127.0.0.1:8765 for interactive reports.\nBatch snapshot: 2026-09-30. Reports flag exceptions; they do not auto-correct sources.\n')
(ROOT/'evidence'/'end_to_end.txt').write_text(''.join(transcript))
print('Saved',out)
