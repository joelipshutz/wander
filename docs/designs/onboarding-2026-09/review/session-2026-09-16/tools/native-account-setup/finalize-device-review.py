"""Publish actual native device-review captures while retaining older study files."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--captures',type=Path,required=True)
parser.add_argument('--source-ref',required=True)
args=parser.parse_args()
ROOT=Path(__file__).resolve().parents[2]
OUT=args.captures.resolve()
required=['N08','N09','N10','N11','N12','Founders-poster','Founders-playing']
for key in required: assert (OUT/(key+'.png')).is_file(),key
source=json.loads((ROOT/'native-copy.json').read_text());cards={c['id']:c for c in source['cards']}
for key in ['N08','N09','N10','N11','N12','N33','N34']:
 image=OUT/(key+'.png')
 if not image.exists():continue
 c=cards[key];c.update(image=str(image.relative_to(ROOT)),sourceCommit=args.source_ref,
  captureNote='Actual Swift · iPhone 16e · combined device review · '+args.source_ref[:7],
  coverage='Actual Swift capture · September 19 device candidate')
 # Prior movies remain accessible through the preserved previous study, rather
 # than silently presenting a different source build as this capture's motion.
 c['motionVideo']=None
for l in cards['N09']['lines']:
 if l['role']=='Headline':l['text']='Find places nearby'
cards['N08']['note']='Photo is optional, explicitly confirmed by Joe in T32. Real identity validation and selected-photo upload failures remain. The live profile preview uses the shared native app header.'
# Stable line references retain their prior numbers when a retired line is removed.
for i,l in enumerate(cards['N04']['lines']):l.setdefault('lineNumber',i+1)
cards['N04']['lines']=[l for l in cards['N04']['lines'] if l['text']!='Close']
film=json.loads((ROOT/'native-film-events-match.json').read_text())
for key,phase in [('W00','community'),('W01','places'),('W02','people'),('N04','account')]:
 c=cards[key];c.update(image='native-captures/film-events-match/film-type-dark-'+phase+'.png',sourceCommit=film['sourceCommit'],
  captureNote='Actual Swift · selected Events-match film C · archived source '+film['sourceCommit'][:7]+'; integrated into this device review',
  coverage='Selected film C · original verified native recording',motionVideo=None)
cards['W00']['video']='native-captures/film-events-match/film-type-dark.mp4'
cards['W00']['title']='Selected opening · film C'
cards['W00']['lines'][0]['role']='Stable italic lead-in'
source['filmSelected']=True
founders=dict(id='N71',title='A quick hello · founders welcome',group='03 · Setup',
 source='Wander/Features/Onboarding/FoundersWelcomeView.swift',image=str((OUT/'Founders-poster.png').relative_to(ROOT)),
 sourceCommit=args.source_ref,coverage='Actual Swift player · September 19 device candidate',
 captureNote='Native AVKit player · full portrait video · iPhone 16e',sampleData=False,
 note='After Notifications, before Ryan’s NUX. Play starts sound; Skip is always available. Background pauses. Ending/Skip fades into the first-use walkthrough. Full outtake included; Joe selected VHS C with the cleaned audio. Use Selected founders C above for the complete video.',
 lines=[dict(role=r,text=t) for r,t in [('Heading','A quick hello'),('Byline','From Joe & Ryan · 1:31'),('Primary','Play welcome'),('Interrupted','Resume welcome'),('Exit','Skip intro'),('Supporting line','A little about why we made Astir.'),('Playback','Pause / Resume'),('Audio','Mute / Sound on')]])
if 'N71' in cards:source['cards']=[founders if c['id']=='N71' else c for c in source['cards']]
else:source['cards'].insert(next(i for i,c in enumerate(source['cards']) if c['id']=='N12')+1,founders)
source['deviceReviewSourceCommit']=args.source_ref
(ROOT/'native-copy.json').write_text(json.dumps(source,indent=2,ensure_ascii=False)+'\n')
manifest={'sourceCommit':args.source_ref,'screens':{p.stem:{'image':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in OUT.glob('*.png')},'openingSourceCommit':film['sourceCommit'],'audioListeningApproval':'C selected by Joe','mainAndTestFlight':'main landed; consult current release ticket for TestFlight'}
(OUT/'verification.json').write_text(json.dumps(manifest,indent=2)+'\n')
subprocess.run(['python3',str(ROOT/'build_native_review.py'),'--publish'],check=True)
