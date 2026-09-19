import subprocess, time, os, pathlib, json
ROOT=pathlib.Path(__file__).parent
DEVICE='D9547521-B57D-4E07-B2CE-F4B647F4604A'
BUNDLE='com.grayline.wander'
def sim(*args, env=None):
    return subprocess.run(['xcrun','simctl',*args],capture_output=True,text=True,env=env)
sim('ui',DEVICE,'appearance','light')
sim('status_bar',DEVICE,'override','--time','9:41','--dataNetwork','wifi','--wifiMode','active','--wifiBars','3','--batteryState','charged','--batteryLevel','100')
base=['-WanderAuthenticatedUITest','-WanderUseDemoFixtures']
jobs=[('welcome-1',base+['-WanderOnboardingUITestSignedOut'],4)]
for step in ['identity','location','contacts','friends','notifications']:
    jobs.append((step,base+['-WanderOnboardingUITestStep',step,'-WanderNotificationAuthorizationNotDeterminedFixture','-WanderBypassProductUpsellFrequencyCap'],3))
jobs.append(('auth',base+['-WanderAuthUITest'],3))
walk=base+['-WanderMapCapture','-WanderEnableWalkthroughs','-WanderResetWalkthroughs']
for target in ['mapAdd','addSearch','saveStatus','mapAddAgain','addImport','mapSendoff']:
    jobs.append((target,walk+['-WanderWalkthroughTarget',target],2))
jobs += [('import-lesson',walk+['-WanderShowImportWalkthrough'],3),('device-features',walk+['-WanderShowDeviceFeaturesWalkthrough'],3)]
for trigger in ['place_saved','follow_created']:
    jobs.append((trigger,base+['-WanderDisableWalkthroughs','-WanderProductUpsellTrigger',trigger,'-WanderNotificationAuthorizationNotDeterminedFixture','-WanderBypassProductUpsellFrequencyCap'],3))
for name,args,delay in jobs:
    sim('terminate',DEVICE,BUNDLE)
    env=os.environ.copy(); env['SIMCTL_CHILD_WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS']='600'
    r=sim('launch',DEVICE,BUNDLE,*args,env=env)
    if r.returncode: print(name,'launch failed',r.stderr[:200],flush=True); continue
    time.sleep(delay)
    r=sim('io',DEVICE,'screenshot',str(ROOT/'screenshots'/f'{name}.png'))
    print(name,'captured' if r.returncode==0 else r.stderr[:100],flush=True)
