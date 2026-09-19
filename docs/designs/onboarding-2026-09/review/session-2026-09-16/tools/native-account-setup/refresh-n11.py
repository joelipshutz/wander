"""Capture and refresh only N11 and its shared-header empty/error states."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
REPO = ROOT.parent.parent / 'wander-native-onboarding-review'
OUT = ROOT / 'native-captures/n11-headline-only'
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
manifest = json.loads((ROOT / 'native-dark-setup.json').read_text())
copy = json.loads((ROOT / 'native-copy.json').read_text())
archive = ROOT / 'archives/n11-before-headline-only-2026-09-18'
archive.mkdir(exist_ok=True)
for name in ['native-copy.json', 'native-dark-setup.json']:
    if not (archive / name).exists():
        shutil.copy2(ROOT / name, archive / name)
if not (ROOT / 'native-n11-headline-archive.html').exists():
    shutil.copy2(ROOT / 'index.html', ROOT / 'native-n11-headline-archive.html')
proof = {}
for screen, route in [('N11', 'friends'), ('N33', 'friends-empty'), ('N34', 'friends-failure')]:
    run('terminate', DEVICE, APP, check=False)
    run('launch', DEVICE, APP, '-WanderNativeOnboardingReview', route, '-WanderUseDemoFixtures')
    time.sleep(3)
    image = OUT / f'{screen}.png'
    run('io', DEVICE, 'screenshot', str(image))
    text = json.loads(subprocess.check_output(['/tmp/astir-native-ocr', str(image)], text=True))['text']
    normalized = ' '.join(text).lower()
    assert 'keep up with the people you love' in normalized, text
    assert 'life takes them' not in normalized and 'few familiar' not in normalized, text
    proof[screen] = text
    evidence = manifest['screens'][screen]
    evidence.update(image=str(image.relative_to(ROOT)), sha256=hashlib.sha256(image.read_bytes()).hexdigest(), sourceCommit=commit)
    card = next(c for c in copy['cards'] if c['id'] == screen)
    # Preserve existing line IDs and their saved review notes after removing .03.
    for index, line in enumerate(card['lines']):
        line.setdefault('lineNumber', index + 1)
        if line['role'] == 'Headline':
            line['text'] = 'Keep up with the people you love'
    card['lines'] = [line for line in card['lines'] if line['role'] != 'Body']
    card.update(image=evidence['image'], sourceCommit=commit, coverage='Actual native Swift · N11 headline-only revision · ' + commit[:7], captureNote='Actual Swift app · iPhone 16e · N11 headline-only revision · local review build.')
manifest['latestSourceCommit'] = commit
manifest['n11CopyRevision'] = {'sourceCommit': commit, 'screens': list(proof), 'headline': 'Keep up with the people you love', 'subtitle': None, 'ocr': proof}
(ROOT / 'native-dark-setup.json').write_text(json.dumps(manifest, indent=2) + '\n')
(ROOT / 'native-copy.json').write_text(json.dumps(copy, ensure_ascii=False, indent=2) + '\n')
(OUT / 'verification.json').write_text(json.dumps({'sourceCommit': commit, 'ocr': proof}, indent=2) + '\n')
subprocess.run(['python3', str(ROOT / 'build_native_review.py'), '--publish'], check=True)
run('shutdown', DEVICE)
print('N11, N33 and N34 captured, OCR-verified and published to the local board.', flush=True)
