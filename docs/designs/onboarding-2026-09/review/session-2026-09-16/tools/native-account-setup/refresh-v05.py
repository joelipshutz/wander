"""Refresh the V05/N12 native notification examples without changing other cards."""
from pathlib import Path
import hashlib
import json
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
REPO = ROOT.parent.parent / 'wander-native-onboarding-review'
OUT = ROOT / 'native-captures/v05-instagram'
DEVICE = '6CB5D49F-FA87-4D3E-9C2E-F9A1296F257C'
APP = 'com.grayline.wander'
OUT.mkdir(exist_ok=True)
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()

def run(*args, check=True):
    return subprocess.run(['xcrun', 'simctl', *args], check=check, capture_output=True, text=True)

run('boot', DEVICE, check=False)
run('bootstatus', DEVICE, '-b')
run('install', DEVICE, str(ROOT.parent.parent / '.dev-cache/xcode/b9bf1d4adbbf761764b5/Build/Products/Debug-iphonesimulator/Wander.app'))
run('status_bar', DEVICE, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100')
run('ui', DEVICE, 'appearance', 'dark')
run('terminate', DEVICE, APP, check=False)
run('launch', DEVICE, APP, '-WanderNativeOnboardingReview', 'notifications', '-WanderUseDemoFixtures', '-WanderAuthenticatedUITest', '-WanderBypassProductUpsellFrequencyCap')
denied_image = OUT / 'N32.png'
if not denied_image.exists():
    time.sleep(3)
    run('io', DEVICE, 'screenshot', str(denied_image))
denied_text = json.loads(subprocess.check_output(['/tmp/astir-native-ocr', str(denied_image)], text=True))['text']
assert 'open settings' in ' '.join(denied_text).lower(), 'Run the notification denial UI test before this capture.'
# This simulator installation is the task-owned, fictional native review app.
# Notifications has no reset API. Preserve the real denied capture, then reset
# only this review installation to capture the separate first-request state.
run('uninstall', DEVICE, APP)
run('install', DEVICE, str(ROOT.parent.parent / '.dev-cache/xcode/b9bf1d4adbbf761764b5/Build/Products/Debug-iphonesimulator/Wander.app'))
run('launch', DEVICE, APP, '-WanderNativeOnboardingReview', 'notifications', '-WanderUseDemoFixtures', '-WanderAuthenticatedUITest', '-WanderBypassProductUpsellFrequencyCap')
movie = OUT / 'N12.mp4'
recorder = subprocess.Popen(['xcrun', 'simctl', 'io', DEVICE, 'recordVideo', '--codec=h264', '--force', str(movie)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
try:
    time.sleep(7)
    image = OUT / 'N12.png'
    run('io', DEVICE, 'screenshot', str(image))
finally:
    recorder.send_signal(signal.SIGINT)
    recorder.communicate(timeout=20)
text = json.loads(subprocess.check_output(['/tmp/astir-native-ocr', str(image)], text=True))['text']
assert 'your instagram import is ready' in ' '.join(text).lower(), text
assert 'continue' in [line.lower() for line in text] and 'open settings' not in ' '.join(text).lower(), text
manifest = json.loads((ROOT / 'native-dark-setup.json').read_text())
copy = json.loads((ROOT / 'native-copy.json').read_text())
archive = ROOT / 'archives/v05-before-instagram-2026-09-18'
archive.mkdir(exist_ok=True)
for name in ['native-copy.json', 'native-dark-setup.json']:
    if not (archive / name).exists():
        shutil.copy2(ROOT / name, archive / name)
if not (ROOT / 'native-v05-notification-archive.html').exists():
    shutil.copy2(ROOT / 'index.html', ROOT / 'native-v05-notification-archive.html')
for screen in ['N12', 'N32']:
    screen_image = image if screen == 'N12' else denied_image
    evidence = manifest['screens'][screen]
    evidence.update(image=str(screen_image.relative_to(ROOT)), sha256=hashlib.sha256(screen_image.read_bytes()).hexdigest(), sourceCommit=commit)
    if screen == 'N12':
        evidence.update(video=str(movie.relative_to(ROOT)), videoSha256=hashlib.sha256(movie.read_bytes()).hexdigest())
    card = next(c for c in copy['cards'] if c['id'] == screen)
    for line in card['lines']:
        if line['text'] == 'Your import is ready':
            line['text'] = 'Your Instagram import is ready'
    card.update(image=evidence['image'], sourceCommit=commit, coverage='Actual native Swift · Instagram notification + centered icons · ' + commit[:7], captureNote='Actual Swift app · iPhone 16e · revised Instagram notification and centered app icons · local review build.')
    if screen == 'N12':
        card['motionVideo'] = evidence['video']
manifest['latestSourceCommit'] = commit
manifest['v05Revision'] = {'sourceCommit': commit, 'title': 'Your Instagram import is ready', 'iconAlignment': 'vertical center of each card text column', 'ocr': text}
(ROOT / 'native-dark-setup.json').write_text(json.dumps(manifest, indent=2) + '\n')
(ROOT / 'native-copy.json').write_text(json.dumps(copy, ensure_ascii=False, indent=2) + '\n')
(OUT / 'verification.json').write_text(json.dumps({'sourceCommit': commit, 'N12ocr': text, 'N32ocr': denied_text}, indent=2) + '\n')
subprocess.run(['python3', str(ROOT / 'build_native_review.py'), '--publish'], check=True)
run('shutdown', DEVICE)
print('V05 movie and N12/N32 stills refreshed from actual Swift.', flush=True)
