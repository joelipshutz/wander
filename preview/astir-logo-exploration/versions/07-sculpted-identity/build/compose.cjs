// Native SVG composition. Source photographs and letter aspect ratios are preserved.
// Run with Node.js; SHARP_MODULE can point at an installed sharp module.
const fs=require('fs'),path=require('path');
const sharp=require(process.env.SHARP_MODULE||'/Users/joelipshutz/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp/dist/index.cjs');
const root=path.resolve(__dirname,'..'),assets=path.join(root,'assets');
const types=JSON.parse(fs.readFileSync(path.join(__dirname,'type-paths.json'),'utf8'));
const inscription=JSON.parse(fs.readFileSync(path.join(__dirname,'oneness-original-paths.json'),'utf8'));
const crops={34:[188,154,380,561],36:[111,82,401,556]};
const palettes={signal:'#F05A3C',mono:'#ADAEA7',oxide:'#A45B42'};
const directions=[
 {id:46,title:'Warm stone / current serif',source:34,type:'current',material:'flat',inspiredBy:28},
 {id:47,title:'Ink and stone / current serif',source:36,type:'current',material:'flat',inspiredBy:30},
 {id:48,title:'Natural stone serif',source:36,type:'generated',material:'stone',inspiredBy:30},
 {id:49,title:'Carved sans',source:36,type:'generated',material:'stone',inspiredBy:32},
 {id:50,title:'Current serif / tighter setting',source:36,type:'narrow',material:'flat'},
 {id:51,title:'Bodoni 72 Book / refined',source:36,type:'refined',material:'flat'},
 {id:52,title:'Sculptor-made letters',source:36,type:'generated',material:'sculpted'},
 {id:53,title:'Imperfect sculpted letters',source:36,type:'generated',material:'sculpted'}
];
function svg(w,h,body,title){return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><title>${title}</title>${body}</svg>`}
function rgb(hex){return hex.match(/[a-f0-9]{2}/ig).map(n=>parseInt(n,16)/255)}
function filter(palette){const c=rgb(palettes[palette]);return `<defs><filter id="base-tone" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0"/><feComponentTransfer>${['R','G','B'].map((x,i)=>`<feFunc${x} type="linear" slope=".45" intercept="${c[i]-.315}"/>`).join('')}</feComponentTransfer></filter><filter id="charcoal" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0"/><feComponentTransfer><feFuncR type="linear" slope=".34" intercept=".055"/><feFuncG type="linear" slope=".35" intercept=".065"/><feFuncB type="linear" slope=".33" intercept=".06"/></feComponentTransfer></filter></defs>`}
function photo(n,x,y,w,h,tone=''){return `<svg x="${x}" y="${y}" width="${w}" height="${h}" viewBox="${crops[n].join(' ')}" overflow="hidden"><image width="1774" height="887" href="source${n}.png"${tone?' filter="url(#charcoal)"':''}/></svg>`}
function tracedInscription(x,y,w,palette){const v=inscription.viewBox,s=w/v[2];const ink=palette==='mono'?'#363934':'#45241C';return `<g transform="translate(${x} ${y}) scale(${s}) translate(${-v[0]} ${-v[1]})" fill="none" stroke-linecap="round" stroke-linejoin="round">`+`<g transform="translate(1.5 2.2)" stroke="#FFF1D8" stroke-opacity=".48" stroke-width="${inscription.strokeWidth+1}">${inscription.paths.map(d=>`<path d="${d}"/>`).join('')}</g><g stroke="${ink}" stroke-opacity=".91" stroke-width="${inscription.strokeWidth}">${inscription.paths.map(d=>`<path d="${d}"/>`).join('')}</g></g>`}
function foundation(x,y,w,h,palette,inscriptionWidth=290){return `<svg x="${x}" y="${y}" width="${w}" height="${h}" viewBox="107 718 1575 105" preserveAspectRatio="none" overflow="hidden"><image width="1774" height="887" href="source35.png" filter="url(#base-tone)"/></svg>`+tracedInscription(x+w-inscriptionWidth-48,y+(h-inscriptionWidth*195/820)/2,inscriptionWidth,palette)}
function embed(s){return s.replace(/href="([^"#][^"]*\.png)"/g,(all,ref)=>{const p=path.resolve(assets,ref);return `href="data:image/png;base64,${fs.readFileSync(p).toString('base64')}"`})}
async function alphaBounds(file){const {data,info}=await sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true});let b=[info.width,info.height,0,0],seen=false;for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){if(data[(y*info.width+x)*4+3]>8){seen=true;b=[Math.min(b[0],x),Math.min(b[1],y),Math.max(b[2],x),Math.max(b[3],y)]}}if(!seen)throw Error('No visible alpha '+file);return [b[0],b[1],b[2]-b[0]+1,b[3]-b[1]+1]}
async function write(name,markup,width=1600){fs.writeFileSync(path.join(assets,name+'.svg'),markup);await sharp(Buffer.from(embed(markup))).resize({width}).png().toFile(path.join(assets,name+'.png'))}
async function buildDirection(d){let b,sourcePath;
 if(d.type==='generated'){sourcePath=path.join(assets,`${d.id}-letters.png`);if(!fs.existsSync(sourcePath)){console.log('Pending native alpha:',d.id);return null;}const m=await sharp(sourcePath).metadata();if(!m.hasAlpha)throw Error('Generated insert is not transparent '+d.id);b=await alphaBounds(sourcePath);}
 else b=types[d.type].bounds;
 const cap=420,letterWidth=b[2]*cap/b[3],baseline=730,gap=d.type==='narrow'?27:34;const files=[];
 for(const height of ['equal','tall'])for(const palette of Object.keys(palettes))for(const light of [false,true]){
  const ah=cap*(height==='tall'?1.25:1),aw=ah*crops[d.source][2]/crops[d.source][3],wordWidth=aw+gap+letterWidth,left=(2200-wordWidth)/2,tx=left+aw+gap,scale=cap/b[3];let letters;
  if(d.type==='generated')letters=`<svg x="${tx}" y="${baseline-cap}" width="${letterWidth}" height="${cap}" viewBox="${b.join(' ')}" overflow="hidden"><image width="1774" height="887" href="${d.id}-letters.png"${light?' filter="url(#charcoal)"':''}/></svg>`;
  else letters=`<g fill="${light?'#141714':d.id===47?'#E6E5DF':'#E6DDCD'}" transform="translate(${tx-b[0]*scale} ${baseline-(b[1]+b[3])*scale}) scale(${scale})">${types[d.type].paths.map(p=>`<path d="${p}"/>`).join('')}</g>`;
  const baseX=left-60,baseW=wordWidth+120,name=`${d.id}-${height}-${palette}${light?'-light':''}`;
  const body=filter(palette)+photo(d.source,left,baseline-ah,aw,ah,light?'charcoal':'')+letters+foundation(baseX,770,baseW,110,palette);
  await write(name,svg(2200,1050,body,`Astir ${d.id}: ${d.title}; ${height} A; ${palette}; ${light?'charcoal material on light':'natural material on ink'}`));
  files.push({height,palette,appearance:light?'light':'ink',png:name+'.png',svg:name+'.svg',wordWidth,statueHeight:ah,letterHeight:cap});
 }
 console.log('Composed',d.id,files.length,'variants');return {...d,font:d.type==='generated'?'Sculpted raster letterforms':types[d.type].font,letterBounds:b,sourceCrop:crops[d.source],files};
}
async function buildIcons(){const records=[];for(const n of [34,36])for(const palette of ['signal','mono','none']){
 const hasBase=palette!=='none',height=hasBase?610:680,width=height*crops[n][2]/crops[n][3],y=hasBase?160:170,name=`icon-${n}-${palette}`;
 const body=`<rect width="1024" height="1024" fill="#080A09"/>`+filter(hasBase?palette:'mono')+photo(n,(1024-width)/2,y,width,height)+(hasBase?foundation(218,794,588,61,palette,150):'');
 const markup=svg(1024,1024,body,`Astir family ${n}, ${hasBase?palette+' foundation':'statue only'}; black square icon and social avatar`);await write(name,markup,1024);
 const social=`social-${n}-${palette}`;fs.copyFileSync(path.join(assets,name+'.png'),path.join(assets,social+'.png'));fs.copyFileSync(path.join(assets,name+'.svg'),path.join(assets,social+'.svg'));
 records.push({source:n,palette,icon:name+'.png',social:social+'.png',svg:name+'.svg',size:[1024,1024],background:'#080A09',circleSafe:true,description:hasBase?'Exact source statue over continuous stone foundation with hand-traced ONENESS':'Exact source statue without foundation'});
 }return records;}
(async()=>{const results=[];const only=process.argv.slice(2).map(Number).filter(Number.isFinite);for(const d of directions){if(only.length&&!only.includes(d.id))continue;const r=await buildDirection(d);if(r)results.push(r)}
 let old=[];const metaFile=path.join(assets,'metadata.json');if(fs.existsSync(metaFile))old=JSON.parse(fs.readFileSync(metaFile,'utf8')).directions||[];const byID=new Map(old.map(v=>[v.id,v]));for(const r of results)byID.set(r.id,r);
 const icons=only.length?JSON.parse(fs.existsSync(metaFile)?fs.readFileSync(metaFile,'utf8'):'{}').icons||[]:await buildIcons();
 fs.writeFileSync(metaFile,JSON.stringify({round:7,svgSize:[2200,1050],pngSize:[1600,764],palettes,directions:[...byID.values()].sort((a,b)=>a.id-b.id),icons,inscription:'Hand-traced centerline recreation of the original ONENESS photo inscription; not a font or exact pixel extraction.',lightTreatment:'Native SVG tonal mapping darkens only statue and generated letters to weathered charcoal; flat glyphs use #141714. Source geometry and alpha are preserved.',rendering:'Sharp/librsvg native SVG rasterization; no browser/file URL navigation.',editableSVG:'SVG compositions reference adjacent local PNG sources. Use build/export-standalone.cjs to embed photos for standalone distribution.'},null,2)+'\n');
})().catch(error=>{console.error(error);process.exit(1)});
