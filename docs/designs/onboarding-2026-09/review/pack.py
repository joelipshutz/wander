import json,pathlib,base64,io
from PIL import Image
R=pathlib.Path(__file__).parent
d=json.loads((R/'content.json').read_text())
# Only attach verified matching screenshot states; never substitute a different screen.
exclude=set()
for n in d['nodes']:
 p=R/'screenshots'/(n['image'] or '')
 if n['image'] and p.is_file() and n['key'] not in exclude:
  im=Image.open(p).convert('RGB'); im.thumbnail((1000,2200)); buf=io.BytesIO(); im.save(buf,format='WEBP',quality=90,method=4); n['image']='data:image/webp;base64,'+base64.b64encode(buf.getvalue()).decode()
 else:n['image']=None
brand=json.loads((R/'brand.json').read_text())
for a in brand['assets']:
 p=R/'brand-assets'/a['file']
 a['download']='data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()
 im=Image.open(p).convert('RGBA');im.thumbnail((800,1000));buf=io.BytesIO();im.save(buf,format='WEBP',quality=90,method=4)
 a['preview']='data:image/webp;base64,'+base64.b64encode(buf.getvalue()).decode()
 if a.get('svg'):a['svgDownload']='data:image/svg+xml;base64,'+base64.b64encode((R/'brand-assets'/a['svg']).read_bytes()).decode()
d['brand']=brand
html=(R/'index.template.html').read_text().replace('__DATA__',json.dumps(d,ensure_ascii=False).replace('</','<\\/'))
(R/'index.html').write_text(html)
md=['# Astir onboarding and NUX — copy baseline','',f"Build 174 · {d['date']} · {d['commit']}",'']
for n in d['nodes']:
 md += [f"## {n['id']} — {n['title']}",f"{n['group']} · {n['state']}",n['note'],f"Source: {n['source']}",'']
 md += [f"{n['id']}.{j+1:02} [{l['role']}] {l['text']}" for j,l in enumerate(n['lines'])]
 md+=['']
(R/'copy-baseline.md').write_text('\n'.join(md))
print('Wrote standalone HTML:',len(html),'bytes; native images:',sum(bool(n['image']) for n in d['nodes']))
