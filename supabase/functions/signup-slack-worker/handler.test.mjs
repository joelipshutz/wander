import test from 'node:test';
import assert from 'node:assert/strict';
import { handleRequest, signupDetails, slackPayload } from './handler.ts';

const config = {
  SUPABASE_URL: 'https://rugmtlgufrhlxwfkumhw.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'test-service',
  ASTIR_SIGNUP_SLACK_WORKER_SECRET: 'test-worker', ASTIR_SIGNUP_CLERK_SECRET_KEY: 'sk_live_test',
  ASTIR_SIGNUP_SLACK_WEBHOOK_URL: 'https://hooks.slack.com/services/T0B9DS16JS2/BTEST/test',
};
const job = {profile_id:'user_test', display_name:'Test Person', clerk_user_ids:[], signed_up_at:new Date().toISOString(), claim_token:'test-claim'};
const user = {id:'user_test', first_name:'John',last_name:'Smith',created_at:Date.parse(job.signed_up_at),
  primary_email_address_id:'email_primary', email_addresses:[
    {id:'email_secondary', email_address:'wrong@example.test',verification:{status:'verified'}},
    {id:'email_primary',email_address:'john@example.test',verification:{status:'verified'}},
  ]};
const request = () => new Request('https://example.test',{method:'POST',headers:{'x-signup-worker-secret':'test-worker'}});
const run = async (opts={}) => {
  const calls=[];
  const response=await handleRequest(opts.request || request(),{env:k=>({...config,...opts.config})[k],fetch:async(url,init)=>{
    calls.push({url,body:init?.body ? JSON.parse(init.body) : undefined});
    if(url.endsWith('claim_signup_slack'))return Response.json(opts.jobs || [job]);
    if(url.endsWith('settle_signup_slack'))return opts.settlementFailure ? new Response('',{status:503}) : Response.json(true);
    if(url.startsWith('https://api.clerk.com/'))return opts.clerkResponse ? opts.clerkResponse() : Response.json(opts.user || user);
    if(url.startsWith('https://hooks.slack.com/'))return opts.slackResponse ? opts.slackResponse() : new Response('ok');
    throw new Error('unexpected URL');
  }});
  return {calls,response,result:await response.json()};
};

test('unauthorized and GET calls never access customer data',async()=>{
  for(const req of [new Request('https://example.test'),new Request('https://example.test',{method:'POST'})]){
    const r=await run({request:req}); assert.ok([401,405].includes(r.response.status));assert.equal(r.calls.length,0);
  }
});
test('fails closed for wrong project/workspace, missing webhook, and development Clerk key',async()=>{
  for(const override of [{SUPABASE_URL:'https://other.supabase.co'},{ASTIR_SIGNUP_SLACK_WEBHOOK_URL:''},
    {ASTIR_SIGNUP_SLACK_WEBHOOK_URL:'https://hooks.slack.com/services/TOTHER/B/x'}, {ASTIR_SIGNUP_CLERK_SECRET_KEY:'sk_test_x'}]){
    const r=await run({config:override});assert.equal(r.response.status,503);assert.equal(r.calls.length,0);
  }
});
test('sends name and verified primary email, then acknowledges claim',async()=>{
  const r=await run();assert.deepEqual(r.result,{sent:1,retrying:0,skipped:0});
  const slack=r.calls.find(c=>c.url.startsWith('https://hooks.slack.com/'));
  assert.equal(slack.body.blocks[0].text.text,'John Smith signed up\nEmail: john@example.test');
  assert.equal(r.calls.at(-1).body.p_claim,job.claim_token);assert.equal(r.calls.at(-1).body.p_outcome,'sent');
});
test('names cannot inject mentions/links, and long/unicode input stays bounded',()=>{
  const d=signupDetails({...user,first_name:'<!everyone>\n🫶'.repeat(1000),last_name:null},job);
  const p=slackPayload(d);assert.ok(d.name.length<=200);assert.equal(p.blocks[0].text.type,'plain_text');
  assert.ok(!p.text.includes('<!everyone>'));assert.equal(p.mrkdwn,false);assert.equal(p.parse,'none');
});
test('handles missing name/email and Apple relay addresses honestly',()=>{
  assert.deepEqual(signupDetails({...user,first_name:null,last_name:null,email_addresses:[]},job),{name:'Test Person',email:'Not provided'});
  const relay={...user,email_addresses:[{id:'email_primary',email_address:'relay@privaterelay.appleid.com',verification:{status:'verified'}}]};
  assert.equal(signupDetails(relay,job).email,'relay@privaterelay.appleid.com');
  relay.email_addresses[0].verification.status='unverified';assert.equal(signupDetails(relay,job).email,'Not provided');
});
test('resolves canonical identity mappings; rejects another account',async()=>{
  const r=await run({user:{...user,id:'user_production',external_id:job.profile_id}});assert.equal(r.result.sent,1);
  const bad=await run({user:{...user,id:'user_wrong'}});assert.equal(bad.result.retrying,1);
  assert.equal(bad.calls.at(-1).body.p_error,'identity_mismatch');assert.ok(!bad.calls.some(c=>c.url.startsWith('https://hooks.slack.com/')));
});
test('does not mistake dev events for an existing production signup',async()=>{
  const r=await run({user:{...user,created_at:Date.parse(job.signed_up_at)-86400000}});
  assert.equal(r.result.skipped,1);assert.equal(r.calls.at(-1).body.p_error,'creation_mismatch');
  assert.ok(!r.calls.some(c=>c.url.startsWith('https://hooks.slack.com/')));
});
test('missing production account retries mapping races, then skips dev/deleted accounts',async()=>{
  const missing=()=>new Response('',{status:404});
  assert.equal((await run({clerkResponse:missing})).result.retrying,1);
  const r=await run({jobs:[{...job,signed_up_at:new Date(Date.now()-3600000).toISOString()}],clerkResponse:missing});
  assert.equal(r.result.skipped,1);
});
for(const failure of ['clerk','slack','timeout'])test('retries '+failure+' failures without exposing private response details',async()=>{
  const r=await run(failure==='clerk'?{clerkResponse:()=>new Response('private data',{status:429})}:
    {slackResponse:()=>{if(failure==='timeout')throw new Error('private webhook URL');return new Response('private data',{status:503});}});
  assert.equal(r.result.retrying,1);assert.equal(r.calls.at(-1).body.p_outcome,'retry');
  assert.ok(!JSON.stringify(r.result).includes('private'));assert.ok(!r.calls.at(-1).body.p_error.includes('private'));
});
test('Slack 200 with non-ok body is retried',async()=>{
  const r=await run({slackResponse:()=>new Response('invalid_payload')});assert.equal(r.result.retrying,1);
});
test('empty queue produces no messages and settlement outage is not reported as success',async()=>{
  const r=await run({jobs:[]});assert.equal(r.calls.length,1);assert.equal(r.result.sent,0);
  assert.equal((await run({settlementFailure:true})).response.status,503);
});
