/* Synthetic geometry check. This does not execute or visually test the browser. */
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import './decision-layout.js';
const base=path.dirname(fileURLToPath(import.meta.url));
const graph=JSON.parse(fs.readFileSync(path.join(base,'decision-tree.json'),'utf8'));
const overlap=(a,b)=>a.x<b.x+b.width-.01&&a.x+a.width>b.x+.01&&a.y<b.y+b.height-.01&&a.y+a.height>b.y+.01;
let scenarios=0,labels=0;
for(const mode of ['compact','variable','expanded'])for(const stage of graph.stages){
 const nodes=stage.nodes.map((n,i)=>({id:n.id,width:n.type==='decision'?280:260,height:n.type==='screen'||n.targetScreen?(mode==='expanded'&&i%4===0?1800:mode==='variable'?440+i%7*97:620):n.type==='decision'?210:mode==='variable'?160+i%4*40:190}));
 const l=globalThis.AstirDecisionLayout(nodes,stage.edges),boxes=Object.values(l.boxes);
 assert.equal(boxes.length,stage.nodes.length);assert.equal(l.routes.length,stage.edges.length);
 for(let i=0;i<boxes.length;i++){const b=boxes[i];assert(b.x>=0&&b.y>=0&&b.x+b.width<=l.width&&b.y+b.height<=l.height,stage.id+' node outside stage');for(let j=0;j<i;j++)assert(!overlap(b,boxes[j]),stage.id+' nodes overlap')}
 for(let i=0;i<l.routes.length;i++){const r=l.routes[i],b=r.label;assert(b.x>=0&&b.y>=0&&b.x+b.width<=l.width&&b.y+b.height<=l.height,stage.id+' label outside stage');for(const box of boxes)assert(!overlap(b,box),stage.id+' label overlaps node');for(let j=0;j<i;j++)assert(!overlap(b,l.routes[j].label),stage.id+' labels overlap');assert(r.path.includes('V'+(b.y+b.height/2)+'H'),stage.id+' label detached from connector');labels++}
 scenarios++;
}
console.log(JSON.stringify({check:'synthetic decision layout',scenarios,labelsChecked:labels,nodeCollisions:0,labelCollisions:0,detachedLabels:0,browserTest:false}));
