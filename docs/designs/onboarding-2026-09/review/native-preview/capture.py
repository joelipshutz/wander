from pathlib import Path
import subprocess,time
R=Path(__file__).parent.parent/'screenshots';D='D9547521-B57D-4E07-B2CE-F4B647F4604A';B='com.astir.copyreview.preview'
for route in ['signup','verify','crop','recovery','friends-empty','notifications-denied','identity-checking','identity-available','identity-taken','identity-saving','system-contacts','system-calendar','system-photos','system-camera']:
 p=subprocess.run(['xcrun','simctl','launch','--terminate-running-process',D,B,route],capture_output=True,text=True)
 if p.returncode:print(route,p.stderr[:150],flush=True);continue
 time.sleep(3)
 subprocess.run(['xcrun','simctl','io',D,'screenshot',str(R/(route+'-component.png'))],capture_output=True)
 print(route,flush=True)
