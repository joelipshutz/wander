#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo 'Usage: scripts/capture-app-store-screenshots.sh <output-directory> [registered-simulator-UDID]' >&2
  exit 2
fi
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT_DIRECTORY=$(mkdir -p "$1" && cd "$1" && pwd)
SIMULATOR_UDID=${2:-A5BCB583-A44D-4DD0-AE1E-083ED019279C}
BUILD_HELPER=${IOS_WORK_HELPER:-"$PROJECT_ROOT/../.tools/ios-work.py"}
[[ -f "$BUILD_HELPER" ]] || { echo 'Set IOS_WORK_HELPER to the workspace build coordinator.' >&2; exit 1; }
[[ ! -e "$OUTPUT_DIRECTORY/capture.xcresult" ]] || { echo 'Choose a new evidence directory; existing capture results are preserved.' >&2; exit 1; }
cd "$PROJECT_ROOT"
python3 "$BUILD_HELPER" build -- test \
  -project Wander.xcodeproj -scheme Wander \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -resultBundlePath "$OUTPUT_DIRECTORY/capture.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:WanderUITests/AppStoreScreenshotsUITests \
  -skip-testing:WanderUITests/AppStoreScreenshotsUITests/testAddOptionsRestoresCompactHeightAfterSeeMore
xcrun xcresulttool export attachments --path "$OUTPUT_DIRECTORY/capture.xcresult" \
  --output-path "$OUTPUT_DIRECTORY/attachments"
python3 - "$OUTPUT_DIRECTORY" <<'PY'
import json, pathlib, re, shutil, sys
root = pathlib.Path(sys.argv[1])
raw = root / 'raw'
raw.mkdir(exist_ok=True)
for test in json.loads((root / 'attachments/manifest.json').read_text()):
    for item in test['attachments']:
        name = item.get('suggestedHumanReadableName', '')
        if not name.startswith('recme-store-'):
            continue
        name = re.sub(r'_[0-9]+_[A-F0-9-]+(?=\.png$)', '', name)
        shutil.copyfile(root / 'attachments' / item['exportedFileName'], raw / name)
expected = {f'recme-store-{n}' for n in [
    '01-map-friends.png', '02-feed-places.png', '03-trusted-search.png',
    '04-place-detail.png', '05-add.png', '06-lists.png',
    '07-feed-moments.png', '08-conversation.png']}
missing = expected - {p.name for p in raw.iterdir()}
if missing:
    raise SystemExit(f'Missing captures: {sorted(missing)}')
PY
swift scripts/generate-astir-app-store-panels.swift "$OUTPUT_DIRECTORY/raw" "$OUTPUT_DIRECTORY/panels"
printf 'Dark-mode captures and candidate panels: %s\n' "$OUTPUT_DIRECTORY"
