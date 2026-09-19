"""Verify or serve the self-contained onboarding review. Python standard library."""
import argparse
import functools
import hashlib
from http.server import ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--verify', action='store_true')
parser.add_argument('--port', type=int, default=8776)
args = parser.parse_args()
if args.verify:
    manifest = json.loads((root / 'review-manifest.json').read_text())
    failures = []
    for item in manifest['files']:
        path = root / 'review' / item['path']
        if not path.is_file() or path.stat().st_size != item['bytes']:
            failures.append(item['path'])
            continue
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        if digest.hexdigest() != item['sha256']:
            failures.append(item['path'])
    if failures:
        raise SystemExit('Missing/changed archive files:\n' + '\n'.join(failures))
    print(f'Verified {len(manifest["files"])} exact review files.')
else:
    spec = importlib.util.spec_from_file_location('review_server', root / 'review/serve_review.py')
    server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server)
    handler = functools.partial(server.ReviewHandler, directory=str(root / 'review'))
    print(f'Open http://127.0.0.1:{args.port}/session-2026-09-16/founders-video-review.html', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), handler).serve_forever()
