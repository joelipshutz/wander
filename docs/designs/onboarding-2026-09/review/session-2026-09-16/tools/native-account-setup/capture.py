from pathlib import Path
import subprocess,time,signal,json,hashlib
ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'native-captures/dark-setup';OUT.mkdir(exist_ok=True)
DEVICE='6CB5D49F-FA87-4D3E-9C2E-F9A1296F257C'; APP='com.grayline.wander'
REPO=ROOT.parent.parent/'wander-native-onboarding-review'
def run(*args,check=True): return subprocess.run(['xcrun','simctl',*args],capture_output=True,text=True,check=check)
def launch(route):
 run('terminate',DEVICE,APP,check=False)
 run('launch',DEVICE,APP,'-WanderNativeOnboardingReview',route,'-WanderUseDemoFixtures','-WanderBypassProductUpsellFrequencyCap')
run('status_bar',DEVICE,'override','--time','9:41','--dataNetwork','wifi','--wifiMode','active','--wifiBars','3','--batteryState','charged','--batteryLevel','100')
manifest={'sourceCheckout':str(REPO),'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),'device':DEVICE,'captureNote':'Actual Swift app · iPhone 16e · September 18 dark setup · local review build.','screens':{}}
for screen,route in [('N31','location'),('N32','notifications'),('N08','identity'),('N09','location'),('N10','contacts'),('N11','friends'),('N12','notifications'),('N33','friends-empty'),('N34','friends-failure')]:
 if screen=='N09': run('privacy',DEVICE,'reset','location',APP)
 movie=None
 launch(route)
 if screen in ['N09','N12']:
  movie=OUT/f'{screen}.mp4'
  recorder=subprocess.Popen(['xcrun','simctl','io',DEVICE,'recordVideo','--codec=h264','--force',str(movie)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 time.sleep(6 if screen in ['N09','N12','N31'] else 3)
 image=OUT/f'{screen}.png';run('io',DEVICE,'screenshot',str(image))
 if movie:
  recorder.send_signal(signal.SIGINT);recorder.communicate(timeout=20)
 source='Wander/Features/Onboarding/'+('OnboardingFriendSuggestionsView.swift' if screen in ['N11','N33','N34'] else 'ProductUpsellScreen.swift' if screen in ['N12','N32'] else 'OnboardingLocationMapPreview.swift' if screen in ['N09','N31'] else 'OnboardingFlowView.swift')
 manifest['screens'][screen]={'image':str(image.relative_to(ROOT)),'sha256':hashlib.sha256(image.read_bytes()).hexdigest(),'source':source}
 if movie:manifest['screens'][screen]['video']=str(movie.relative_to(ROOT))
 (ROOT/'native-dark-setup.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print('Captured '+screen,flush=True)
