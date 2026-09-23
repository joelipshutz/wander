import {notificationAuditEvents,exportNotificationAudit,type NotificationAuditRow} from './audit-analytics.ts';
function assert(ok:unknown,message:string):asserts ok{if(!ok)throw Error(message);}
const row:NotificationAuditRow={audit_id:'audit1',notification_ref:'reference1',user_id:'user_fixture',username:'fictional',recorded_at:'2026-09-23T12:00:00Z',occurred_at:'2026-09-23T11:59:00Z',record_kind:'device_attempt',status:'retryable_failure',environment:'production',attempt_count:1,notification_type:'followed_you',title:'Fictional title',body:'Fictional body',reason:'ServiceUnavailable',http_status:503,history_source:'live_transition'};
Deno.test('audit includes requested text and recipient, never arbitrary payload fields or staff',()=>{
 const dirty={...row,device_token:'private-token',actor_user_id:'private-actor',data:{private:'payload'},deeplink:'private-url'};
 const events=notificationAuditEvents([dirty,{...row,user_id:'staff'}],new Set(['staff']));
 assert(events.length===1,'staff included');
 assert(events[0].properties.notification_body==='Fictional body'&&events[0].properties.username==='fictional','requested columns missing');
 assert(!JSON.stringify(events).includes('private-'),'unallowlisted data exported');
 assert(events[0].properties.audit_id==='audit1','dedup key missing');
});
Deno.test('failed capture leaves audit unacknowledged; successful retry acknowledges only that batch',async()=>{
 let acked=false;let queries=0;
 const rpc=async<T>(name:string,body:Record<string,unknown>):Promise<T>=>{
  if(name==='ack_notification_audit_export'){assert(JSON.stringify(body.input_ids)==='["audit1"]','wrong ack');acked=true;return null as T;}
  assert(name==='notification_audit_export_batch','unexpected RPC');queries++;return (acked?[]:[row]) as T;
 };
 const failed=await exportNotificationAudit(rpc,()=>Promise.resolve(false),new Set());
 assert(!failed.ok&&!acked,'failed export acknowledged');
 const retried=await exportNotificationAudit(rpc,()=>Promise.resolve(true),new Set());
 assert(retried.ok&&acked&&retried.exported===1&&queries===3,'retry incorrect');
});
Deno.test('audit acknowledgement failure propagates so the next run can retry',async()=>{
 let threw=false;
 const rpc=async<T>(name:string):Promise<T>=>{if(name==='ack_notification_audit_export')throw Error('temporary');return [row] as T;};
 try{await exportNotificationAudit(rpc,()=>Promise.resolve(true),new Set());}catch{threw=true;}
 assert(threw,'ack failure hidden');
});
