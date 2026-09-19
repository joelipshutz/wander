from pathlib import Path
import json,hashlib,shutil,datetime,subprocess
root=Path('/Users/joelipshutz/Documents/ChatGPT/New project/onboarding-copy-review/session-2026-09-16');media=root/'native-captures/signal-slide';repo=root.parent.parent/'wander-native-onboarding-review'
m=json.loads((root/'native-finishes.signal.json').read_text());assert len(m['finishes'])==1;assert m['motionRevision']=='signal-slide-v1';assert m['sourceCommit']==subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
for mode,a in m['finishes'][0]['appearances'].items():
 assert a['accountConfirmed'];assert hashlib.sha256((root/a['file']).read_bytes()).hexdigest()==a['sha256']
 assert 'LOCAL' in a['phaseTextProof']['final']
 assert 'EXPERIMENT' in a['phaseTextProof']['final']
 assert any('COMMUNITY' in t for t in a['phaseTextProof']['community'])
 assert any('PLACES' in t for t in a['phaseTextProof']['wordPlaces'])
 for phase,copy in [('places','KEEPTRACKOFEVERYWHEREYOUVEBEEN'),('people','KEEPUPWITHTHEPEOPLEYOULOVE')]:
  normalized=''.join(c for c in ''.join(a['phaseTextProof'][phase]).upper() if c.isalpha());assert copy in normalized,(mode,phase,normalized)
assert len(json.loads((media/'compact-checks.json').read_text()))==6
for no,key in [('01','community'),('02','wordPlaces'),('03','final'),('04','places')]:shutil.copyfile(media/f'signal-dark-{key}.png',root/f'native-captures/opening-state-{no}.png')
for card,key in [('W00','community'),('W01','places'),('W02','people')]:shutil.copyfile(media/f'signal-dark-{key}.png',root/f'native-captures/{card}.png')
shutil.copyfile(media/'signal-dark-W00-compact.png',root/'native-captures/W00-compact.png')
shutil.copyfile(root/'native-finishes.signal.json',root/'native-finishes.json');shutil.copyfile(root/'opening-signal-slide.next.html',root/'opening-explorations.html')
a=root/'archives/native-finishes-readable/opening-explorations.html';s=a.read_text().replace("fetch('native-finishes.json'","fetch('archives/native-finishes-readable/native-finishes.json'");a.write_text(s)
a=root/'archives.html';s=a.read_text().replace('<ul>','<ul><li><a href="archives/native-finishes-readable/opening-explorations.html">Physical flip-board exploration · archived before the plain Signal slide pivot</a><br>Three native finishes with serif lead-in and larger benefit caps. T15 supersedes this mechanism.</li>',1);a.write_text(s)
a=root/'opening-physical-first.html';a.write_text('<!doctype html><html><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=opening-explorations.html"><title>Current native opening</title><a href="opening-explorations.html">Current Signal slide review</a> · <a href="archives/native-finishes-readable/opening-physical-first.html">Archived physical take</a></html>')
a=root/'native-review.template.html';s=a.read_text().replace('Opening · three finishes','Opening · Signal slide');a.write_text(s)
a=root/'build_native_review.py';s=a.read_text().replace('Current external-lead / longer-flutter recordings are linked from the Opening review above.','Current plain Signal text slides are linked from the Opening review above.');a.write_text(s)
a=root/'native-copy.json';d=json.loads(a.read_text());d['sourceCommit']=m['sourceCommit'];d['auditedAt']=datetime.datetime.now(datetime.timezone.utc).isoformat();d['auditNote']='T15 current launch-blocker checkpoint: one plain Signal-orange Avenir Next Bold slide treatment; serif lead-in; whole outgoing/incoming words move simultaneously. Full Swift dark/light recordings and compact screens. Earlier physical mechanism superseded. Separate NUX work untouched.'
for source in d['sourceFiles']:source['sha256']=hashlib.sha256(Path(source['path']).read_bytes()).hexdigest()
for card in d['cards']:
 if card['id'] in ['W00','W01','W02']:
  card['coverage']='Actual native Signal slide revision '+m['sourceCommit'][:7]+'; complete light/dark recordings in opening-explorations.html.'
  card['note']=('Plain Signal-orange Avenir Next Bold uppercase whole-word slides with a serif Connect with your. COMMUNITY → PEOPLE → PLACES → LOVED ONES. Initial entrance 1.5s; holds 1.8s; simultaneous word handoffs 1.5s. Description enters at 5.1s. Serif lead fades at 13.02–13.20s, final A / LOCAL / EXPERIMENT slides in by 14.7s and holds 2.4s. Full opening slides to Places at 17.1s. No active boards, texture or flap haptics. One treatment for review.' if card['id']=='W00' else 'Exact three-line benefit copy in plain Signal-orange Avenir Next Bold. Complete outgoing/incoming text blocks and upper native UI slide together over 1.5s; each settled scene holds for 7s. Actual Hotchkiss Park photo/preview and native activity postcard. One treatment for review.')
a.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
subprocess.run(['python3',str(root/'brief/build_motion_brief.py')],check=True);subprocess.run(['python3',str(root/'build_native_review.py'),'--publish'],check=True)
print('Published ONE native Signal slide treatment',m['sourceCommit'],flush=True)
