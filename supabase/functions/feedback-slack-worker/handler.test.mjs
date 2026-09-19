import assert from 'node:assert/strict';
import test from 'node:test';
import { handleRequest, slackPayload, verifiedContact } from './handler.ts';
const job={id:'54500000-0000-0000-0000-000000000003',user_id:'user_original',body:'<!channel> <https://bad.example|click>',attachments:[],display_name:'Feedback Test',handle:'feedbacktest',clerk_user_ids:['user_live'],app_version:'1',build_number:'176',submitted_at:'2026-09-19',claim_token:'claim'};
const config={SUPABASE_URL:'https://rugmtlgufrhlxwfkumhw.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-service-key',ASTIR_FEEDBACK_SLACK_WORKER_SECRET:'test-worker-secret',ASTIR_FEEDBACK_SLACK_WEBHOOK_URL:'https://hooks.slack.com/services/TTEST/BTEST/test',ASTIR_FEEDBACK_CLERK_SECRET_KEY:'test-clerk-key'};
const user={id:'user_live',public_metadata:{canonical_user_id:'user_original'},primary_email_address_id:'email',email_addresses:[{id:'email',email_address:'feedback@example.test',verification:{status:'verified'}}],primary_phone_number_id:'phone',phone_numbers:[{id:'phone',phone_number:'+15555550100',verification:{status:'verified'}}]};
const request=()=>new Request('https://example.test',{method:'POST',headers:{'x-feedback-worker-secret':'test-worker-secret'}});
const deps=(fetch,overrides={})=>({env:key=>({...config,...overrides})[key],fetch});
test('requires worker authentication before any work',async()=>{
 let calls=0;const r=await handleRequest(new Request('https://example.test',{method:'POST'}),deps(async()=>{calls++;}));
 assert.equal(r.status,401);assert.equal(calls,0);
});
for(const overrides of [{ASTIR_FEEDBACK_SLACK_WEBHOOK_URL:undefined},{ASTIR_FEEDBACK_CLERK_SECRET_KEY:undefined},{SUPABASE_URL:'https://other.supabase.co'},{ASTIR_FEEDBACK_SLACK_WEBHOOK_URL:'https://bad.example/secret'}])test('missing or misrouted configuration does not claim reports '+JSON.stringify(overrides),async()=>{
 let calls=0;const r=await handleRequest(request(),deps(async()=>{calls++;},overrides));assert.equal(r.status,503);assert.equal(calls,0);
});
test('verified contact follows the canonical account and excludes unverified or MFA-only numbers',()=>{
 assert.deepEqual(verifiedContact(user,'user_original'),{email:'feedback@example.test',phone:'+15555550100'});
 assert.deepEqual(verifiedContact(user,'user_other'),{});
 assert.deepEqual(verifiedContact({...user,email_addresses:[{...user.email_addresses[0],verification:{status:'unverified'}}],phone_numbers:[{...user.phone_numbers[0],reserved_for_second_factor:true}]},'user_original'),{email:undefined,phone:undefined});
});
test('long feedback stays plain text and does not create Slack mentions or unfurls',()=>{
 const p=slackPayload({...job,body:job.body.repeat(200)}, {}, []);
 assert.equal(p.text,'New Astir feedback');assert.equal(p.unfurl_links,false);
 for(const block of p.blocks.filter(x=>x.type==='section')) {assert.equal(block.text.type,'plain_text');assert.ok(block.text.text.length<=3000);}
 assert.ok(p.blocks.some(x=>x.text?.text.includes('Not available')));
});
test('real delivery path resolves migrated identity, signs private media, and settles Slack independently',async()=>{
 const seen=[];const mediaJob={...job,attachments:[{filename:'photo.jpg',kind:'photo'},{filename:'voice.m4a',kind:'voice'}]};
 const r=await handleRequest(request(),deps(async(url,init)=>{
  seen.push({url,init});
  if(url.endsWith('claim_feedback_slack'))return Response.json([mediaJob]);
  if(url.includes('api.clerk.com'))return Response.json(user);
  if(url.includes('/object/sign/'))return Response.json({signedURL:url.replace(config.SUPABASE_URL+'/storage/v1','')+'?token=test'});
  if(url===config.ASTIR_FEEDBACK_SLACK_WEBHOOK_URL)return new Response('ok');
  return Response.json(true);
 }));
 assert.deepEqual(await r.json(),{sent:1,retrying:0});
 const payload=JSON.parse(seen.find(x=>x.url===config.ASTIR_FEEDBACK_SLACK_WEBHOOK_URL).init.body);
 assert.ok(payload.blocks[1].text.text.includes('feedback@example.test'));
 assert.ok(payload.blocks.some(x=>x.elements?.some(e=>e.text.text==='Listen to voice note')));
 assert.equal(JSON.parse(seen.at(-1).init.body).p_accepted,true);
 assert.ok(seen.at(-1).url.endsWith('settle_feedback_slack'));
});
for(const failure of ['clerk','media','slack','timeout'])test('retains stored reports and retries when '+failure+' fails',async()=>{
 const settlements=[];let posts=0;
 const r=await handleRequest(request(),deps(async(url,init)=>{
  if(url.endsWith('claim_feedback_slack'))return Response.json([{...job,attachments:[{filename:'photo.jpg',kind:'photo'}]}]);
  if(url.includes('api.clerk.com'))return failure==='clerk'?new Response('',{status:503}):Response.json(user);
  if(url.includes('/object/sign/'))return failure==='media'?new Response('',{status:404}):Response.json({signedURL:url.replace(config.SUPABASE_URL+'/storage/v1','')+'?token=test'});
  if(url===config.ASTIR_FEEDBACK_SLACK_WEBHOOK_URL){posts++;if(failure==='timeout')throw new DOMException('timeout','TimeoutError');return new Response('',{status:429});}
  settlements.push(JSON.parse(init.body));return Response.json(true);
 }));
 assert.deepEqual(await r.json(),{sent:0,retrying:1});assert.equal(settlements[0].p_accepted,false);
 if(['clerk','media'].includes(failure))assert.equal(posts,0);
});
test('no verified contact still delivers report with an explicit account lookup fallback',async()=>{
 let payload;
 const r=await handleRequest(request(),deps(async(url,init)=>{
  if(url.endsWith('claim_feedback_slack'))return Response.json([job]);
  if(url.includes('api.clerk.com'))return new Response('',{status:404});
  if(url===config.ASTIR_FEEDBACK_SLACK_WEBHOOK_URL){payload=JSON.parse(init.body);return new Response('ok');}
  return Response.json(true);
 }));assert.equal((await r.json()).sent,1);assert.ok(payload.blocks[1].text.text.includes('Not available'));
});
test('lost settlement can retry the same report without claiming exactly-once Slack delivery',async()=>{
 const posted=[];let settleCalls=0;
 const fetch=async(url,init)=>{
  if(url.endsWith('claim_feedback_slack'))return Response.json([job]);
  if(url.includes('api.clerk.com'))return Response.json(user);
  if(url===config.ASTIR_FEEDBACK_SLACK_WEBHOOK_URL){posted.push(JSON.parse(init.body));return new Response('ok');}
  if(settleCalls++===0)throw new TypeError('connection lost after Slack acceptance');
  return Response.json(true);
 };
 assert.equal((await handleRequest(request(),deps(fetch))).status,503);
 // SQL allows a subsequent claim only after its lease expires.
 assert.deepEqual(await (await handleRequest(request(),deps(fetch))).json(),{sent:1,retrying:0});
 assert.equal(posted.length,2);
 for(const payload of posted)assert.ok(payload.blocks.some(block=>block.text?.text.includes('Report: '+job.id)));
});
