"""Compatibility launcher for the shared historical onboarding review."""
import argparse
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--verify', action='store_true')
parser.add_argument('--prepare', action='store_true')
parser.add_argument('--download', action='store_true')
parser.add_argument('--port', type=int, default=8776)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[3]
command = 'prepare' if args.prepare else 'verify' if args.verify else 'serve'
options = [sys.executable, str(repo / 'scripts/review-media.py'), command,
           'onboarding-2026-09', '--port', str(args.port)]
if args.download:
    options.append('--download')
raise SystemExit(subprocess.call(options))
