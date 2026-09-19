from pathlib import Path
import json,shutil
R=Path(__file__).parent
S=R.parent/'astir-brand-drive-package-2026-09-16'
A=R/'brand-assets';A.mkdir(exist_ok=True)
specs=[
('Wordmark · Signal','03 Wordmark — Approved Signal','Transparent.png','Approved direction 56. Preserve the statue, outlined lettering, spacing, and full-width Signal base.','dark'),
('App icon','01 App Icon','.png','Approved direction 55 · 1024 × 1024 master.','dark'),
('Instagram / profile','02 Instagram and Profile','.png','Approved square profile artwork.','dark'),
('Static splash artwork','04 Splash — Static','Transparent.png','Transparent master. The approved splash is static; glimmer is off.','dark'),
('Splash · opening','04 Splash — Static','Opening.png','Native component layout reference, not a complete running-app capture.','dark'),
('Splash · loading','04 Splash — Static','Map.png','Native component layout reference. Artwork stays fixed while the loading message appears.','dark')]
assets=[]
for title,folder,ending,note,bg in specs:
 f=next(f for f in (S/folder).iterdir() if f.name.endswith(ending))
 shutil.copy2(f,A/f.name)
 item=dict(title=title,file=f.name,note=note,bg=bg,source=str(f.relative_to(S)))
 if title.startswith('Wordmark'):
  svg=next((S/folder).glob('*.svg'));shutil.copy2(svg,A/svg.name);item['svg']=svg.name
 assets.append(item)
for f in sorted((S/'05 App Store — Approved Panels').glob('[0-9][0-9]-*.png')):
 shutil.copy2(f,A/f.name)
 assets.append(dict(title='App Store '+f.stem[:2]+' · '+f.stem[3:].replace('-',' '),file=f.name,note='Approved September 14 App Store panel · original export.',bg='paper',source=str(f.relative_to(S))))
brand=dict(assets=assets,colors=[['Signal coral','#F05A3C'],['Warm lettering','#E6DDCD'],['Splash background','#080A09']],source='Approved brand package · September 16, 2026',sourceKit='https://drive.google.com/drive/folders/1c1D-20a1pPk7s8DZO6uxtZcq2DQbcTdj')
(R/'brand.json').write_text(json.dumps(brand,ensure_ascii=False,indent=2))
p=R/'pack.py';t=p.read_text();needle="html=(R/'index.template.html')"
insert="""brand=json.loads((R/'brand.json').read_text())
for a in brand['assets']:
 p=R/'brand-assets'/a['file']
 a['download']='data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()
 im=Image.open(p).convert('RGBA');im.thumbnail((800,1000));buf=io.BytesIO();im.save(buf,format='WEBP',quality=90,method=4)
 a['preview']='data:image/webp;base64,'+base64.b64encode(buf.getvalue()).decode()
 if a.get('svg'):a['svgDownload']='data:image/svg+xml;base64,'+base64.b64encode((R/'brand-assets'/a['svg']).read_bytes()).decode()
d['brand']=brand
"""
assert needle in t;t=t.replace(needle,insert+needle);p.write_text(t)
