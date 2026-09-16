/* Deterministic, DOM-independent layered layout for the review decision trees. */
(function(root){
 'use strict';
 function layoutTree(nodes,edges){
  const byId=new Map(nodes.map(n=>[n.id,n])),incoming=new Map(nodes.map(n=>[n.id,[]])),outgoing=new Map(nodes.map(n=>[n.id,[]]));
  const forward=edges.filter(e=>e.kind!=='retry');
  for(const e of forward){if(!byId.has(e.from)||!byId.has(e.to))throw new Error('Unknown tree endpoint: '+JSON.stringify(e));incoming.get(e.to).push(e.from);outgoing.get(e.from).push(e.to)}
  const degree=new Map(nodes.map(n=>[n.id,incoming.get(n.id).length])),rank=new Map(nodes.map(n=>[n.id,0])),queue=nodes.filter(n=>!degree.get(n.id)).map(n=>n.id),ordered=[];
  while(queue.length){const id=queue.shift();ordered.push(id);for(const next of outgoing.get(id)){rank.set(next,Math.max(rank.get(next),rank.get(id)+1));degree.set(next,degree.get(next)-1);if(!degree.get(next))queue.push(next)}}
  if(ordered.length!==nodes.length)throw new Error('Decision graph contains an unmarked cycle');
  const layers=[];for(const n of nodes)(layers[rank.get(n.id)]||= []).push(n.id);
  const order=new Map();const refresh=()=>layers.forEach(layer=>layer.forEach((id,i)=>order.set(id,i)));
  refresh();for(let pass=0;pass<6;pass++){const down=pass%2===0,seq=down?layers:[...layers].reverse();for(const layer of seq){layer.sort((a,b)=>{const score=id=>{const peers=(down?incoming:outgoing).get(id);return peers.length?peers.reduce((v,p)=>v+order.get(p),0)/peers.length:order.get(id)};return score(a)-score(b)});refresh()}}
  const gap=110,padding=100,layerWidths=layers.map(layer=>layer.reduce((s,id)=>s+byId.get(id).width,0)+Math.max(0,layer.length-1)*gap),contentWidth=Math.max(720,...layerWidths)+padding*2;
  const longEdges=edges.filter(e=>e.kind==='retry'||rank.get(e.to)!==rank.get(e.from)+1),width=contentWidth+longEdges.length*18+60;
  const boxes={},ranks=layers.map(layer=>({height:Math.max(...layer.map(id=>byId.get(id).height)),tracks:[]}));
  layers.forEach((layer,r)=>{let x=(contentWidth-layerWidths[r])/2;for(const id of layer){const n=byId.get(id);boxes[id]={x,y:0,width:n.width,height:n.height,rank:r};x+=n.width+gap}});
  const routes=edges.map((edge,index)=>{
   const a=boxes[edge.from],b=boxes[edge.to],siblings=edges.filter(e=>e.from===edge.from),parents=edges.filter(e=>e.to===edge.to),si=siblings.indexOf(edge),pi=parents.indexOf(edge);
   const sx=a.x+a.width*(si+1)/(siblings.length+1),tx=b.x+b.width*(pi+1)/(parents.length+1),indirect=edge.kind==='retry'||b.rank!==a.rank+1,rail=contentWidth+30+longEdges.indexOf(edge)*18;
   const labelWidth=234,labelHeight=18*Math.max(1,Math.ceil(edge.label.length/28))+12,labelX=((sx+(indirect?rail:tx))/2)-labelWidth/2;
   const tracks=ranks[a.rank].tracks;let track=tracks.findIndex(t=>t.labels.every(l=>labelX+labelWidth+18<l.x||labelX>l.x+l.width+18));
   if(track<0){track=tracks.length;tracks.push({height:0,labels:[]})}tracks[track].height=Math.max(tracks[track].height,labelHeight);tracks[track].labels.push({x:labelX,width:labelWidth});
   return {...edge,index,sx,tx,indirect,rail,track,label:{x:labelX,y:0,width:labelWidth,height:labelHeight}};
  });
  let y=42;layers.forEach((layer,r)=>{const band=ranks[r];band.y=y;for(const id of layer)boxes[id].y=y;let trackY=y+band.height+40;for(const track of band.tracks){track.y=trackY;trackY+=track.height+20}y=Math.max(y+band.height+100,trackY+70)});
  for(const route of routes){const a=boxes[route.from],b=boxes[route.to],track=ranks[a.rank].tracks[route.track];route.label.y=track.y;const mid=track.y+route.label.height/2;route.path=route.indirect?`M${route.sx} ${a.y+a.height}V${mid}H${route.rail}V${b.y-26}H${route.tx}V${b.y-5}`:`M${route.sx} ${a.y+a.height}V${mid}H${route.tx}V${b.y-5}`}
  return {width,height:y,boxes,ranks,layers,routes};
 }
 root.AstirDecisionLayout=layoutTree;
})(typeof window!=='undefined'?window:globalThis);
