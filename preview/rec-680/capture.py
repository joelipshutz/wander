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
p.add_argument('--delay', type=float, default=30, help='Seconds to settle each native state')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)

def sim(*args):
    subprocess.run(['xcrun', 'simctl', *args], check=True, timeout=90,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

sim('status_bar', a.device, 'override', '--time', '9:41', '--dataNetwork',
    'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState',
    'charged', '--batteryLevel', '100')
screens = ['quick', 'details', 'later', 'saved', 'edit', 'rated', 'options',
           'invitation', 'profile', 'history', 'place', 'visits', 'visit', 'updated',
           'reminders', 'notification', 'push-edit', 'wanna', 'wanna-saved',
           'wannas', 'wanna-detail', 'wanna-edit']
cases = [(screen, []) for screen in screens]
cases += [('invitation-dark', ['--dark']), ('history-dark', ['--dark']),
          ('edit-large-text', ['--large-text'])]
if a.compact:
    cases = [('invitation', []), ('history', []), ('edit', []),
             ('reminders', []), ('edit-large-text', ['--large-text'])]
if a.only:
    requested = set(a.only.split(','))
    unknown = requested - {name for name, _ in cases}
    if unknown:
        p.error('Unknown capture states: ' + ', '.join(sorted(unknown)))
    cases = [case for case in cases if case[0] in requested]
for name, flags in cases:
    screen = name.removesuffix('-dark').removesuffix('-large-text')
    sim('ui', a.device, 'appearance', 'dark' if '--dark' in flags else 'light')
    sim('launch', '--terminate-running-process', a.device,
        'com.astir.preview.quickcapture', '--screen', screen, *flags)
    time.sleep(a.delay)
    sim('io', a.device, 'screenshot', str(a.output / (name + '.png')))
    print('Captured ' + name, flush=True)
