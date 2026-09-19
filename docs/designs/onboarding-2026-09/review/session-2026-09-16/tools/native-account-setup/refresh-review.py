"""Refresh only reviewed setup cards from actual native capture evidence."""
from pathlib import Path
import json, shutil, subprocess, datetime
ROOT=Path(__file__).resolve().parents[2]
manifest=json.loads((ROOT/'native-dark-setup.json').read_text())
p=ROOT/'native-copy.json'; source=json.loads(p.read_text())
archive=ROOT/'archives/account-setup-before-dark'; archive.mkdir(parents=True,exist_ok=True)
if not (archive/'native-copy.json').exists(): shutil.copy2(p,archive/'native-copy.json')
by_id={c['id']:c for c in source['cards']}
for ident,evidence in manifest['screens'].items():
 if ident not in by_id: continue
 card=by_id[ident]
 card.update(image=evidence['image'],captureNote=manifest['captureNote'],source=manifest['sourceCheckout']+'/'+evidence['source'],coverage='Actual native Swift · dark account-setup pass · '+manifest['sourceCommit'][:7])
 card['motionVideo']=evidence.get('video')
 card['sourceCommit']=evidence.get('sourceCommit',manifest['sourceCommit'])
 card['coverage']='Actual native Swift · dark account-setup pass · '+card['sourceCommit'][:7]
 card['sampleData']=ident in ['N10','N11','N12','N32']
card=by_id['N08'];card['note']='Live name, username and photo use the real shared profile header. Photo remains optional, preserving current main. Apple sign-in asks only for username; other accounts show both fields. Continue keeps current identity validation.'
for line in card['lines']:
 if line['role']=='Handle preview · empty fallback':line['text']='@username'
if not any(l['text']=='Make yourself easy to find.' for l in card['lines']): card['lines'].insert(5,{'role':'Supporting line','text':'Make yourself easy to find.'})
by_id['N09']['lines']=[{'role':r,'text':t} for r,t in [
 ('Real place preview','Hotchkiss Park'),('Place category','Park'),('Eyebrow','AROUND YOU'),('Headline','Find the good stuff nearby'),
 ('Body','See places your friends recommend and save spots around you without searching for an address.'),
 ('Privacy line','Your location is yours.'),('Primary','Continue'),('Primary · requesting','Requesting location…')]]
by_id['N09']['note']='Production MapKit and selected-place surface, including the full real Hotchkiss Park photo returned by the app’s place service and cached for onboarding. No fictional coffee shop or invented friend rating. Native map entrance respects Reduce Motion. Denied footer uses Open Settings and Not now.'
by_id['N10']['lines']=[{'role':r,'text':t} for r,t in [('Example activity badge','CHECKED IN'),('Example place','Marigold Table'),('Example category','Santa Monica · Restaurant'),('Example actor','Mina checked in'),('Example metadata','2h ago · someone you follow'),('Example rating','5'),('Example note','“The patio at golden hour. Get the focaccia!”'),('Eyebrow','YOUR PEOPLE'),('Headline','Connect with your people'),('Body','Use your contacts to connect with people you know.'),('Primary','Continue'),('Primary · requesting','Opening settings…')]]
by_id['N10']['note']='The same native activity postcard as the approved opening shows what connecting unlocks. Mina/Marigold Table are illustrative onboarding content. Contacts still uses the existing permission flow; automatic contact matching/ranking remains unimplemented.'
by_id['N12']['note']='Three native notification examples arrive in sequence: check-in, import ready, new follower. Real app icon and dark surfaces; these are examples, not actual delivered notifications. This visual change applies to the signup primer only. Later contextual notification campaigns remain unchanged.'
if not any(l['text']=='Open Settings' for l in by_id['N12']['lines']): by_id['N12']['lines'].append({'role':'Primary · denied (shown in this capture)','text':'Open Settings'})
source['updatedAccountSetupAt']=datetime.datetime.now(datetime.timezone.utc).isoformat()
source['accountSetupManifest']='native-dark-setup.json'
p.write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n')
subprocess.run(['python3',str(ROOT/'build_native_review.py'),'--publish'],cwd=ROOT,check=True)
