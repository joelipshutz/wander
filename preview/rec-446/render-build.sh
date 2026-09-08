#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${1:-/private/tmp/rec446-native}"
APP_DIR="$BUILD_DIR/CompactAddPreview.app"
mkdir -p "$APP_DIR"
xcrun swiftc -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios17.0-simulator -parse-as-library \
  "$SOURCE_DIR/CompactAddPreview.swift" -o "$APP_DIR/CompactAddPreview"
python3 - "$APP_DIR" <<'PY'
import plistlib, sys
from pathlib import Path
plistlib.dump({'CFBundleIdentifier':'com.recme.preview.compactadd','CFBundleName':'CompactAddPreview','CFBundleExecutable':'CompactAddPreview','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'17.0','UIDeviceFamily':[1],'UILaunchScreen':{},'UIUserInterfaceStyle':'Dark'},open(Path(sys.argv[1])/'Info.plist','wb'))
PY
