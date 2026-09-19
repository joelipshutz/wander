"""Check texture-frame changes in the empty header during scene handoffs."""
from pathlib import Path
import json, subprocess
import numpy as np
from PIL import Image, ImageDraw
root=Path(__file__).resolve().parents[2]
results={}
for title,manifestName in [('before','native-film-comparison-v2.json'),('after','native-film-continuous.json')]:
 manifest=json.loads((root/manifestName).read_text())
 take=manifest['takes']['film-type-dark']
 previous=None; diffs=[]; shots=[]
 for i in range(45):
  offset=15.5+i*.1
  path=Path('/tmp/film-continuity-frame.png')
  subprocess.run(['/tmp/astir-native-video','frame',str(root/take['file']),str(take['startSeconds']+offset),str(path)],check=True,stdout=subprocess.DEVNULL)
  picture=Image.open(path).convert('RGB')
  # This is an empty, stationary part of the header. Only the film moves here.
  values=np.asarray(picture.crop((470,180,700,260))).astype(float)
  if previous is not None: diffs.append({'offset':round(offset,2),'meanPixelChange':round(float(np.abs(values-previous).mean()),4)})
  previous=values
  if i in [10,15,20,25,30]:
   picture.thumbnail((234,507));shots.append((offset,picture.copy()))
 run=longest=0
 for item in diffs:
  run=run+1 if item['meanPixelChange']<.2 else 0
  longest=max(longest,run)
 results[title]={'source':take['sourceCommit'],'maxNearFrozenSeconds':round(longest*.1,2),'samples':diffs}
 sheet=Image.new('RGB',(234*5,540),'#151914');draw=ImageDraw.Draw(sheet)
 for i,(offset,picture) in enumerate(shots):
  sheet.paste(picture,(234*i,30));draw.text((234*i+8,8),f'+{offset:.1f}s',fill='white')
 sheet.save(root/f'native-board-qa/film-continuity-{title}.jpg',quality=92)
(root/'native-board-qa/film-continuity-pixels.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps({k:{a:b for a,b in v.items() if a!='samples'} for k,v in results.items()},indent=2))
