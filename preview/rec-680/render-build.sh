#!/bin/bash
set -euo pipefail
# Run from the repository root; supply a dedicated booted simulator UUID.
: "${1:?Usage: preview/rec-680/render-build.sh SIMULATOR_UUID DERIVED_DATA [PACKAGE_CACHE]}"
: "${2:?Provide an issue-specific DerivedData directory}"
xcodegen generate
build_args=(-quiet build -project Wander.xcodeproj -scheme Wander -configuration Debug
  -destination "platform=iOS Simulator,id=$1" -derivedDataPath "$2"
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -jobs 4)
if [[ -n "${3:-}" ]]; then
  build_args+=(-clonedSourcePackagesDirPath "$3" -disableAutomaticPackageResolution)
fi
xcodebuild "${build_args[@]}"
xcrun simctl install "$1" "$2/Build/Products/Debug-iphonesimulator/Wander.app"
