import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import {
  validateBaselineReceipt, generateBaselineSQL, generateVerificationSQL, generateContractVerificationSQL,
  generateTransitionSQL, generateReconcileSQL, generateCleanupSQL, createCleanupCompanion,
  isVerifiedCleanupCompanion, CleanupCompanionError,
} from './rec636-cleanup-companion.mjs';

const ID = (suffix) => `10000000-0000-4000-8000-${suffix.toString(16).padStart(12, '0')}`;
const NOW = '2026-10-14T00:00:00.000000Z';
const clone = (v) => JSON.parse(JSON.stringify(v));
function scope() { return {runID:ID(1),targetRef:'abcdefghijklmnopqrst',accounts:{A:'fixture_account_a',B:'fixture_account_b'},context:{kind:'place',id:ID(2)}}; }
function baseline() {
  const s = scope();
  const flag = (id) => ({id:ID(id),xmin:'100',enabled:true,valueType:'boolean',integerValue:null});
  const follow = (id) => ({id:ID(id),xmin:'100',source:'profile',createdAt:NOW,updatedAt:NOW});
  return {version:1,...s,capturedAt:NOW,profiles:[{id:s.accounts.A,xmin:'100',deleted:false},{id:s.accounts.B,xmin:'100',deleted:false}],
    globalFlag:{...flag(3),enabled:false},accountFlags:[{userID:s.accounts.A,row:flag(4)},{userID:s.accounts.B,row:flag(5)}],
    follows:[{followerID:s.accounts.A,followedID:s.accounts.B,row:follow(6)},{followerID:s.accounts.B,followedID:s.accounts.A,row:follow(7)}],
    blocks:[{blockerID:s.accounts.A,blockedID:s.accounts.B,row:null},{blockerID:s.accounts.B,blockedID:s.accounts.A,row:null}],
    contextReceipt:{kind:'place',id:ID(2),xmin:'100',ownerID:s.accounts.A,placeID:ID(2),visibility:'mutuals',deleted:false,allowedA:true,allowedB:true,userPlaceID:ID(8),sourceXmin:'100'},
    conversationCount:0,messageCount:0,sharedVisitCount:0,sourceSideEffectCount:0};
}
function state(intents = [], phase = 'active') { return {version:1,...scope(),createdAt:NOW,revision:intents.length,phase,baseline:baseline(),intents:clone(intents)}; }
const start = () => ({id:ID(10),kind:'start',actor:'A',recipient:'B',context:scope().context,state:'acknowledged',ack:{conversationID:ID(11)}});
const send = (ack = true) => ({id:ID(12),kind:'send',actor:'A',conversationID:ID(11),clientID:ID(13),context:scope().context,state:ack?'acknowledged':'interrupted',...(ack?{ack:{conversationID:ID(11),messageID:ID(14),senderID:scope().accounts.A,clientID:ID(13)}}:{})});
const transition = (resource, action, actor='A', id=20) => ({id:ID(id),kind:'operator_transition',actor,state:'intent',transition:{resource,action,actor,...(['follow','block'].includes(resource)?{targetActor:actor==='A'?'B':'A'}:{})}});
const blocked = (fn, code) => assert.throws(fn,(e) => e instanceof CleanupCompanionError && (!code || e.code===code));
const source = readFileSync(new URL('./rec636-cleanup-companion.mjs',import.meta.url),'utf8');

test('scope is injection safe and rejects unknown/accessor/prototype input', () => {
  for (const bad of [ {...scope(),accounts:{A:"x';delete from profiles;--",B:'b'}}, {...scope(),context:{kind:'place',id:'notuuid'}}, {...scope(),secret:'do not disclose'}, Object.assign(Object.create({}),scope()) ]) blocked(()=>generateBaselineSQL(bad));
  const bad=scope(); Object.defineProperty(bad,'runID',{get(){throw new Error('secret');},enumerable:true}); blocked(()=>generateBaselineSQL(bad));
  assert.match(generateBaselineSQL(scope()), /begin isolation level serializable read only/);
});
test('baseline examines all private tables, including hidden and empty conversations', () => {
  const sql=generateBaselineSQL(scope());
  assert.match(sql,/from public.private_conversations where low_user_id=any/);
  assert.match(sql,/or high_user_id=any/);
  assert.doesNotMatch(sql,/private_message_inbox/);
  const countClause=sql.split("'conversationCount',")[1].split("'messageCount',")[0];
  assert.doesNotMatch(countClause,/context_allowed|pair_allowed|private_messages/);
  for (const [field,value] of [['conversationCount',1],['messageCount',1],['sharedVisitCount',1],['sourceSideEffectCount',1]]) {
    const b=baseline(); b[field]=value; blocked(()=>validateBaselineReceipt(b));
  }
});
test('both explicit enrollments, mutual edges and unblocked fixture baseline are required', () => {
  for (const modify of [b=>b.globalFlag.enabled=true,b=>b.accountFlags[1].row.enabled=false,b=>b.accountFlags[0].row=null,b=>b.follows[0].row=null,b=>b.blocks[1].row={id:ID(50),xmin:'100',createdAt:NOW},b=>b.profiles[0].deleted=true,b=>b.contextReceipt.allowedB=false,b=>b.contextReceipt.visibility='followers',b=>delete b.contextReceipt.sourceXmin]) {
    const b=baseline(); modify(b); blocked(()=>validateBaselineReceipt(b));
  }
  assert.deepEqual(validateBaselineReceipt(baseline()),baseline());
});
test('ordinary source IDs cannot establish synthetic ownership or permit third-party exposure', () => {
  const sql=generateBaselineSQL(scope());
  assert.match(sql,/source_provider='rec636_validation'/);
  assert.match(sql,/source_provider_place_id='rec636:'\|\|/);
  assert.match(sql,/canonical_name='REC-636 verification fixture'/);
  assert.match(sql,/saved.note is null and saved.rating_signal is null/);
  assert.match(sql,/select saved.xmin::text as source_revision,saved.\*/);
  assert.match(sql,/'sourceXmin',saved.source_revision/);
  assert.match(sql,/count\(\*\) from public.user_places p[^;]*\)=1 then 0 else 1/s);
  assert.match(sql,/not\(follower_user_id=any.*and followed_user_id=any/);
  assert.match(sql,/public.place_list_items/); assert.match(sql,/app.private_list_companion_origins/);
  assert.match(sql,/public.place_visits/); assert.match(sql,/public.place_taxonomy_snapshots/);
});
test('activity fixtures require the exact canonical Wanna event owned by the selected source', () => {
  const s=scope(); s.context={kind:'activity',id:ID(15)};
  const sql=generateBaselineSQL(s);
  assert.match(sql,/app.canonical_activity_id\(event.id\)=event.id/);
  assert.match(sql,/event.actor_user_id=saved.user_id and event.place_id=saved.place_id/);
  assert.match(sql,/event.list_id is null and event.list_item_id is null/);
  assert.match(sql,/event.event_type='place_want_to_go'/);
});
test('all SQL is bounded, catalog-pinned and leaves global activation unchanged', () => {
  const scripts=[generateBaselineSQL(scope()),generateContractVerificationSQL(),generateVerificationSQL(baseline()),generateTransitionSQL(state([transition('account_flag','revoke')]),ID(20)),generateCleanupSQL(state([start(),send()],'cleanup_planned')),generateReconcileSQL(state([start(),send(false)]))];
  for (const sql of scripts) {
    assert.match(sql,/lock_timeout='5s'/); assert.match(sql,/statement_timeout='30s'/); assert.match(sql,/search_path=pg_catalog/);
    assert.doesNotMatch(sql,/grant |create (?:or replace )?function|drop table|delete from public.profiles|session_replication_role|disable trigger|set role/iu);
    assert.doesNotMatch(sql,/update public.feature_flags[^;]*user_id is null/iu);
  }
});
test('mutating and reconciliation transactions serialize both senders then lock all matching messages', () => {
  const sql=generateCleanupSQL(state([start(),send()],'cleanup_planned'));
  assert.equal((sql.match(/pg_advisory_xact_lock/g)||[]).length,2);
  assert.ok(sql.indexOf("'private-message:'||'fixture_account_a'")<sql.indexOf("'private-message:'||'fixture_account_b'"));
  assert.match(sql,/public.private_conversations.*order by id for update/s);
  assert.match(sql,/public.private_messages.*order by id for update/s);
  assert.ok(sql.indexOf('global_live_drift')<sql.indexOf('delete from public.private_messages'));
});
test('cleanup requires the durable frozen phase and no unresolved mutation or retry', () => {
  blocked(()=>generateCleanupSQL(state([start(),send()])), 'cleanup_freeze_required');
  blocked(()=>generateCleanupSQL(state([start(),send(false)],'cleanup_planned')));
  const pending=transition('account_flag','revoke'); blocked(()=>generateCleanupSQL(state([pending],'cleanup_planned')));
  assert.match(generateCleanupSQL(state([start(),send()],'cleanup_planned')), /baselineRestored/);
});
test('foreign conversations and message identities fail closed before any deletion', () => {
  const sql=generateCleanupSQL(state([start(),send()],'cleanup_planned'));
  assert.ok(sql.indexOf("raise exception 'foreign_conversation'")<sql.indexOf('delete from public.private_messages'));
  assert.ok(sql.indexOf("raise exception 'foreign_message'")<sql.indexOf('delete from public.private_messages'));
  for (const id of [ID(11),ID(13),ID(14)]) assert.ok(sql.includes(id));
  assert.match(sql,/m.sender_id='fixture_account_a'/); assert.match(sql,/m.context_kind='place'/);
  assert.match(sql,/delete from public.private_messages where id=any\(array\[/);
  assert.match(sql,/delete from public.private_conversations where id=any\(array\[/);
  assert.doesNotMatch(sql,/delete from public.private_messages where sender_id/);
});
test('exact concurrent baseline revisions are guarded and profile rows are never rewritten', () => {
  const s=state([start(),send()],'cleanup_planned'); s.baseline.accountFlags[0].row.xmin='123456789';
  const sql=generateCleanupSQL(s);
  assert.match(sql,/123456789/); assert.match(sql,/operator_baseline_drift/); assert.match(sql,/profile_baseline_drift/);
  assert.doesNotMatch(sql,/(?:update|delete from) public.profiles/);
  const bad=transition('account_flag','revoke'); bad.state='acknowledged'; bad.ack={before:{...baseline().accountFlags[0].row,xmin:'999'},after:{...baseline().accountFlags[0].row,xmin:'1000',enabled:false}};
  blocked(()=>generateCleanupSQL(state([bad],'cleanup_planned')));
});
test('follow restoration preserves identity and creation time without disabling notification triggers', () => {
  const removed=transition('follow','remove'); removed.state='acknowledged'; removed.ack={before:baseline().follows[0].row,after:null};
  const restored=transition('follow','restore','A',21);
  const sql=generateTransitionSQL(state([removed,restored]),ID(21));
  assert.match(sql,/values\([^;]*'signup_default'/);
  assert.match(sql,/update public.follows set source='profile'/);
  assert.ok(sql.includes(ID(6))); assert.ok(sql.includes(NOW));
  assert.match(sql,/unexpected_notification_effect/); assert.doesNotMatch(sql,/disable|replication_role/i);
  const cleanup=generateCleanupSQL(state([removed],'cleanup_planned')); assert.match(cleanup,/ - 'xmin' - 'updatedAt'/);
});
test('block IDs belong to the intent and source revocation belongs to its exact owner', () => {
  const block=generateTransitionSQL(state([transition('block','insert')]),ID(20)); assert.ok(block.includes(ID(20)));
  blocked(()=>generateTransitionSQL(state([transition('context','revoke','B')]),ID(20)), 'context_not_owned');
  const revoked=generateTransitionSQL(state([transition('context','revoke')]),ID(20));
  assert.match(revoked,/where id='10000000-0000-4000-8000-000000000008'::uuid and user_id='fixture_account_a'/);
  const b=baseline(); b.contextReceipt.visibility='self'; const s=state([transition('context','revoke')]); s.baseline=b; blocked(()=>generateTransitionSQL(s,ID(20)));
});
test('a lost send acknowledgment reconciles only the exact pair/client/context identity', () => {
  const sql=generateReconcileSQL(state([start(),send(false)]));
  assert.match(sql,/foreign_client_identity/); assert.match(sql,/m.client_id='10000000-0000-4000-8000-00000000000d'::uuid/);
  assert.match(sql,/m.conversation_id='10000000-0000-4000-8000-00000000000b'::uuid/);
  assert.match(sql,/m.context_id='10000000-0000-4000-8000-000000000002'::uuid/);
  assert.doesNotMatch(sql,/m.body|lastMessagePreview|display_name|avatar/);
});
test('an unacknowledged empty start remains ambiguous, never inferred run-owned', () => {
  const pending=start(); pending.state='interrupted'; delete pending.ack;
  assert.match(generateReconcileSQL(state([pending])), /then 'ambiguous' else 'absent'/);
  blocked(()=>generateCleanupSQL(state([pending],'cleanup_planned')));
});
test('unacknowledged operator/read changes require operator reconciliation before cleanup', () => {
  blocked(()=>generateReconcileSQL(state([transition('account_flag','revoke')])), 'operator_or_read_reconciliation_required');
  const read={id:ID(21),kind:'mark_read',actor:'B',state:'interrupted',conversationID:ID(11),throughMessageID:ID(14)};
  blocked(()=>generateReconcileSQL(state([start(),send(),read])), 'operator_or_read_reconciliation_required');
});
test('completed cleanup authorizes read-only idempotent verification without deleting fixtures', () => {
  const s=state([start(),send()],'cleaned'); s.cleanupReceipt={runID:ID(1),conversationCount:0,messageCount:0,baselineRestored:true,globalLiveEnabled:false};
  const sql=generateCleanupSQL(s); assert.match(sql,/read only/); assert.doesNotMatch(sql,/delete |update |insert /i);
  assert.doesNotMatch(generateCleanupSQL(state([start(),send()],'cleanup_planned')), /delete from public\.(?:places|user_places|feed_events)/);
});
test('repeated cleanup verifies original follow/source identity and logical contents rather than eligibility alone', () => {
  const s=state([start(),send()],'cleaned'); s.cleanupReceipt={runID:ID(1),conversationCount:0,messageCount:0,baselineRestored:true,globalLiveEnabled:false};
  const sql=generateCleanupSQL(s);
  assert.match(sql,/baseline_restoration_failed/); assert.match(sql,/context_restoration_failed/);
  assert.match(sql,/global_live_drift/); assert.match(sql,/profile_baseline_drift/); assert.match(sql,/fixture_side_effect_risk/);
  assert.ok(sql.includes(ID(6))); assert.ok(sql.includes(ID(8))); assert.ok(sql.includes(NOW));
  assert.match(sql,/"source":"profile"/); assert.match(sql,/"visibility":"mutuals"/);
  assert.match(sql,/ - 'xmin' - 'updatedAt'\) is distinct from/);
  assert.match(sql,/ - 'xmin' - 'sourceXmin' - 'allowedA' - 'allowedB'\) is distinct from/);
  assert.doesNotMatch(sql,/delete |update |insert /i);
});
test('context denial is asserted inside the operator transaction before any successful receipt or commit', () => {
  const sql=generateTransitionSQL(state([transition('context','revoke')]),ID(20));
  const denial=sql.indexOf("raise exception 'context_revocation_failed'");
  assert.ok(denial>sql.indexOf("set visibility='self'"));
  assert.ok(denial<sql.indexOf("set_config('rec636.result'"));
  assert.ok(denial<sql.indexOf('commit;'));
});
test('metadata-only proof never claims account trials and validates the checked-in body fingerprints', () => {
  const sql=generateContractVerificationSQL(); assert.match(sql,/'accountTrialsVerified',false/);
  assert.match(sql,/read only/); assert.match(sql,/rollback;/); assert.doesNotMatch(sql,/fixture_account|private_messages where sender_id/);
  const contract=readFileSync(new URL('../supabase/tests/rec636_dormant_metadata.sql',import.meta.url),'utf8');
  for (const match of source.matchAll(/\['((?:app|public)\.[^']+)', '([0-9a-f]{32})'\]/g)) {
    if (contract.includes(match[1])) { assert.ok(contract.includes(match[2]),match[1]); continue; }
    const fn=match[1].slice(4).split('(')[0]; let body;
    const directory=new URL('../supabase/migrations/',import.meta.url);
    for (const name of readdirSync(directory).filter(n=>n.endsWith('.sql')).sort()) {
      const text=readFileSync(new URL(name,directory),'utf8');
      const regex=new RegExp(`create\\s+(?:or\\s+replace\\s+)?function\\s+app\\.${fn}\\([^;]*?as\\s+\\$\\$(.*?)\\$\\$;`,'gis');
      for (const parsed of text.matchAll(regex)) body=parsed[1];
    }
    assert.ok(body,fn); assert.equal(createHash('md5').update(body).digest('hex'),match[2],fn);
  }
});
test('factory requires an actual injected SQL path and only a strict successful rollback proof brands the object', async () => {
  await assert.rejects(()=>createCleanupCompanion({spec:scope()}), e=>e.code==='operator_adapter_required');
  for (const proof of [{approved:true},{version:1,runID:ID(1),targetRef:scope().targetRef,operatorVerified:true,globalLiveOff:true,pristineBaseline:true,fixtureTransitionsVerified:true,rolledBack:false,contractChecks:24}]) {
    await assert.rejects(()=>createCleanupCompanion({spec:scope(),executeSQL:async(_sql,{purpose})=>[{rec636_result:purpose==='baseline'?baseline():proof}]}));
  }
  const calls=[];
  const c=await createCleanupCompanion({spec:scope(),executeSQL:async(sql,meta)=>{calls.push([sql,meta]); return [{rec636_result:meta.purpose==='baseline'?baseline():{version:1,runID:ID(1),targetRef:scope().targetRef,operatorVerified:true,globalLiveOff:true,pristineBaseline:true,fixtureTransitionsVerified:true,rolledBack:true,contractChecks:24}}];}});
  assert.equal(isVerifiedCleanupCompanion(c),true); assert.equal(isVerifiedCleanupCompanion({...c}),false);
  assert.equal(c.capabilities.fixtureProvisioning,false); assert.equal(c.capabilities.fixtureDeletion,false);
  assert.deepEqual(calls.map(c=>c[1].purpose),['baseline','verification']); assert.match(calls[1][0],/rollback;/);
  assert.deepEqual(await c.assertReady(state()),{globalLiveOff:true,pristineBaseline:true,fixtureTransitionsVerified:true});
});
test('executor faults and baseline drift return code-only errors without SQL or private payloads', async () => {
  const secret='private payload token=do-not-disclose';
  await assert.rejects(()=>createCleanupCompanion({spec:scope(),executeSQL:async()=>{throw new Error(secret);}}), e=>e.message==='operator_execution_failed'&&!JSON.stringify(e).includes(secret));
  let reads=0;
  const c=await createCleanupCompanion({spec:scope(),executeSQL:async(_sql,{purpose})=>{
    if(purpose==='verification') return [{rec636_result:{version:1,runID:ID(1),targetRef:scope().targetRef,operatorVerified:true,globalLiveOff:true,pristineBaseline:true,fixtureTransitionsVerified:true,rolledBack:true,contractChecks:24}}];
    const b=baseline(); if(reads++) b.globalFlag.xmin='101'; return [{rec636_result:b}];
  }});
  await assert.rejects(()=>c.assertReady(state()),e=>e.code==='baseline_drift');
});
