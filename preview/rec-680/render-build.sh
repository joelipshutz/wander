#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${1:?Pass an output directory outside the source tree}"
APP_DIR="$BUILD_DIR/QuickCapturePreview.app"
mkdir -p "$APP_DIR" "$BUILD_DIR/module-cache"
xcrun swiftc -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios17.0-simulator -parse-as-library \
  -module-cache-path "$BUILD_DIR/module-cache" \
  "$SOURCE_DIR/QuickCapturePreview.swift" -o "$APP_DIR/QuickCapturePreview"
python3 - "$APP_DIR" <<'PY'
import plistlib, sys
from pathlib import Path
with (Path(sys.argv[1])/'Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier':'com.astir.preview.quickcapture',
      'CFBundleName':'Quick Capture Preview','CFBundleExecutable':'QuickCapturePreview',
      'CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0',
      'MinimumOSVersion':'17.0','UIDeviceFamily':[1],'UILaunchScreen':{}}, f)
PY
codesign --force --sign - "$APP_DIR"
