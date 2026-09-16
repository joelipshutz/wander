// Native SVG compositions for round08. No shape regeneration or image-model calls.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
let sharp;try{sharp=require(process.env.SHARP_MODULE||'sharp')}catch{sharp=require('/Users/joelipshutz/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp/dist/index.cjs')}
const root=path.resolve(__dirname,'..'),assets=path.join(root,'assets');
const type=JSON.parse(fs.readFileSync(path.join(__dirname,'type-paths.json'),'utf8')).current;
const inscription=JSON.parse(fs.readFileSync(path.join(__dirname,'oneness-original-paths.json'),'utf8'));
const crops={34:[188,154,380,561],36:[111,82,401,556]};
const palettes={signal:'#F05A3C',oxide:'#A45B42'};
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const hashText=t=>crypto.createHash('sha256').update(t).digest('hex');
const sumMean=rows=>[0,1,2].map(k=>rows.reduce((s,p)=>s+p[k],0)/rows.length);
async function sourcePixels(n){const {data,info}=await sharp(path.join(assets,`source${n}.png`)).ensureAlpha().raw().toBuffer({resolveWithObject:true}),c=crops[n],pixels=[];
 for(let y=c[1];y<c[1]+c[3];y++)for(let x=c[0];x<c[0]+c[2];x++){const i=(y*info.width+x)*4;if(data[i+3]>250){const rgb=[data[i]/255,data[i+1]/255,data[i+2]/255];pixels.push([...rgb,.2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2]])}}return pixels.sort((a,b)=>a[3]-b[3]);}
async function fitWarm(){const target=await sourcePixels(34),source=await sourcePixels(36),tables=[[],[],[]];
 // Map the source36 luminance percentile to the neighboring source34 RGB values.
 // This changes tone per pixel; no spatial filter, redraw, alpha or geometry operation.
 for(let i=0;i<=64;i++){const l=i/64;let lo=0,hi=source.length;while(lo<hi){const m=(lo+hi)>>1;if(source[m][3]<=l)lo=m+1;else hi=m}const q=lo/source.length,center=Math.round(q*(target.length-1)),radius=Math.max(64,Math.round(target.length*.008));const window=target.slice(Math.max(0,center-radius),Math.min(target.length,center+radius+1));const color=sumMean(window);for(let k=0;k<3;k++)tables[k].push(i===0?0:i===64?1:color[k]);}
 // Monotone tables retain shadow/highlight order and fine carved relief.
 for(const t of tables)for(let i=1;i<t.length;i++)t[i]=Math.max(t[i],t[i-1]);
 const stats=p=>({opaquePixelCount:p.length,meanRGB:sumMean(p).map(n=>n*255),luminanceQuantiles:[.05,.25,.5,.75,.95].map(q=>p[Math.floor(q*(p.length-1))][3]*255)});
 const fit={description:'Approximate, source-aware color match from source36 toward source34. A luminance-dependent RGB lookup is applied with native SVG filter primitives; geometry, faces, child and source alpha silhouette are retained. This is a tonal approximation, not a redrawn sculpture or exact photographic match.',method:'Source36 masked luminance percentiles mapped to local source34 RGB averages, with 65 monotone lookup samples per channel.',source:36,reference:34,alphaThreshold:250,sourceStatistics:stats(source),referenceStatistics:stats(target),tableValues:tables.map(t=>t.map(v=>Number(v.toFixed(7)))),sourceHashes:{34:sha(path.join(assets,'source34.png')),36:sha(path.join(assets,'source36.png'))}};
 fs.writeFileSync(path.join(__dirname,'warm-tone-fit.json'),JSON.stringify(fit,null,2)+'\n');return fit;}
function svg(w,h,body,title){return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><title>${title}</title>${body}</svg>`}
function defs(palette,warm){const c=palettes[palette].match(/[a-f0-9]{2}/ig).map(n=>parseInt(n,16)/255);return `<defs><filter id="base-tone" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0"/><feComponentTransfer>${['R','G','B'].map((x,i)=>`<feFunc${x} type="linear" slope=".45" intercept="${c[i]-.315}"/>`).join('')}</feComponentTransfer></filter><filter id="warm-statue" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values=".2126 .7152 .0722 0 0 .2126 .7152 .0722 0 0 .2126 .7152 .0722 0 0 0 0 0 1 0"/><feComponentTransfer>${['R','G','B'].map((x,i)=>`<feFunc${x} type="table" tableValues="${warm.tableValues[i].join(' ')}"/>`).join('')}<feFuncA type="identity"/></feComponentTransfer></filter></defs>`}
function photo(family,x,y,w,h){const n=family==='34'?34:36;return `<svg x="${x}" y="${y}" width="${w}" height="${h}" viewBox="${crops[n].join(' ')}" overflow="hidden"><image width="1774" height="887" href="source${n}.png"${family==='36-warm'?' filter="url(#warm-statue)"':''}/></svg>`}
function traced(x,y,w){const v=inscription.viewBox;return `<g transform="translate(${x} ${y}) scale(${w/v[2]}) translate(${-v[0]} ${-v[1]})" fill="none" stroke-linecap="round" stroke-linejoin="round"><g transform="translate(1.5 2.2)" stroke="#FFF1D8" stroke-opacity=".48" stroke-width="${inscription.strokeWidth+1}">${inscription.paths.map(d=>`<path d="${d}"/>`).join('')}</g><g stroke="#45241C" stroke-opacity=".91" stroke-width="${inscription.strokeWidth}">${inscription.paths.map(d=>`<path d="${d}"/>`).join('')}</g></g>`}
function foundation(x,y,w,h,inscriptionWidth=290,rightInset=48){return `<svg x="${x}" y="${y}" width="${w}" height="${h}" viewBox="107 718 1575 105" preserveAspectRatio="none" overflow="hidden"><image width="1774" height="887" href="source35.png" filter="url(#base-tone)"/></svg>`+traced(x+w-inscriptionWidth-rightInset,y+(h-inscriptionWidth*195/820)/2,inscriptionWidth)}
function embedded(markup){return markup.replace(/href="([^"#][^"]*\.png)"/g,(all,ref)=>`href="data:image/png;base64,${fs.readFileSync(path.resolve(assets,ref)).toString('base64')}"`)}
async function write(name,markup,width){fs.writeFileSync(path.join(assets,name+'.svg'),markup);await sharp(Buffer.from(embedded(markup))).resize({width}).png().toFile(path.join(assets,name+'.png'))}
async function main(){const warm=await fitWarm(),metadata={round:8,svgSize:[2200,1050],pngSize:[1600,764],palettes,font:type.font,textColor:'#E6DDCD',glyphPathsSha256:hashText(JSON.stringify(type.paths)),tracking:type.tracking,sourceCopies:[34,35,36].map(n=>({source:n,file:`source${n}.png`,sha256:sha(path.join(assets,`source${n}.png`))})),warmTreatment:warm.description,warmRenderingNote:"The source image and SVG geometry are identical for 54 and 55. Native filter rasterization changes 132 edge alpha samples by at most 2/255; their silhouette at 50% alpha is identical. No spatial filtering or shape regeneration is applied.",directions:[],icons:[]};
 for(const d of [{id:46,family:'34',reference:true,title:'Retained warm editorial reference'},{id:54,family:'36',title:'Original36 /46 lettering'},{id:55,family:'36-warm',title:'Warmer36 /46 lettering'}]){
  const n=d.family==='34'?34:36,b=type.bounds,cap=420,ah=525,aw=ah*crops[n][2]/crops[n][3],letterWidth=b[2]*cap/b[3],gap=34,wordWidth=aw+gap+letterWidth,left=(2200-wordWidth)/2,tx=left+aw+gap,s=cap/b[3],files=[];
  for(const palette of Object.keys(palettes)){const name=`${d.id}-tall-${palette}`,geometry={statue:{height:ah,width:aw,x:left,y:205,crop:crops[n]},letters:{height:cap,width:letterWidth,x:tx,baseline:730,scale:s},gap,wordWidth,base:{x:left-60,y:770,width:wordWidth+120,height:110,inscriptionWidth:290,rightInset:48}};
   if(!d.reference){const letters=`<g fill="#E6DDCD" transform="translate(${tx-b[0]*s} ${730-(b[1]+b[3])*s}) scale(${s})">${type.paths.map(p=>`<path d="${p}"/>`).join('')}</g>`;await write(name,svg(2200,1050,defs(palette,warm)+photo(d.family,left,205,aw,ah)+letters+foundation(left-60,770,wordWidth+120,110),`Astir ${d.id}: ${d.title}; tall statue; ${palette} foundation`),1600);}
   files.push({palette,png:name+'.png',svg:name+'.svg',geometry});
  }metadata.directions.push({...d,source:n,files});
 }
 for(const family of ['34','36','36-warm'])for(const base of ['long','compact','none'])for(const palette of base==='none'?[null]:Object.keys(palettes)){
  const n=family==='34'?34:36,height=610,width=height*crops[n][2]/crops[n][3],statueX=(1024-width)/2,baseWidth=base==='long'?588:width,baseX=(1024-baseWidth)/2,p=palette||'signal',name=`icon-${family}-${base}${palette?'-'+palette:''}`,social=name.replace(/^icon-/,'social-');
  const inscriptionWidth=150*baseWidth/588,rightInset=48*baseWidth/588;
  const body='<rect width="1024" height="1024" fill="#080A09"/>'+defs(p,warm)+photo(family,statueX,160,width,height)+(base==='none'?'':foundation(baseX,794,baseWidth,61,inscriptionWidth,rightInset));
  await write(name,svg(1024,1024,body,`Astir ${family}: fixed statue scale, ${base} foundation${palette?', '+palette:''}`),1024);for(const ext of ['png','svg'])fs.copyFileSync(path.join(assets,name+'.'+ext),path.join(assets,social+'.'+ext));
  metadata.icons.push({family,source:n,base,palette,icon:name+'.png',social:social+'.png',svg:name+'.svg',socialSvg:social+'.svg',size:[1024,1024],background:'#080A09',geometry:{statue:{height,width,x:statueX,y:160,crop:crops[n]},base:base==='none'?null:{width:baseWidth,height:61,x:baseX,y:794,inscriptionWidth,rightInset}},description:family==='36-warm'?'Native source-aware tonal approximation toward34; same36geometry':'Original photographic statue colors'});
 }
 fs.writeFileSync(path.join(assets,'metadata.json'),JSON.stringify(metadata,null,2)+'\n');console.log(JSON.stringify({newLockups:4,retainedReferenceLockups:2,icons:metadata.icons.length,socials:metadata.icons.length}));
}
main().catch(e=>{console.error(e);process.exit(1)});
