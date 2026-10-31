"""Required 1500-row import stress routing. All native commands are mocked."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("file_performance_runner", ROOT / "scripts/run-parent-regression.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
METHODS = {
    "import-file-performance": "WanderTests/ImportAutoSaveFileResponsivenessTests/testPerformanceFileAutoSaveWith1500ResolvedRowsAndList",
    "import-autosave-performance": "WanderTests/ImportAutoSavePerformanceTests/testPerformanceGoogleWannaAutoSaveWith1500ResolvedRows",
    "import-autosave-no-list-performance": "WanderTests/ImportAutoSaveWithoutListPerformanceTests/testPerformanceGoogleWannaAutoSaveWithoutListWith1500ResolvedRows",
}
WORKFLOW_CASES = {
    "import-file-performance": ("Required 1500-row file import performance", "ImportFilePerformance"),
    "import-autosave-performance": ("Required 1500-row automatic import performance", "ImportAutoSavePerformance"),
    "import-autosave-no-list-performance": ("Required 1500-row automatic import without list performance", "ImportAutoSaveWithoutListPerformance"),
}


class ImportPerformanceRoutingTests(unittest.TestCase):
    def test_contact_job_has_privacy_budget_for_required_serial_stress_and_replay(self):
        def native_job(name, job="native"):
            source = (ROOT / ".github/workflows" / name).read_text()
            return re.split(r"\n  [\w-]+:\n", source.split("\n  " + job + ":\n", 1)[1], maxsplit=1)[0]
        contact = native_job("contact-discovery-validation.yml")
        privacy = native_job("privacy-validation.yml", "native-main")
        budget = lambda job: int(re.search(r"^    timeout-minutes: (\d+)$", job, re.MULTILINE).group(1))
        self.assertEqual(budget(contact), 100)
        self.assertEqual(budget(contact), budget(privacy))
        self.assertEqual(contact.count('"-default-test-execution-time-allowance", "120"'), 4)
        self.assertEqual(contact.count('"-maximum-test-execution-time-allowance", "180"'), 4)

    def selection(self, suite):
        output = io.StringIO()
        with mock.patch("sys.argv", ["runner", "--suite", suite, "--list-only"]), \
                mock.patch.object(runner.subprocess, "run", side_effect=AssertionError("No native work")), \
                contextlib.redirect_stdout(output):
            self.assertEqual(runner.main(), 0)
        return json.loads(output.getvalue())

    def test_exact_three_stress_cases_move_and_500_cases_stay_ordinary(self):
        self.assertEqual(runner.IMPORT_PERFORMANCE_METHODS, METHODS)
        unit = self.selection("unit")
        self.assertEqual(unit["identifiers"], ["WanderTests"])
        for suite, method in METHODS.items():
            with self.subTest(suite=suite):
                selection = self.selection(suite)
                self.assertEqual(selection["identifiers"], [method])
                self.assertEqual(selection["isolatedTestSuites"], {})
                self.assertEqual(unit["isolatedTestSuites"][method], suite)
                self.assertNotIn(method.rsplit("/", 1)[0], unit["isolatedTestSuites"])
                self.assertNotIn(method.replace("1500", "500"), unit["isolatedTestSuites"])
                _, case, function = method.split("/")
                source = (ROOT / "WanderTests" / (case + ".swift")).read_text()
                self.assertEqual(source.count("func " + function + "()"), 1)

    @staticmethod
    def result(method):
        summary = {"result": "Passed", "totalTestCount": 1, "passedTests": 1, "failedTests": 0,
                   "skippedTests": 0, "expectedFailures": 0, "devicesAndConfigurations": [
                       {"device": {"deviceId": "device", "platform": "iOS Simulator"}}]}
        tests = {"testNodes": [{"nodeType": "Test Case", "result": "Passed",
                                "nodeIdentifier": method.split("/", 1)[1] + "()",
                                "nodeIdentifierURL": "test://com.apple.xcode/Wander/" + method}]}
        return summary, tests

    def dispatch(self, suite, *, products=True, native_exit=0, failure=None):
        method = METHODS[suite]
        with tempfile.TemporaryDirectory() as directory:
            result = Path(directory) / "ImportFilePerformance.xcresult"
            summary, tests = self.result(method)
            if failure == "skip":
                summary.update(passedTests=0, skippedTests=1)
            if failure == "empty":
                summary.update(passedTests=0, totalTestCount=0)
                tests["testNodes"] = []
            if failure == "wrong-method":
                tests["testNodes"][0]["nodeIdentifier"] = "Different/testMethod()"
            commands = []
            def run(command, **kwargs):
                commands.append(command)
                if command[0] == "xcodebuild":
                    return SimpleNamespace(returncode=native_exit)
                kind = command[4]
                self.assertEqual(command[:4], ["xcrun", "xcresulttool", "get", "test-results"])
                self.assertEqual(kwargs["timeout"], 120)
                if failure == "timeout" and kind == "summary":
                    raise subprocess.TimeoutExpired(command, 120)
                kwargs["stdout"].write(b"{" if failure == "malformed" and kind == "summary" else
                                       json.dumps(summary if kind == "summary" else tests).encode())
                return SimpleNamespace(returncode=1 if failure == "export" and kind == "summary" else 0)
            arguments = ["runner", "--suite", suite, "--destination", "device",
                         "--result-bundle", str(result), "--selection-file", str(Path(directory) / "selection.json")]
            arguments += ["--test-products", "Parent.xctestproducts"] if products else ["--derived-data", "DerivedData"]
            with mock.patch("sys.argv", arguments), mock.patch.object(runner.subprocess, "run", side_effect=run), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = runner.main()
            self.assertEqual(len(commands), 3)
            self.assertEqual(commands[1][4], "summary")
            self.assertEqual(commands[2][4], "tests")
            self.assertTrue(result.with_suffix(".summary.json").is_file())
            self.assertTrue(result.with_suffix(".tests.json").is_file())
            self.assertEqual(json.loads((Path(directory) / "selection.json").read_text())["identifiers"], [method])
            return code, commands[0]

    def test_ordinary_products_and_derived_dispatch_preserve_existing_performance_allowance(self):
        for suite, method in METHODS.items():
            for products in [True, False]:
                with self.subTest(suite=suite, products=products):
                    code, command = self.dispatch(suite, products=products)
                    self.assertEqual(code, 0)
                    self.assertEqual(command[:2], ["xcodebuild", "test-without-building" if products else "test"])
                    self.assertEqual([x for x in command if x.startswith("-only-testing:")], ["-only-testing:" + method])
                    self.assertFalse(any(x.startswith(("-skip-testing", "-test-iterations", "-retry-tests", "GCC_OPTIMIZATION_LEVEL", "SWIFT_OPTIMIZATION_LEVEL")) for x in command))
                    for flag, value in [("-default-test-execution-time-allowance", "600"),
                                        ("-maximum-test-execution-time-allowance", "900"),
                                        ("-parallel-testing-enabled", "NO")]:
                        self.assertEqual(command[command.index(flag) + 1], value)

    def test_native_failure_cannot_be_cleared_by_a_passing_export(self):
        for suite in METHODS:
            with self.subTest(suite=suite):
                self.assertEqual(self.dispatch(suite, native_exit=65)[0], 65)

    def test_missing_skipped_wrong_malformed_or_unexportable_result_cannot_pass(self):
        for suite in METHODS:
            for failure in ["skip", "empty", "wrong-method", "malformed", "export", "timeout"]:
                with self.subTest(suite=suite, failure=failure):
                    self.assertEqual(self.dispatch(suite, failure=failure)[0], 1)

    def test_performance_dispatch_cannot_request_replay_host(self):
        with mock.patch("sys.argv", ["runner", "--suite", "import-file-performance", "--test-products", "Parent.xctestproducts",
                                     "--replay-fixture-host", "inert", "--list-only"]), \
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as stopped:
            runner.main()
        self.assertEqual(stopped.exception.code, 2)

    def test_all_four_workflows_require_three_separate_runs_and_retain_all_evidence(self):
        for name in ["feed-checkin-validation.yml", "privacy-validation.yml", "contact-discovery-validation.yml", "app-clip-validation.yml"]:
            source = (ROOT / ".github/workflows" / name).read_text()
            for suite, method in METHODS.items():
                with self.subTest(workflow=name, suite=suite):
                    title, result = WORKFLOW_CASES[suite]
                    self.assertEqual(source.count("--suite " + suite + " "), 1)
                    block = source.split("      - name: " + title + "\n", 1)[1].split("\n      - ", 1)[0]
                    self.assertIn("success() || failure()", block)
                    self.assertNotIn("continue-on-error", block)
                    self.assertNotIn("Replay.xctestproducts", block)
                    self.assertNotIn("GCC_OPTIMIZATION_LEVEL", block)
                    if name == "app-clip-validation.yml":
                        self.assertIn("matrix.suite == 'unit'", block)
                        self.assertIn('--test-products "$RUNNER_TEMP/Parent.xctestproducts"', block)
                    else:
                        self.assertIn('--derived-data "$RUNNER_TEMP/DerivedData"', block)
                        self.assertEqual(source.count("-skip-testing:" + method), 1)
                        self.assertNotIn("-skip-testing:" + method.replace("1500", "500"), source)
                    if name == "feed-checkin-validation.yml":
                        self.assertIn("!inputs.compact_only && !inputs.unpassed_only", block)
                    if name == "privacy-validation.yml":
                        self.assertIn("!inputs.compact_privacy_recovery_only", block)
                    for filename in [result + ".xcresult", result + ".summary.json", result + ".tests.json", suite + "-selection.json"]:
                        self.assertIn("${{ runner.temp }}/" + filename, source)
                    self.assertIn("'scripts/test_import_performance_routing.py'", source)
                    self.assertIn("'WanderTests/" + method.split("/")[1] + ".swift'", source)


if __name__ == "__main__":
    unittest.main()
