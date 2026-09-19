from pathlib import Path
import os,subprocess,time,json,signal,sys
root=Path('/Users/joelipshutz/Documents/ChatGPT/New project/onboarding-copy-review/session-2026-09-16')
sys.path.insert(0,str(root));import capture_native as c
c.run('boot',c.DEVICE,check=False);c.run('bootstatus',c.DEVICE,'-b')
c.run('install',c.DEVICE,str(root.parent.parent/'.dev-cache/xcode/b9bf1d4adbbf761764b5/Build/Products/Debug-iphonesimulator/Wander.app'))
out=root/'native-captures/signal-slide';out.mkdir(exist_ok=True);log=json.loads((out/'recording-checks.json').read_text()) if (out/'recording-checks.json').exists() else []
for finish in ['signal']:
 for mode in ['dark','light']:
  if any(x['finish']==finish and x['mode']==mode and x['accountConfirmed'] for x in log):continue
  os.environ['SIMCTL_CHILD_WANDER_ONBOARDING_FLAP_FINISH']=finish
  c.run('ui',c.DEVICE,'appearance',mode)
  c.run('terminate',c.DEVICE,c.APP,check=False)
  path=out/f'{finish}-{mode}.mp4'
  recorder=subprocess.Popen(['xcrun','simctl','io',c.DEVICE,'recordVideo','--codec=h264','--force',str(path)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
  try:
   time.sleep(.6);c.launch('W00',hold=False);start=time.monotonic()
   print('Recording complete flow:',finish,mode,flush=True)
   time.sleep(46)
   while True:
    screenshot=out/f'{finish}-{mode}-live-end.png';c.run('io',c.DEVICE,'screenshot',str(screenshot))
    text=json.loads(subprocess.check_output(['/tmp/astir-native-ocr',str(screenshot)],text=True))
    complete=any('create your account' in x.lower() for x in text['text'])
    if complete or time.monotonic()-start>80:break
    time.sleep(5)
   if not complete:raise RuntimeError('No account end state: '+finish+' '+mode)
   time.sleep(2)
  finally:
   recorder.send_signal(signal.SIGINT);recorder.communicate(timeout=30)
  log.append({'finish':finish,'mode':mode,'accountConfirmed':complete,'visibleText':text['text'],'elapsed':time.monotonic()-start})
  (out/'recording-checks.json').write_text(json.dumps(log,indent=2)+'\n')
  print('Account verified:',finish,mode,flush=True)
  if '--first' in sys.argv:sys.exit(0)
print('Two complete native flows recorded.',flush=True)
