#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: scripts/capture-app-store-screenshots.sh <output-directory> [simulator-name] [os-version]" >&2
  exit 2
fi

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT_DIRECTORY=$1
SIMULATOR_NAME=${2:-"iPhone 16 Plus"}
OS_VERSION=${3:-"18.6"}

for command_name in xcodegen xcodebuild xcrun jq swift; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

CAPTURE_ROOT=$(mktemp -d /tmp/recme-app-store-capture.XXXXXX)
DERIVED_DATA=${RECME_CAPTURE_DERIVED_DATA:-"$CAPTURE_ROOT/DerivedData"}
RESULT_BUNDLE="$CAPTURE_ROOT/AppStoreScreenshots.xcresult"
ATTACHMENTS="$CAPTURE_ROOT/attachments"
RAW_SCREENSHOTS="$CAPTURE_ROOT/raw"

cleanup() {
  rm -rf "$CAPTURE_ROOT"
}
trap cleanup EXIT

mkdir -p "$ATTACHMENTS" "$RAW_SCREENSHOTS" "$OUTPUT_DIRECTORY" "$DERIVED_DATA"

cd "$PROJECT_ROOT"
xcodegen generate
xcodebuild test \
  -project Wander.xcodeproj \
  -scheme Wander \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME,OS=$OS_VERSION" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO \
  -jobs 1 \
  -only-testing:WanderUITests/AppStoreScreenshotsUITests

xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$ATTACHMENTS" >/dev/null

while IFS=$'\t' read -r exported_name suggested_name; do
  output_name=$(printf '%s' "$suggested_name" | sed -E 's/_[0-9]+_[A-F0-9-]+(\.png)$/\1/')
  cp "$ATTACHMENTS/$exported_name" "$RAW_SCREENSHOTS/$output_name"
done < <(
  jq -r '
    .[]
    | .attachments[]
    | select(.suggestedHumanReadableName | startswith("recme-store-"))
    | [.exportedFileName, .suggestedHumanReadableName]
    | @tsv
  ' "$ATTACHMENTS/manifest.json"
)

CAPTURE_COUNT=$(find "$RAW_SCREENSHOTS" -maxdepth 1 -type f -name 'recme-store-*.png' | wc -l | tr -d ' ')
if [[ "$CAPTURE_COUNT" != "6" ]]; then
  echo "Expected 6 storefront screenshots, found $CAPTURE_COUNT" >&2
  exit 1
fi

swift scripts/generate-app-store-concepts.swift "$RAW_SCREENSHOTS" "$OUTPUT_DIRECTORY"
cp "$RAW_SCREENSHOTS"/recme-store-*.png "$OUTPUT_DIRECTORY"/

echo "Captured 6 public-safe storefront screens on $SIMULATOR_NAME / iOS $OS_VERSION"
echo "Output: $OUTPUT_DIRECTORY"
