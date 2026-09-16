"""Add a self-contained canvas shell around the reviewed card HTML; never regenerate product content."""
from pathlib import Path
import re,json,hashlib,sys
root=Path(__file__).resolve().parents[1]
source=root/'astir-events-linear.html'
if not source.exists():source=root/'astir-events-flowchart.html'
if len(sys.argv)>1:source=Path(sys.argv[1])
text=source.read_text()
if 'id="canvas-viewport"' in text:raise SystemExit('Use the preserved linear source, not an already generated canvas.')
style=re.search(r'<style>([\s\S]*?)</style>',text).group(1)
main=re.search(r'<main>([\s\S]*?)</main>',text).group(1)
assets=re.search(r'<script[^>]*id="preview-assets"[^>]*>[\s\S]*?</script>',text).group(0)
# Reserve intrinsic space before lazy images decode, so panning never shifts the board.
import base64,struct
asset_map=json.loads(re.search(r'<script[^>]*id="preview-assets"[^>]*>([\s\S]*?)</script>',text).group(1))
def jpeg_size(payload):
 data=base64.b64decode(payload.split(',',1)[1]);i=2
 while i<len(data):
  if data[i]!=255:i+=1;continue
  while data[i]==255:i+=1
  marker=data[i];i+=1
  if marker in (0xd8,0xd9) or 0xd0<=marker<=0xd7:continue
  length=int.from_bytes(data[i:i+2],'big')
  if marker in (0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf):
   height,width=struct.unpack('>HH',data[i+3:i+7]);return width,height
  if length<2:raise ValueError('Invalid JPEG segment')
  i+=length
 raise ValueError('JPEG dimensions absent')
dims={key:jpeg_size(value) for key,value in asset_map.items()}
def reserve_image(match):
 tag=match.group(0);asset=re.search(r'data-asset="([^"]+)"',tag).group(1);w,h=dims[asset]
 return tag[:-1]+f' width="{w}" height="{h}">'
main=re.sub(r'<img\b[^>]*data-asset="[^"]+"[^>]*>',reserve_image,main)
def reserve_video(match):
 tag=match.group(0);payload=re.search(r'src="data:video/mp4;base64,([^"]+)"',tag).group(1);data=base64.b64decode(payload);pos=data.find(b'tkhd');assert pos>=4
 size=int.from_bytes(data[pos-4:pos],'big');end=pos-4+size;width,height=struct.unpack('>II',data[end-8:end]);w,h=width>>16,height>>16;assert w>0 and h>0
 return tag[:-1]+f' width="{w}" height="{h}" data-no-pan>'
main=re.sub(r'<video\b[^>]*>',reserve_video,main)

model=json.loads((root/'flowchart/continuous-layout.json').read_text())
ids=re.findall(r'<article[^>]+data-id="([^"]+)"',main)
assert len(ids)==len(set(ids))==172
assert set(ids)=={i for s in model for l in s['lanes'] for i in l['ids']}
core=['entry','surfaces','account','reservation','texts','install','door','return','recap','map']
short={'entry':'Find the event','surfaces':'Open the right surface','account':'Sign in & verify','reservation':'RSVP outcome','texts':'Texts & guest controls','install':'Prepare the app & QR','door':'Arrive & get admitted','return':'Return after the event','recap':'Check-in & recap','map':'Map & place history','offline-door':'Offline door','home':'Home-location rules','console':'Astir console'}
nav=''.join(f'<button class="stage-link" data-stage="{id}"><span>{i+1:02}</span>{short[id]}</button>' for i,id in enumerate(core))
nav+='<div class="nav-separator"></div><p class="nav-kicker">Supporting branches</p>'+''.join(f'<button class="stage-link" data-stage="{id}"><span>↳</span>{short[id]}</button>' for id in ['offline-door','home','console'])
html='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Astir Events · Review canvas</title><style>'''+style+'\n'+(root/'flowchart/canvas.css').read_text()+'''</style></head><body>
<header class="canvas-header"><div class="canvas-brand"><button class="navigator-toggle" id="navigator-toggle" aria-label="Toggle journey navigation" aria-expanded="false">☰</button><span class="brand">astir</span><div><h1>Events / review canvas</h1><p>172 screens · all flows · native mocks + wireframes</p></div></div><div class="board-search"><input id="board-search" type="search" placeholder="Find a screen…  /" aria-label="Find a screen by number or name" autocomplete="off" aria-controls="search-results"><div id="search-results" class="search-results" hidden></div></div><div class="canvas-actions"><a class="optional" href="astir-events-linear.html">Linear view ↗</a><button id="help" aria-label="Canvas controls and keyboard shortcuts">?</button><button id="start" class="primary">Start at the beginning</button></div></header>
<aside class="navigator" id="navigator" aria-label="Journey navigation"><p class="nav-kicker">The guest journey →</p>'''+nav+'''<div class="nav-separator"></div><div class="surface-key"><span><i class="dot app"></i>App</span><span><i class="dot clip"></i>App Clip</span><span><i class="dot browser"></i>Browser</span><span><i class="dot sms"></i>Text</span><span><i class="dot console"></i>Console</span></div><p class="nav-invariant"><strong>RSVP → texts → download later.</strong><br>The app is required for the door QR. Admission and the later event check-in are separate.</p><p class="nav-invariant">Arrows = sequence.<br>Brackets = alternate states.<br>Layouts and open options keep their review status.</p></aside>
<div id="canvas-viewport" class="canvas-viewport" tabindex="0" role="region" aria-label="Pannable event flowchart. Drag to pan; pinch to zoom. Use navigation or search to focus a screen."><main id="canvas-world" class="canvas-world"><svg id="canvas-connections" class="canvas-connections" aria-hidden="true"></svg><div class="stage-title-rail">The guest journey · follow left to right →</div>'''+main+'''</main></div>
<div id="selection-bar" class="selection-bar" hidden></div><div class="board-help"><span>Drag anywhere to move · Pinch to zoom</span><span>Double-click a screen to focus · Esc to clear</span></div>
<div class="dock" aria-label="Canvas view controls"><button id="zoom-out" aria-label="Zoom out">−</button><button id="zoom-label" title="Reset to 100%">100%</button><button id="zoom-in" aria-label="Zoom in">+</button><span class="divider"></span><button id="fit-all">Fit all</button><button id="fit-stage">Fit stage</button><button id="focus-screen">Focus screen</button><span class="divider"></span><button id="collapse-all" title="Collapse expanded previews">Collapse</button></div>
<div class="minimap"><p>Whole journey · drag to navigate</p><svg id="minimap" aria-label="Canvas overview" role="img" viewBox="0 0 200 100"><g id="minimap-stages"></g><rect class="map-view" id="minimap-view"/></svg></div>
<div class="board-help-pop" id="help-pop" hidden><button id="close-help" aria-label="Close help">×</button><h2>A board you can move around.</h2><p>Drag the board or scroll with two fingers to pan. Pinch, or hold <kbd>Ctrl</kbd> while scrolling, to zoom around your pointer.</p><p>Click a preview to expand it in place. Double-click a screen to focus. Nothing opens in another page.</p><p><kbd>/</kbd> Search · <kbd>+</kbd> / <kbd>−</kbd> Zoom<br><kbd>F</kbd> Focus screen · <kbd>Shift 1</kbd> Fit all<br><kbd>0</kbd> 100% · Arrow keys pan · <kbd>Esc</kbd> Clear</p></div>
<div id="canvas-toast" class="canvas-toast" role="status" hidden></div><div id="live-status" class="sr-only" aria-live="polite"></div>
'''+assets+'\n<script id="canvas-layout" type="application/json">'+json.dumps({'sections':model,'core':core,'short':short},ensure_ascii=False).replace('</','<\/')+'</script>\n<script>\n'+(root/'flowchart/canvas-camera.js').read_text()+'\n'+(root/'flowchart/canvas-review.js').read_text()+'\n</script></body></html>'
output=root/'astir-events-flowchart.html';output.write_text(html)
print(json.dumps({'output':str(output),'screen_count':len(ids),'source_sha256':hashlib.sha256(text.encode()).hexdigest(),'bytes':len(html.encode())}))
