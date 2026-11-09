#!/usr/bin/env python3
"""Capture a booted, dedicated simulator; no production accounts are used."""
import argparse
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('device')
p.add_argument('output', type=Path)
p.add_argument('--compact', action='store_true')
p.add_argument('--only', help='Comma-separated capture state names')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)

def sim(*args):
    subprocess.run(['xcrun', 'simctl', *args], check=True, timeout=90,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

sim('status_bar', a.device, 'override', '--time', '9:41', '--dataNetwork',
    'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState',
    'charged', '--batteryLevel', '100')
cases = [('quick', []), ('details', []), ('later', []), ('wanna', []),
         ('saved', []), ('edit', []), ('quick-dark', ['--dark']),
         ('quick-large-text', ['--large-text'])]
if a.compact:
    cases = [('quick', []), ('details', []), ('quick-large-text', ['--large-text'])]
if a.only:
    cases = [case for case in cases if case[0] in a.only.split(',')]
for name, flags in cases:
    screen = 'quick' if name.startswith('quick-') else name
    sim('launch', '--terminate-running-process', a.device,
        'com.astir.preview.quickcapture', '--screen', screen, *flags)
    time.sleep(30)
    sim('io', a.device, 'screenshot', str(a.output / (name + '.png')))
    print('Captured ' + name, flush=True)
