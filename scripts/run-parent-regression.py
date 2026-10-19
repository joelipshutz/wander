#!/usr/bin/env python3
"""Run every parent test across bounded, non-overlapping CI jobs."""

import argparse
from collections import Counter
from contextlib import contextmanager
import copy
import hashlib
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

# This wall-clock UI budget includes XCTest capture work. Keep the existing
# screen-recording mode used by its reference run, isolated from screenshot jobs.
ISOLATED_UI_WARM_PERFORMANCE = {
    "WanderUITests/MapFilterInteractionUITests/testPerformanceFixtureKeepsWarmSourceSwitchesResponsive",
}

# The original display-frame limit remains a required reference-machine check,
# alongside the CPU limits. Shared CI runs the identical dense-map workload and
# its bounded native annotation-work assertions through the companion case.
REFERENCE_UI_PERFORMANCE = {
    "WanderUITests/MapFilterInteractionUITests/testPerformanceFixtureTracesDenseMapPanZoomWithoutCondensedPins",
}

UI_RECOVERY_METHODS = {
    "ui-profile-share-recovery": "WanderUITests/ProfileResponsivenessUITests/testProfileSharePresentsAndCancelsOnColdAndWarmEntry",
    "ui-snapshot-recovery": "WanderUITests/YourMapPrototypeUITests/testSnapshotCreatesListAndOpensEditorWithoutDuplicatePlaceControls",
}

REPLAY_METHODS = {
    "replay-private": "WanderTests/ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage",
    "replay-credentials": "WanderTests/ReplayMaskingTests/testReadableContentAndCredentialMaskingInActualReplayImage",
}


@contextmanager
def replay_fixture_host(products: Path):
    """Change only the generated unit-host arguments, then restore exact bytes."""
    root = products.resolve()
    if products.is_symlink() or not root.is_dir():
        raise ValueError("Replay products must be a regular owned directory")
    info = root / "Info.plist"
    if not info.is_file() or info.is_symlink():
        raise ValueError("Replay product Info is missing")
    originals, documents, targets = {}, {}, []
    for entry in plistlib.loads(info.read_bytes())["Tests"]:
        generated_path = root / entry["xctestrun"]
        if generated_path.is_symlink():
            raise ValueError("Replay configuration must be a regular file")
        path = generated_path.resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError("Replay configuration must stay inside products")
        if path in documents:
            continue
        originals[path] = path.read_bytes()
        document = plistlib.loads(originals[path])
        documents[path] = document
        configurations = document.get("TestConfigurations")
        candidates = ([target for configuration in configurations for target in configuration["TestTargets"]]
                      if configurations is not None else
                      [target for name, target in document.items() if not name.startswith("__") and isinstance(target, dict)])
        targets.extend((path, target) for target in candidates if target.get("BlueprintName") == "WanderTests"
                       and not target.get("IsUITestBundle", False))
    if len(targets) != 1:
        raise ValueError("Exactly one WanderTests host target is required")
    path, target = targets[0]
    arguments = target.get("CommandLineArguments", [])
    flag = "-WanderReplayFixtureHost"
    if (not isinstance(arguments, list) or not all(isinstance(x, str) for x in arguments)
            or any(x == flag or x.startswith(flag + "=") for x in arguments)):
        raise ValueError("Conflicting Replay host arguments")
    original_had_arguments = "CommandLineArguments" in target
    before = copy.deepcopy(documents)
    target["CommandLineArguments"] = [*arguments, flag, "inert"]
    effective = copy.deepcopy(documents)
    # Compare against the untouched originals through an explicit one-key delta.
    def strip_argument_delta(value):
        result = copy.deepcopy(value)
        for document in result.values():
            configs = document.get("TestConfigurations")
            rows = ([t for c in configs for t in c["TestTargets"]] if configs is not None else
                    [t for n, t in document.items() if not n.startswith("__") and isinstance(t, dict)])
            for row in rows:
                if row.get("BlueprintName") == "WanderTests" and not row.get("IsUITestBundle", False):
                    if original_had_arguments:
                        row["CommandLineArguments"] = list(arguments)
                    else:
                        row.pop("CommandLineArguments", None)
        return result
    # Preserve presence versus absence of the original key as well as its values.
    if strip_argument_delta(effective) != before:
        raise ValueError("Replay preparation changed unrelated configuration")
    record = {"target": "WanderTests", "appendedArguments": [flag, "inert"],
              "allOtherValuesUnchanged": True, "restored": False,
              "beforeSHA256": {str(p.relative_to(root)): hashlib.sha256(raw).hexdigest() for p, raw in originals.items()}}
    try:
        for p, document in effective.items():
            p.write_bytes(plistlib.dumps(document))
        if any(plistlib.loads(p.read_bytes()) != document for p, document in effective.items()):
            raise ValueError("Replay effective configuration differs")
        record["effectiveSHA256"] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in originals}
        yield record
        if any(plistlib.loads(p.read_bytes()) != document for p, document in effective.items()):
            raise ValueError("Replay configuration changed during native invocation")
        record["effectiveConfigurationStillMatchedAfterNative"] = True
    finally:
        for p, raw in originals.items():
            p.write_bytes(raw)
        record["restored"] = all(p.read_bytes() == raw for p, raw in originals.items())
        record["restoredSHA256"] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in originals}
        if not record["restored"]:
            raise ValueError("Replay configuration restoration failed")


def validate_replay_host_admission(value: dict) -> None:
    keys = {"schema", "requested", "mode", "expected_host", "inert_root_mounted",
            "ordinary_root_mounted", "admitted", "elapsed_ms", "limit_ms"}
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError("Replay admission schema mismatch")
    if (type(value["schema"]) is not int or value["schema"] != 1 or value["mode"] != "inert"
            or any(value[k] is not True for k in ["requested", "expected_host", "inert_root_mounted", "admitted"])
            or value["ordinary_root_mounted"] is not False or type(value["limit_ms"]) is not int
            or value["limit_ms"] != 10000 or type(value["elapsed_ms"]) is not int
            or not 0 <= value["elapsed_ms"] < 10000):
        raise ValueError("Required exclusive inert Replay host was not admitted")


def run_isolated_replay(*, suite: str, products: Path, device_id: str,
                        result_bundle: Path, command: list[str], receipt: Path) -> int:
    """Run one exact method and require its actual mount evidence after restoration."""
    if suite not in REPLAY_METHODS:
        raise ValueError("Inert host is restricted to the two exact Replay methods")
    def option(name):
        if command.count(name) != 1 or command.index(name) + 1 >= len(command):
            raise ValueError("Replay command option is missing or ambiguous")
        return command[command.index(name) + 1]
    if ([x for x in command if x.startswith("-only-testing:")] != ["-only-testing:" + REPLAY_METHODS[suite]]
            or any(x.startswith(("-skip-testing", "-test-iterations", "-retry-tests", "-run-tests-until")) for x in command)
            or command[:2] != ["xcodebuild", "test-without-building"]
            or Path(option("-testProductsPath")).resolve() != products.resolve()
            or option("-destination") != "platform=iOS Simulator,id=" + device_id
            or Path(option("-resultBundlePath")).absolute() != result_bundle.absolute()):
        raise ValueError("Replay command must select the exact method, products, result and device once")
    output = receipt.with_suffix("")
    if any(p.exists() or p.is_symlink() for p in [receipt, output, result_bundle]):
        raise ValueError("Preserve previous Replay evidence; use fresh output paths")
    record = {"suite": suite, "identifier": REPLAY_METHODS[suite], "deviceID": device_id,
              "nativeExitCode": None, "hostAdmissionVerified": False}
    try:
        with replay_fixture_host(products) as configuration:
            record["configuration"] = configuration
            record["nativeExitCode"] = subprocess.run(command, cwd=Path(__file__).resolve().parents[1], check=False).returncode
        info = result_bundle / "Info.plist"
        if not info.is_file() or info.is_symlink():
            raise ValueError("Replay result is incomplete")
        info_sha = hashlib.sha256(info.read_bytes()).hexdigest()
        url = "test://com.apple.xcode/Wander/" + REPLAY_METHODS[suite]
        exported = subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result_bundle),
                                   "--test-id", url, "--output-path", str(output)], check=False,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        if exported.returncode:
            raise ValueError("Replay admission attachment export failed")
        manifest_path = output / "manifest.json"
        manifest = json.loads(manifest_path.read_bytes())
        if not isinstance(manifest, list) or len(manifest) != 1 or manifest[0].get("testIdentifierURL") != url:
            raise ValueError("Replay admission attachment belongs to another case")
        def is_admission(row):
            name = row.get("suggestedHumanReadableName", row.get("name", ""))
            return (name == "Replay host admission"
                    or re.fullmatch(r"Replay host admission_[0-9]+_[0-9a-fA-F-]{36}\.(?:json|txt)", name) is not None)
        rows = [x for x in manifest[0].get("attachments", []) if is_admission(x)]
        if len(rows) != 1:
            raise ValueError("Exactly one Replay host admission attachment is required")
        if rows[0].get("deviceId") != device_id:
            raise ValueError("Replay admission attachment belongs to another device")
        name = rows[0]["exportedFileName"]
        path = output / name
        if Path(name).name != name or not path.is_file() or path.is_symlink() or path.stat().st_size > 4096:
            raise ValueError("Replay admission attachment path or size is invalid")
        data = path.read_bytes()
        admission = json.loads(data)
        validate_replay_host_admission(admission)
        if hashlib.sha256(info.read_bytes()).hexdigest() != info_sha:
            raise ValueError("Replay result changed during admission export")
        record.update(hostAdmissionVerified=True, resultInfoSHA256=info_sha,
                      manifestSHA256=hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                      admissionSHA256=hashlib.sha256(data).hexdigest(), admission=admission)
    except Exception as error:
        record["validationErrorType"] = type(error).__name__
        if isinstance(error, PermissionError):
            raise
    finally:
        with receipt.open("x") as stream:
            json.dump(record, stream, indent=2, sort_keys=True)
            stream.write("\n")
    return record["nativeExitCode"] if record["nativeExitCode"] else (0 if record["hostAdmissionVerified"] else 1)


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


def prepare_ui_performance_products(products: Path, preserve_system_failures: bool = False,
                                    *, screen_capture_format: str = "screenshots") -> int:
    """Set the selected UI suite's capture mode without changing its test selection."""
    if screen_capture_format not in {"screenshots", "screenRecording"}:
        raise ValueError("Unsupported UI screen capture format")
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
                target["PreferredScreenCaptureFormat"] = screen_capture_format
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
    parser.add_argument("--suite", choices=["clip", "unit", "replay", *REPLAY_METHODS, "performance", "ui-performance", "ui-warm-performance", "ui-reference-performance", *UI_RECOVERY_METHODS, "ui", "graphics"], required=True)
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--shard-count", type=int, default=4)
    parser.add_argument("--destination")
    parser.add_argument("--derived-data")
    parser.add_argument("--test-products", help="Prepared .xctestproducts bundle; run without recompiling")
    parser.add_argument("--result-bundle")
    parser.add_argument("--selection-file")
    parser.add_argument("--list-only", action="store_true")
    parser.add_argument("--replay-fixture-host", choices=["inert"])
    parser.add_argument("--replay-host-receipt")
    args = parser.parse_args()
    if args.shard_count < 1 or not 0 <= args.shard < args.shard_count:
        parser.error("shard must be within shard-count")
    if args.replay_fixture_host and (args.suite not in REPLAY_METHODS or not args.test_products):
        parser.error("inert host requires one exact Replay method and prepared test products")
    if args.replay_host_receipt and not args.replay_fixture_host:
        parser.error("host receipt requires explicit inert-host execution")
    root = Path(__file__).resolve().parents[1]
    replay = "WanderTests/ReplayMaskingTests"
    performance = [
        "WanderTests/TrustedPlaceSearchTests/testSearchOneThousandMemoriesP95UnderFiftyMilliseconds",
        "WanderTests/WanderPlaceCategoryTests/testPerformanceFixtureExercisesARealisticHighDataAccountWithinBudget",
    ]
    inventory = (["AstirClipTests", "AstirClipUITests"] if args.suite == "clip" else
                 ui_test_identifiers(root) if args.suite in {"ui", "ui-performance", "ui-warm-performance", "ui-reference-performance", *UI_RECOVERY_METHODS, "graphics"} else
                 [REPLAY_METHODS[args.suite]] if args.suite in REPLAY_METHODS else
                 [replay] if args.suite == "replay" else
                 performance if args.suite == "performance" else ["WanderTests"])
    isolated_ui = ISOLATED_UI_PERFORMANCE | ISOLATED_UI_WARM_PERFORMANCE | REFERENCE_UI_PERFORMANCE
    if args.suite in {"ui", "ui-performance", "ui-warm-performance", "ui-reference-performance", *UI_RECOVERY_METHODS, "graphics"} and not isolated_ui.issubset(inventory):
        parser.error("isolated UI performance selection no longer matches the test inventory")
    if args.suite in UI_RECOVERY_METHODS:
        selected = [UI_RECOVERY_METHODS[args.suite]]
        if not set(selected).issubset(inventory):
            parser.error("exact UI recovery selection no longer matches the test inventory")
    elif args.suite == "graphics":
        selected = sorted(ISOLATED_UI_PERFORMANCE | REFERENCE_UI_PERFORMANCE | {
            "WanderUITests/EventsComingSoonUITests/testLightTabBarStaysLightAcrossEventsVisits",
            "WanderUITests/EventsComingSoonUITests/testDarkTabBarStaysDarkAcrossEventsVisits",
            "WanderUITests/EventsComingSoonUITests/testTabGlassSurvivesScrubbingAndLiveAppearanceChanges",
        })
        if not set(selected).issubset(inventory):
            parser.error("graphics diagnostic selection no longer matches the test inventory")
    elif args.suite == "ui-performance":
        selected = sorted(ISOLATED_UI_PERFORMANCE)
    elif args.suite == "ui-warm-performance":
        selected = sorted(ISOLATED_UI_WARM_PERFORMANCE)
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
                    **{test: "ui-warm-performance" for test in sorted(ISOLATED_UI_WARM_PERFORMANCE)},
                    **{test: "ui-reference-performance" for test in sorted(REFERENCE_UI_PERFORMANCE)}}
    excluded = list(isolated)
    if not selected:
        parser.error("empty test selection")
    selection = {"suite": args.suite, "shard": args.shard, "totalUIInventory": len(inventory) if args.suite in {"ui", "ui-performance", "ui-warm-performance", "ui-reference-performance", *UI_RECOVERY_METHODS, "graphics"} else None,
                 "identifiers": selected, "isolatedTestSuites": isolated}
    if args.selection_file:
        Path(args.selection_file).write_text(json.dumps(selection, indent=2) + "\n")
    if args.list_only:
        print(json.dumps(selection, indent=2))
        return 0
    if not all([args.destination, args.result_bundle]) or not (args.derived_data or args.test_products):
        parser.error("destination, result-bundle and either derived-data or test-products are required to run tests")
    if any(identifier in selected for identifier in (
        "WanderUITests/NativeOnboardingFlowUITests/testProfilePreviewUpdatesWithOptionalPhoto",
        "WanderUITests/NativeAccountSetupUITests/testProfilePhotoPickerCropAndValidation",
    )):
        # The real PhotoKit picker needs an actual library item on a fresh CI
        # simulator. Use the same public bundled artwork as the review fixture;
        # do not depend on photos left behind by another test or recording run.
        subprocess.run(["xcrun", "simctl", "bootstatus", args.destination, "-b"], check=True)
        photo = root / "Wander/Resources/Assets.xcassets/PlaceCarouselAvatars.imageset/place-carousel-avatars.png"
        subprocess.run(["xcrun", "simctl", "addmedia", args.destination, str(photo)], check=True)
    print(f"Running {args.suite} selection {args.shard + 1}: {len(selected)} identifiers", flush=True)
    if args.test_products:
        if args.suite in {"ui", "graphics", "ui-performance", "ui-warm-performance", "ui-reference-performance", *UI_RECOVERY_METHODS}:
            capture_format = "screenRecording" if args.suite == "ui-warm-performance" else "screenshots"
            count = prepare_ui_performance_products(
                Path(args.test_products),
                preserve_system_failures=args.suite in {"ui", "graphics", "ui-warm-performance", *UI_RECOVERY_METHODS},
                screen_capture_format=capture_format
            )
            print(f"Using {capture_format} for {count} UI target(s)", flush=True)
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
    if args.replay_fixture_host:
        result = Path(args.result_bundle)
        receipt = Path(args.replay_host_receipt) if args.replay_host_receipt else result.with_suffix(".host-admission.json")
        return run_isolated_replay(suite=args.suite, products=Path(args.test_products), device_id=args.destination,
                                   result_bundle=result, command=command, receipt=receipt)
    return subprocess.run(command, cwd=root, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
