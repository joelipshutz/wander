#!/usr/bin/env python3
"""Record the three motion options on a dedicated simulator, using bundled fixtures."""
import argparse
from pathlib import Path
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('simulator')
parser.add_argument('app', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--compact', action='store_true')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

def sim(*command, check=True):
    return subprocess.run(['xcrun', 'simctl', *command], check=check, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE if not check else subprocess.DEVNULL)

sim('install', args.simulator, str(args.app))
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.simulator, 'com.grayline.wander', 'data'], text=True).strip())
sim('ui', args.simulator, 'appearance', 'light')
sim('status_bar', args.simulator, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100')
for role in ['owner', 'member']:
    for variant in (['spring'] if args.compact else ['glide', 'spring', 'arc']):
        stem = f'{role}-{variant}' + ('-compact' if args.compact else '')
        sim('terminate', args.simulator, 'com.grayline.wander', check=False)
        command = ['launch', args.simulator, 'com.grayline.wander', '-WanderAuthenticatedUITest', '-ProfileHeaderMotion', variant, '-ProfileMotionAutoplay', '-ProfileMotionCapture']
        if role == 'member':
            command.append('-ProfileMotionMember')
        ready = container / 'Documents/profile-motion-ready'
        start = container / 'Documents/profile-motion-start'
        ready.unlink(missing_ok=True)
        start.unlink(missing_ok=True)
        sim(*command)
        deadline = time.monotonic() + 45
        while not ready.exists():
            if time.monotonic() > deadline:
                raise RuntimeError(f'Preview did not become ready: {stem}')
            time.sleep(0.2)
        time.sleep(0.8)
        record = subprocess.Popen(['xcrun', 'simctl', 'io', args.simulator, 'recordVideo', '--codec=h264', str(args.output / f'{stem}.mp4')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.3)
        start.touch()
        try:
            for delay, state in [(1.5, 'original'), (4.5, 'pinned'), (10, 'restored')]:
                time.sleep(delay)
                sim('io', args.simulator, 'screenshot', str(args.output / f'{stem}-{state}.png'))
            time.sleep(1)
        finally:
            record.send_signal(signal.SIGINT)
            record.wait(timeout=20)
        if record.returncode != 0:
            raise RuntimeError(f'Video capture failed: {stem}')
        print(f'Captured {stem}', flush=True)
