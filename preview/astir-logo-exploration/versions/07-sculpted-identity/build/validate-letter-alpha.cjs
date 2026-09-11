const fs=require('fs'),path=require('path');
const sharp=require(process.env.SHARP_MODULE||'/Users/joelipshutz/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp/dist/index.cjs');
const root=path.resolve(__dirname,'..');
const counters={48:[1370,315],49:[1320,345],52:[1490,320],53:[1450,330]};
(async()=>{const results=[];for(const id of [48,49,52,53]){const p=path.join(root,'assets',`${id}-letters.png`);if(!fs.existsSync(p))continue;
 const m=await sharp(p).metadata(),{data,info}=await sharp(p).ensureAlpha().extractChannel(3).raw().toBuffer({resolveWithObject:true});let min=255,max=0,count=0;for(const a of data){min=Math.min(min,a);max=Math.max(max,a);if(a>128)count++}
 const visited=new Uint8Array(data.length),stack=new Int32Array(data.length),components=[];
 for(let start=0;start<data.length;start++){if(visited[start]||data[start]<128)continue;let size=0,tail=1,b=[info.width,info.height,0,0];stack[0]=start;visited[start]=1;
  while(tail){const i=stack[--tail],x=i%info.width,y=Math.floor(i/info.width);size++;b=[Math.min(b[0],x),Math.min(b[1],y),Math.max(b[2],x),Math.max(b[3],y)];for(const next of [x>0?i-1:-1,x<info.width-1?i+1:-1,y>0?i-info.width:-1,y<info.height-1?i+info.width:-1]){if(next>=0&&!visited[next]&&data[next]>=128){visited[next]=1;stack[tail++]=next}}}
  if(size>1000)components.push({pixels:size,bounds:b});
 }
 components.sort((a,b)=>a.bounds[0]-b.bounds[0]);const sample=counters[id],counterAlpha=data[sample[1]*info.width+sample[0]],cornerAlpha=[data[0],data[info.width-1],data[data.length-info.width],data[data.length-1]],pass=m.hasAlpha&&min===0&&max===255&&components.length===4&&counterAlpha===0&&cornerAlpha.every(v=>v===0);
 results.push({id,size:[info.width,info.height],hasAlpha:m.hasAlpha,alphaRange:[min,max],visibleFraction:count/data.length,components,counterSample:sample,counterAlpha,cornerAlpha,pass});
 }
 fs.writeFileSync(path.join(__dirname,'letter-alpha-validation.json'),JSON.stringify(results,null,2)+'\n');console.log(JSON.stringify(results));if(results.some(v=>!v.pass))process.exitCode=1;
})().catch(e=>{console.error(e);process.exit(1)});
