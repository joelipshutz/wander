import assert from 'node:assert/strict';
import {api,productionSQL} from './posthog-product-dashboard.mjs';
import {permissionOverviewSQL,recipientDailySQL,recipientGuard} from './posthog-permissions-dashboard.mjs';

if(process.env.WANDER_POSTHOG_PROJECT_ID!=='557259')throw Error('Expected Astir project');
const quote = value => "'"+String(value).replaceAll('\\','\\\\').replaceAll("'","\\'")+"'";
function fixtureSQL(query,rows,filter='1=1') {
  const source=rows.map(([event,user,timestamp,properties],index)=>`select ${quote(event)}${index===0?' as event':''},${quote(user)}${index===0?' as distinct_id':''},${quote(user)}${index===0?' as person_id':''},toDateTime(${quote(timestamp)})${index===0?' as timestamp':''},${quote(JSON.stringify(properties))}${index===0?' as properties':''}`).join(' union all ');
  const sql=query.replaceAll(productionSQL,'1=1').replaceAll(recipientGuard,'1=1')
    .replaceAll('{filters}',filter).replaceAll('from events','from fixture_events')
    .replace(/properties\.([a-zA-Z_]+)/g,(_,name)=>`JSONExtractString(properties,'${name}')`)
    .replaceAll('now()',"toDateTime('2026-09-21 20:00:00')");
  return 'with fixture_events as ('+source+'), '+sql.slice(5);
}
async function run(label,query,check) {
  let id;try {
    id=(await api('/api/projects/557259/insights/',{method:'POST',body:{name:'REC-581 temporary permission fixture',query:{kind:'HogQLQuery',query},saved:false}})).id;
    const result=await api(`/api/projects/557259/insights/${id}/?refresh=force_blocking`);
    assert.ok(Array.isArray(result.result),result.query_status?.error_message || 'Missing result');
    check(result.result);console.log(JSON.stringify({label,passed:true}));
  } finally {if(id)await api(`/api/projects/557259/insights/${id}/`,{method:'PATCH',body:{deleted:true}});}
}

const observations=[
  ['app_session_started','user_a','2026-09-21 10:00:00',{}],
  ['app_session_started','user_b','2026-09-21 10:00:00',{}],
  ['app_session_started','user_c','2026-09-21 10:00:00',{}],
  ['permission_status_observed','user_a','2026-09-21 11:00:00',{permission:'notifications',status:'denied'}],
  ['permission_status_observed','user_a','2026-09-21 12:00:00',{permission:'notifications',status:'limited'}],
  ['permission_status_observed','user_b','2026-09-21 12:00:00',{permission:'notifications',status:'not_determined'}],
];
await run('latest status; limited enabled; not asked in denominator; missing unknown',fixtureSQL(permissionOverviewSQL(),observations),rows=>{
  assert.equal(rows.length,7);
  assert.deepEqual(rows.find(row=>row[0]==='notifications'),['notifications',3,2,1,1,0,1,0,1,50]);
  assert.equal(rows.find(row=>row[0]==='camera').at(-1),null);
});

const daily=accepted=>JSON.stringify([{day:'2026-09-20',accepted:0,failed:0,skipped:0,pending:0},{day:'2026-09-21',accepted,failed:0,skipped:1,pending:0}]);
const row=(batch,user,accepted)=>['notification_recipient_snapshot',user,'2026-09-21 12:00:00',{
  snapshot_id:batch,analytics_audience:'external_recipients_v1',username:user,push_enabled:'true',preferences_known:'true',active_production_tokens:'1',preferences:'{}',daily_counts:daily(accepted),
}];
const complete=batch=>['notification_recipient_snapshot_completed','operations','2026-09-21 12:00:00',{snapshot_id:batch,analytics_audience:'external_recipients_v1',recipient_count:'2'}];
const rows=[row('old','user_a',2),row('old','user_b',0),complete('old'),row('newer','user_a',9),complete('newer'),
  ['notification_opened','user_a','2026-09-21 13:00:00',{delivery_channel:'remote'}],
  ['notification_opened','user_b','2026-09-21 13:00:00',{delivery_channel:'remote'}],
];
// ISO batch IDs sort chronologically in production; use the same ordering here.
for(const entry of rows)if(entry[3].snapshot_id)entry[3].snapshot_id=entry[3].snapshot_id==='old'?'2026-09-21T10:00:00Z':'2026-09-21T11:00:00Z';
await run('incomplete generation ignored, other user excluded, zero days retained',fixtureSQL(recipientDailySQL(),rows,"properties.username='user_a'"),result=>{
  assert.equal(result.length,2);assert.equal(result[0][1],0);assert.equal(result[1][1],2);assert.equal(result[1][5],1);
});
await run('unselected multi-user directory cannot produce a single-user total',fixtureSQL(recipientDailySQL(),rows),result=>assert.equal(result.length,0));
await run('missing username produces no fabricated zeroes',fixtureSQL(recipientDailySQL(),rows,"properties.username='missing'"),result=>assert.equal(result.length,0));
await run('known user with zero sends still has daily rows',fixtureSQL(recipientDailySQL(),rows,"properties.username='user_b'"),result=>{
  assert.equal(result.length,2);assert.equal(result.reduce((sum,row)=>sum+row[1],0),0);
});
const emptyBatch=[...rows,['notification_recipient_snapshot_completed','operations','2026-09-21 13:00:00',{
  snapshot_id:'2026-09-21T12:00:00Z',analytics_audience:'external_recipients_v1',recipient_count:'0',
}]];
await run('completed empty generation supersedes older recipients',fixtureSQL(recipientDailySQL(),emptyBatch,"properties.username='user_a'"),result=>assert.equal(result.length,0));
