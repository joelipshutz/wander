#!/usr/bin/env python3
"""Capture REC-680 review routes inside the real Wander app on a dedicated simulator."""
import argparse
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('device', help='Dedicated, already-booted simulator UUID')
p.add_argument('output', type=Path)
p.add_argument('--only', help='Comma-separated route names')
p.add_argument('--delay', type=float, default=6)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
routes = ['baselineMap', 'baselineEditor', 'quick', 'past', 'wanna', 'details',
          'options', 'wannaDetails', 'edit', 'invitation', 'saved', 'history', 'placeHistory', 'reminders']
if a.only:
    requested = a.only.split(',')
    if set(requested) - set(routes):
        p.error('Unknown route')
    routes = requested

def sim(*args):
    subprocess.run(['xcrun', 'simctl', *args], check=True, timeout=90,
                   stdout=subprocess.DEVNULL)

sim('status_bar', a.device, 'override', '--time', '9:41', '--dataNetwork',
    'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState',
    'charged', '--batteryLevel', '100')
sim('ui', a.device, 'appearance', 'light')
for route in routes:
    sim('launch', '--terminate-running-process', a.device, 'com.grayline.wander',
        '-WanderQuickCaptureReview', route, '-WanderAuthenticatedUITest',
        '-WanderUseDemoFixtures', '-WanderDisableWalkthroughs', '-WanderUnifiedLiveUITest')
    time.sleep(a.delay)
    sim('io', a.device, 'screenshot', str(a.output / (route + '.png')))
    print('Captured actual app: ' + route, flush=True)
