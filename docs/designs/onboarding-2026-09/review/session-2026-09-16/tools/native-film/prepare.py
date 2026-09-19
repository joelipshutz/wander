"""Extract full native review frames; never redraw onboarding in the browser."""
from pathlib import Path
import hashlib
import argparse
import json
import subprocess
from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument('--output', default='film-exploration')
parser.add_argument('--keep-approved', action='store_true')
parser.add_argument('--manifest', default='native-film-comparison.json')
parser.add_argument('--find-account', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
media = root / 'native-captures' / args.output
source = root.parent.parent / 'wander-native-onboarding-review'
checks = json.loads((media / 'capture-checks.json').read_text())
meta = {
    'sourceCommit': subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip(),
    'native': True,
    'newHiggsfieldGenerations': 0,
    'textureSource': 'Original unlettered Coming Soon / Ocean Park Higgsfield texture',
    'device': 'iPhone 16e, iOS 26.3.1',
    'takes': {},
}
if args.keep_approved:
    original = json.loads((root / 'native-film-comparison.json').read_text())
    for key, take in original['takes'].items():
        if key.startswith('approved-'):
            meta['takes'][key] = {**take, 'sourceCommit': take.get('sourceCommit', original['sourceCommit'])}

def frame(raw, seconds, path):
    subprocess.run(['/tmp/astir-native-video', 'frame', str(raw), str(seconds), str(path)], check=True, stdout=subprocess.DEVNULL)

for check in checks:
    assert check['accountConfirmed']
    name = check['id']
    raw = media / f'{name}.mp4'
    duration = float(subprocess.check_output(['/tmp/astir-native-video', 'inspect', str(raw)], text=True).strip().split('=')[-1])
    onset = None
    continuous = []
    scratch = Path('/tmp/onboarding-film-onset.png')
    for quarter in range(65):
        seconds = quarter / 4
        frame(raw, seconds, scratch)
        with Image.open(scratch) as image:
            r, g, b = image.convert('RGB').getpixel((int(image.width * .25), int(image.height * .86)))
        if r > 135 and 25 < g < 155 and b < 130 and r - g > 35:
            continuous.append(seconds)
        else:
            continuous = []
        if len(continuous) == 2:
            onset = continuous[0]
            break
    if onset is None:
        raise RuntimeError('No stable native opening found: ' + name)
    phases = {'community': 2.0, 'tracking': 1.57, 'wordChange': 2.95, 'placesWord': 8.4,
              'localExperiment': 15.8, 'sceneChange': 17.5, 'places': 22.5,
              'peopleChange': 26.3, 'people': 31.5}
    proof = {}
    shots = []
    for key, seconds in phases.items():
        path = media / f'{name}-{key}.png'
        frame(raw, onset + seconds, path)
        proof[key] = json.loads(subprocess.check_output(['/tmp/astir-native-ocr', str(path)], text=True))['text']
        picture = Image.open(path).convert('RGB')
        picture.thumbnail((218, 472))
        shots.append((key, picture))
    frame(raw, onset + phases['community'], raw.with_suffix('.png'))
    account = Image.open(media / f'{name}-account.png').convert('RGB')
    account.thumbnail((218, 472))
    shots.append(('account', account))
    sheet = Image.new('RGB', (218 * 5, 505 * 2), '#202522')
    draw = ImageDraw.Draw(sheet)
    for index, (label, picture) in enumerate(shots):
        x, y = (index % 5) * 218, (index // 5) * 505
        sheet.paste(picture, (x, y + 27))
        draw.text((x + 6, y + 6), label, fill='white')
    sheet.save(root / f'native-board-qa/{name}-{args.output}-states.jpg', quality=92)
    account_start = None
    if args.find_account:
        # Find the settled, readable native account screen rather than guessing
        # its timestamp from the final hold or an earlier version's pacing.
        for second in range(int(onset + 32), int(duration - 2)):
            frame(raw, second, scratch)
            text = json.loads(subprocess.check_output(['/tmp/astir-native-ocr', str(scratch)], text=True)).get('text', [])
            if 'create your account' in ' '.join(text).lower() and 'continue with email' in ' '.join(text).lower():
                account_start = second + 1.5
                break
        if account_start is None:
            raise RuntimeError('No settled account timestamp found: ' + name)
    meta['takes'][name] = {
        'file': str(raw.relative_to(root)), 'poster': str(raw.with_suffix('.png').relative_to(root)),
        'startSeconds': onset, 'durationSeconds': duration, 'accountConfirmed': True,
        'sha256': hashlib.sha256(raw.read_bytes()).hexdigest(),
        'sourceCommit': meta['sourceCommit'],
        'phaseSeconds': phases, 'phaseTextProof': proof,
        **({'accountStartSeconds': account_start} if account_start is not None else {}),
    }
    print(name, 'start', onset, 'duration', duration, flush=True)
(root / args.manifest).write_text(json.dumps(meta, indent=2) + '\n')
