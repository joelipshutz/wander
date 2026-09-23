// Validate actual aggregation using synthetic SQL rows; never capture fake product events.
import {appEntrySQL} from './posthog-product-dashboard.mjs';
const key=process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
if(process.env.WANDER_POSTHOG_PROJECT_ID!=='557259'||!key)throw Error('Expected Astir credentials');
async function api(path,method='GET',body){const r=await fetch('https://us.posthog.com/api/projects/557259/'+path,{method,headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});if(!r.ok)throw Error(`PostHog ${method} ${r.status}: ${(await r.text()).slice(0,300)}`);return r.json()}

const fixtures = [
 ['app_entry_started','e1','cold_launch','p1','','',''],
 ['app_entry_started','e1','cold_launch','p1','','',''],
 ['app_entry_source_observed','e1','','p1','notification','followed_you','remote'],
 ['app_entry_source_observed','e1','','p1','notification','followed_you','remote'],
 ['app_entry_source_observed','e1','','p1','link','',''],
 ['app_entry_started','e2','foreground_return','p1','','',''],
 ['app_entry_started','e3','cold_launch','p2','','',''],
 ['app_entry_source_observed','e3','','p2','link','',''],
 ['app_entry_started','e4','foreground_return','p3','','',''],
 ['app_entry_source_observed','e4','','p3','notification','',''],
 ['app_entry_started','e5','cold_launch','p2','','',''],
 ['app_entry_source_observed','orphan','','p9','notification','followed_you','remote'],
];
const names=['event','entry_id','entry_kind','person_id','entry_source','notification_type','delivery_channel'];
const fixtureSQL=fixtures.map((row,i)=>`select ${row.map((v,j)=>`'${v}'${i===0?' as '+names[j]:''}`).join(', ')}, toDateTime('2026-09-21 12:00:00')${i===0?' as timestamp':''}`).join(' union all ');
for(const daily of [false,true]) {
 let sql=appEntrySQL({daily});
 const predicate=sql.split("event = 'app_entry_started' and ")[1].split('\n    and notEmpty')[0];
 if(sql.split(predicate).length!==3)throw Error('Expected two production filters');
 sql=sql.replaceAll(predicate,'1 = 1').replaceAll('from events','from fixture_events').replaceAll('properties.','').replaceAll('now()', "toDateTime('2026-09-21 18:00:00')");
 sql='with fixture_events as ('+fixtureSQL+'), '+sql.slice(5);
 let id;
 try{
  id=(await api('insights/','POST',{name:'REC-581 temporary app entry arithmetic fixture',query:{kind:'HogQLQuery',query:sql},saved:false,tags:['recme:validation-only']})).id;
  const r=await api(`insights/${id}/?refresh=force_blocking`);
  if(r.error||!Array.isArray(r.result))throw Error('Fixture failed '+JSON.stringify(r.error));
  const rows=r.result;
  const assert=(ok,message)=>{if(!ok)throw Error(message)};
  if(daily)assert(JSON.stringify(rows[0].slice(1))===JSON.stringify([2,1,1,1]),'Daily one-entry accounting');
  else{
   assert(rows.reduce((n,r)=>n+r[4],0)===5,'Duplicate entries/sources and orphan callbacks must not multiply entries');
   assert(rows.some(r=>r[0]==='notification'&&r[1]==='cold_launch'&&r[2]==='followed_you'&&r[3]==='remote'&&r[4]===1),'Notification wins over link');
   assert(rows.some(r=>r[0]==='notification'&&r[2]==='unknown'&&r[3]==='unknown'),'Missing type/channel remain unknown');
   assert(rows.filter(r=>r[0]==='direct_or_unknown').reduce((n,r)=>n+r[4],0)===2,'Unmatched entries retained');
  }
  console.log(JSON.stringify({daily,result:'PASS',columns:r.columns,rows}));
 }finally{if(id)await api(`insights/${id}/`,'PATCH',{deleted:true})}
}
