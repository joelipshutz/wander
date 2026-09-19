import subprocess,time,os,pathlib
R=pathlib.Path(__file__).parent/'screenshots';D='D9547521-B57D-4E07-B2CE-F4B647F4604A';B='com.grayline.wander'
def sim(*a,env=None):return subprocess.run(['xcrun','simctl',*a],capture_output=True,env=env)
def snap(n):sim('io',D,'screenshot',str(R/(n+'.png')));print(n,flush=True)
sim('terminate',D,B)
env=os.environ.copy();env['SIMCTL_CHILD_WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS']='8';env['SIMCTL_CHILD_WANDER_ONBOARDING_FORCE_AUTO_ADVANCE']='1'
sim('launch',D,B,'-WanderAuthenticatedUITest','-WanderOnboardingUITestSignedOut',env=env)
time.sleep(11);snap('welcome-2');time.sleep(8);snap('welcome-3')
sim('terminate',D,B);sim('privacy',D,'reset','location',B)
sim('launch',D,B,'-WanderAuthenticatedUITest','-WanderUseDemoFixtures','-WanderOnboardingUITestStep','location')
time.sleep(6);snap('location')
sim('launch','--terminate-running-process',D,B,'-WanderMapCapture','-WanderUseDemoFixtures','-WanderEnableWalkthroughs','-WanderResetWalkthroughs','-WanderWalkthroughTarget','addImport')
time.sleep(10);snap('addImport')
