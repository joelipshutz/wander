import { recipientAnalyticsEvents, type RecipientSnapshot } from './recipient-analytics.ts';
import { handleRequest } from './index.ts';

function assert(ok: unknown, message: string): asserts ok { if (!ok) throw Error(message); }
const fixture: RecipientSnapshot = {
  snapshot_at: '2026-09-21T20:00:00Z', window_days: 30, analytics_audience: 'external_recipients_v1',
  recipients: [
    {user_id:'user_external',username:'fixture',push_enabled:true,preferences_known:true,active_production_tokens:2,
      preferences:{social_graph:true,untrusted_payload:true},
      daily_counts:[{day:'2026-09-21',accepted:3,failed:0,skipped:1,pending:0}]},
    {user_id:'user_staff',username:'staff',push_enabled:true,preferences_known:true,active_production_tokens:1,preferences:{},daily_counts:[]},
  ],
};

Deno.test('recipient export excludes staff and allowlists fields and preferences', () => {
  const result=recipientAnalyticsEvents(fixture,new Set(['user_staff']));
  assert(result.rows.length===1,'staff included');
  assert(result.completion.properties.recipient_count===1,'wrong generation count');
  assert(result.rows[0].properties.distinct_id==='user_external','identity lost');
  assert(!JSON.stringify(result).includes('untrusted_payload'),'unallowlisted preference leaked');
  assert(result.rows[0].properties.$process_person_profile===false,'unexpected person mutation');
  for(const forbidden of ['device_token','actor_user_id','notification_id','title','body','email']) {
    assert(!Object.keys(result.rows[0].properties).includes(forbidden),'private property leaked');
  }
});

Deno.test('recipient export rejects a legacy audience', () => {
  let threw=false;try {recipientAnalyticsEvents({...fixture,analytics_audience:'legacy'},new Set());}catch {threw=true;}
  assert(threw,'legacy audience accepted');
});

Deno.test('reporting route never sends pushes and publishes completion only after all rows succeed', async () => {
  const originalFetch=globalThis.fetch;
  const env={SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'fixture-service',WANDER_WORKER_SECRET:'fixture-worker',WANDER_POSTHOG_PROJECT_TOKEN:'fixture-project'};
  const previous=Object.fromEntries(Object.keys(env).map(key=>[key,Deno.env.get(key)]));
  for(const [key,value] of Object.entries(env))Deno.env.set(key,value);
  try {
    for(const rejectRows of [false,true]) {
      const captures: string[][]=[];let rpcCalls=0;
      globalThis.fetch=((input: string|URL|Request, init?: RequestInit)=>{
        const url=String(input);
        if(url.endsWith('/rest/v1/rpc/notification_recipient_analytics_snapshot')) {rpcCalls++;return Promise.resolve(Response.json(fixture));}
        assert(url==='https://us.i.posthog.com/batch/','reporting route attempted an unrelated request');
        const batch=JSON.parse(String(init?.body)).batch;captures.push(batch.map((row:{event:string})=>row.event));
        return Promise.resolve(new Response('{}',{status:rejectRows?500:200}));
      }) as typeof fetch;
      const result=await handleRequest(new Request('https://fixture/report',{method:'POST',headers:{'x-wander-worker-secret':'fixture-worker'},body:JSON.stringify({analytics_snapshot:true})}));
      assert(rpcCalls===1,'reporting should issue exactly one read-only RPC');
      assert(result.status===(rejectRows?502:200),'incorrect reporting outcome');
      assert(captures.length===(rejectRows?1:2),'completion published before successful rows');
      if(!rejectRows)assert(captures[1][0]==='notification_recipient_snapshot_completed','completion missing');
    }
  } finally {
    globalThis.fetch=originalFetch;
    for(const [key,value] of Object.entries(previous)){if(value===undefined)Deno.env.delete(key);else Deno.env.set(key,value);}
  }
});
