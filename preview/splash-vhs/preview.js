/* REC-557: reuse the selected Events 03C signal; draw the approved PNG, never type. */
'use strict';
const $ = selector => document.querySelector(selector);
const canvas = $('#splash'), artwork = $('#original'), texture = $('#texture');
const reference = $('#reference'), phone = $('.phone'), status = $('#status');
const scene = document.createElement('canvas'), ctx = scene.getContext('2d', {alpha:false});
const grain = document.createElement('canvas'); grain.width=180; grain.height=320;
const gc=grain.getContext('2d'), noise=gc.createImageData(180,320);
const devices={standard:{w:393,h:852},compact:{w:375,h:667},large:{w:440,h:956}};
const reduceMotion=matchMedia('(prefers-reduced-motion: reduce)');
let device=devices.standard, mode='splash', elapsed=0, previous=performance.now(), lastFrame=-1;
let paused=reduceMotion.matches, ready=false, seed=987123, renderTape;
try { renderTape=createTapeRenderer(canvas); } catch(error) { status.textContent=error.message; }
function rand(){seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return(seed>>>0)/4294967296;}
function updateGrain(t){seed=987123+Math.floor(t*24)*131;for(let i=0;i<noise.data.length;i+=4){const l=rand()*110;noise.data[i]=l+rand()*22;noise.data[i+1]=l+rand()*26;noise.data[i+2]=l+rand()*24;noise.data[i+3]=255;}gc.putImageData(noise,0,0);}
function resize(){canvas.width=scene.width=720;canvas.height=scene.height=Math.round(720*device.h/device.w);phone.style.setProperty('--ratio',device.w/device.h);phone.dataset.viewport=device.w+'x'+device.h;artwork.style.width=(Math.min(460,device.w-32)/device.w*100)+'%';lastFrame=-1;if(ready)draw(elapsed);}
function cover(video,w,h){const s=Math.max(w/video.videoWidth,h/video.videoHeight);ctx.drawImage(video,(w-video.videoWidth*s)/2,(h-video.videoHeight*s)/2,video.videoWidth*s,video.videoHeight*s);}
// The spatial degradation remains 03C. Move its brief faults into launch time
// and across the central artwork so even a sub-second opening shows tape wear.
function faultAt(t){
  if(t<.08)return[0,.5];
  if(t<.29)return[1,.53+(t-.08)*.18];
  if(t>=.46&&t<.59)return[1,.44];
  if(t>=.86&&t<1.05)return[1,.57-(t-.86)*.32];
  if(t>=1.31&&t<1.44)return[1,.49];
  return[0,.5];
}
function density(t){for(const[a,b,p]of[[.08,.16,.35],[.16,.20,.94],[.20,.29,.16],[.31,.39,.58],[.46,.53,.35],[.53,.59,.58],[.86,.95,.35],[.95,1.05,.58],[1.31,1.38,.35]])if(t>=a&&t<b)return p;return .94;}
function draw(t){
  if(!ready||!renderTape)return;
  const still=reduceMotion.matches, w=device.w,h=device.h,r=720/w;
  updateGrain(t);ctx.setTransform(1,0,0,1,0,0);ctx.fillStyle='#0c1010';ctx.fillRect(0,0,scene.width,scene.height);ctx.save();ctx.scale(r,r);
  if(texture.readyState>=2){ctx.globalAlpha=.78;ctx.filter='brightness(.88) saturate(1.15)';cover(texture,w,h);ctx.filter='none';ctx.globalAlpha=1;}
  const hue=still?0:t*.12,cloud=ctx.createRadialGradient(w*(.45+.2*Math.sin(hue)),h*.43,0,w*.45,h*.48,h*.65);
  cloud.addColorStop(0,'rgba(25,36,29,.25)');cloud.addColorStop(1,'rgba(0,0,0,.48)');ctx.fillStyle=cloud;ctx.fillRect(0,0,w,h);
  ctx.imageSmoothingEnabled=false;ctx.globalCompositeOperation='screen';ctx.globalAlpha=.11;ctx.drawImage(grain,0,0,w,h);ctx.globalAlpha=1;ctx.globalCompositeOperation='source-over';ctx.imageSmoothingEnabled=true;
  const artW=Math.min(460,w-32),artH=artW/(1600/764);
  ctx.globalAlpha=still?.94:density(t);ctx.drawImage(artwork,(w-artW)/2,(h-artH)/2,artW,artH);ctx.globalAlpha=1;
  ctx.globalCompositeOperation='multiply';ctx.globalAlpha=.23;ctx.imageSmoothingEnabled=false;ctx.drawImage(grain,0,0,w,h);ctx.globalAlpha=1;ctx.globalCompositeOperation='source-over';ctx.restore();
  renderTape(scene,t+.17,1,still,still?[0,.5]:faultAt(t));
  canvas.dataset.time=t.toFixed(3);canvas.dataset.fault=String(!still&&faultAt(t)[0]===1);
}
function updateStatus(text){status.textContent=text;}
function syncPlayback(){
  const playing=ready&&!paused&&!document.hidden&&!reduceMotion.matches;
  if(playing&&mode==='splash')texture.play().catch(()=>{});else texture.pause();
  if(playing&&mode==='reference')reference.play().catch(()=>{});else reference.pause();
  $('#pause').textContent=paused?'Play':'Pause';
}
function replay(){mode='splash';elapsed=0;previous=performance.now();lastFrame=-1;paused=reduceMotion.matches;texture.currentTime=0;setMode('splash');draw(0);syncPlayback();}
function setMode(next){mode=next;canvas.hidden=mode!=='splash';artwork.hidden=mode!=='original';reference.hidden=mode!=='reference';phone.style.background=mode==='original'?'#080a09':'#0c1010';document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.mode===mode)));$('#pause').disabled=mode==='original'||reduceMotion.matches;updateStatus(mode==='original'?'Exact approved artwork.':mode==='reference'?'Approved Coming Soon film · original 8-second loop.':reduceMotion.matches?'Reduce Motion · static tape treatment.':'VHS splash · 1.8-second preview.');syncPlayback();}
function tick(now){const delta=Math.min((now-previous)/1000,.1);previous=now;if(ready&&!paused&&!document.hidden&&mode==='splash'){
  elapsed+=delta;const duration=Number($('#duration').value);if(elapsed>=duration+.65&&$('#loop').checked){elapsed=0;texture.currentTime=0;syncPlayback();}
  const t=Math.min(elapsed,duration),frame=Math.floor(t*24);if(frame!==lastFrame){draw(t);lastFrame=frame;}
  if(elapsed>=duration){texture.pause();updateStatus($('#loop').checked?'End of splash · replaying…':'End of splash · replay to watch again.');}else updateStatus(`${t.toFixed(1)} / ${duration.toFixed(1)} seconds`);
}requestAnimationFrame(tick);}
document.querySelectorAll('[data-mode]').forEach(b=>b.addEventListener('click',()=>setMode(b.dataset.mode)));
$('#replay').addEventListener('click',replay);$('#pause').addEventListener('click',()=>{paused=!paused;previous=performance.now();if(!paused&&mode==='splash'&&elapsed>=Number($('#duration').value))elapsed=0;syncPlayback();updateStatus(paused?'Paused.':'Playing.');});
$('#duration').addEventListener('change',replay);$('#size').addEventListener('change',e=>{device=devices[e.target.value];resize();});
document.addEventListener('visibilitychange',()=>{previous=performance.now();syncPlayback();});reduceMotion.addEventListener('change',()=>{paused=reduceMotion.matches;elapsed=0;draw(0);setMode(mode);});
function loaded(element,event){return new Promise((resolve,reject)=>{element.addEventListener(event,resolve,{once:true});element.addEventListener('error',reject,{once:true});});}
resize();$('#pause').textContent=paused?'Play':'Pause';
Promise.all([artwork.decode(),texture.readyState>=2?Promise.resolve():loaded(texture,'loadeddata')]).then(()=>{ready=true;if(!renderTape){setMode('original');updateStatus('WebGL unavailable. Showing the original artwork.');return;}replay();requestAnimationFrame(tick);}).catch(()=>{setMode('original');updateStatus('A preview asset could not load. Serve from the repository root.');});
// Deterministic inspection hook for local visual verification and exports.
window.splashPreview={renderAt:async t=>{paused=true;elapsed=t;syncPlayback();const target=t%8;if(Math.abs(texture.currentTime-target)>.001){const seeking=loaded(texture,'seeked');texture.currentTime=target;await seeking;}draw(t);return{time:t,fault:faultAt(t),viewport:device,artwork:[artwork.naturalWidth,artwork.naturalHeight]};},getState:()=>({ready,paused,mode,elapsed,reduceMotion:reduceMotion.matches,webgl:!!renderTape,viewport:device})};
