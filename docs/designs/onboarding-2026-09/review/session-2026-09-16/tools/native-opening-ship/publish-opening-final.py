from pathlib import Path
import json,hashlib,subprocess,shutil,datetime,html,re
root=Path(__file__).resolve().parents[2];repo=root.parent.parent/'wander-native-onboarding-review';archive=root.parent.parent/'wander-onboarding-review-archive';media=root/'native-captures/signal-slide-final'
commit=subprocess.check_output(['git','-C',str(repo),'rev-parse','4cba092'],text=True).strip()
m=json.loads((root/'native-finishes.signal.json').read_text());assert m['sourceCommit']==commit and m['motionRevision']=='signal-slide-v2'
assert len(m['finishes'])==1
for mode,a in m['finishes'][0]['appearances'].items():
 assert a['accountConfirmed'] and hashlib.sha256((root/a['file']).read_bytes()).hexdigest()==a['sha256']
 for phase,copy in [('community','COMMUNITY'),('wordPlaces','PLACES'),('final','ALOCAL EXPERIMENT'),('places','KEEP TRACK OF EVERYWHERE YOUVE BEEN'),('people','KEEP UP WITH THE PEOPLE YOU LOVE')]:
  normalize=lambda value: ''.join(c for c in value.upper() if c.isalpha())
  assert normalize(copy) in normalize(''.join(a['phaseTextProof'][phase])),(mode,phase,a['phaseTextProof'][phase])
assert len(json.loads((media/'compact-checks.json').read_text()))==6
previous=root/'archives/native-signal-slide-v1';previous.mkdir(exist_ok=True)
for name in ['native-finishes.json','opening-explorations.html']:
 if not (previous/name).exists():shutil.copy2(root/name,previous/name)
for no,key in [('01','community'),('02','wordPlaces'),('03','final'),('04','places')]:shutil.copyfile(media/f'signal-dark-{key}.png',root/f'native-captures/opening-state-{no}.png')
for card,key in [('W00','community'),('W01','places'),('W02','people')]:shutil.copyfile(media/f'signal-dark-{key}.png',root/f'native-captures/{card}.png')
shutil.copyfile(media/'signal-dark-W00-compact.png',root/'native-captures/W00-compact.png')
(root/'native-finishes.json').write_text(json.dumps(m,indent=2)+'\n')
p=root/'opening-explorations.html';s=p.read_text();s=s.replace('signal-slide-v1','signal-slide-v2');s=s.replace('Astir · Launch-blocker review','Astir · Approved opening').replace('Signal slide checkpoint','Approved Signal slide')
s=s.replace('The serif lead-in fades quickly, then', 'The larger serif lead-in sits closer to the centered orange word. It fades quickly, then')
s=s.replace('Review the word handoffs, readable holds, final phrase and complete screen transitions. The events-placeholder style is deferred until after this checkpoint.','Approved native opening with final heading size and spacing. Events is the next separate pass.')
s=s.replace('Your latest direction · exact transcript','Final adjustment · exact transcript')
# Replace the current transcript block while retaining the original pivot below it.
transcript=html.escape((root/'transcripts/T16-approved-opening-final-spacing.txt').read_text().strip())
s=re.sub(r'(<details[^>]*>\s*<summary>Final adjustment · exact transcript</summary>).*?(</details>)',lambda x:x[1]+'<blockquote>'+transcript+'</blockquote>'+x[2],s,flags=re.S)
p.write_text(s)
p=root/'native-copy.json';d=json.loads(p.read_text());old=str(repo);arch=str(archive)
d['sourceCheckout']=arch;d['sourceCommit']=subprocess.check_output(['git','-C',arch,'rev-parse','HEAD'],text=True).strip();d['openingSourceCheckout']=str(repo);d['openingSourceCommit']=commit
d['auditedAt']=datetime.datetime.now(datetime.timezone.utc).isoformat();d['auditNote']='T16 approved opening extracted onto current main with final typography, static accessibility and production account transitions. W00–W02 use the new opening commit; other NUX cards retain preserved review-branch source and earlier capture evidence.'
for source in d['sourceFiles']:
 source['path']=source['path'].replace(old,arch)
 assert hashlib.sha256(Path(source['path']).read_bytes()).hexdigest()==source['sha256'],source['path']
for card in d['cards']:
 if card['id'] in ['W00','W01','W02']:
  card['sourceCommit']=commit;card['coverage']='Actual native approved opening '+commit[:7]+'; full dark/light Swift recordings.'
  file='OnboardingWelcomeContent.swift' if card['id']=='W00' else 'LoggedOutCarouselView.swift'
  card['source']=str(repo/'Wander/Features/Onboarding'/file)
  card.pop('sourceRefs',None);card.pop('sourceReferences',None)
  if card['id']=='W00':
   card['lines'][0]['role']='Stable serif lead-in'
   card['note']='Final T16: larger editorial serif lead-in moved closer to the centered Signal-orange words. One native whole-word slide treatment, unchanged approved copy and 1.5-second slide timing. Static accessibility includes the complete final phrase.'
 else:
  for key in ['source','sourceRefs','sourceReferences']:
   if isinstance(card.get(key),str):card[key]=card[key].replace(old,arch)
   elif isinstance(card.get(key),list):card[key]=[x.replace(old,arch) for x in card[key]]
for path in sorted((repo/'Wander/Features/Onboarding').glob('*.swift')):
 if path.name in ['LoggedOutCarouselView.swift','OnboardingWelcomeContent.swift','SignedOutOnboardingFlowView.swift','OnboardingPlacePhotoRepository.swift']:
  d['sourceFiles'].append({'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'scope':'T16 approved opening','commit':commit})
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
p=root/'brief/build_motion_brief.py';s=p.read_text();anchor='md = ['
s=s.replace("current_manifest.get('motionRevision') == 'signal-slide-v1'","current_manifest.get('motionRevision') == 'signal-slide-v2'")
addition="""# T16 approval and final typography supersede the prior checkpoint.
quotes.insert(0, ('Approved opening: final size and spacing', 'T16-approved-opening-final-spacing.txt', (root / 'transcripts/T16-approved-opening-final-spacing.txt').read_text().strip()))
states[0]['top'] += ' The stable serif lead-in is slightly larger and closer to the orange word, whose center stays fixed.'
gap = 'The approved Swift opening now includes the final heading size and spacing. Native dark/light recordings show this exact implementation. Static accessibility retains the complete message. Events remains the next separate pass.'

"""
assert anchor in s;s=s.replace(anchor,addition+anchor,1);p.write_text(s)
subprocess.run(['python3',str(root/'brief/build_motion_brief.py')],check=True)
subprocess.run(['python3',str(root/'build_native_review.py'),'--publish'],check=True)
print('Published final approved native opening',commit)
