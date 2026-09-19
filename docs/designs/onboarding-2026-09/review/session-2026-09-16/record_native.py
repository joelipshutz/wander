"""Record the simulator's real output; no browser animation or reconstructed UI."""
from pathlib import Path
import argparse, os, signal, subprocess, time
from capture_native import APP, DEVICE, ROOT, launch, run

parser = argparse.ArgumentParser()
parser.add_argument('screen')
parser.add_argument('filename')
parser.add_argument('--seconds', type=float, default=25)
options = parser.parse_args()
destination = ROOT / 'native-captures' / options.filename
run('terminate', DEVICE, APP, check=False)
recording = subprocess.Popen(['xcrun','simctl','io',DEVICE,'recordVideo','--codec=h264','--force',str(destination)],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
try:
    time.sleep(0.6)
    launch(options.screen, hold=False)
    print('Recording actual native sequence:', options.screen, flush=True)
    time.sleep(options.seconds)
finally:
    recording.send_signal(signal.SIGINT)
    output, _ = recording.communicate(timeout=30)
    print(output, flush=True)
    print('Recorded:', destination.name, destination.stat().st_size if destination.exists() else 'MISSING', flush=True)
