#!/usr/bin/env python3
"""Run every parent test across bounded, non-overlapping CI jobs."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess


def ui_test_identifiers(root: Path) -> list[str]:
    identifiers = []
    for path in sorted((root / "WanderUITests").rglob("*.swift")):
        source = path.read_text()
        classes = list(re.finditer(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source))
        all_methods = re.findall(r"\bfunc\s+(test\w*)\s*\(", source)
        assigned = []
        for index, match in enumerate(classes):
            end = classes[index + 1].start() if index + 1 < len(classes) else len(source)
            methods = re.findall(r"\bfunc\s+(test\w*)\s*\(", source[match.end():end])
            assigned.extend(methods)
            identifiers.extend(f"WanderUITests/{match.group(1)}/{method}" for method in methods)
        if Counter(assigned) != Counter(all_methods):
            raise ValueError(f"Unassigned XCTest methods in {path.name}; update discovery before running")
        if re.search(r"@Test\b", source):
            raise ValueError(f"Swift Testing UI tests require explicit discovery support: {path.name}")
    if not identifiers or len(identifiers) != len(set(identifiers)):
        raise ValueError("UI test inventory must be nonempty and contain unique identifiers")
    return sorted(identifiers)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=["unit", "replay", "performance", "ui"], required=True)
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--shard-count", type=int, default=4)
    parser.add_argument("--destination")
    parser.add_argument("--derived-data")
    parser.add_argument("--result-bundle")
    parser.add_argument("--selection-file")
    parser.add_argument("--list-only", action="store_true")
    args = parser.parse_args()
    if args.shard_count < 1 or not 0 <= args.shard < args.shard_count:
        parser.error("shard must be within shard-count")
    root = Path(__file__).resolve().parents[1]
    replay = "WanderTests/ReplayMaskingTests"
    performance = "WanderTests/TrustedPlaceSearchTests/testSearchOneThousandMemoriesP95UnderFiftyMilliseconds"
    inventory = (ui_test_identifiers(root) if args.suite == "ui" else
                 [replay] if args.suite == "replay" else
                 [performance] if args.suite == "performance" else ["WanderTests"])
    selected = inventory[args.shard::args.shard_count] if args.suite == "ui" else inventory
    # The SDK installs process-wide replay observers. Keep this required test in
    # its own test host, matching the independently passing Feed validation job.
    # Keep the unchanged search threshold required in a fresh process too,
    # rather than measuring after thousands of unrelated fixtures and SDKs.
    isolated = {replay: "replay", performance: "performance"} if args.suite == "unit" else {}
    excluded = list(isolated)
    if not selected:
        parser.error("empty test selection")
    selection = {"suite": args.suite, "shard": args.shard, "totalUIInventory": len(inventory) if args.suite == "ui" else None,
                 "identifiers": selected, "isolatedTestSuites": isolated}
    if args.selection_file:
        Path(args.selection_file).write_text(json.dumps(selection, indent=2) + "\n")
    if args.list_only:
        print(json.dumps(selection, indent=2))
        return 0
    if not all([args.destination, args.derived_data, args.result_bundle]):
        parser.error("destination, derived-data and result-bundle are required to run tests")
    if "WanderUITests/NativeOnboardingFlowUITests/testProfilePreviewUpdatesWithOptionalPhoto" in selected:
        # The real PhotoKit picker needs an actual library item on a fresh CI
        # simulator. Use the same public bundled artwork as the review fixture;
        # do not depend on photos left behind by another test or recording run.
        subprocess.run(["xcrun", "simctl", "bootstatus", args.destination, "-b"], check=True)
        photo = root / "Wander/Resources/Assets.xcassets/PlaceCarouselAvatars.imageset/place-carousel-avatars.png"
        subprocess.run(["xcrun", "simctl", "addmedia", args.destination, str(photo)], check=True)
    print(f"Running {args.suite} selection {args.shard + 1}: {len(selected)} identifiers", flush=True)
    command = ["xcodebuild", "test", "-quiet", "-project", "Wander.xcodeproj", "-scheme", "Wander",
               "-destination", f"platform=iOS Simulator,id={args.destination}",
               "-derivedDataPath", args.derived_data, "-jobs", "2", "-parallel-testing-enabled", "NO",
               "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "600",
               "-maximum-test-execution-time-allowance", "900", "-resultBundlePath", args.result_bundle,
               "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "GENERATE_INFOPLIST_FILE=YES"]
    command.extend(f"-only-testing:{identifier}" for identifier in selected)
    command.extend(f"-skip-testing:{identifier}" for identifier in excluded)
    return subprocess.run(command, cwd=root, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
