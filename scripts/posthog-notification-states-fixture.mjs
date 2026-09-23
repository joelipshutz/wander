import assert from 'node:assert/strict';
import {api,productionSQL} from './posthog-product-dashboard.mjs';
import {notificationStateDailySQL,recipientGuard,notificationStateColumns,permissionInsights,permissionSections} from './posthog-permissions-dashboard.mjs';

if(process.env.WANDER_POSTHOG_PROJECT_ID!=='557259')throw Error('Expected Astir project');
const quote=value=>"'"+String(value).replaceAll('\\','\\\\').replaceAll("'","\\'")+"'";
const audience={analytics_audience:'external_recipients_v1'};
const batch='2026-09-20T12:00:00Z';
function snapshot(user,{push='true',known='true',tokens='1',accepted=0,failed=0,id=batch}={}) {
 return ['notification_recipient_snapshot',user,id.slice(0,19).replace('T',' '),{
  ...audience,snapshot_id:id,push_enabled:push,preferences_known:known,active_production_tokens:tokens,
  daily_counts:JSON.stringify([{day:'2026-09-19',accepted:9,failed:0},{day:'2026-09-20',accepted,failed}]),
 }];
}
const completion=(id,count)=>['notification_recipient_snapshot_completed','operations',id.slice(0,19).replace('T',' '),{...audience,snapshot_id:id,recipient_count:String(count)}];
const permission=(user,status,at='2026-09-20 11:00:00')=>['permission_status_observed',user,at,{permission:'notifications',status}];
const users=[snapshot('a',{accepted:2}),snapshot('b'),snapshot('c',{tokens:'0'}),snapshot('d',{accepted:2,failed:1}),snapshot('e'),snapshot('f',{push:'false'}),snapshot('g'),snapshot('h'),snapshot('i',{known:'false'})];
const rows=[...users,completion(batch,9),...['a','c','d','f','i'].map(u=>permission(u,'enabled')),permission('b','limited'),permission('e','denied'),permission('g','not_determined'),
 permission('a','denied','2026-09-21 11:00:00'), // Future changes cannot rewrite the prior day.
 snapshot('a',{id:'2026-09-20T13:00:00Z',push:'false'}),completion('2026-09-20T13:00:00Z',9), // Incomplete later generation ignored.
 snapshot('a',{accepted:2}), // Duplicate exported row does not create a tenth person.
 completion('2026-09-18T12:00:00Z',0),completion('2026-09-21T12:00:00Z',0),
];
function fixtureSQL(input) {
 const source=input.map(([event,user,time,properties],i)=>`select ${quote(event)}${i===0?' as event':''},${quote(user)}${i===0?' as distinct_id':''},${quote(user)}${i===0?' as person_id':''},toDateTime(${quote(time)})${i===0?' as timestamp':''},${quote(JSON.stringify(properties))}${i===0?' as properties':''}`).join(' union all ');
 const sql=notificationStateDailySQL().replaceAll(productionSQL,'1=1').replaceAll(recipientGuard,'1=1')
  .replaceAll('from events','from fixture_events').replace(/properties\.([a-zA-Z_]+)/g,(_,name)=>`JSONExtractString(properties,'${name}')`)
  .replaceAll('now()',"toDateTime('2026-09-21 20:00:00')");
 return 'with fixture_events as ('+source+'), '+sql.slice(5);
}
async function run(label,input,check) {
 let id;try {
  id=(await api('/api/projects/557259/insights/',{method:'POST',body:{name:'REC-581 temporary daily notification state fixture',saved:false,query:{kind:'HogQLQuery',query:fixtureSQL(input)}}})).id;
  const r=await api(`/api/projects/557259/insights/${id}/?refresh=force_blocking`);
  assert.ok(Array.isArray(r.result),r.query_status?.error_message||'Missing result');check(r.result);
  console.log(JSON.stringify({label,passed:true}));
 }finally{if(id)await api(`/api/projects/557259/insights/${id}/`,{method:'PATCH',body:{deleted:true}});}
}
const definition=permissionInsights.find(x=>x.key==='notifications-user-states-daily');
assert.deepEqual(definition.query.chartSettings.yAxis.map(x=>x.column),notificationStateColumns);
assert.equal(permissionSections.flatMap(x=>x.insightKeys).filter(x=>x===definition.key).length,1);
assert.ok(definition.query.source.query.includes(recipientGuard));
assert.ok(!definition.query.source.query.includes('{filters}'));
await run('exclusive states; token and failure problems; limited; as-of permissions; incomplete and duplicate exports',rows,result=>{
 assert.deepEqual(result.find(r=>r[0]==='2026-09-20'),['2026-09-20',9,1,1,2,2,3]);
 assert.ok(result.filter(r=>r[1]!==null).every(r=>r[1]===r.slice(2).reduce((sum,n)=>sum+n,0)));
});
await run('missing days blank; complete empty days zero; no invented history before snapshots',rows,result=>{
 assert.equal(result.length,4);
 assert.deepEqual(result[0],['2026-09-18',0,0,0,0,0,0]);
 assert.deepEqual(result[1],['2026-09-19',null,null,null,null,null,null]);
 assert.deepEqual(result[3],['2026-09-21',0,0,0,0,0,0]);
});
await run('permissions older than 30 days are unconfirmed even with tokens and accepted sends',[
 snapshot('stale',{accepted:2}),completion(batch,1),permission('stale','enabled','2026-08-01 11:00:00'),
],result=>assert.deepEqual(result.find(r=>r[0]==='2026-09-20'),['2026-09-20',1,0,0,0,0,1]));
await run('no complete snapshot produces no fabricated history',[
 snapshot('a'),completion(batch,2),permission('a','enabled'),
],result=>assert.equal(result.length,0));
