#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_VOLUME="/System/Volumes/Data"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedData"
DESTINATION="${RECME_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6}"
MIN_FREE_GIB="${RECME_MIN_FREE_GIB:-20}"
MAX_USAGE_PERCENT="${RECME_MAX_DISK_USAGE_PERCENT:-90}"
JOBS="${RECME_TEST_JOBS:-1}"
PREFLIGHT_ONLY=0
VERBOSE=0
ONLY_TESTING=()
EXTRA_ARGS=()
ONLY_TESTING_COUNT=0
EXTRA_ARGS_COUNT=0

usage() {
  cat <<'EOF'
Usage: scripts/run-ios-tests.sh [options] [-- <extra xcodebuild arguments>]

Options:
  --only-testing <target/test>  Run one test target, case, or method. Repeatable.
  --preflight                   Check disk capacity and exit without testing.
  --verbose                     Show normal xcodebuild output instead of quiet mode.
  -h, --help                    Show this help.

Environment:
  RECME_TEST_DESTINATION         Override the simulator destination.
  RECME_MIN_FREE_GIB             Minimum free space required (default: 20).
  RECME_MAX_DISK_USAGE_PERCENT   Maximum allowed Data-volume usage (default: 90).
  RECME_TEST_JOBS                xcodebuild job count (default: 1).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only-testing)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --only-testing requires a value" >&2
        exit 2
      fi
      ONLY_TESTING+=("$2")
      ONLY_TESTING_COUNT=$((ONLY_TESTING_COUNT + 1))
      shift 2
      ;;
    --preflight)
      PREFLIGHT_ONLY=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      EXTRA_ARGS_COUNT=$#
      break
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$MIN_FREE_GIB" =~ ^[0-9]+$ || ! "$MAX_USAGE_PERCENT" =~ ^[0-9]+$ || ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: disk thresholds must be non-negative integers and RECME_TEST_JOBS must be positive" >&2
  exit 2
fi

if (( EXTRA_ARGS_COUNT > 0 )); then
  for arg in "${EXTRA_ARGS[@]}"; do
    case "$arg" in
      -derivedDataPath|-derivedDataPath=*|-destination|-destination=*|-project|-project=*|-scheme|-scheme=*)
        echo "error: $arg is managed by this script" >&2
        exit 2
        ;;
    esac
  done
fi

read -r _ _ _ available_kib capacity _ < <(df -Pk "$DATA_VOLUME" | tail -n 1)
usage_percent="${capacity%%%}"
minimum_kib=$((MIN_FREE_GIB * 1024 * 1024))
available_gib="$(awk -v kib="$available_kib" 'BEGIN { printf "%.1f", kib / 1024 / 1024 }')"
derived_data_mib=0

if [[ -d "$DERIVED_DATA_PATH" ]]; then
  derived_data_kib="$(du -sk "$DERIVED_DATA_PATH" | awk '{print $1}')"
  derived_data_mib=$((derived_data_kib / 1024))
fi

echo "disk: ${available_gib} GiB free, ${usage_percent}% used; DerivedData: ${derived_data_mib} MiB"

if (( available_kib < minimum_kib || usage_percent > MAX_USAGE_PERCENT )); then
  echo "blocked: testing requires at least ${MIN_FREE_GIB} GiB free and at most ${MAX_USAGE_PERCENT}% Data-volume usage" >&2
  echo "clean verified generated artifacts or ask Joe before changing the guard" >&2
  exit 75
fi

if (( PREFLIGHT_ONLY == 1 )); then
  exit 0
fi

XCODEBUILD_ARGS=(
  test
  -project "$ROOT_DIR/Wander.xcodeproj"
  -scheme Wander
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED=NO
  -jobs "$JOBS"
)

if (( VERBOSE == 0 )); then
  XCODEBUILD_ARGS+=(-quiet)
fi

if (( ONLY_TESTING_COUNT > 0 )); then
  for test_identifier in "${ONLY_TESTING[@]}"; do
    XCODEBUILD_ARGS+=("-only-testing:$test_identifier")
  done
fi

if (( EXTRA_ARGS_COUNT > 0 )); then
  XCODEBUILD_ARGS+=("${EXTRA_ARGS[@]}")
fi

exec xcodebuild "${XCODEBUILD_ARGS[@]}"
