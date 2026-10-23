const devices={compact:{w:320,h:568},standard:{w:393,h:852},large:{w:440,h:956}};
const profiles=[
 {id:'light',number:'03A',name:'Light wear',damage:.23,note:'<b>A well-loved tape.</b> Softened ink, fine grain, stable orange and small timing errors.'},
 {id:'heavy',number:'03B',name:'Heavy wear',damage:.62,note:'<b>A few generations down.</b> Chroma bleed, uneven flicker, bent edges and wandering tracking.'},
 {id:'failure',number:'03C',name:'Near failure',damage:1,note:'<b>Almost lost to time.</b> Sparse speckles, stronger tracking hits, and smeared ink in signal orange.'}
];
const icons={Map:'<path d="m3 5 6-2 6 2 6-2v16l-6 2-6-2-6 2Zm6-2v16m6-14v16"/>',Feed:'<rect x="5" y="3" width="16" height="18" rx="2"/><path d="M5 8H2v11a2 2 0 0 0 2 2h3M9 7h8M9 11h8M9 15h3M9 18h3m4-3h1v3h-1z"/>',Events:'<path fill="currentColor" stroke="none" d="m12 2 2.9 7.1L22 12l-7.1 2.9L12 22l-2.9-7.1L2 12l7.1-2.9ZM20 0l1.1 2.9L24 4l-2.9 1.1L20 8l-1.1-2.9L16 4l2.9-1.1Z"/>',Lists:'<rect x="3" y="7" width="18" height="14" rx="2"/><path d="M5 4h14M8 1h8"/>',Profile:'<circle cx="12" cy="12" r="10"/><circle cx="12" cy="9" r="3"/><path d="M5 20c0-7 14-7 14 0"/>'};
const tabs=Object.entries(icons).map(([name,path])=>`<span class="tab ${name==='Events'?'active':''}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round">${path}</svg><span>${name}</span></span>`).join('');
document.getElementById('board').innerHTML=profiles.map(p=>`<article><div class="variant-heading"><span>${p.number}</span><h2>${p.name}</h2></div><div class="phone-slot"><div class="phone" data-wear="${p.id}"><div class="screen"><canvas class="tape-screen" role="img" aria-label="Coming soon in faded orange, a pale vertical bar, and An Ocean Park Experiment on three lines. ${p.name}."></canvas><div class="status" aria-hidden="true"><span>9:41</span><span class="status-icons"><svg viewBox="0 0 20 15" fill="currentColor"><rect x="1" y="10" width="3" height="4" rx=".5"/><rect x="6" y="7" width="3" height="7" rx=".5"/><rect x="11" y="4" width="3" height="10" rx=".5"/><rect x="16" y="1" width="3" height="13" rx=".5"/></svg><span class="battery"><i></i></span></span></div><div class="island" aria-hidden="true"></div><div class="glass-tabs" aria-hidden="true">${tabs}</div><div class="home" aria-hidden="true"></div></div></div></div><p class="variant-note">${p.note}</p><button class="choose" data-pick="${p.id}" type="button" aria-pressed="false">Choose ${p.number}</button></article>`).join('');
const source=document.getElementById('tape-source');source.muted=true;
const frames=[...document.querySelectorAll('.phone')].map((phone,i)=>{
 let canvas=phone.querySelector('canvas'),renderer=null;
 try{renderer=createTapeRenderer(canvas);}catch(error){phone.dataset.renderError=error.message;canvas.replaceWith(canvas.cloneNode());canvas=phone.querySelector('canvas');}
 const scene=document.createElement('canvas');phone.dataset.renderer=renderer?'WebGL':'Canvas';
 return {phone,screen:phone.querySelector('.screen'),canvas,renderer,ctx:renderer?null:canvas.getContext('2d',{alpha:false}),scene,sc:scene.getContext('2d',{alpha:false}),profile:profiles[i]};
});
const exportMode=new URLSearchParams(location.search).has('export');
let device=devices.standard,arrangement='whole',dirty=true;
const grain=document.createElement('canvas');grain.width=180;grain.height=320;const gc=grain.getContext('2d'),noise=gc.createImageData(grain.width,grain.height);
let seed=987123;function rand(){seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return (seed>>>0)/4294967296;}
function updateGrain(){for(let i=0;i<noise.data.length;i+=4){const l=rand()*110;noise.data[i]=l+rand()*22;noise.data[i+1]=l+rand()*26;noise.data[i+2]=l+rand()*24;noise.data[i+3]=255;}gc.putImageData(noise,0,0);}
function resize(){const {w,h}=device;const max=Math.max(172,Math.min(275,(innerHeight-290)*w/h));document.documentElement.style.setProperty('--phone-max',max+'px');for(const f of frames){f.phone.style.setProperty('--ratio',w/h);f.screen.style.width=w+'px';f.screen.style.height=h+'px';f.phone.style.setProperty('--scale',f.phone.clientWidth/w);const raster=.95;f.canvas.width=f.scene.width=Math.round(w*raster);f.canvas.height=f.scene.height=Math.round(h*raster);f.raster=f.canvas.width/w;f.screen.dataset.viewport=w+'x'+h;const bar=f.phone.querySelector('.glass-tabs');bar.style.bottom=(h<700?27:41)+'px';bar.style.height=(h<700?65:73)+'px';bar.querySelectorAll('.tab').forEach(t=>t.style.height=(h<700?55:61)+'px');f.phone.querySelector('.status').style.top=(h<700?20:25)+'px';f.phone.querySelector('.island').style.width=(w<350?100:122)+'px';f.phone.querySelector('.island').style.height=(w<350?28:35)+'px';}dirty=true;}
const observer=new ResizeObserver(()=>{for(const f of frames)f.phone.style.setProperty('--scale',f.phone.clientWidth/device.w);dirty=true;});frames.forEach(f=>observer.observe(f.phone));addEventListener('resize',resize);document.getElementById('size').addEventListener('change',e=>{device=devices[e.target.value];resize();});resize();
document.getElementById('words').addEventListener('change',e=>{arrangement=e.target.value;dirty=true;});
const main=document.querySelector('.vhs-main');document.getElementById('expand').addEventListener('click',e=>{const on=main.classList.toggle('large');e.currentTarget.setAttribute('aria-pressed',String(on));e.currentTarget.textContent=on?'Fit all three':'Larger view';});
function cover(ctx,video,w,h){const scale=Math.max(w/video.videoWidth,h/video.videoHeight),vw=video.videoWidth*scale,vh=video.videoHeight*scale;ctx.drawImage(video,(w-vw)/2,(h-vh)/2,vw,vh);}
function signal(t){t%=12;for(const [a,b,p] of [[.72,.81,.35],[.81,.86,.94],[.86,.99,.16],[1.04,1.13,.58],[3.20,3.28,.12],[3.31,3.45,.43],[5.74,5.88,.35],[5.88,5.94,1.08],[5.94,6.08,.18],[8.64,8.76,.38],[8.79,8.91,.06],[9.00,9.13,.51],[10.47,10.60,.28]])if(t>=a&&t<b)return p;return .94;}
const family='"VHS Grotesk", "Arial Black", Arial, sans-serif';
function fitFont(ctx,word,width){ctx.font=`900 100px ${family}`;return width/ctx.measureText(word).width*100;}
function layout(ctx,w,h){const textW=w*.752,firstSize=fitFont(ctx,'COMING',textW),secondSize=fitFont(ctx,'SOON',textW*.955),cap=.721;const captionSize=w*.0445,lineH=captionSize*1.17;const headlineH=(firstSize+secondSize)*cap+w*.018;const blockH=headlineH+w*.075+lineH*3;const top=h<700?88:130,bottom=h-(h<700?123:164);const y=top+Math.max(0,bottom-top-blockH)*.49;return {x:w*.168,barX:w*.107,y,textW,firstSize,secondSize,headlineH,captionSize,lineH,captionY:y+headlineH+w*.075,barBottom:y+blockH+2,cap};}
function drawType(ctx,f,t,still){const {w,h}=device,p=layout(ctx,w,h),d=f.profile.damage;const altWord=Math.floor(t/2)%2===0?'COMING':'SOON';let power=still?.94:1-(1-signal(t+d*.23))*(.25+d*.75);if(arrangement==='alternate'&&!still&&t%2<.13)power*=.42;
 f.screen.dataset.word=arrangement==='alternate'?altWord:'COMING SOON';f.screen.dataset.phase=(t%12).toFixed(2);f.screen.dataset.signal=power.toFixed(2);f.screen.dataset.bounds=JSON.stringify({left:p.barX,top:p.y,right:p.x+p.textW,bottom:p.barBottom});
 ctx.save();ctx.globalAlpha=power;ctx.fillStyle='#d77554';ctx.textBaseline='alphabetic';ctx.shadowColor='rgba(176,55,40,.38)';ctx.shadowBlur=.7+d*.8;ctx.shadowOffsetX=.4;
 // Natural glyph proportions: the two words fit by font size, never by stretching.
 if(arrangement==='whole'){ctx.font=`900 ${p.firstSize}px ${family}`;ctx.fillText('COMING',p.x,p.y+p.firstSize*p.cap);ctx.font=`900 ${p.secondSize}px ${family}`;ctx.fillText('SOON',p.x-.3,p.y+p.headlineH);}else{const fs=fitFont(ctx,altWord,p.textW);ctx.font=`900 ${fs}px ${family}`;ctx.fillText(altWord,p.x,p.y+(p.headlineH+fs*p.cap)*.5);}
 ctx.shadowColor='rgba(136,164,152,.33)';ctx.shadowBlur=1;ctx.shadowOffsetX=.5;ctx.fillStyle='#dedccd';ctx.strokeStyle='#d9d9c9';ctx.lineWidth=w*.007;ctx.lineCap='butt';ctx.beginPath();for(let i=0;i<=24;i++){const y=p.y-2+(p.barBottom-p.y+2)*i/24;const dx=Math.sin(i*.73)*.6+Math.sin(i*.22+.6)*.65+(still?0:Math.sin(i*.87+t)*d*.3);if(!i)ctx.moveTo(p.barX+dx,y);else ctx.lineTo(p.barX+dx,y);}ctx.stroke();
 ctx.font=`italic 800 ${p.captionSize}px Arial,sans-serif`;ctx.letterSpacing=(w*.0026)+'px';['AN','OCEAN PARK','EXPERIMENT'].forEach((line,i)=>ctx.fillText(line,p.x,p.captionY+p.captionSize*.74+p.lineH*i));ctx.restore();
}
function render(f,t,still){const {w,h}=device,{sc,raster:r}=f,d=f.profile.damage;const pw=f.canvas.width,ph=f.canvas.height;sc.setTransform(1,0,0,1,0,0);sc.fillStyle='#0c1010';sc.fillRect(0,0,pw,ph);sc.save();sc.scale(r,r);
 if(source.readyState>=2){sc.globalAlpha=.78;sc.filter='brightness(.88) saturate(1.15)';cover(sc,source,w,h);sc.filter='none';sc.globalAlpha=1;}
 const hue=still?0:t*.12;const cloud=sc.createRadialGradient(w*(.45+.2*Math.sin(hue)),h*.43,0,w*.45,h*.48,h*.65);cloud.addColorStop(0,`rgba(${Math.round(19+d*6)},${Math.round(31+d*5)},29,${.13+d*.12})`);cloud.addColorStop(1,'rgba(0,0,0,.48)');sc.fillStyle=cloud;sc.fillRect(0,0,w,h);
 sc.imageSmoothingEnabled=false;sc.globalCompositeOperation='screen';sc.globalAlpha=.065+d*.045;sc.drawImage(grain,0,0,w,h);sc.globalAlpha=1;sc.globalCompositeOperation='source-over';sc.imageSmoothingEnabled=true;
 drawType(sc,f,t,still);
 // The grain belongs to the recorded lettering as well as to the dark field.
 sc.globalCompositeOperation='multiply';sc.globalAlpha=.09+d*.14;sc.imageSmoothingEnabled=false;sc.drawImage(grain,0,0,w,h);sc.globalAlpha=1;sc.globalCompositeOperation='source-over';sc.restore();
 if(f.renderer){f.renderer(f.scene,t+d*.17,d,still);}else{const ctx=f.ctx;ctx.fillStyle='#080c0a';ctx.fillRect(0,0,pw,ph);for(let y=0;y<ph;y+=2){const dx=still?0:Math.sin(y*.052+t*9)*d*1.6;ctx.drawImage(f.scene,0,y,pw,Math.min(2,ph-y),dx,y,pw,Math.min(2,ph-y));}}
}
let paused=exportMode||matchMedia('(prefers-reduced-motion: reduce)').matches,elapsed=0,last=performance.now(),lastFrame=-1;const pause=document.getElementById('pause');pause.textContent=paused?'Play':'Pause';if(paused)source.pause();else source.play().catch(()=>{});
function tick(now){if(!paused&&!document.hidden)elapsed+=Math.min((now-last)/1000,.25);last=now;const frame=Math.floor(elapsed*24);if(!document.hidden&&(dirty||frame!==lastFrame)){if(!paused||lastFrame<0)updateGrain();frames.forEach(f=>render(f,elapsed,paused&&elapsed===0));lastFrame=frame;dirty=false;}requestAnimationFrame(tick);}if(!exportMode)requestAnimationFrame(tick);
pause.addEventListener('click',()=>{paused=!paused;pause.textContent=paused?'Play':'Pause';paused?source.pause():source.play().catch(()=>{});});document.getElementById('restart').addEventListener('click',()=>{elapsed=0;last=performance.now();lastFrame=-1;dirty=true;paused=false;pause.textContent='Pause';source.currentTime=0;source.play().catch(()=>{});});document.addEventListener('visibilitychange',()=>{last=performance.now();document.hidden||paused?source.pause():source.play().catch(()=>{});});source.addEventListener('loadeddata',()=>dirty=true);document.fonts.load('900 100px "VHS Grotesk"').then(()=>{dirty=true;document.documentElement.dataset.fontReady='true';});
let chosen='';try{chosen=localStorage.getItem('astir-vhs-wear-choice-v3')||'';}catch{}
function showChoice(){document.querySelectorAll('[data-pick]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.pick===chosen)));const p=profiles.find(p=>p.id===chosen);document.getElementById('selection').textContent=p?`Selected: ${p.number} — ${p.name}. Tell me in chat when you’re ready.`:'Pick the degree of wear that feels right.';}
document.querySelectorAll('[data-pick]').forEach(b=>b.addEventListener('click',()=>{chosen=chosen===b.dataset.pick?'':b.dataset.pick;try{localStorage.setItem('astir-vhs-wear-choice-v3',chosen);}catch{}showChoice();}));showChoice();

// Deterministic, frame-by-frame export for the bundled loop and clean reel asset.
window.captureTapeFrame=async function(t,width,height){
 await document.fonts.ready;
 source.pause();
 if(source.readyState<2)await new Promise(resolve=>source.addEventListener('loadeddata',resolve,{once:true}));
 const target=t%8;
 if(Math.abs(source.currentTime-target)>.0001){await new Promise((resolve,reject)=>{source.addEventListener('seeked',resolve,{once:true});source.addEventListener('error',reject,{once:true});source.currentTime=target;});}
 device={w:393,h:393*height/width};const f=frames[2];f.canvas.width=f.scene.width=width;f.canvas.height=f.scene.height=height;f.raster=width/393;
 // Identical random grain every time a frame is rendered.
 seed=987123+Math.round(t*24)*131;updateGrain();render(f,t,false);
 return f.canvas.toDataURL('image/png');
};
