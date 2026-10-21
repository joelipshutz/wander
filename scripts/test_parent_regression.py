import copy
from collections import Counter
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import textwrap
from types import SimpleNamespace
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location(
    "parent_regression", Path(__file__).with_name("run-parent-regression.py")
)
regression = importlib.util.module_from_spec(spec)
spec.loader.exec_module(regression)


def xctest_method_names(source, class_name):
    """Mirror the runner's class partitions; compiled inventory remains authoritative."""
    classes = list(re.finditer(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source))
    if sum(match.group(1) == class_name for match in classes) != 1:
        raise ValueError("Expected exactly one named XCTestCase declaration")
    assigned = []
    selected = []
    for index, match in enumerate(classes):
        end = classes[index + 1].start() if index + 1 < len(classes) else len(source)
        methods = re.findall(r"\bfunc\s+(test\w*)\s*\(", source[match.end():end])
        assigned.extend(methods)
        if match.group(1) == class_name:
            selected = methods
    if Counter(assigned) != Counter(re.findall(r"\bfunc\s+(test\w*)\s*\(", source)):
        raise ValueError("Unassigned XCTest methods; update discovery before checking isolation")
    return selected


class ReplaySourceAttributionTests(unittest.TestCase):
    def test_sibling_classes_do_not_enter_replay_selection(self):
        source = """
        final class EarlierTests: XCTestCase { func testSharedName() {} }
        final class ReplayMaskingTests: XCTestCase {
            func testSharedName() { if true { let braces = "}" } }
            func testOtherReplayCase() { /* { } */ }
        }
        final class ReplayLayoutPacingTests: XCTestCase {
            func testSharedName() {}
            func testStartupPacing() {}
        }
        """
        self.assertEqual(xctest_method_names(source, "ReplayMaskingTests"),
                         ["testSharedName", "testOtherReplayCase"])

    def test_missing_or_duplicate_named_class_is_rejected(self):
        declaration = "class ReplayMaskingTests: XCTestCase { func testExample() {} }"
        for source in ["class OtherTests: XCTestCase {}", declaration + declaration]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                xctest_method_names(source, "ReplayMaskingTests")

    def test_unassigned_method_is_rejected_instead_of_silently_dropped(self):
        source = """
        func testOutsideSupportedClass() {}
        class ReplayMaskingTests: XCTestCase { func testExample() {} }
        """
        with self.assertRaises(ValueError):
            xctest_method_names(source, "ReplayMaskingTests")

    def test_method_counts_are_preserved_for_exact_counter_comparison(self):
        source = """
        class ReplayMaskingTests: XCTestCase {
            func testDuplicate() {}
            func testDuplicate() {}
        }
        """
        self.assertEqual(xctest_method_names(source, "ReplayMaskingTests"),
                         ["testDuplicate", "testDuplicate"])


class ReplayIsolationTests(unittest.TestCase):
    def selection(self, suite):
        output = io.StringIO()
        with mock.patch("sys.argv", ["run-parent-regression.py", "--suite", suite, "--list-only"]), \
                mock.patch.object(regression.subprocess, "run", side_effect=AssertionError("No native execution")), \
                contextlib.redirect_stdout(output):
            self.assertEqual(regression.main(), 0)
        return json.loads(output.getvalue())

    def test_isolated_modes_cover_each_original_replay_method_once(self):
        root = Path(__file__).resolve().parents[1]
        source = (root / "WanderTests/ReplayMaskingTests.swift").read_text()
        original = ["WanderTests/ReplayMaskingTests/" + name
                    for name in xctest_method_names(source, "ReplayMaskingTests")]
        selected = [identifier for suite in regression.REPLAY_METHODS
                    for identifier in self.selection(suite)["identifiers"]]
        self.assertEqual(Counter(selected), Counter(original))
        self.assertEqual(len(selected), 2)
        self.assertEqual(self.selection("replay")["identifiers"], ["WanderTests/ReplayMaskingTests"])
        self.assertEqual(self.selection("unit")["isolatedTestSuites"]["WanderTests/ReplayMaskingTests"], "replay")

    def test_each_isolated_dispatch_preserves_native_execution_contract(self):
        for suite, identifier in regression.REPLAY_METHODS.items():
            with self.subTest(suite=suite), \
                    mock.patch("sys.argv", ["run-parent-regression.py", "--suite", suite,
                                            "--destination", "fixture-device", "--test-products", "prepared.xctestproducts",
                                            "--result-bundle", suite + ".xcresult"]), \
                    mock.patch.object(regression.subprocess, "run", return_value=SimpleNamespace(returncode=65)) as run, \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(regression.main(), 65)
                command = run.call_args.args[0]
                self.assertEqual(run.call_count, 1)
                self.assertEqual(command[:3], ["xcodebuild", "test-without-building", "-quiet"])
                self.assertEqual([x for x in command if x.startswith("-only-testing:")], ["-only-testing:" + identifier])
                self.assertFalse(any(x.startswith("-skip-testing:") for x in command))
                for flag, value in [("-testProductsPath", "prepared.xctestproducts"),
                                    ("-parallel-testing-enabled", "NO"), ("-test-timeouts-enabled", "YES"),
                                    ("-default-test-execution-time-allowance", "600"),
                                    ("-maximum-test-execution-time-allowance", "900")]:
                    self.assertEqual(command[command.index(flag) + 1], value)
                self.assertNotIn("-retry-tests-on-failure", command)
                self.assertNotIn("-test-iterations", command)

    def result_fixture(self, suite):
        identifier = regression.REPLAY_METHODS[suite]
        summary = {"result": "Passed", "totalTestCount": 1, "passedTests": 1,
                   "failedTests": 0, "skippedTests": 0, "expectedFailures": 0,
                   "devicesAndConfigurations": [{"device": {"deviceId": "fixture-device", "platform": "iOS Simulator"}}]}
        tests = {"testNodes": [{"nodeType": "Test Case", "result": "Passed",
                                "nodeIdentifier": identifier.split("/", 1)[1] + "()",
                                "nodeIdentifierURL": "test://com.apple.xcode/Wander/" + identifier}]}
        return summary, tests

    def test_required_result_rejects_wrong_method_device_skips_and_empty_pass(self):
        suite = "replay-private"
        summary, tests = self.result_fixture(suite)
        regression.validate_replay_result(suite, summary, tests, "fixture-device")
        for description, changed_summary, changed_tests in [
            ("other method", summary, self.result_fixture("replay-credentials")[1]),
            ("no case", summary, {"testNodes": []}),
            ("two cases", summary, {"testNodes": tests["testNodes"] * 2}),
            ("skip", {**summary, "passedTests": 0, "skippedTests": 1}, tests),
            ("empty pass", {**summary, "passedTests": 0, "totalTestCount": 0}, {"testNodes": []}),
            ("wrong device", {**summary, "devicesAndConfigurations": []}, tests),
        ]:
            with self.subTest(description=description), self.assertRaises(ValueError):
                regression.validate_replay_result(suite, changed_summary, changed_tests, "fixture-device")

    def workflow_step(self, name):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/app-clip-validation.yml").read_text()
        block = workflow.split("      - name: " + name + "\n", 1)[1]
        return block.split("\n      - ", 1)[0]

    def test_workflow_requires_both_once_after_units_and_retains_both_results(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/app-clip-validation.yml").read_text()
        prior = workflow.index("- name: Run complete parent suite")
        for suite, name in [("replay-private", "Run private replay proof after parent units"),
                            ("replay-credentials", "Run credential replay proof after parent units")]:
            self.assertLess(prior, workflow.index("- name: " + name))
            prior = workflow.index("- name: " + name)
            block = self.workflow_step(name)
            self.assertIn("(success() || failure()) && matrix.suite == 'unit'", block)
            self.assertEqual(block.count("--suite " + suite), 1)
            self.assertNotIn("continue-on-error", block)
            self.assertNotIn("--suite replay\n", block)
        gate = self.workflow_step("Summarize and require both replay proofs")
        self.assertIn("always() && matrix.suite == 'unit'", gate)
        self.assertIn("regression.validate_replay_result", gate)
        retained = self.workflow_step("Retain regression evidence")
        self.assertIn("if: always()", retained)
        for name in ["ParentReplayPrivate.xcresult", "ParentReplayCredentials.xcresult",
                     "replay-private-summary.json", "replay-private-tests.json", "replay-private-selection.json",
                     "replay-credentials-summary.json", "replay-credentials-tests.json", "replay-credentials-selection.json"]:
            self.assertIn("${{ runner.temp }}/" + name, retained)

    def test_workflow_still_exports_second_result_when_first_fails_or_is_missing(self):
        block = self.workflow_step("Summarize and require both replay proofs")
        code = textwrap.dedent(block.split("python3 - <<'PY'\n", 1)[1].rsplit("\n          PY", 1)[0])
        for first in ["passed", "failed", "missing", "export-failed"]:
            with self.subTest(first=first), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for name in ["ParentReplayPrivate", "ParentReplayCredentials"]:
                    if name == "ParentReplayPrivate" and first == "missing":
                        continue
                    (root / (name + ".xcresult")).mkdir()
                    (root / (name + ".xcresult") / "Info.plist").touch()
                calls = []

                def export(command, stdout, timeout):
                    self.assertEqual(timeout, 120)
                    self.assertEqual(command[:4], ["xcrun", "xcresulttool", "get", "test-results"])
                    kind = command[4]
                    private = "ParentReplayPrivate.xcresult" in command[command.index("--path") + 1]
                    suite = "replay-private" if private else "replay-credentials"
                    calls.append((suite, kind))
                    summary, tests = self.result_fixture(suite)
                    if private and first == "failed":
                        summary.update(result="Failed", passedTests=0, failedTests=1)
                        tests["testNodes"][0]["result"] = "Failed"
                    stdout.write(json.dumps(summary if kind == "summary" else tests).encode())
                    return SimpleNamespace(returncode=64 if private and first == "export-failed" and kind == "summary" else 0)

                with mock.patch.dict(os.environ, {"RUNNER_TEMP": directory, "TEST_DEVICE_ID": "fixture-device"}), \
                        mock.patch.object(subprocess, "run", side_effect=export):
                    if first == "passed":
                        exec(compile(code, "workflow-replay-gate", "exec"), {})
                    else:
                        with self.assertRaises(SystemExit):
                            exec(compile(code, "workflow-replay-gate", "exec"), {})
                self.assertEqual(Counter(calls)[("replay-credentials", "summary")], 1)
                self.assertEqual(Counter(calls)[("replay-credentials", "tests")], 1)
                self.assertTrue((root / "replay-credentials-summary.json").is_file())
                self.assertTrue((root / "replay-credentials-tests.json").is_file())


class PhotoFixturePreparationTests(unittest.TestCase):
    def dispatch(self, identifier, *, fail_seed=False):
        calls = []

        def native(command, **kwargs):
            calls.append((command, kwargs))
            if fail_seed and command[:3] == ["xcrun", "simctl", "addmedia"]:
                raise subprocess.CalledProcessError(1, command)
            return SimpleNamespace(returncode=65 if command[0] == "xcodebuild" else 0)

        with mock.patch("sys.argv", ["run-parent-regression.py", "--suite", "ui", "--shard", "0",
                                    "--shard-count", "1", "--destination", "fixture-device",
                                    "--test-products", "prepared.xctestproducts", "--result-bundle", "photo.xcresult"]), \
                mock.patch.object(regression, "ui_test_identifiers", return_value=sorted({identifier} | regression.ISOLATED_UI_PERFORMANCE | regression.ISOLATED_UI_WARM_PERFORMANCE | regression.REFERENCE_UI_PERFORMANCE)), \
                mock.patch.object(regression, "prepare_ui_performance_products", return_value=1), \
                mock.patch.object(regression.subprocess, "run", side_effect=native), \
                contextlib.redirect_stdout(io.StringIO()):
            if fail_seed:
                with self.assertRaises(subprocess.CalledProcessError):
                    regression.main()
                return calls
            self.assertEqual(regression.main(), 65, "Preserve the actual native failure exit.")
        return calls

    def test_each_photo_journey_seeds_the_same_owned_asset_before_native_execution(self):
        for identifier in [
            "WanderUITests/NativeOnboardingFlowUITests/testProfilePreviewUpdatesWithOptionalPhoto",
            "WanderUITests/NativeAccountSetupUITests/testProfilePhotoPickerCropAndValidation",
        ]:
            with self.subTest(identifier=identifier):
                calls = self.dispatch(identifier)
                asset = Path(regression.__file__).resolve().parents[1] / "Wander/Resources/Assets.xcassets/PlaceCarouselAvatars.imageset/place-carousel-avatars.png"
                self.assertEqual(calls[0], (["xcrun", "simctl", "bootstatus", "fixture-device", "-b"], {"check": True}))
                self.assertEqual(calls[1], (["xcrun", "simctl", "addmedia", "fixture-device", str(asset)], {"check": True}))
                self.assertEqual(len(calls), 3)
                command = calls[2][0]
                self.assertEqual(command[:3], ["xcodebuild", "test-without-building", "-quiet"])
                self.assertEqual([x for x in command if x.startswith("-only-testing:")], ["-only-testing:" + identifier])
                for flag, value in [("-default-test-execution-time-allowance", "600"),
                                    ("-maximum-test-execution-time-allowance", "900"),
                                    ("-parallel-testing-enabled", "NO")]:
                    self.assertEqual(command[command.index(flag) + 1], value)
                self.assertNotIn("-retry-tests-on-failure", command)

    def test_unrelated_ui_case_does_not_seed_or_boot_a_photo_fixture(self):
        calls = self.dispatch("WanderUITests/NativeAccountSetupUITests/testProfilePreviewRetainsIdentityAcrossBackground")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0][0], "xcodebuild")

    def test_failed_photo_import_stops_before_native_execution(self):
        calls = self.dispatch("WanderUITests/NativeAccountSetupUITests/testProfilePhotoPickerCropAndValidation", fail_seed=True)
        self.assertEqual(len(calls), 2)
        self.assertFalse(any(command[0] == "xcodebuild" for command, _ in calls))


class PerformanceProductsTests(unittest.TestCase):
    def test_ui_inventory_has_disjoint_complete_hosted_and_reference_coverage(self):
        inventory = regression.ui_test_identifiers(Path(__file__).resolve().parents[1])
        hosted = regression.ISOLATED_UI_PERFORMANCE | regression.ISOLATED_UI_WARM_PERFORMANCE
        reference = regression.REFERENCE_UI_PERFORMANCE
        self.assertFalse(hosted & reference)
        self.assertTrue((hosted | reference).issubset(inventory))
        ordinary = [test for shard in range(8) for test in inventory[shard::8]
                    if test not in hosted | reference]
        self.assertEqual(Counter(ordinary + sorted(hosted) + sorted(reference)), Counter(inventory))

    def selection(self, suite, shard=0):
        output = io.StringIO()
        with mock.patch("sys.argv", ["run-parent-regression.py", "--suite", suite,
                                     "--shard", str(shard), "--shard-count", "8", "--list-only"]), \
                mock.patch.object(regression.subprocess, "run", side_effect=AssertionError("No native execution")), \
                contextlib.redirect_stdout(output):
            self.assertEqual(regression.main(), 0)
        return json.loads(output.getvalue())

    def test_warm_is_required_once_and_does_not_reshuffle_other_ui_methods(self):
        inventory = regression.ui_test_identifiers(Path(__file__).resolve().parents[1])
        warm = regression.ISOLATED_UI_WARM_PERFORMANCE
        self.assertEqual(warm, {
            "WanderUITests/MapFilterInteractionUITests/testPerformanceFixtureKeepsWarmSourceSwitchesResponsive"})
        ordinary = []
        for shard in range(8):
            selected = self.selection("ui", shard)
            expected = [identifier for identifier in inventory[shard::8]
                        if identifier not in regression.ISOLATED_UI_PERFORMANCE | regression.REFERENCE_UI_PERFORMANCE | warm]
            self.assertEqual(selected["identifiers"], expected)
            for identifier in warm:
                self.assertEqual(selected["isolatedTestSuites"][identifier], "ui-warm-performance")
            ordinary += selected["identifiers"]
        isolated = [identifier for suite in ("ui-performance", "ui-warm-performance", "ui-reference-performance")
                    for identifier in self.selection(suite)["identifiers"]]
        self.assertEqual(Counter(ordinary + isolated), Counter(inventory))
        self.assertFalse(warm & set(self.selection("graphics")["identifiers"]))

    def test_only_warm_dispatch_uses_recording_and_keeps_original_native_contract(self):
        for suite, capture, preserve in [("ui-warm-performance", "screenRecording", True),
                                          ("ui-performance", "screenshots", False),
                                          ("ui-reference-performance", "screenshots", False),
                                          ("ui", "screenshots", True), ("graphics", "screenshots", True),
                                          ("ui-snapshot-recovery", "screenshots", True),
                                          ("ui-profile-share-recovery", "screenshots", True),
                                          ("ui-three-case-recovery", "screenshots", True)]:
            with self.subTest(suite=suite), \
                    mock.patch("sys.argv", ["run-parent-regression.py", "--suite", suite,
                        "--destination", "fixture-device", "--test-products", "prepared.xctestproducts",
                        "--result-bundle", "result.xcresult"]), \
                    mock.patch.object(regression, "prepare_ui_performance_products", return_value=1) as prepare, \
                    mock.patch.object(regression.subprocess, "run", return_value=SimpleNamespace(returncode=65)) as run, \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(regression.main(), 65)
                prepare.assert_called_once_with(Path("prepared.xctestproducts"),
                    preserve_system_failures=preserve, screen_capture_format=capture)
                # Ordinary shards may seed PhotoKit before their one native dispatch.
                native_calls = [call for call in run.call_args_list if call.args[0][0] == "xcodebuild"]
                self.assertEqual(len(native_calls), 1)
                command = native_calls[0].args[0]
                self.assertEqual(command[:3], ["xcodebuild", "test-without-building", "-quiet"])
                for flag, value in [("-testProductsPath", "prepared.xctestproducts"),
                    ("-destination", "platform=iOS Simulator,id=fixture-device"), ("-jobs", "2"),
                    ("-parallel-testing-enabled", "NO"), ("-test-timeouts-enabled", "YES"),
                    ("-default-test-execution-time-allowance", "600"),
                    ("-maximum-test-execution-time-allowance", "900")]:
                    self.assertEqual(command[command.index(flag) + 1], value)
                self.assertFalse(any(x.startswith(("-test-iterations", "-retry-tests")) for x in command))
                if suite == "ui-three-case-recovery":
                    self.assertEqual([x for x in command if x.startswith("-only-testing:")],
                                     ["-only-testing:" + identifier for identifier in regression.UI_THREE_CASE_RECOVERY])
                    self.assertFalse(any(x.startswith("-skip-testing:") for x in command))
                if suite == "ui-warm-performance" or suite in regression.UI_RECOVERY_METHODS:
                    identifier = (next(iter(regression.ISOLATED_UI_WARM_PERFORMANCE))
                                  if suite == "ui-warm-performance" else regression.UI_RECOVERY_METHODS[suite])
                    self.assertEqual([x for x in command if x.startswith("-only-testing:")],
                                     ["-only-testing:" + identifier])
                    self.assertFalse(any(x.startswith("-skip-testing:") for x in command))

    def test_invalid_capture_mode_fails_before_any_configuration_write(self):
        with tempfile.TemporaryDirectory() as temporary, self.assertRaisesRegex(ValueError, "Unsupported"):
            regression.prepare_ui_performance_products(Path(temporary), screen_capture_format="none")

    def test_full_workflow_requires_the_separate_warm_suite(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/app-clip-validation.yml").read_text()
        self.assertEqual(workflow.count('{"name":"UI warm performance","suite":"ui-warm-performance","shard":0}'), 2)
        self.assertIn("'ui-performance', 'ui-warm-performance', 'ui-snapshot-recovery', 'ui-profile-share-recovery', 'graphics'", workflow)

    def test_recovery_methods_are_exact_and_do_not_leave_ordinary_coverage(self):
        expected = {
            "ui-snapshot-recovery": "WanderUITests/YourMapPrototypeUITests/testSnapshotCreatesListAndOpensEditorWithoutDuplicatePlaceControls",
            "ui-profile-share-recovery": "WanderUITests/ProfileResponsivenessUITests/testProfileSharePresentsAndCancelsOnColdAndWarmEntry",
        }
        self.assertEqual(regression.UI_RECOVERY_METHODS, expected)
        ordinary = [case for shard in range(8) for case in self.selection("ui", shard)["identifiers"]]
        inventory = regression.ui_test_identifiers(Path(__file__).resolve().parents[1])
        for suite, identifier in expected.items():
            with self.subTest(suite=suite):
                self.assertEqual(self.selection(suite)["identifiers"], [identifier])
                self.assertEqual(ordinary.count(identifier), 1)
                with mock.patch.object(regression, "ui_test_identifiers", return_value=[x for x in inventory if x != identifier]), \
                        contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    self.selection(suite)

    def test_recovery_mode_selects_only_three_jobs_and_rejects_conflicting_modes_before_build(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/app-clip-validation.yml").read_text()
        self.assertIn("parent_ui_recovery:\n        description: Run only the original warm-source timing, Your Map snapshot and Profile share checks\n        type: boolean\n        default: false", workflow)
        matrix = next(line for line in workflow.splitlines() if "include: ${{ fromJSON(" in line)
        modes = {name or "default": json.loads(value) for name, value in
                 re.findall(r"(?:inputs\.(\w+) && )?'(\[.*?\])'", matrix)}
        self.assertEqual(set(modes), {"parent_ui_recovery", "parent_three_case_recovery", "unpassed_only", "graphics_only", "default"})
        self.assertEqual(modes["parent_three_case_recovery"],
                         [{"name": "three-case recovery", "suite": "ui-three-case-recovery", "shard": 0}])
        self.assertEqual([(x["suite"], x["shard"]) for x in modes["parent_ui_recovery"]],
                         [("ui-warm-performance", 0), ("ui-snapshot-recovery", 0), ("ui-profile-share-recovery", 0)])
        self.assertEqual([(x["suite"], x["shard"]) for x in modes["unpassed_only"]], [("ui", 0), ("ui", 2)])
        self.assertEqual([(x["suite"], x["shard"]) for x in modes["graphics_only"]], [("graphics", 0)])
        self.assertEqual(sum(x["suite"] == "ui-warm-performance" for x in modes["default"]), 1)
        self.assertFalse(set(regression.UI_RECOVERY_METHODS) & {x["suite"] for x in modes["default"]})
        self.assertEqual(workflow.count('if [ "$UNPASSED_ONLY" != "true" ] && [ "$PARENT_UI_RECOVERY" != "true" ] && [ "$PARENT_THREE_CASE_RECOVERY" != "true" ]; then'), 2)
        guard = textwrap.dedent(workflow.split("        run: |\n", 1)[1].split("          python3 -B", 1)[0])
        self.assertNotIn("xcodebuild", guard)
        self.assertNotIn("brew", guard)
        for mask in range(16):
            values = ["true" if mask & (1 << index) else "false" for index in range(4)]
            with self.subTest(values=values):
                result = subprocess.run(["/bin/bash", "-c", guard], capture_output=True,
                    env={"UNPASSED_ONLY": values[0], "GRAPHICS_ONLY": values[1], "PARENT_UI_RECOVERY": values[2], "PARENT_THREE_CASE_RECOVERY": values[3]})
                self.assertEqual(result.returncode, 0 if values.count("true") <= 1 else 1)

    def test_three_case_recovery_keeps_exact_original_membership(self):
        expected = [
            "WanderUITests/SenderNotificationFlowUITests/testSharedAcceptanceAndExplicitInvitationCopyUseRealComposer",
            "WanderUITests/OnboardingUITests/testCheckInCalendarTrayPresentationLatency",
            "WanderUITests/MapFilterInteractionUITests/testPerformanceFixtureTracesDenseMapPanZoomAndBoundsAnnotationWork",
        ]
        self.assertEqual(list(regression.UI_THREE_CASE_RECOVERY), expected)
        self.assertEqual(self.selection("ui-three-case-recovery")["identifiers"], expected)
        ordinary = [case for shard in range(8) for case in self.selection("ui", shard)["identifiers"]]
        self.assertEqual(ordinary.count(expected[0]), 1)
        performance = self.selection("ui-performance")["identifiers"]
        for identifier in expected[1:]:
            self.assertEqual(performance.count(identifier), 1)
        inventory = regression.ui_test_identifiers(Path(__file__).resolve().parents[1])
        for identifier in expected:
            with self.subTest(identifier=identifier), \
                    mock.patch.object(regression, "ui_test_identifiers", return_value=[x for x in inventory if x != identifier]), \
                    contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                self.selection("ui-three-case-recovery")

    def test_three_case_recovery_is_default_off_and_parent_only(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/app-clip-validation.yml").read_text()
        self.assertIn("parent_three_case_recovery:\n        description: Run only Shared acceptance, Calendar tray latency and dense-map trace checks\n        type: boolean\n        default: false", workflow)
        self.assertIn("permissions:\n  contents: read\n", workflow)
        self.assertNotIn("actions: read", workflow)
        self.assertNotIn("overwrite:", workflow)
        self.assertNotIn("run-id:", workflow)
        for skip_clip in re.findall(r'if \[ "\$UNPASSED_ONLY".*?; then', workflow):
            self.assertIn('"$PARENT_THREE_CASE_RECOVERY" != "true"', skip_clip)
        matrix = next(line for line in workflow.splitlines() if "include: ${{ fromJSON(" in line)
        modes = {name or "default": json.loads(value) for name, value in
                 re.findall(r"(?:inputs\.(\w+) && )?'(\[.*?\])'", matrix)}
        self.assertFalse(any(row["suite"] == "ui-three-case-recovery" for row in modes["default"]))

    def test_both_formats_preserve_selection_binaries_and_unit_configuration(self):
        for version, preserve_failures, capture in [(v, p, c) for v in (1, 2) for p in (False, True)
                                                    for c in ("screenshots", "screenRecording")]:
            with self.subTest(version=version, preserve_failures=preserve_failures, capture=capture), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                unit = {"BlueprintName": "WanderTests", "TestBundlePath": "units.xctest"}
                ui = {"IsUITestBundle": True, "BlueprintName": "WanderUITests",
                      "OnlyTestIdentifiers": ["MapTests/testFrames"],
                      "TestBundlePath": "ui.xctest", "UserAttachmentLifetime": "keepAlways",
                      "PreferredScreenCaptureFormat": "screenRecording",
                      "SystemAttachmentLifetime": "deleteOnSuccess"}
                document = ({"WanderTests": unit, "WanderUITests": ui} if version == 1 else
                            {"TestConfigurations": [{"TestTargets": [unit, ui]}]})
                expected = copy.deepcopy(document)
                expected_ui = (expected["WanderUITests"] if version == 1 else
                               expected["TestConfigurations"][0]["TestTargets"][1])
                expected_ui.update(PreferredScreenCaptureFormat=capture,
                                   SystemAttachmentLifetime="deleteOnSuccess" if preserve_failures else "keepNever")
                (root / "Info.plist").write_bytes(plistlib.dumps({
                    "Tests": [{"xctestrun": "tests.plist"}]}))
                configuration = root / "tests.plist"
                configuration.write_bytes(plistlib.dumps(document))
                self.assertEqual(regression.prepare_ui_performance_products(root, preserve_failures,
                                                                          screen_capture_format=capture), 1)
                self.assertEqual(plistlib.loads(configuration.read_bytes()), expected)

    def test_missing_ui_target_fails_without_rewriting_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Info.plist").write_bytes(plistlib.dumps({
                "Tests": [{"xctestrun": "tests.plist"}]}))
            configuration = root / "tests.plist"
            original = plistlib.dumps({"WanderTests": {"BlueprintName": "WanderTests"}})
            configuration.write_bytes(original)
            with self.assertRaisesRegex(ValueError, "No UI test target"):
                regression.prepare_ui_performance_products(root)
            self.assertEqual(configuration.read_bytes(), original)

    def test_configuration_path_cannot_escape_products_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Info.plist").write_bytes(plistlib.dumps({
                "Tests": [{"xctestrun": "../outside.plist"}]}))
            with self.assertRaisesRegex(ValueError, "inside the products bundle"):
                regression.prepare_ui_performance_products(root)


class ReplayFixtureHostTests(unittest.TestCase):
    @staticmethod
    def admission():
        return {"schema": 1, "requested": True, "mode": "inert", "expected_host": True,
                "inert_root_mounted": True, "ordinary_root_mounted": False,
                "admitted": True, "elapsed_ms": 12, "limit_ms": 10000}

    @contextlib.contextmanager
    def products(self, version=1, arguments=None, extra_unit=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            unit = {"BlueprintName": "WanderTests", "ProductModuleName": "WanderTests",
                    "TestBundlePath": "__TESTROOT__/Wander.app/PlugIns/WanderTests.xctest",
                    "TestHostPath": "__TESTROOT__/Wander.app/Wander",
                    "CommandLineArguments": list(arguments or []),
                    "EnvironmentVariables": {"FICTIONAL_UNRELATED_SETTING": "retained"},
                    "OnlyTestIdentifiers": ["ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage"],
                    "UserAttachmentLifetime": "keepAlways"}
            ui = {"BlueprintName": "WanderUITests", "IsUITestBundle": True,
                  "CommandLineArguments": ["-UnrelatedUITestArgument"],
                  "TestBundlePath": "__TESTROOT__/WanderUITests.xctest"}
            targets = [unit, ui] + ([copy.deepcopy(unit)] if extra_unit else [])
            document = ({"WanderTests": unit, "WanderUITests": ui,
                         **({"DuplicateUnit": targets[-1]} if extra_unit else {})} if version == 1 else
                        {"TestConfigurations": [{"TestTargets": targets}]})
            info = root / "Info.plist"
            info.write_bytes(plistlib.dumps({"Tests": [{"xctestrun": "tests.xctestrun"}]}))
            path = root / "tests.xctestrun"
            original = plistlib.dumps(document, fmt=plistlib.FMT_XML, sort_keys=False)
            path.write_bytes(original)
            binary = root / "fictional-product-bytes"
            binary.write_bytes(b"No executable code: preserve these bytes")
            yield root, path, original, document, binary

    def test_admission_accepts_only_actual_exclusive_inert_mount(self):
        regression.validate_replay_host_admission(self.admission())
        for field, value in [("requested", False), ("mode", "ordinary"), ("mode", "unknown"),
                             ("expected_host", False), ("inert_root_mounted", False),
                             ("ordinary_root_mounted", True), ("admitted", False),
                             ("elapsed_ms", -1), ("elapsed_ms", 10000),
                             ("elapsed_ms", 10001), ("limit_ms", 10001)]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                regression.validate_replay_host_admission({**self.admission(), field: value})

    def test_admission_rejects_missing_extra_and_coerced_field_types(self):
        for field in self.admission():
            value = self.admission()
            del value[field]
            with self.subTest(missing=field), self.assertRaises(ValueError):
                regression.validate_replay_host_admission(value)
        for field, value in [("schema", True), ("requested", 1), ("expected_host", "true"),
                             ("inert_root_mounted", 1), ("ordinary_root_mounted", 0),
                             ("admitted", 1), ("elapsed_ms", True), ("elapsed_ms", 1.5),
                             ("limit_ms", 10000.0)]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                regression.validate_replay_host_admission({**self.admission(), field: value})
        with self.assertRaises(ValueError):
            regression.validate_replay_host_admission({**self.admission(), "unrecognized": True})

    def test_context_changes_only_exact_unit_arguments_in_both_formats_then_restores_bytes(self):
        for version in [1, 2]:
            with self.subTest(version=version), self.products(version, ["-RetainedArgument"]) as fixture:
                products, path, original, document, binary = fixture
                binary_before = binary.read_bytes()
                expected = copy.deepcopy(document)
                unit = expected["WanderTests"] if version == 1 else expected["TestConfigurations"][0]["TestTargets"][0]
                unit["CommandLineArguments"] += ["-WanderReplayFixtureHost", "inert"]
                with regression.replay_fixture_host(products) as receipt:
                    self.assertIsInstance(receipt, dict)
                    self.assertEqual(plistlib.loads(path.read_bytes()), expected)
                    self.assertEqual(binary.read_bytes(), binary_before)
                self.assertEqual(path.read_bytes(), original)
                self.assertEqual(binary.read_bytes(), binary_before)

    def test_context_restores_exact_bytes_when_native_body_fails(self):
        with self.products() as fixture:
            products, path, original, _, _ = fixture
            with self.assertRaisesRegex(RuntimeError, "fictional native failure"):
                with regression.replay_fixture_host(products):
                    raise RuntimeError("fictional native failure")
            self.assertEqual(path.read_bytes(), original)

    def test_context_restores_partial_preparation_write_before_yield(self):
        with self.products() as fixture:
            products, path, original, _, _ = fixture
            write_bytes = Path.write_bytes
            failed = False
            entered = False
            def write(target, data):
                nonlocal failed
                if target.resolve() == path.resolve() and data != original and not failed:
                    failed = True
                    write_bytes(target, b"fictional interrupted write")
                    raise OSError("fictional preparation failure")
                return write_bytes(target, data)
            with mock.patch.object(Path, "write_bytes", write), self.assertRaises(OSError):
                with regression.replay_fixture_host(products):
                    entered = True
            self.assertTrue(failed)
            self.assertFalse(entered)
            self.assertEqual(path.read_bytes(), original)

    def test_context_rejects_duplicate_targets_and_conflicting_launch_arguments_without_writes(self):
        for arguments, extra in [([], True), (["-WanderReplayFixtureHost"], False),
                                 (["-WanderReplayFixtureHost", "inert"], False),
                                 (["-WanderReplayFixtureHost=ordinary"], False)]:
            with self.subTest(arguments=arguments, duplicate=extra), self.products(arguments=arguments, extra_unit=extra) as fixture:
                products, path, original, _, _ = fixture
                with self.assertRaises(ValueError):
                    with regression.replay_fixture_host(products):
                        self.fail("Invalid preparation must not yield")
                self.assertEqual(path.read_bytes(), original)

    def test_context_rejects_missing_unit_and_escaping_configuration_without_writes(self):
        with self.products() as fixture:
            products, path, _, document, _ = fixture
            del document["WanderTests"]
            path.write_bytes(plistlib.dumps(document))
            original = path.read_bytes()
            with self.assertRaises(ValueError):
                with regression.replay_fixture_host(products):
                    self.fail("Missing unit target must not yield")
            self.assertEqual(path.read_bytes(), original)
            (products / "Info.plist").write_bytes(plistlib.dumps({"Tests": [{"xctestrun": "../outside.xctestrun"}]}))
            with self.assertRaises(ValueError):
                with regression.replay_fixture_host(products):
                    self.fail("Escaping configuration must not yield")

    def test_parent_opt_in_delegates_only_the_two_exact_methods_with_original_timeouts(self):
        for suite, identifier in regression.REPLAY_METHODS.items():
            with self.subTest(suite=suite), mock.patch("sys.argv", ["run-parent-regression.py", "--suite", suite,
                    "--destination", "fixture-device", "--test-products", "prepared.xctestproducts",
                    "--result-bundle", suite + ".xcresult", "--replay-fixture-host", "inert",
                    "--replay-host-receipt", suite + ".json"]), \
                    mock.patch.object(regression, "run_isolated_replay", return_value=65) as isolated, \
                    mock.patch.object(regression.subprocess, "run", side_effect=AssertionError("No native execution")), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(regression.main(), 65)
                self.assertEqual(isolated.call_count, 1)
                keywords = isolated.call_args.kwargs
                self.assertEqual(keywords["suite"], suite)
                command = keywords["command"]
                self.assertEqual([x for x in command if x.startswith("-only-testing:")], ["-only-testing:" + identifier])
                for flag, value in [("-test-timeouts-enabled", "YES"),
                                    ("-default-test-execution-time-allowance", "600"),
                                    ("-maximum-test-execution-time-allowance", "900")]:
                    self.assertEqual(command[command.index(flag) + 1], value)

    def test_parent_rejects_inert_opt_in_for_combined_and_ordinary_suites(self):
        for suite in ["replay", "unit", "clip"]:
            with self.subTest(suite=suite), mock.patch("sys.argv", ["run-parent-regression.py", "--suite", suite,
                    "--destination", "fixture-device", "--test-products", "prepared.xctestproducts",
                    "--result-bundle", "result.xcresult", "--replay-fixture-host", "inert",
                    "--replay-host-receipt", "receipt.json"]), \
                    mock.patch.object(regression, "run_isolated_replay", side_effect=AssertionError("No isolated dispatch")), \
                    mock.patch.object(regression.subprocess, "run", side_effect=AssertionError("No native execution")), \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()), \
                    self.assertRaises(SystemExit):
                regression.main()


    def dispatch_isolated(self, *, native_exit=0, admission_change=None, manifest_change=None,
                          malformed_json=False, export_exit=0, mutate_info=False, timeout_policy=()):
        with self.products() as fixture:
            products, path, original, _, _ = fixture
            result = products / "result.xcresult"
            receipt = products / "host-receipt.json"
            identifier = regression.REPLAY_METHODS["replay-private"]
            url = "test://com.apple.xcode/Wander/" + identifier
            command = ["xcodebuild", "test-without-building", "-quiet", "-testProductsPath", str(products),
                       "-destination", "platform=iOS Simulator,id=fixture-device",
                       "-only-testing:" + identifier, *timeout_policy, "-resultBundlePath", str(result)]
            calls = []
            def run(argv, **kwargs):
                calls.append((argv, kwargs))
                if argv[0] == "xcodebuild":
                    self.assertEqual(argv, command, "Do not change the caller's timeout policy or native selection.")
                    effective = plistlib.loads(path.read_bytes())
                    self.assertEqual(effective["WanderTests"]["CommandLineArguments"],
                                     ["-WanderReplayFixtureHost", "inert"])
                    result.mkdir()
                    (result / "Info.plist").write_bytes(b"fictional immutable result identity")
                    return SimpleNamespace(returncode=native_exit)
                self.assertEqual(argv[:4], ["xcrun", "xcresulttool", "export", "attachments"])
                self.assertEqual(argv[argv.index("--test-id") + 1], url)
                self.assertEqual(path.read_bytes(), original, "Restore host configuration before exporting evidence.")
                self.assertEqual(kwargs.get("timeout"), 120)
                output = Path(argv[argv.index("--output-path") + 1])
                output.mkdir()
                value = self.admission()
                if admission_change:
                    value.update(admission_change)
                (output / "admission.json").write_bytes(b"{" if malformed_json else json.dumps(value).encode())
                manifest = [{"testIdentifierURL": url, "attachments": [{
                    "suggestedHumanReadableName": "Replay host admission_0_00000000-0000-0000-0000-000000000001.txt",
                    "deviceId": "fixture-device", "exportedFileName": "admission.json"}]}]
                if manifest_change:
                    manifest_change(manifest)
                (output / "manifest.json").write_text(json.dumps(manifest))
                if mutate_info:
                    (result / "Info.plist").write_bytes(b"fictional changed result identity")
                return SimpleNamespace(returncode=export_exit)
            with mock.patch.object(regression.subprocess, "run", side_effect=run):
                code = regression.run_isolated_replay(suite="replay-private", products=products,
                    device_id="fixture-device", result_bundle=result, command=command, receipt=receipt)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(sum(argv[0] == "xcodebuild" for argv, _ in calls), 1)
            self.assertEqual(sum(argv[0] == "xcrun" for argv, _ in calls), 1)
            return code, json.loads(receipt.read_text()), calls

    def test_isolated_api_preserves_native_failure_and_all_three_timeout_policies(self):
        policies = [(), ("-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "120",
                         "-maximum-test-execution-time-allowance", "180"),
                    ("-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "600",
                     "-maximum-test-execution-time-allowance", "900")]
        for policy in policies:
            with self.subTest(policy=policy):
                code, receipt, _ = self.dispatch_isolated(native_exit=65, timeout_policy=policy)
                self.assertEqual(code, 65, "Valid host admission must never clear a native failure.")
                self.assertTrue(receipt["hostAdmissionVerified"])
                self.assertTrue(receipt["configuration"]["restored"])
                self.assertEqual(receipt["nativeExitCode"], 65)

    def test_isolated_api_requires_actual_unique_timely_admission_after_native_pass(self):
        changes = [
            {"admission_change": {"requested": False, "mode": "ordinary"}},
            {"admission_change": {"elapsed_ms": 10000}},
            {"admission_change": {"ordinary_root_mounted": True}},
            {"malformed_json": True},
            {"manifest_change": lambda rows: rows[0].update(attachments=[])},
            {"manifest_change": lambda rows: rows[0]["attachments"].append(copy.deepcopy(rows[0]["attachments"][0]))},
            {"manifest_change": lambda rows: rows[0].update(testIdentifierURL="test://com.apple.xcode/Wander/OtherTests/testOther")},
            {"manifest_change": lambda rows: rows[0]["attachments"][0].update(deviceId="other-device")},
            {"export_exit": 64}, {"mutate_info": True},
        ]
        for index, arguments in enumerate(changes):
            with self.subTest(index=index):
                code, receipt, _ = self.dispatch_isolated(**arguments)
                self.assertNotEqual(code, 0)
                self.assertFalse(receipt["hostAdmissionVerified"])
                self.assertEqual(receipt["nativeExitCode"], 0)
                self.assertTrue(receipt["configuration"]["restored"])

    def test_isolated_api_accepts_native_pass_only_with_actual_admission_and_restoration(self):
        code, receipt, _ = self.dispatch_isolated()
        self.assertEqual(code, 0)
        self.assertTrue(receipt["hostAdmissionVerified"])
        self.assertTrue(receipt["configuration"]["restored"])
        self.assertEqual(receipt["identifier"], regression.REPLAY_METHODS["replay-private"])
        self.assertEqual(receipt["admission"], self.admission())

    def test_isolated_api_rejects_wrong_selector_and_retries_before_native_execution(self):
        with self.products() as fixture:
            products, _, _, _, _ = fixture
            result = products / "result.xcresult"
            receipt = products / "host.json"
            command = ["xcodebuild", "test-without-building", "-testProductsPath", str(products),
                       "-destination", "platform=iOS Simulator,id=fixture-device",
                       "-only-testing:" + regression.REPLAY_METHODS["replay-private"],
                       "-resultBundlePath", str(result)]
            variants = [command + ["-retry-tests-on-failure"],
                        command + ["-only-testing:" + regression.REPLAY_METHODS["replay-credentials"]],
                        [x.replace("platform=iOS Simulator,id=fixture-device", "platform=iOS Simulator,id=other-device") for x in command]]
            for variant in variants:
                with self.subTest(command=variant), self.assertRaises(ValueError), \
                        mock.patch.object(regression.subprocess, "run", side_effect=AssertionError("No native execution")):
                    regression.run_isolated_replay(suite="replay-private", products=products,
                        device_id="fixture-device", result_bundle=result, command=variant, receipt=receipt)
            self.assertFalse(receipt.exists())

    def test_context_rejects_configuration_file_symlink_even_inside_products(self):
        with self.products() as fixture:
            products, path, original, _, _ = fixture
            target = products / "real.xctestrun"
            path.rename(target)
            path.symlink_to(target.name)
            with self.assertRaises(ValueError):
                with regression.replay_fixture_host(products):
                    self.fail("A configuration-file symlink must not yield")
            self.assertEqual(target.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
