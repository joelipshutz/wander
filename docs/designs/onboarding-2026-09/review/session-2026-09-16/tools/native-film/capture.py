from pathlib import Path
import argparse,json,os,subprocess,time,signal
parser=argparse.ArgumentParser()
parser.add_argument('--output',default='film-exploration')
parser.add_argument('--film-only',action='store_true')
parser.add_argument('--treatment',choices=['approved','film','film-type'])
parser.add_argument('--account-hold',type=float,default=1)
parser.add_argument('--device',default='6CB5D49F-FA87-4D3E-9C2E-F9A1296F257C')
args=parser.parse_args()
ROOT=Path('/Users/joelipshutz/Documents/ChatGPT/New project/onboarding-copy-review/session-2026-09-16')
OUT=ROOT/'native-captures'/args.output;OUT.mkdir(parents=True,exist_ok=True)
DEVICE=args.device;APP='com.grayline.wander'
APP_PATH=ROOT.parent.parent/'.dev-cache/xcode/b9bf1d4adbbf761764b5/Build/Products/Debug-iphonesimulator/Wander.app'
def run(*args,check=True,env=None):
 return subprocess.run(['xcrun','simctl',*args],capture_output=True,text=True,check=check,env=env)
run('boot',DEVICE,check=False);run('bootstatus',DEVICE,'-b');run('install',DEVICE,str(APP_PATH))
run('status_bar',DEVICE,'override','--time','9:41','--dataNetwork','wifi','--wifiMode','active','--wifiBars','3','--batteryState','charged','--batteryLevel','100')
checks=[]
takes=[('film','dark'),('film-type','dark')] if args.film_only else [('approved','dark'),('approved','light'),('film','dark'),('film-type','dark')]
if args.treatment:takes=[(args.treatment,'dark')]
for treatment,mode in takes:
 key=f'{treatment}-{mode}';print('Recording '+key,flush=True)
 run('ui',DEVICE,'appearance',mode);run('terminate',DEVICE,APP,check=False)
 env=os.environ.copy();env['SIMCTL_CHILD_WANDER_ONBOARDING_TREATMENT']=treatment
 for k in ['PAUSED','START_STEP','REVIEW_PICKER']:env.pop('SIMCTL_CHILD_WANDER_ONBOARDING_'+k,None)
 path=OUT/f'{key}.mp4'
 recorder=subprocess.Popen(['xcrun','simctl','io',DEVICE,'recordVideo','--codec=h264','--force',str(path)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 try:
  time.sleep(.5)
  run('launch',DEVICE,APP,'-WanderAuthenticatedUITest','-WanderOnboardingUITestSignedOut','-WanderUseDemoFixtures',env=env)
  begin=time.monotonic();time.sleep(42)
  while True:
   screenshot=OUT/f'{key}-account.png';run('io',DEVICE,'screenshot',str(screenshot))
   proof=json.loads(subprocess.check_output(['/tmp/astir-native-ocr',str(screenshot)],text=True))
   complete='create your account' in ' '.join(proof['text']).lower()
   if complete or time.monotonic()-begin>62:break
   time.sleep(3)
  if not complete:raise RuntimeError('Account not reached: '+key+' '+str(proof))
  if args.account_hold >= 2:
   time.sleep(1.25)
   run('io',DEVICE,'screenshot',str(OUT/f'{key}-account-after.png'))
   time.sleep(args.account_hold-1.25)
  else:time.sleep(args.account_hold)
 finally:
  recorder.send_signal(signal.SIGINT);recorder.communicate(timeout=25)
 checks.append({'id':key,'treatment':treatment,'appearance':mode,'accountConfirmed':complete,'visibleText':proof['text'],'elapsedSeconds':time.monotonic()-begin})
 (OUT/'capture-checks.json').write_text(json.dumps(checks,indent=2)+'\n')
 print('Verified account: '+key,flush=True)
print('All requested native recordings complete.',flush=True)
