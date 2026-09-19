"""Preserve the complete review locally, with exact media and source hashes.

No git add/commit/push, upload, cleanup, or build-cache copying occurs here.
APFS clones avoid allocating a second copy of several GiB of review media.
"""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--destination', type=Path, required=True)
args = parser.parse_args()
source, destination = args.source.resolve(), args.destination.resolve()
assert source != destination and source not in destination.parents
allowed = {'.html', '.md', '.json', '.jsonl', '.py', '.swift', '.js', '.css', '.txt', '.png', '.jpg', '.jpeg', '.svg', '.webp', '.mp4', '.mov', '.woff', '.woff2', '.ttf', '.otf'}
omit_directories = {'native-test-results', '__pycache__', 'node_modules', '.git', 'source-frames', 'native-device-review-attachments', 'cache-cleanup-2026-09-19', 'native-benefit-accessibility-attachments', 'native-final-login-attachments'}
libc = ctypes.CDLL(None, use_errno=True)
clone = getattr(libc, 'clonefile', None)
if clone:
    clone.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    clone.restype = ctypes.c_int

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(part)
    return h.hexdigest()

entries, excluded = [], []
for original in sorted(source.rglob('*')):
    if not original.is_file():
        continue
    rel = original.relative_to(source)
    if (original.is_symlink() or any(p.startswith('.') or p.endswith('.xcresult') or p in omit_directories for p in rel.parts)
        or original.suffix.lower() not in allowed
        or original.name.endswith('-picture.mp4')
        or any('tests-all' in p or 'tests-final' in p for p in rel.parts)):
        excluded.append(str(rel))
        continue
    target = destination / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    expected = digest(original)
    if target.exists():
        if digest(target) != expected:
            # This dedicated generated package is refreshed from its named source.
            target.unlink()
        else:
            entries.append({'path': str(rel), 'bytes': original.stat().st_size, 'sha256': expected})
            continue
    if not clone or clone(bytes(original), bytes(target), 0) != 0:
        shutil.copy2(original, target)
    assert digest(target) == expected, rel
    entries.append({'path': str(rel), 'bytes': original.stat().st_size, 'sha256': expected})

manifest = {'format': 1, 'status': 'release preparation; Joe selected full founders C and authorized main and TestFlight',
            'files': entries, 'excludedExecutionOutputs': excluded,
            'bytes': sum(e['bytes'] for e in entries),
            'largeMediaRequiringPublicationPackaging': [e['path'] for e in entries if e['bytes'] >= 100 * 1024**2]}
(destination.parent / 'review-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Preserved and verified {len(entries)} files ({manifest["bytes"] / 1024**3:.2f} GiB logical; APFS clones when supported).')
print(f'{len(manifest["largeMediaRequiringPublicationPackaging"])} files exceed ordinary GitHub file limits; package with LFS or reviewed media renditions before any commit/publication.')
