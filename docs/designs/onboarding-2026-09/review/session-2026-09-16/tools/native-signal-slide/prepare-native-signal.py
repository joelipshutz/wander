from pathlib import Path
import subprocess,json,hashlib
from PIL import Image,ImageDraw
root=Path('/Users/joelipshutz/Documents/ChatGPT/New project/onboarding-copy-review/session-2026-09-16');media=root/'native-captures/signal-slide'
meta={'sourceCommit':subprocess.check_output(['git','-C',str(root.parent.parent/'wander-native-onboarding-review'),'rev-parse','HEAD'],text=True).strip(),'native':True,'higgsfieldGenerationUsed':False,'motionRevision':'signal-slide-v1','font':'AvenirNext-Bold','leadFont':'native editorial serif, title semibold','sceneSlideSeconds':1.5,'initialEntranceSeconds':1.5,'openingSeconds':17.1,'wordHoldSeconds':1.8,'activeFlapHaptics':False,'finishes':[]}
style=dict(id='signal',name='Signal slide',summary='Whole words, one shared motion.',detail='Plain Signal-orange Avenir Next Bold text with a serif lead-in. Simultaneous whole-word slides and complete native benefit transitions.',appearances={})
def frame(raw,t,path):subprocess.run(['/tmp/astir-native-video','frame',str(raw),str(t),str(path)],check=True,stdout=subprocess.DEVNULL)
for mode in ['dark','light']:
 assert any(x['mode']==mode and x['accountConfirmed'] for x in json.loads((media/'recording-checks.json').read_text()))
 raw=media/f'signal-{mode}.mp4';onset=None;p=Path('/tmp/signal-onset.png');run=[]
 duration=float(subprocess.check_output(['/tmp/astir-native-video','inspect',str(raw)],text=True).strip().split('=')[-1])
 for q in range(0,65):
  t=q/4;frame(raw,t,p);im=Image.open(p).convert('RGB');r,g,b=im.getpixel((int(im.width*.25),int(im.height*.86)))
  if r>180 and 40<g<150 and b<120:run.append(t)
  else:run=[]
  if len(run)>=4:onset=run[0];break
 if onset is None:raise RuntimeError('No stable opening detected '+str(raw))
 phases={'community':2.0,'wordChange':2.95,'wordPlaces':8.4,'finalChange':12.8,'final':15.8,'sceneChange':16.6,'places':22.5,'peopleChange':25.2,'people':31.5}
 proof={};shots=[]
 for key,t in phases.items():
  path=media/f'signal-{mode}-{key}.png';frame(raw,onset+t,path)
  proof[key]=json.loads(subprocess.check_output(['/tmp/astir-native-ocr',str(path)],text=True))['text']
  pic=Image.open(path).convert('RGB');pic.thumbnail((218,480));shots.append((key,pic))
 frame(raw,onset+phases['community'],raw.with_suffix('.png'))
 sheet=Image.new('RGB',(218*5,515*2),'#252c23');draw=ImageDraw.Draw(sheet)
 for n,(label,pic) in enumerate(shots):
  x=(n%5)*218;y=(n//5)*515;sheet.paste(pic,(x,y+28));draw.text((x+8,y+8),mode+' '+label,fill='white')
 sheet.save(root/f'native-board-qa/signal-{mode}-states.jpg',quality=92)
 style['appearances'][mode]={'file':str(raw.relative_to(root)),'poster':str(raw.with_suffix('.png').relative_to(root)),'startSeconds':onset,'durationSeconds':duration,'accountConfirmed':True,'sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'phaseSeconds':phases,'phaseTextProof':proof}
 print(mode,'start',onset,'duration',duration,flush=True)
meta['finishes'].append(style);(root/'native-finishes.signal.json').write_text(json.dumps(meta,indent=2)+'\n')
