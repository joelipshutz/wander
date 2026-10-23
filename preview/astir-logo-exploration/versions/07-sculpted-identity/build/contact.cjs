// Native contact-sheet rendering, independent of the browser review UI.
const fs=require('fs'),path=require('path');
const sharp=require(process.env.SHARP_MODULE||'/Users/joelipshutz/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp/dist/index.cjs');
const root=path.resolve(__dirname,'..'),assets=path.join(root,'assets');
const metadata=JSON.parse(fs.readFileSync(path.join(assets,'metadata.json'),'utf8'));
const png=name=>'data:image/png;base64,'+fs.readFileSync(path.join(assets,name)).toString('base64');
(async()=>{let body='';metadata.directions.forEach((d,row)=>{['equal','tall'].forEach((height,col)=>{for(const light of [false,true]){const x=400*(col*2+Number(light)),y=row*255;body+=`<rect x="${x}" y="${y}" width="400" height="255" fill="${light?'#F3F4F0':'#080A09'}"/><text x="${x+16}" y="${y+26}" fill="${light?'#222':'#eee'}" font-family="sans-serif" font-size="14">${d.id} · ${height} · ${light?'light':'ink'}</text><image x="${x}" y="${y+36}" width="400" height="191" href="${png(`${d.id}-${height}-signal${light?'-light':''}.png`)}"/>`}})});
await sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="${metadata.directions.length*255}">${body}</svg>`)).png().toFile(path.join(__dirname,'assets-contact.png'));
let icons='';metadata.icons.forEach((icon,i)=>{const x=i*256;icons+=`<defs><clipPath id="circle${i}"><circle cx="${x+128}" cy="460" r="116"/></clipPath></defs><rect x="${x}" width="256" height="600" fill="#141714"/><text x="${x+12}" y="22" font-size="13" fill="#eee" font-family="sans-serif">${icon.source} · ${icon.palette}</text><image x="${x}" y="34" width="256" height="256" href="${png(icon.icon)}"/><image x="${x+12}" y="344" width="232" height="232" href="${png(icon.social)}" clip-path="url(#circle${i})"/>`});
await sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1536" height="600">${icons}</svg>`)).png().toFile(path.join(__dirname,'social-contact.png'));
console.log('Rendered native asset and square/circle social contact sheets');
})().catch(e=>{console.error(e);process.exit(1)});
