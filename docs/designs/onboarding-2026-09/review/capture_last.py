import subprocess,time,os,pathlib
R=pathlib.Path(__file__).parent/'screenshots';D='D9547521-B57D-4E07-B2CE-F4B647F4604A';B='com.grayline.wander'
def sim(*a,env=None):return subprocess.run(['xcrun','simctl',*a],capture_output=True,env=env)
def snap(n):sim('io',D,'screenshot',str(R/(n+'.png')));print(n,flush=True)
env=os.environ.copy();env['SIMCTL_CHILD_WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS']='5';env['SIMCTL_CHILD_WANDER_ONBOARDING_FORCE_AUTO_ADVANCE']='1'
sim('launch','--terminate-running-process',D,B,'-WanderAuthenticatedUITest','-WanderOnboardingUITestSignedOut',env=env)
time.sleep(15)
for i in range(6):snap('carousel-final-'+str(i));time.sleep(3)
sim('launch','--terminate-running-process',D,B,'-WanderAuthenticatedUITest','-WanderUseDemoFixtures','-WanderOnboardingUITestStep','location')
time.sleep(18);snap('location')
