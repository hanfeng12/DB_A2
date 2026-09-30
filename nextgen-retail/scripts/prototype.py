#!/usr/bin/env python3
"""Stdlib-only runner. Uses the course's existing PostgreSQL Docker container."""
import argparse, csv, io, json, os, pathlib, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
DOCKER = shutil.which('docker') or '/usr/local/bin/docker'
CONTAINER = os.environ.get('NEXTGEN_PG_CONTAINER','student-postgres')
USER = os.environ.get('NEXTGEN_PG_USER','student')
DB = 'nextgen_dw'

def sql(text, db=DB, scalar=False):
    cmd=[DOCKER,'exec','-i',CONTAINER,'psql','-X','-v','ON_ERROR_STOP=1','-U',USER,'-d',db]
    if scalar: cmd+=['-A','-t','-q']
    r=subprocess.run(cmd,input=text,text=True,capture_output=True)
    if r.returncode: raise RuntimeError(f'PostgreSQL ({db}): {r.stderr.strip()}')
    return r.stdout.strip()

def file(name,db=DB):
    print(f'  {name} -> {db}',flush=True)
    sql((ROOT/'sql'/name).read_text(),db)

def rows(query):
    return json.loads(sql('SELECT coalesce(json_agg(r),\'[]\'::json) FROM ('+query+')r;',scalar=True))

def etl():
    return int(sql("SELECT etl.run(DATE '2026-09-30');",scalar=True))

def build():
    file('00_databases.sql','lab')
    for n,s in [(1,'pos'),(2,'ecom'),(3,'wms')]: file(f'{n:02}_{s}.sql','nextgen_'+s)
    for s in ['pos','ecom','wms']: file('04_seed_'+s+'.sql','nextgen_'+s)
    for f in ['05_warehouse.sql','06_fdw.sql','07_etl.sql','08_reports.sql']: file(f)
    print(f'ETL batch {etl()} completed')

def export():
    data={'meta': rows("SELECT batch_id,started_at,finished_at,snapshot_date,product_count,sales_count,inventory_count,transfer_count FROM etl.batch ORDER BY batch_id DESC LIMIT 1")[0]}
    for key,view,order in [('prices','price_comparison','sku'),('inventory','inventory_comparison','sku'),('transfers','transfer_monitor','transfer_id'),('sales','sales_by_month','month,channel'),('categories','sales_by_category','category,channel')]:
        data[key]=rows(f'SELECT * FROM reporting.{view} ORDER BY {order}')
        with (ROOT/'evidence'/f'{key}.csv').open('w',newline='') as f:
            writer=csv.DictWriter(f,lineterminator='\n',fieldnames=list(data[key][0]) if data[key] else []);writer.writeheader();writer.writerows(data[key])
    (ROOT/'dashboard'/'data.json').write_text(json.dumps(data,indent=2))
    # Local file mode works without fetch/CORS or any external service.
    (ROOT/'dashboard'/'data.js').write_text('window.NEXTGEN_DATA = '+json.dumps(data).replace('<','\\u003c')+';\n')
    (ROOT/'evidence'/'latest_batch.json').write_text(json.dumps(data['meta'],indent=2)+'\n')
    print('Exported dashboard data and five CSV reports')

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['build','etl','export','test','all','serve']);p.add_argument('--port',type=int,default=8765);a=p.parse_args()
    if a.action in ['build','all']: build()
    if a.action=='etl': print(f'ETL batch {etl()} completed')
    if a.action in ['test','all']:
        sys.path.insert(0,str(ROOT/'tests'));from integration import run;run()
    if a.action in ['export','all','etl']: export()
    if a.action=='serve':
        from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
        from functools import partial
        print(f'Dashboard: http://127.0.0.1:{a.port}',flush=True)
        ThreadingHTTPServer(('127.0.0.1',a.port),partial(SimpleHTTPRequestHandler,directory=str(ROOT/'dashboard'))).serve_forever()
if __name__=='__main__': main()
