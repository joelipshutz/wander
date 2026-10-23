from pathlib import Path
import base64,json
from svg_images import deduplicate_images
out=Path(__file__).resolve().parent.parent;a=out/'assets'
types=json.loads((out/'build/type-paths.json').read_text())
def data(p):return 'data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()
sources={n:data(a/f'source{n}.png') for n in [34,36]};base=data(a/'source35.png')
crops={34:[185,150,385,571],36:[107,78,409,563]}
def photo(n,x,y,w,h):
 c=' '.join(map(str,crops[n]));return f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="{c}" overflow="hidden"><image width="1774" height="887" href="{sources[n]}"/></svg>'
def pathgroup(kind,phrase,x,y,s,attrs=''):
 return f'<g transform="translate({x} {y}) scale({s})" {attrs}>'+''.join(f'<path d="{p}"/>' for p in types[kind]['phrases'][phrase]['paths'])+'</g>'
def defs(n):
 # Reflect the interior of real chiseled stone into a seamless photographic texture.
 tx,ty,tw,th=(160,770,700,62) if n==34 else (180,740,700,49)
 patch=f'<svg width="700" height="90" viewBox="{tx} {ty} {tw} {th}" preserveAspectRatio="none" overflow="hidden"><image width="1774" height="887" href="{sources[n]}"/></svg>'
 return '<defs><pattern id="stone" patternUnits="userSpaceOnUse" width="700" height="180">'+patch+'<g transform="translate(0 180) scale(1 -1)">'+patch+'</g></pattern><linearGradient id="depth" x2="0.85" y2="1"><stop stop-color="#b8ae9b"/><stop offset=".6" stop-color="#7e7363"/><stop offset="1" stop-color="#544b40"/></linearGradient><filter id="edge" x="-10%" y="-10%" width="120%" height="120%" color-interpolation-filters="sRGB"><feGaussianBlur in="SourceAlpha" stdDeviation="1.1" result="soft"/><feSpecularLighting in="soft" surfaceScale="3" specularConstant=".48" specularExponent="18" lighting-color="#fff9e9" result="light"><feDistantLight azimuth="225" elevation="48"/></feSpecularLighting><feComposite in="light" in2="SourceAlpha" operator="in" result="edgeLight"/><feComposite in="SourceGraphic" in2="edgeLight" operator="arithmetic" k2="1" k3=".7"/></filter><filter id="signal" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0"/><feComponentTransfer><feFuncR type="linear" slope=".55" intercept=".47"/><feFuncG type="linear" slope=".44" intercept=".03"/><feFuncB type="linear" slope=".36" intercept="0"/></feComponentTransfer></filter></defs>'
def foundation(x,y,w,h):
 return f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="107 718 1575 105" preserveAspectRatio="none" overflow="hidden"><image width="1774" height="887" href="{base}" filter="url(#signal)"/></svg>'
def engraving(kind,xright,y,width):
 s=width/types[kind]['phrases']['ONENESS']['advance'];x=xright-width
 # A pale lower rim and a dark inset create a quiet right-aligned engraved inscription.
 return pathgroup(kind,'ONENESS',x+.8,y+1.4,s,'fill="#ffd5b1" opacity=".65"')+pathgroup(kind,'ONENESS',x,y,s,'fill="#772719" opacity=".90"')
metadata=[]
for id,n,kind in [(42,34,'current'),(43,36,'current'),(44,34,'bold'),(45,36,'bold')]:
 fh=640;fw=fh*crops[n][2]/crops[n][3];tw=1390;gap=57;left=(2200-fw-gap-tw)/2;baseline=766;tx=left+fw+gap;s=tw/types[kind]['phrases']['STIR']['advance']
 face=pathgroup(kind,'STIR',tx,baseline,s,'fill="url(#stone)" filter="url(#edge)"')
 # Repeat the unchanged outline a few pixels behind the face, producing a real visible side plane.
 relief=''.join(pathgroup(kind,'STIR',tx+d,baseline+d*.65,s,'fill="url(#depth)"') for d in [11,8,5,2])
 svg='<svg xmlns="http://www.w3.org/2000/svg" width="2200" height="1050" viewBox="0 0 2200 1050"><title>Astir '+str(id)+' — photographed family '+str(n)+', '+kind+' New York stone letters</title><desc>Unchanged photographic A. Exact New York glyph outlines with chiseled photographic stone faces and shallow native relief. Continuous signal foundation with right-aligned ONENESS. Transparent background.</desc>'+defs(n)+photo(n,left,baseline-fh,fw,fh)+relief+face+foundation(105,813,1990,136)+engraving(kind,2014,906,298)+'</svg>'
 (a/f'{id}-wordmark.svg').write_text(deduplicate_images(svg))
 bg={42:'#F2E9DB',43:'#141714',44:'#F05A3C',45:'#141714'}[id]; ih=790 if id in [42,43,44] else 733; iw=ih*crops[n][2]/crops[n][3];iy=80
 icon=f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><title>Astir icon {id}</title><rect width="1024" height="1024" fill="{bg}"/>'+defs(n)+photo(n,(1024-iw)/2,iy,iw,ih)
 if id in [42,45]:icon+=foundation(130,iy+ih+24,764,70)+engraving('current',854,iy+ih+74,190)
 icon+='</svg>';(a/f'icon{id}.svg').write_text(deduplicate_images(icon))
 metadata.append(dict(id=id,title=f'{n} family · {kind} stone serif',source=n,type=kind,font=types[kind]['font'],wordmark=f'{id}-wordmark.svg',wordmarkPng=f'{id}-wordmark.png',icon=f'icon{id}.svg',iconPng=f'icon{id}.png',sourceFile=f'source{n}.png',sourceCrop=crops[n],baseColor='#F05A3C',iconBackground=bg,baseSource='02-wordmarks/transparent/35-coral-stone-foundation.png',letterTextureSource=f'source{n}.png — original stone base face',letterTextureRect=[160,770,700,62] if n==34 else [180,740,700,49],wordmarkSize=[2200,1050],iconSize=[1024,1024],transparent=True,description=f'Pixel-faithful family A from {n}, {kind} New York stone letters, signal foundation, right-aligned engraved ONENESS.'))
(a/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('Built42–45 SVG wordmarks/icons and source copies.')
