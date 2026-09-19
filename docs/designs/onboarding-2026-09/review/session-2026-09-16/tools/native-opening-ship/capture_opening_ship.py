from pathlib import Path
import os, subprocess
DEVICE='3634A858-7A50-4EC3-8C21-56E6B16A6985'
APP='com.grayline.wander'
def run(*args,check=True,env=None):
 return subprocess.run(['xcrun','simctl',*args],check=check,capture_output=True,text=True,env=env)
def launch(screen,device=DEVICE,hold=True):
 run('terminate',device,APP,check=False)
 environment=os.environ.copy()
 environment['SIMCTL_CHILD_WANDER_ONBOARDING_PAUSED']='1' if hold else '0'
 environment['SIMCTL_CHILD_WANDER_ONBOARDING_START_STEP']={'W00':'opening','W01':'places','W02':'people'}[screen]
 args=['-WanderAuthenticatedUITest','-WanderOnboardingUITestSignedOut','-WanderUseDemoFixtures']
 run('launch',device,APP,*args,env=environment)
 return args
