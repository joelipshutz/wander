#!/usr/bin/env python3
"""Run every parent test across bounded, non-overlapping CI jobs."""

import argparse
from collections import Counter
import json
from pathlib import Path
import plistlib
import re
import subprocess


# Display-link/CPU budgets need a fresh simulator process, not one that has
# already rendered dozens of unrelated MapKit, camera, and movie fixtures.
# These remain required tests with the same assertions and thresholds.
ISOLATED_UI_PERFORMANCE = {
    "WanderUITests/MapFilterInteractionUITests/testPerformanceFixtureMeasuresSelectedPinPanCPUAndAnnotationWork",
    "WanderUITests/MapFilterInteractionUITests/testPerformanceFixtureTracesDenseMapPanZoomAndBoundsAnnotationWork",
    "WanderUITests/OnboardingUITests/testCheckInCalendarTrayPresentationLatency",
}

# The original display-frame limit remains a required reference-machine check,
# alongside the CPU limits. Shared CI runs the identical dense-map workload and
# its bounded native annotation-work assertions through the companion case.
REFERENCE_UI_PERFORMANCE = {
    "WanderUITests/MapFilterInteractionUITests/testPerformanceFixtureTracesDenseMapPanZoomWithoutCondensedPins",
}

REPLAY_METHODS = {
    "replay-private": "WanderTests/ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage",
    "replay-credentials": "WanderTests/ReplayMaskingTests/testReadableContentAndCredentialMaskingInActualReplayImage",
}


def validate_replay_result(suite: str, summary: dict, tests: dict, device_id: str) -> None:
    """Require the named real-image proof once; warnings do not change its result."""
    if suite not in REPLAY_METHODS:
        raise ValueError("Unknown single-method Replay suite")
    expected = {"result": "Passed", "totalTestCount": 1, "passedTests": 1,
                "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
    if not isinstance(summary, dict) or any(summary.get(k) != v for k, v in expected.items()):
        raise ValueError("Required Replay method did not pass exactly once")
    configurations = summary.get("devicesAndConfigurations")
    if (not isinstance(configurations, list) or len(configurations) != 1
            or configurations[0].get("device", {}).get("deviceId") != device_id
            or configurations[0].get("device", {}).get("platform") != "iOS Simulator"):
        raise ValueError("Required Replay result has the wrong device")
    cases = []

    def visit(value):
        if isinstance(value, dict):
            if value.get("nodeType") == "Test Case":
                cases.append(value)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(tests)
    identifier = REPLAY_METHODS[suite]
    if (len(cases) != 1 or cases[0].get("result") != "Passed"
            or cases[0].get("nodeIdentifier", "").removesuffix("()") != identifier.split("/", 1)[1]
            or cases[0].get("nodeIdentifierURL") != "test://com.apple.xcode/Wander/" + identifier):
        raise ValueError("Required Replay case identity or outcome does not match")


def prepare_ui_performance_products(products: Path, preserve_system_failures: bool = False) -> int:
    """Avoid automatic video encoding; optionally retain failure diagnostics."""
    root = products.resolve()
    info = plistlib.loads((root / "Info.plist").read_bytes())
    documents = {}
    targets_changed = 0
    for entry in info["Tests"]:
        path = (root / entry["xctestrun"]).resolve()
        if not path.is_relative_to(root):
            raise ValueError("Test configuration must stay inside the products bundle")
        if path in documents:
            continue
        document = plistlib.loads(path.read_bytes())
        if "TestConfigurations" in document:
            targets = [target for configuration in document["TestConfigurations"]
                       for target in configuration["TestTargets"]]
        else:
            targets = [target for name, target in document.items()
                       if not name.startswith("__") and isinstance(target, dict)]
        for target in targets:
            if target.get("IsUITestBundle"):
                # These are Xcode's normal test-plan capture settings. Explicit
                # test attachments, assertions and test selection are unchanged.
                target["PreferredScreenCaptureFormat"] = "screenshots"
                target["SystemAttachmentLifetime"] = "deleteOnSuccess" if preserve_system_failures else "keepNever"
                targets_changed += 1
        documents[path] = document
    if not targets_changed:
        raise ValueError("No UI test target found in performance test products")
    for path, document in documents.items():
        path.write_bytes(plistlib.dumps(document))
    return targets_changed


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
    parser.add_argument("--suite", choices=["clip", "unit", "replay", *REPLAY_METHODS, "performance", "ui-performance", "ui-reference-performance", "ui", "graphics"], required=True)
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
                 ui_test_identifiers(root) if args.suite in {"ui", "ui-performance", "ui-reference-performance", "graphics"} else
                 [REPLAY_METHODS[args.suite]] if args.suite in REPLAY_METHODS else
                 [replay] if args.suite == "replay" else
                 performance if args.suite == "performance" else ["WanderTests"])
    isolated_ui = ISOLATED_UI_PERFORMANCE | REFERENCE_UI_PERFORMANCE
    if args.suite in {"ui", "ui-performance", "ui-reference-performance", "graphics"} and not isolated_ui.issubset(inventory):
        parser.error("isolated UI performance selection no longer matches the test inventory")
    if args.suite == "graphics":
        selected = sorted(isolated_ui | {
            "WanderUITests/EventsComingSoonUITests/testLightTabBarStaysLightAcrossEventsVisits",
            "WanderUITests/EventsComingSoonUITests/testDarkTabBarStaysDarkAcrossEventsVisits",
            "WanderUITests/EventsComingSoonUITests/testTabGlassSurvivesScrubbingAndLiveAppearanceChanges",
        })
        if not set(selected).issubset(inventory):
            parser.error("graphics diagnostic selection no longer matches the test inventory")
    elif args.suite == "ui-performance":
        selected = sorted(ISOLATED_UI_PERFORMANCE)
    elif args.suite == "ui-reference-performance":
        selected = sorted(REFERENCE_UI_PERFORMANCE)
    elif args.suite == "ui":
        # Preserve shard assignment/order for all remaining tests.
        selected = [test for test in inventory[args.shard::args.shard_count]
                    if test not in isolated_ui]
    else:
        selected = inventory
    # The SDK installs process-wide replay observers. CI runs each required
    # image proof in its own host, as Feed/Privacy do. The combined replay mode
    # remains available for local lifecycle diagnostics; isolation does not
    # establish the cause of a failed combined invocation.
    # Original CPU timing limits run separately with --suite performance on the
    # controlled reference simulator. Full-size deterministic contracts remain
    # in the unit suite, matching the main branch shared-runner policy.
    isolated = {replay: "replay", **{test: "performance" for test in performance}} if args.suite == "unit" else {}
    if args.suite == "ui":
        isolated = {**{test: "ui-performance" for test in sorted(ISOLATED_UI_PERFORMANCE)},
                    **{test: "ui-reference-performance" for test in sorted(REFERENCE_UI_PERFORMANCE)}}
    excluded = list(isolated)
    if not selected:
        parser.error("empty test selection")
    selection = {"suite": args.suite, "shard": args.shard, "totalUIInventory": len(inventory) if args.suite in {"ui", "ui-performance", "ui-reference-performance", "graphics"} else None,
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
        if args.suite in {"ui", "graphics", "ui-performance", "ui-reference-performance"}:
            count = prepare_ui_performance_products(
                Path(args.test_products), preserve_system_failures=args.suite in {"ui", "graphics"}
            )
            print(f"Using screenshots instead of automatic video for {count} UI target(s)", flush=True)
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
