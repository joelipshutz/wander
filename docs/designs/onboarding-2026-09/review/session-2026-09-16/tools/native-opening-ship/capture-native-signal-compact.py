import sys,os,time,subprocess,json
from pathlib import Path
root=Path('/Users/joelipshutz/Documents/ChatGPT/New project/onboarding-copy-review/session-2026-09-16');sys.path.insert(0,str(root));import capture_opening_ship as c
sim='7BE74040-8A1F-40AF-994D-7EBDD9E17194';c.run('boot',sim,check=False);c.run('bootstatus',sim,'-b');c.run('install',sim,str(root.parent.parent/'.dev-cache/xcode/b9bf1d4adbbf761764b5/Build/Products/Debug-iphonesimulator/Wander.app'))
checks=[]
for mode in ['dark','light']:
 os.environ['SIMCTL_CHILD_WANDER_ONBOARDING_FLAP_FINISH']='signal';c.run('ui',sim,'appearance',mode)
 for screen in ['W00','W01','W02']:
  c.launch(screen,device=sim);time.sleep(8)
  path=root/'native-captures/signal-slide-final'/f'signal-{mode}-{screen}-compact.png'
  for attempt in range(5):
   c.run('io',sim,'screenshot',str(path));texts=json.loads(subprocess.check_output(['/tmp/astir-native-ocr',str(path)],text=True))['text']
   normalized=''.join(x for x in ''.join(texts).upper() if x.isalpha())
   expected={'W00':'CONNECTWITHYOUR','W01':'HOTCHKISSPARK','W02':'MARIGOLDTABLE'}[screen]
   if expected in normalized and 'NEXT' in normalized:break
   time.sleep(3)
  else:raise RuntimeError('Native compact state not ready '+screen+' '+mode)
  checks.append({'finish':'signal','mode':mode,'screen':screen,'text':texts,'file':path.name});print('Compact verified',screen,mode,flush=True)
(root/'native-captures/signal-slide-final/compact-checks.json').write_text(json.dumps(checks,indent=2)+'\n')
c.run('shutdown',sim)
