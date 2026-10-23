/* REC-557 v4. Early tracking bend on an elapsed launch clock; no brightness flicker. */
'use strict';
const $=s=>document.querySelector(s), art=$('#artwork'), texture=$('#texture'), reference=$('#reference');
const status=$('#status'), reduced=matchMedia('(prefers-reduced-motion: reduce)');
const W=393,H=852,R=720/W, LEAD=0, STATIC_TIME=.4, TEAR_TIME=.6;
const frames=['splash','account'].map(id=>{const canvas=$('#'+id);canvas.width=720;canvas.height=1560;const scene=document.createElement('canvas');scene.width=720;scene.height=1560;const signal=scene.cloneNode();return{id,canvas,ctx:canvas.getContext('2d'),scene,sc:scene.getContext('2d'),signal,render:createBrandTapeRenderer(signal)};});
const detail=$('#detail');detail.width=1000;detail.height=478;const dc=detail.getContext('2d');
const grain=document.createElement('canvas');grain.width=180;grain.height=320;const gc=grain.getContext('2d'),pixels=gc.createImageData(180,320);
let seed=987123,treatment=reduced.matches?'static':'motion',paused=reduced.matches,ready=false,recording=false,cycleElapsed=0,lastNow=performance.now(),lastTick=-1;
function random(){seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return(seed>>>0)/4294967296;}
function makeGrain(t){seed=987123+Math.round(t*24)*131;for(let i=0;i<pixels.data.length;i+=4){const l=random()*110;pixels.data[i]=l+random()*22;pixels.data[i+1]=l+random()*26;pixels.data[i+2]=l+random()*24;pixels.data[i+3]=255;}gc.putImageData(pixels,0,0);}
function artRect(kind){const w=kind==='splash'?361:172,h=w/(1600/764);return{x:(W-w)/2,y:kind==='splash'?(H-h)/2:72,w,h};}
function cover(c,video){const scale=Math.max(W/video.videoWidth,H/video.videoHeight);c.drawImage(video,(W-video.videoWidth*scale)/2,(H-video.videoHeight*scale)/2,video.videoWidth*scale,video.videoHeight*scale);}
function background(c,t){c.fillStyle='#0c1010';c.fillRect(0,0,W,H);if(texture.readyState>=2){c.globalAlpha=.78;c.filter='brightness(.88) saturate(1.15)';cover(c,texture);c.filter='none';c.globalAlpha=1;}const cloud=c.createRadialGradient(W*(.45+.2*Math.sin(t*.12)),H*.43,0,W*.45,H*.48,H*.65);cloud.addColorStop(0,'rgba(25,36,29,.25)');cloud.addColorStop(1,'rgba(0,0,0,.48)');c.fillStyle=cloud;c.fillRect(0,0,W,H);c.imageSmoothingEnabled=false;c.globalCompositeOperation='screen';c.globalAlpha=.11;c.drawImage(grain,0,0,W,H);c.globalAlpha=1;c.globalCompositeOperation='source-over';c.imageSmoothingEnabled=true;}
function label(c,text,x,y,font,color='#e6ddcd',align='center'){c.font=font;c.fillStyle=color;c.textAlign=align;c.textBaseline='alphabetic';c.fillText(text,x,y);}
function round(c,x,y,w,h,r,fill,stroke){c.beginPath();c.roundRect(x,y,w,h,r);c.fillStyle=fill;c.fill();if(stroke){c.strokeStyle=stroke;c.lineWidth=.8;c.stroke();}}
// A representative native layout. Only the logo is under review; form ink is
// drawn after the signal pass, keeping controls legible and stationary.
function accountUI(c){
 label(c,'Create your account',W/2,207,'900 38px FilmGrotesk','#f05a3c');
 label(c,'Keep your places synced and discover',W/2,239,'14px AppBody','#a6a797');label(c,'recommendations from people you trust.',W/2,259,'14px AppBody','#a6a797');
 round(c,16,281,361,54,12,'#000');label(c,' Continue with Apple',W/2,315,'22px system-ui','#fff');
 round(c,16,347,361,52,12,'#21271f','#69705d');label(c,'G',39,381,'600 22px system-ui','#4285f4');label(c,'Continue with Google',W/2+7,379,'17px AppDemi');
 c.strokeStyle='#717765';c.lineWidth=.8;c.beginPath();c.moveTo(16,424);c.lineTo(178,424);c.moveTo(214,424);c.lineTo(377,424);c.stroke();label(c,'or',W/2,428,'13px AppBody','#aaa995');
 label(c,'Email',16,466,'15px AppDemi','#e6ddcd','left');round(c,16,482,361,52,12,'#20261f','#626b55');label(c,'you@example.com',32,515,'17px AppBody','#929987','left');
 round(c,16,550,361,52,12,'#f05a3c');label(c,'Continue with email',W/2,583,'17px AppDemi','#10160e');
 label(c,'If Apple or Google returns the same verified email,',W/2,639,'12px AppBody','#a6a797');label(c,'it connects to your existing Astir account.',W/2,657,'12px AppBody','#a6a797');
 label(c,'By continuing, you agree to the Terms of Use and',W/2,690,'12px AppBody','#a6a797');label(c,'Community Guidelines, and acknowledge',W/2,708,'12px AppBody','#a6a797');label(c,'the Privacy Policy.',W/2,726,'12px AppBody','#a6a797');
 label(c,'Already have an account? Log in',W/2,771,'16px AppDemi');
}
function draw(t){if(!ready)return;makeGrain(STATIC_TIME);for(const f of frames){const c=f.sc,box=artRect(f.id);c.setTransform(R,0,0,1560/H,0,0);background(c,STATIC_TIME);c.save();c.globalAlpha=treatment==='clean'?1:.94;if(treatment!=='clean'){c.shadowColor='rgba(176,55,40,.38)';c.shadowBlur=1.5*R;c.shadowOffsetX=.4*R;}c.drawImage(art,box.x,box.y,box.w,box.h);c.restore();
 if(treatment!=='clean'){c.globalCompositeOperation='multiply';c.globalAlpha=.23;c.imageSmoothingEnabled=false;c.drawImage(grain,0,0,W,H);c.globalAlpha=1;c.globalCompositeOperation='source-over';c.imageSmoothingEnabled=true;}
 if(treatment==='clean')f.ctx.drawImage(f.scene,0,0);else{f.render(f.scene,t,1,false,[box.x/W,1-(box.y+box.h)/H,box.w/W,box.h/H]);f.ctx.drawImage(f.signal,0,0);}
 if(f.id==='account'){f.ctx.save();f.ctx.scale(R,1560/H);accountUI(f.ctx);f.ctx.restore();}
 f.canvas.dataset.elapsedTime=t.toFixed(3);f.canvas.dataset.treatment=treatment;
 }
 const b=artRect('splash');dc.drawImage(frames[0].canvas,b.x*R,b.y*1560/H,b.w*R,b.h*1560/H,0,0,detail.width,detail.height);
 $('#time').value=t.toFixed(2)+' s';$('#scrub').value=t;$('#detail-label').textContent=treatment==='clean'?'Original artwork pixels. No replacement font.':treatment==='static'?'Static material: the same grain, softened density and registration, held still.':'Actual logo pixels: inspect a tracking fault to see the silhouette tear.';
}
function loaded(el,event){return new Promise((resolve,reject)=>{el.addEventListener(event,resolve,{once:true});el.addEventListener('error',reject,{once:true});});}
async function seek(t){texture.pause();if(Math.abs(texture.currentTime-STATIC_TIME)>.002){const done=loaded(texture,'seeked');texture.currentTime=STATIC_TIME;await done;}cycleElapsed=t;draw(t);lastTick=Math.floor(t*24);}
function mediaPlayback(){texture.pause();if(document.hidden)reference.pause();$('#play').textContent=paused?'Play':'Pause';$('#play').disabled=treatment!=='motion';}
async function setTreatment(value){if(recording)return;treatment=value;paused=value!=='motion'||reduced.matches;document.querySelectorAll('[data-treatment]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.treatment===value)));await seek(value==='motion'?LEAD:STATIC_TIME);cycleElapsed=0;lastNow=performance.now();mediaPlayback();status.textContent=value==='motion'?'Bend starts 0.50 seconds after launch. No flicker or extra loading time.':value==='static'?'Static material only. No moving grain, jitter, flicker or tears.':'Original raster artwork on the same tape field.';}
async function restart(){if(recording)return;await seek(LEAD);paused=reduced.matches;cycleElapsed=0;lastNow=performance.now();mediaPlayback();}
let seeking=false;
async function tick(now){const dt=Math.max(0,Math.min((now-lastNow)/1000,.15));lastNow=now;if(ready&&treatment==='motion'&&!paused&&!document.hidden&&!seeking){cycleElapsed+=dt;const max=Number($('#cycle').value);if(cycleElapsed>=max){cycleElapsed=0;seeking=true;await seek(LEAD);seeking=false;mediaPlayback();}const t=cycleElapsed,n=Math.floor(t*24);if(n!==lastTick){draw(t);lastTick=n;}}requestAnimationFrame(tick);}
$('#tear').addEventListener('click',async()=>{if(recording)return;await setTreatment('motion');paused=true;mediaPlayback();await seek(TEAR_TIME);status.textContent='The selected bend, moved to 0.60 seconds after launch. Brightness stays steady.';});
$('#enlarge').addEventListener('click',e=>{const on=document.body.classList.toggle('large');e.currentTarget.setAttribute('aria-pressed',String(on));e.currentTarget.textContent=on?'Fit previews':'Larger previews';});
$('#play').addEventListener('click',()=>{if(recording)return;paused=!paused;lastNow=performance.now();mediaPlayback();});$('#restart').addEventListener('click',restart);$('#cycle').addEventListener('change',restart);
for(const b of document.querySelectorAll('[data-treatment]'))b.addEventListener('click',()=>setTreatment(b.dataset.treatment));
let seekQueue=Promise.resolve();$('#scrub').addEventListener('input',e=>{if(recording)return;paused=true;mediaPlayback();const t=Number(e.target.value);seekQueue=seekQueue.then(()=>seek(t));status.textContent='Paused at elapsed time since launch. Play resumes from here.';});
document.addEventListener('visibilitychange',()=>{lastNow=performance.now();mediaPlayback();});reduced.addEventListener('change',()=>setTreatment(reduced.matches?'static':'motion'));
async function save(name,blob){const response=await fetch('/__export/'+name,{method:'POST',body:blob});if(!response.ok)throw new Error('Start this page with serve.py to save media.');}
const png=c=>new Promise(resolve=>c.toBlob(resolve,'image/png'));
async function exportMedia(){
 if(!ready||recording)return;const button=$('#export'),previousCycle=$('#cycle').value;button.disabled=true;
 try{
  await setTreatment('static');for(const f of frames)await save(f.id+'-static.png',await png(f.canvas));await save('logo-static.png',await png(detail));
  await setTreatment('motion');paused=true;await seek(TEAR_TIME);await save('logo-tear.png',await png(detail));
  const mime=['video/mp4','video/webm;codecs=vp9','video/webm'].find(m=>MediaRecorder.isTypeSupported(m));if(!mime)throw new Error('Video recording is unavailable in this browser.');
  const extension=mime.startsWith('video/mp4')?'mp4':'webm';
  await seek(LEAD);cycleElapsed=0;$('#cycle').value='8';recording=true;paused=false;lastNow=performance.now();
  const sessions=frames.map(f=>{const stream=f.canvas.captureStream(24),recorder=new MediaRecorder(stream,{mimeType:mime,videoBitsPerSecond:4500000}),chunks=[];const done=new Promise((resolve,reject)=>{recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data);};recorder.onstop=()=>{stream.getTracks().forEach(t=>t.stop());resolve(new Blob(chunks,{type:mime}));};recorder.onerror=reject;});recorder.start();return{f,recorder,done};});
  status.textContent='Recording both preview videos · 8 seconds…';mediaPlayback();
  await new Promise(resolve=>setTimeout(resolve,8000));for(const s of sessions)s.recorder.stop();
  for(const s of sessions)await save(s.f.id+'-v2.'+extension,await s.done);
  document.querySelectorAll('.saved-link').forEach((a,i)=>a.href='media/'+frames[i].id+'-v2.'+extension);
  status.textContent='Saved both videos and four stills into the branch media folder.';
 }catch(error){status.textContent='Export: '+error.message;}finally{recording=false;button.disabled=false;$('#cycle').value=previousCycle;await restart();}
}
$('#export').addEventListener('click',exportMedia);
Promise.all([art.decode(),document.fonts.load('900 38px FilmGrotesk'),document.fonts.load('14px AppBody'),document.fonts.load('17px AppDemi'),... [texture,reference].map(v=>v.readyState>=2?Promise.resolve():loaded(v,'loadeddata'))]).then(async()=>{ready=true;await setTreatment(treatment);requestAnimationFrame(tick);}).catch(error=>{status.textContent='Unable to load the local study assets: '+error.message;});
