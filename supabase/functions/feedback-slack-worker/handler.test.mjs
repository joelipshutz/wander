import assert from 'node:assert/strict';
import test from 'node:test';
import { attachmentLinkLifetimeSeconds, handleRequest, slackPayload, verifiedContact } from './handler.ts';
const job={id:'54500000-0000-0000-0000-000000000003',user_id:'user_original',body:'<!channel> <https://bad.example|click>',attachments:[],display_name:'Feedback Test',handle:'feedbacktest',clerk_user_ids:['user_live'],app_version:'1',build_number:'176',submitted_at:'2026-09-19',claim_token:'claim'};
const config={SUPABASE_URL:'https://rugmtlgufrhlxwfkumhw.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-service-key',ASTIR_FEEDBACK_SLACK_WORKER_SECRET:'test-worker-secret',ASTIR_FEEDBACK_SLACK_WEBHOOK_URL:'https://hooks.slack.com/services/TTEST/BTEST/test',ASTIR_FEEDBACK_CLERK_SECRET_KEY:'test-clerk-key'};
const user={id:'user_live',public_metadata:{canonical_user_id:'user_original'},primary_email_address_id:'email',email_addresses:[{id:'email',email_address:'feedback@example.test',verification:{status:'verified'}}],primary_phone_number_id:'phone',phone_numbers:[{id:'phone',phone_number:'+15555550100',verification:{status:'verified'}}]};
const request=()=>new Request('https://example.test',{method:'POST',headers:{'x-feedback-worker-secret':'test-worker-secret'}});
const deps=(fetch,overrides={})=>({env:key=>({...config,...overrides})[key],fetch});
const elements=payload=>payload.blocks.filter(block=>block.type==='rich_text').flatMap(block=>block.elements.flatMap(section=>section.elements));
const literalText=payload=>elements(payload).filter(element=>element.type==='text').map(element=>element.text).join('\n');
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
test('long feedback stays literal and bold without creating Slack mentions, links or unfurls',()=>{
 const body=('🙂 *bold* <!channel> <@U123> <https://bad.example|click> & ').repeat(100);
 const p=slackPayload({...job,body,display_name:'<!everyone>',handle:'<@U123>'}, {}, []);
 assert.equal(p.text,'New Astir feedback');assert.equal(p.unfurl_links,false);assert.equal(p.unfurl_media,false);
 for(const element of elements(p)) {
  assert.ok(['text','date'].includes(element.type));assert.equal(element.style.bold,true);
  if(element.type==='text'){assert.ok(element.text.length<=3000);assert.ok(element.text.isWellFormed());}
 }
 const bodyBlocks=p.blocks.slice(2,-1).flatMap(block=>block.elements.flatMap(section=>section.elements));
 assert.equal(bodyBlocks.map(element=>element.text).join('').replace(/^Feedback text\n/,''),body);
 assert.ok(literalText(p).includes('Sender: <!everyone> (@<@U123>)'));
 assert.ok(literalText(p).includes('Not available'));
 assert.ok(!p.blocks.some(block=>block.type==='actions'));
 assert.ok(!JSON.stringify(p).includes('Open server inbox'));
 assert.ok(!JSON.stringify(p).includes('Attachment links expire'));
});
test('available media gets explicit bold sections and a readable local timestamp',()=>{
 const submitted='2026-09-19T17:30:00Z';
 const p=slackPayload({...job,body:'Great app!',submitted_at:submitted},{email:'feedback@example.test',phone:'+15555550100'},[
  {kind:'photo',url:'https://example.test/photo1'}, {kind:'photo',url:'https://example.test/photo2'},
  {kind:'voice',url:'https://example.test/voice'},
 ]);
 const text=literalText(p);
 for(const label of ['Sender:','Email: feedback@example.test','Phone: +15555550100','Feedback text\nGreat app!','Feedback photo 1:','Feedback photo 2:','Feedback voice note:','Submitted:'])assert.ok(text.includes(label),label);
 const links=elements(p).filter(element=>element.type==='link');
 assert.deepEqual(links.map(element=>element.url),['https://example.test/photo1','https://example.test/photo2','https://example.test/voice']);
 for(const element of elements(p))assert.equal(element.style.bold,true);
 const date=elements(p).find(element=>element.type==='date');
 assert.equal(date.timestamp,Date.parse(submitted)/1000);assert.equal(date.format,'{date_long_pretty} at {time}');
 assert.match(date.fallback,/September 19, 2026/);assert.match(date.fallback,/UTC$/);
 assert.ok(!text.includes(submitted));
});
test('attachment-only feedback omits the empty text section and invalid dates use a safe fallback',()=>{
 const p=slackPayload({...job,body:'',submitted_at:'not a date'}, {},[{kind:'photo',url:'https://example.test/photo'}]);
 assert.ok(literalText(p).includes('Feedback photo:'));
 assert.ok(!literalText(p).includes('Feedback text'));
 assert.ok(!literalText(p).includes('Feedback voice note'));
 assert.ok(!elements(p).some(element=>element.type==='date'));
 assert.ok(literalText(p).includes('Submitted: \nNot available'));
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
 assert.ok(literalText(payload).includes('feedback@example.test'));
 assert.ok(elements(payload).some(element=>element.type==='link'&&element.text==='Listen to voice note'));
 const signatures=seen.filter(call=>call.url.includes('/object/sign/'));
 assert.equal(signatures.length,2);assert.equal(attachmentLinkLifetimeSeconds,2592000);
 for(const call of signatures)assert.equal(JSON.parse(call.init.body).expiresIn,2592000);
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
 }));assert.equal((await r.json()).sent,1);assert.ok(literalText(payload).includes('Not available'));
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
 for(const payload of posted)assert.ok(literalText(payload).includes('Report: '+job.id));
});
