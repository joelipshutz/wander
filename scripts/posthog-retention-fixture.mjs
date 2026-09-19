// SQL-only arithmetic validation. Creates one unsaved insight and soft-deletes it; never captures events.
import { retentionSQL } from './posthog-product-dashboard.mjs';
if (process.env.WANDER_POSTHOG_PROJECT_ID !== '557259') throw new Error('Expected Astir project 557259');
const key = process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
if (!key) throw new Error('Missing WANDER_POSTHOG_PERSONAL_API_KEY');
async function api(path, method='GET', body) {
 const r=await fetch('https://us.posthog.com/api/projects/557259/'+path,{method,headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:body ? JSON.stringify(body):undefined});
 if(!r.ok) throw new Error(`PostHog ${method} ${r.status}`);
 return r.json();
}
let sql=retentionSQL('core_action_performed','core_action_performed');
const observed=sql.slice(sql.indexOf('), observed as ('));
sql=`with cohort as (
 select 'returning' as person_id, now() - interval 40 day as started_at
 union all select 'absent', now() - interval 40 day
 union all select 'immature', now() - interval 36 hour
), return_events as (
 select 'returning' as person_id, now() - interval 39 day + interval 1 hour as timestamp
 union all select 'returning', now() - interval 33 day + interval 1 hour
 union all select 'returning', now() - interval 26 day + interval 1 hour
 union all select 'returning', now() - interval 10 day + interval 1 hour
 union all select 'immature', now() - interval 2 hour
${observed}`;
let id;
try {
 const saved=await api('insights/','POST',{name:'REC-170 temporary retention arithmetic validation',query:{kind:'HogQLQuery',query:sql},saved:false,tags:['recme:validation-only']}); id=saved.id;
 const result=await api(`insights/${id}/?refresh=force_blocking`);
 if(result.error || !Array.isArray(result.result)) throw new Error('Fixture did not execute');
 const data=result.result.map(row=>Object.fromEntries(result.columns.map((c,i)=>[c,row[i]])));
 const mature=data.find(row=>Number(row.cohort_users)===2);
 const young=data.find(row=>Number(row.cohort_users)===1);
 for(const d of [1,7,14,30]) {
  if(Number(mature?.[`d${d}_eligible`])!==2 || Number(mature?.[`d${d}_returned`])!==1 || Number(mature?.[`d${d}_percent`])!==50) throw new Error(`D${d} mature calculation failed`);
  if(Number(young?.[`d${d}_eligible`])!==0 || young?.[`d${d}_percent`]!==null) throw new Error(`D${d} immature calculation failed`);
 }
 console.log(JSON.stringify({result:'PASS',assertions:8,scope:'PostHog SQL fixture: 50% for mature cohorts; immature observed returns excluded; zero denominator is null',rows:data}));
} finally {
 if(id) {await api(`insights/${id}/`,'PATCH',{deleted:true});console.log('Temporary validation insight soft-deleted. No events ingested.');}
}
