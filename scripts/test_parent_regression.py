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
                    for name in re.findall(r"\bfunc\s+(test\w*)\s*\(", source)]
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
                mock.patch.object(regression, "ui_test_identifiers", return_value=sorted({identifier} | regression.ISOLATED_UI_PERFORMANCE | regression.REFERENCE_UI_PERFORMANCE)), \
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
        hosted = regression.ISOLATED_UI_PERFORMANCE
        reference = regression.REFERENCE_UI_PERFORMANCE
        self.assertFalse(hosted & reference)
        self.assertTrue((hosted | reference).issubset(inventory))
        ordinary = [test for shard in range(8) for test in inventory[shard::8]
                    if test not in hosted | reference]
        self.assertEqual(Counter(ordinary + sorted(hosted) + sorted(reference)), Counter(inventory))

    def test_both_formats_preserve_selection_binaries_and_unit_configuration(self):
        for version, preserve_failures in ((1, False), (2, False), (1, True), (2, True)):
            with self.subTest(version=version, preserve_failures=preserve_failures), tempfile.TemporaryDirectory() as temporary:
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
                expected_ui.update(PreferredScreenCaptureFormat="screenshots",
                                   SystemAttachmentLifetime="deleteOnSuccess" if preserve_failures else "keepNever")
                (root / "Info.plist").write_bytes(plistlib.dumps({
                    "Tests": [{"xctestrun": "tests.plist"}]}))
                configuration = root / "tests.plist"
                configuration.write_bytes(plistlib.dumps(document))
                self.assertEqual(regression.prepare_ui_performance_products(root, preserve_failures), 1)
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


if __name__ == "__main__":
    unittest.main()
