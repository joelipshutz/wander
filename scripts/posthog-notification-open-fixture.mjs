// Regression fixtures use synthetic SQL rows, never captured product events.
import {insights,remoteOpenRateSQL} from './posthog-product-dashboard.mjs';
const key=process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
if(process.env.WANDER_POSTHOG_PROJECT_ID!=='557259'||!key)throw Error('Expected Astir credentials');
async function api(path,method='GET',body){const r=await fetch('https://us.posthog.com/api/projects/557259/'+path,{method,headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});if(!r.ok)throw Error(`PostHog ${method} ${r.status}: ${(await r.text()).slice(0,300)}`);return r.json()}

const assert=(ok,message)=>{if(!ok)throw Error(message)};
async function runTemporary(label,query){let id;try{
 id=(await api('insights/','POST',{name:'REC-581 temporary '+label,query:{kind:'HogQLQuery',query},saved:false,tags:['recme:validation-only']})).id;
 const r=await api(`insights/${id}/?refresh=force_blocking`);
 assert(!r.error&&Array.isArray(r.result),'Query failed '+label);
 console.log(JSON.stringify({label,columns:r.columns,result:r.result}));return r;
}finally{if(id)await api(`insights/${id}/`,'PATCH',{deleted:true})}}
const production=remoteOpenRateSQL();
const clientFilter=production.split("and properties.delivery_channel = 'remote'\n    and ")[1].split('\n    and timestamp')[0];
const cols=['event','delivery_channel','analytics_audience','delivery_outcome','timestamp'];
const make=(rows)=>rows.map((r,i)=>'select '+r.map((v,j)=> (j===4?`toDateTime('${v}')`:`'${v}'`)+(i===0?' as '+cols[j]:'')).join(', ')).join(' union all ');
const opens=[
 ['notification_opened','remote','','','2026-09-21 11:59:59'],
 ['notification_opened','remote','','','2026-09-21 12:00:00'],
 ['notification_opened','remote','','','2026-09-21 13:00:00'],
 ['notification_opened','local','','','2026-09-21 13:00:00'],
 ['notification_opened','remote','','','2026-08-01 13:00:00'],
];
const legacy=[['notification_delivery_processed','','','sent','2026-09-21 10:00:00']];
const delivered=[
 ['notification_delivery_processed','','external_recipients_v1','sent','2026-09-21 12:00:00'],
 ['notification_delivery_processed','','external_recipients_v1','sent','2026-09-21 13:00:00'],
];
for(const [label,rows,expected] of [
 ['no comparable delivery',[...opens,...legacy],[3,'Awaiting comparable delivery data',null,null,null,null]],
 ['comparable delivery',[...opens,...legacy,...delivered],[3,'Comparable window available',2,2,100]],
 ['measured zero opens',delivered,[0,'Comparable window available',2,0,0]]
]){
 let sql=production.replace(clientFilter,'1 = 1').replaceAll('properties.','').replaceAll('from events','from fixture_events').replaceAll('now()',"toDateTime('2026-09-21 18:00:00')");
 sql='with fixture_events as ('+make(rows)+'), '+sql.slice(5);
 const r=await runTemporary(label,sql);
 assert(JSON.stringify(r.result[0].slice(0,expected.length))===JSON.stringify(expected),label+' mismatch');
}
