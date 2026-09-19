import pathlib,subprocess,time
r=pathlib.Path(__file__).parent/'sequence';r.mkdir(exist_ok=True)
for i in range(55):
 subprocess.run(['xcrun','simctl','io','D9547521-B57D-4E07-B2CE-F4B647F4604A','screenshot',str(r/f'{i:02}.png')],capture_output=True)
 if i%10==0:print('Captured frame',i,flush=True)
 time.sleep(1.0)
