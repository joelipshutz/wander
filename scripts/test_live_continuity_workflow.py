"""Exercise the workflow's actual continuity exporter without native commands."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
from types import SimpleNamespace
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/feed-checkin-validation.yml"
REGRESSIONS = [
    "SenderNotificationFlowUITests/testLargeTextAndDarkNativeControls()",
    "YourMapPrototypeUITests/testAdaptiveMapKeepsEveryPlaceAndExpandsAllDotsAtCloseZoom()",
]
RECOVERY = {
    "large": ["LiveExperienceUITests/testLiveAutomaticPaginationReachesTerminalBufferedPage()", REGRESSIONS[0]],
    "compact": ["LiveExperienceUITests/testLiveAutomaticPaginationReachesTerminalBufferedPage()", REGRESSIONS[0],
                "LiveDrawerAndFilterUITests/testEveryDrawerDetentAndNativeMapPanKeepTheLoadedActivity()"],
}


def selected_class_methods():
    source = (ROOT / "WanderUITests/LiveReviewContinuityUITests.swift").read_text()
    classes = list(re.finditer(r"(?m)^final class (\w+): XCTestCase \{", source))
    result = []
    for index, match in enumerate(classes):
        if match.group(1) not in {"LiveReviewContinuityUITests", "LiveDrawerAndFilterUITests"}:
            continue
        body = source[match.end():classes[index + 1].start() if index + 1 < len(classes) else len(source)]
        result.extend(match.group(1) + "/" + method + "()" for method in
                      re.findall(r"(?m)^\s+func (test\w+)\(", body))
    return result


class LiveContinuityWorkflowTests(unittest.TestCase):
    def run_exporter(self, *, remaining=False, mutation=None):
        source = WORKFLOW.read_text()
        script = textwrap.dedent(source.split("          python3 - <<'PY_EVIDENCE'\n", 1)[1]
                                 .split("          PY_EVIDENCE", 1)[0])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for label in ("large", "compact"):
                (root / f"live-continuity-{label}.xcresult").mkdir()
            commands = []

            def run(command, **kwargs):
                commands.append(command)
                self.assertEqual(command[:2], ["xcrun", "xcresulttool"])
                if command[2:4] == ["export", "attachments"]:
                    return SimpleNamespace(returncode=0)
                self.assertEqual(command[2:4], ["get", "test-results"])
                label = "large" if "-large.xcresult" in command[command.index("--path") + 1] else "compact"
                identifiers = list(RECOVERY[label] if remaining else selected_class_methods() + REGRESSIONS)
                cases = [{"nodeType": "Test Case", "nodeIdentifier": identifier, "result": "Passed",
                          "nodeIdentifierURL": "test://com.apple.xcode/Wander/WanderUITests/" + identifier.removesuffix("()")}
                         for identifier in identifiers]
                if mutation is not None:
                    mutation(label, cases)
                device = {"deviceId": label + "-device", "platform": "iOS Simulator"}
                counts = {"passedTests": sum(row["result"] == "Passed" for row in cases),
                          "failedTests": sum(row["result"] == "Failed" for row in cases),
                          "skippedTests": sum(row["result"] == "Skipped" for row in cases), "expectedFailures": 0}
                summary = {"result": "Passed" if counts["passedTests"] == len(cases) else "Failed",
                           "totalTestCount": len(cases), **counts,
                           "devicesAndConfigurations": [{"device": device, **counts}]}
                document = summary if command[4] == "summary" else {"testNodes": cases, "devices": [device]}
                return SimpleNamespace(returncode=0, stdout=json.dumps(document), stderr="")

            error = None
            with mock.patch.dict(os.environ, {"RUNNER_TEMP": str(root),
                    "CONTINUITY_REMAINING_ONLY": str(remaining).lower(), "LARGE_DEVICE_ID": "large-device",
                    "SMALL_DEVICE_ID": "compact-device"}), mock.patch.object(subprocess, "run", side_effect=run):
                try:
                    exec(compile(script, str(WORKFLOW) + ":evidence", "exec"), {})
                except SystemExit as stopped:
                    error = str(stopped)
            evidence = root / "live-continuity-evidence"
            coverage = json.loads((evidence / "expected-coverage.json").read_text())
            proofs = {label: json.loads((evidence / f"{label}-named-case-proof.json").read_text())
                      for label in ("large", "compact")}
            self.assertEqual(len(commands), 6)  # Both phones are checked, even after the first failure.
            return error, coverage, proofs

    def test_full_selected_source_inventory_requires_ten_distinct_passes_per_phone(self):
        source = WORKFLOW.read_text()
        methods = selected_class_methods()
        self.assertEqual(len(methods), 8)
        self.assertEqual(len(set(methods)), 8)
        self.assertIn("'scripts/test_live_continuity_workflow.py'", source)
        self.assertIn("python3 -B -m unittest discover -s scripts -p test_live_continuity_workflow.py", source)
        for class_name in ("LiveReviewContinuityUITests", "LiveDrawerAndFilterUITests"):
            self.assertEqual(source.count("-only-testing:WanderUITests/" + class_name + "\n"), 2)
        error, coverage, proofs = self.run_exporter()
        self.assertIsNone(error)
        self.assertEqual(coverage["expectedCasesPerDevice"], len(methods) + len(REGRESSIONS))
        for proof in proofs.values():
            self.assertEqual(set(proof["requiredContinuityCases"]), set(methods))
            self.assertEqual(set(proof["requiredRegressionCases"]), set(REGRESSIONS))
            self.assertTrue(proof["allSelectedCasesAccountedFor"])
            self.assertTrue(proof["continuityAllPassed"])

    def test_missing_either_edge_case_cannot_pass(self):
        for edge in ("Leading", "Trailing"):
            with self.subTest(edge=edge):
                error, _, _ = self.run_exporter(mutation=lambda label, cases:
                    cases.__setitem__(slice(None), [row for row in cases if f"testFilters{edge}Edge" not in row["nodeIdentifier"]]))
                self.assertIsNotNone(error)

    def test_duplicate_unexpected_skipped_and_failed_cases_cannot_pass(self):
        def duplicate(label, cases):
            cases[-1] = dict(cases[0])
        def unexpected(label, cases):
            cases[0]["nodeIdentifier"] = "OtherUITests/testOther()"
        def skipped(label, cases):
            cases[0]["result"] = "Skipped"
        def failed(label, cases):
            cases[0]["result"] = "Failed"
        for mutate in (duplicate, unexpected, skipped, failed):
            with self.subTest(mutation=mutate.__name__):
                error, _, _ = self.run_exporter(mutation=mutate)
                self.assertIsNotNone(error)

    def test_passing_compact_phone_cannot_hide_large_failure(self):
        def fail_large(label, cases):
            if label == "large":
                cases[0]["result"] = "Failed"
        error, _, proofs = self.run_exporter(mutation=fail_large)
        self.assertIn("large:", error)
        self.assertNotIn("compact:", error)
        self.assertTrue(proofs["compact"]["allSelectedCasesAccountedFor"])

    def test_existing_recovery_keeps_its_exact_two_and_three_cases(self):
        error, coverage, proofs = self.run_exporter(remaining=True)
        self.assertIsNone(error)
        self.assertEqual(coverage["expectedCasesByDevice"], {"large": 2, "compact": 3})
        for label, proof in proofs.items():
            self.assertEqual(proof["expectedCaseCount"], len(RECOVERY[label]))
            self.assertEqual(set(proof["requiredRegressionCases"]) | set(proof["requiredContinuityCases"]), set(RECOVERY[label]))
            self.assertTrue(proof["deviceMatched"])
            self.assertTrue(proof["fullNativeIdentifiersMatched"])


if __name__ == "__main__":
    unittest.main()
