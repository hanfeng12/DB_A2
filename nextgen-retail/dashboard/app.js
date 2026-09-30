'use strict';
const data=window.NEXTGEN_DATA;
const $=id=>document.getElementById(id);
const fmt=new Intl.NumberFormat('en-AU');
const money=v=>v==null?'Unknown':new Intl.NumberFormat('en-AU',{style:'currency',currency:'AUD',maximumFractionDigits:2}).format(v);
const escape=s=>String(s??'Unknown').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const configs={
 prices:{title:'Price consistency',label:'REPORT 01 / MASTER DATA',description:'List-price snapshot, POS minus online. A mismatch is an investigation signal; channel promotions may be legitimate. Product descriptions follow the POS master; channel prices remain distinct.',columns:{sku:'SKU',product_name:'Product',category:'Category',pos_price:'POS price',online_price:'Online price',difference:'Difference',difference_pct:'Difference %',status:'Status'}},
 inventory:{title:'Inventory alignment',label:'REPORT 02 / SHARED FULFILMENT POOL',description:'Online advertised availability compared with warehouse on-hand minus reserved stock, using the same snapshot date and online fulfilment pool. Unknown or incomplete source data is flagged separately and is never replaced with zero.',columns:{sku:'SKU',product_name:'Product',online_available:'Online available',warehouse_available:'WMS available',difference:'Difference',warehouse_count:'Warehouses',status:'Status'}},
 transfers:{title:'Transfer monitor',label:'REPORT 03 / MOVEMENT VISIBILITY',description:'Warehouse transfers matched to POS store receipts by transfer ID, canonical product and destination. Completed movements without a receipt, short receipts and overdue transfers are highlighted. Overdue is evaluated at the batch snapshot date.',columns:{transfer_id:'Transfer',sku:'SKU',source_location:'From',destination_location:'To',quantity:'Sent',received_quantity:'Received',transfer_status:'WMS status',expected_date:'Expected',exception:'Exception'}},
 sales:{title:'Channel performance',label:'REPORT 04 / COMPLETED SALES',description:'Completed sales across stores and e-commerce, grouped by month and channel. Cancelled and pending online orders are excluded. Revenue is quantity × the original transaction unit price, with no tax or returns model in this pilot.',columns:{month:'Month',channel:'Channel',line_count:'Sales lines',units:'Units',revenue:'Revenue (AUD)'}}
};
let current='overview',visible=[];
function isException(r){return !['MATCH','RECONCILED','ON_TRACK','CANCELLED'].includes(r.status||r.exception||'MATCH')}
function renderTable(){
 const c=configs[current];if(!c)return;
 const term=$('search').value.trim().toLowerCase();
 visible=data[current].filter(r=>(!$('exceptions').checked||isException(r))&&Object.values(r).some(v=>String(v??'unknown').toLowerCase().includes(term)));
 $('thead').innerHTML='<tr>'+Object.values(c.columns).map(x=>'<th scope="col">'+escape(x)+'</th>').join('')+'</tr>';
 $('tbody').innerHTML=visible.map(r=>'<tr>'+Object.keys(c.columns).map(k=>{
 let v=r[k],s=escape(v);
 if(k==='status'||k==='exception'){const ok=['MATCH','RECONCILED','ON_TRACK'].includes(v);s='<span class="status '+(ok?'ok':String(v).includes('UNKNOWN')||String(v).includes('INCOMPLETE')?'unknown':'')+'">'+escape(String(v).replaceAll('_',' '))+'</span>'}
 else if(k==='revenue'||(current==='prices'&&['pos_price','online_price','difference'].includes(k)))s=money(v);
 else if(k==='difference_pct')s=v==null?'Unknown':escape(v)+'%';
 else if(typeof v==='number')s=fmt.format(v);
 return '<td>'+s+'</td>'}).join('')+'</tr>').join('')||'<tr><td colspan="'+Object.keys(c.columns).length+'">No rows match these filters.</td></tr>';
 $('row-count').textContent=visible.length+' of '+data[current].length+' rows';
}
function show(view){
 if(view!=='overview'&&!configs[view])view='overview';current=view;
 document.querySelectorAll('nav button').forEach(b=>{b.classList.toggle('active',b.dataset.view===view);b.setAttribute('aria-pressed',b.dataset.view===view)});
 $('overview').hidden=view!=='overview';$('report').hidden=view==='overview';
 $('title').textContent=view==='overview'?'One view. Three connected systems.':configs[view].title;
 $('subtitle').textContent=view==='overview'?'Find the gaps between your stores, online channel and fulfilment network.':'From operational records to a consistent analytical view.';
 if(view!=='overview'){const c=configs[view];$('report-label').textContent=c.label;$('report-title').textContent=c.title;$('definition').textContent=c.description;$('search').value='';$('exceptions').checked=false;$('exceptions').parentElement.hidden=view==='sales';renderTable()}
 history.replaceState(null,'','#'+view);
}
if(!data){$('title').textContent='Generate your warehouse snapshot first';$('subtitle').textContent='Run: python3 scripts/prototype.py all';}else{
 const revenue=data.sales.reduce((s,r)=>s+Number(r.revenue),0),priceCount=data.prices.filter(r=>r.status==='MISMATCH').length,stockCount=data.inventory.filter(r=>r.status==='MISMATCH').length,unknownCount=data.inventory.filter(r=>r.status.startsWith('UNKNOWN')||r.status==='INCOMPLETE_WMS').length,transferCount=data.transfers.filter(isException).length;
 $('snapshot').textContent='Snapshot · '+data.meta.snapshot_date;$('batch').textContent='Batch '+data.meta.batch_id+' · '+data.meta.sales_count+' sales lines';$('loaded').textContent='Exported batch completed '+new Date(data.meta.finished_at).toLocaleString('en-AU');
 $('kpis').innerHTML=[['Integrated revenue',money(revenue),'Completed POS + online sales','positive'],['Price mismatches',priceCount,'Across '+data.prices.length+' canonical SKUs','warn'],['Stock discrepancies',stockCount,unknownCount+' additional unknown / incomplete','warn'],['Transfer exceptions',transferCount,'Across '+data.transfers.length+' warehouse movements','warn']].map(([l,v,n,c])=>'<article class="kpi"><span class="label">'+l+'</span><strong class="'+c+'">'+v+'</strong><small>'+n+'</small></article>').join('');
 const max=Math.max(1,...data.sales.map(r=>Number(r.revenue)));const months=[...new Set(data.sales.map(r=>r.month))];
 $('chart').innerHTML=months.map(m=>'<div class="bar-group">'+['POS','ONLINE'].map(ch=>{const r=data.sales.find(r=>r.month===m&&r.channel===ch),v=Number(r?.revenue||0);return '<div class="bar '+(ch==='ONLINE'?'online':'')+'" style="height:'+Math.round(v/max*80)+'%" title="'+escape(m+' '+ch+': '+money(v))+'"><small>'+Math.round(v/1000)+'k</small></div>'}).join('')+'<b>'+new Date(m+'-01T00:00:00').toLocaleDateString('en-AU',{month:'short',year:'numeric'})+'</b></div>').join('');
 $('attention').innerHTML=[['prices','Review price differences',priceCount],['inventory','Investigate stock discrepancies',stockCount],['transfers','Resolve transfer exceptions',transferCount]].map(([v,t,n])=>'<button data-view="'+v+'"><span>'+t+' →</span><b>'+n+'</b></button>').join('');
 document.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>show(b.dataset.view)));
 $('search').addEventListener('input',renderTable);$('exceptions').addEventListener('change',renderTable);
 $('download').addEventListener('click',()=>{const keys=Object.keys(configs[current].columns),cell=v=>'"'+String(v??'').replaceAll('"','""')+'"';const csv=[keys,...visible.map(r=>keys.map(k=>r[k]))].map(r=>r.map(cell).join(',')).join('\r\n');const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8;'}));const a=document.createElement('a');a.href=url;a.download='nextgen-'+current+'-'+data.meta.snapshot_date+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)});
 window.addEventListener('hashchange',()=>show(location.hash.slice(1)||'overview'));
 show(location.hash.slice(1)||'overview');
}
