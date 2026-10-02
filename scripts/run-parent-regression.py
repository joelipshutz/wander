#!/usr/bin/env python3
"""Run every parent test across bounded, non-overlapping CI jobs."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess


# Display-link/CPU budgets need a fresh simulator process, not one that has
# already rendered dozens of unrelated MapKit, camera, and movie fixtures.
# These remain required tests with the same assertions and thresholds.
ISOLATED_UI_PERFORMANCE = {
    "WanderUITests/MapFilterInteractionUITests/testPerformanceFixtureMeasuresSelectedPinPanCPUAndAnnotationWork",
    "WanderUITests/MapFilterInteractionUITests/testPerformanceFixtureTracesDenseMapPanZoomWithoutCondensedPins",
}


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
    parser.add_argument("--suite", choices=["clip", "unit", "replay", "performance", "ui-performance", "ui", "graphics"], required=True)
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--shard-count", type=int, default=4)
    parser.add_argument("--destination")
    parser.add_argument("--derived-data")
    parser.add_argument("--test-products", help="Prepared .xctestproducts bundle; run without recompiling")
    parser.add_argument("--result-bundle")
    parser.add_argument("--selection-file")
    parser.add_argument("--list-only", action="store_true")
    args = parser.parse_args()
    if args.shard_count < 1 or not 0 <= args.shard < args.shard_count:
        parser.error("shard must be within shard-count")
    root = Path(__file__).resolve().parents[1]
    replay = "WanderTests/ReplayMaskingTests"
    performance = [
        "WanderTests/TrustedPlaceSearchTests/testSearchOneThousandMemoriesP95UnderFiftyMilliseconds",
        "WanderTests/WanderPlaceCategoryTests/testPerformanceFixtureExercisesARealisticHighDataAccountWithinBudget",
    ]
    inventory = (["AstirClipTests", "AstirClipUITests"] if args.suite == "clip" else
                 ui_test_identifiers(root) if args.suite in {"ui", "ui-performance", "graphics"} else
                 [replay] if args.suite == "replay" else
                 performance if args.suite == "performance" else ["WanderTests"])
    if args.suite in {"ui", "ui-performance", "graphics"} and not ISOLATED_UI_PERFORMANCE.issubset(inventory):
        parser.error("isolated UI performance selection no longer matches the test inventory")
    if args.suite == "graphics":
        selected = sorted(ISOLATED_UI_PERFORMANCE | {
            "WanderUITests/EventsComingSoonUITests/testLightTabBarStaysLightAcrossEventsVisits",
            "WanderUITests/EventsComingSoonUITests/testDarkTabBarStaysDarkAcrossEventsVisits",
            "WanderUITests/EventsComingSoonUITests/testTabGlassSurvivesScrubbingAndLiveAppearanceChanges",
        })
        if not set(selected).issubset(inventory):
            parser.error("graphics diagnostic selection no longer matches the test inventory")
    elif args.suite == "ui-performance":
        selected = sorted(ISOLATED_UI_PERFORMANCE)
    elif args.suite == "ui":
        # Preserve shard assignment/order for all remaining tests.
        selected = [test for test in inventory[args.shard::args.shard_count]
                    if test not in ISOLATED_UI_PERFORMANCE]
    else:
        selected = inventory
    # The SDK installs process-wide replay observers. Keep this required test in
    # its own test host, matching the independently passing Feed validation job.
    # Keep the unchanged search threshold required in a fresh process too,
    # rather than measuring after thousands of unrelated fixtures and SDKs.
    isolated = {replay: "replay", **{test: "performance" for test in performance}} if args.suite == "unit" else {}
    if args.suite == "ui":
        isolated = {test: "ui-performance" for test in sorted(ISOLATED_UI_PERFORMANCE)}
    excluded = list(isolated)
    if not selected:
        parser.error("empty test selection")
    selection = {"suite": args.suite, "shard": args.shard, "totalUIInventory": len(inventory) if args.suite in {"ui", "ui-performance", "graphics"} else None,
                 "identifiers": selected, "isolatedTestSuites": isolated}
    if args.selection_file:
        Path(args.selection_file).write_text(json.dumps(selection, indent=2) + "\n")
    if args.list_only:
        print(json.dumps(selection, indent=2))
        return 0
    if not all([args.destination, args.result_bundle]) or not (args.derived_data or args.test_products):
        parser.error("destination, result-bundle and either derived-data or test-products are required to run tests")
    if "WanderUITests/NativeOnboardingFlowUITests/testProfilePreviewUpdatesWithOptionalPhoto" in selected:
        # The real PhotoKit picker needs an actual library item on a fresh CI
        # simulator. Use the same public bundled artwork as the review fixture;
        # do not depend on photos left behind by another test or recording run.
        subprocess.run(["xcrun", "simctl", "bootstatus", args.destination, "-b"], check=True)
        photo = root / "Wander/Resources/Assets.xcassets/PlaceCarouselAvatars.imageset/place-carousel-avatars.png"
        subprocess.run(["xcrun", "simctl", "addmedia", args.destination, str(photo)], check=True)
    print(f"Running {args.suite} selection {args.shard + 1}: {len(selected)} identifiers", flush=True)
    if args.test_products:
        command = ["xcodebuild", "test-without-building", "-quiet", "-testProductsPath", args.test_products]
    else:
        scheme = "AstirClip" if args.suite == "clip" else "Wander"
        command = ["xcodebuild", "test", "-quiet", "-project", "Wander.xcodeproj", "-scheme", scheme,
                   "-derivedDataPath", args.derived_data,
                   "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "GENERATE_INFOPLIST_FILE=YES"]
    command += ["-destination", f"platform=iOS Simulator,id={args.destination}",
               "-jobs", "2", "-parallel-testing-enabled", "NO",
               "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "600",
               "-maximum-test-execution-time-allowance", "900", "-resultBundlePath", args.result_bundle]
    command.extend(f"-only-testing:{identifier}" for identifier in selected)
    command.extend(f"-skip-testing:{identifier}" for identifier in excluded)
    return subprocess.run(command, cwd=root, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
