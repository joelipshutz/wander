"""Verify T26's moving logo / still account UI using two native PNG captures."""
from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('--capture-folder', required=True)
parser.add_argument('--report', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
media = root / 'native-captures' / args.capture_folder
before = np.asarray(Image.open(media / 'film-type-dark-account.png').convert('RGB'))
after = np.asarray(Image.open(media / 'film-type-dark-account-after.png').convert('RGB'))
assert before.shape == after.shape
h, w, _ = before.shape
changed = np.any(before != after, axis=2)
logo = changed[int(h * .075):int(h * .195), int(w * .15):int(w * .85)]
heading = changed[int(h * .20):int(h * .26)]
still_ui = changed[int(h * .20):]
sample = before[int(h * .67), int(w * .13)].tolist()
report = {
    'dimensions': [w, h],
    'framesSeparatedSeconds': 1.25,
    'logoChangedPixels': int(logo.sum()),
    'headingChangedPixels': int(heading.sum()),
    'headingAndAllUIBelowChangedPixels': int(still_ui.sum()),
    'emailButtonRGB': sample,
    'regions': {'logo': 'x 15–85%, y 7.5–19.5%', 'heading': 'y 20–26%', 'stillUI': 'y 20–100%'},
}
(root / args.report).write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
assert report['logoChangedPixels'] > 100, 'Account artwork is not moving'
assert report['headingAndAllUIBelowChangedPixels'] == 0, 'Account heading or controls are moving'
assert sample == [240, 90, 60], 'Email CTA is not solid app Signal'
