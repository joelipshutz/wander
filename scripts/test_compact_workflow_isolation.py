"""Compact UI scheduling and stable native gates; no native commands are run."""
import contextlib
import io
import itertools
import json
import os
from pathlib import Path
import re
import tempfile
import textwrap
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
FEED = "feed-checkin-validation.yml"
PRIVACY = "privacy-validation.yml"
FEED_MODES = ["COMPACT_ONLY", "UNPASSED_ONLY", "CONTINUITY_ONLY", "CONTINUITY_REMAINING_ONLY"]
FEED_SELECTORS = [
    "WanderUITests/FeedPaginationUITests",
    "WanderUITests/FeedConsolidationUITests/testRecentActivityOpensConversationAndAcknowledgesSharedBadge",
    "WanderUITests/FeedConsolidationUITests/testUnseenDotsClearOnlyAfterBrowsingAndPersistAcrossReopening",
    "WanderUITests/LiveDrawerActionsUITests",
    "WanderUITests/MapFilterInteractionUITests/testMoreFiltersHidesMapDockAndBottomNavigationDismissesWithoutResetting",
    "WanderUITests/FeedActivityGroupingUITests/testFeedRatingsStayAtTopRightForShortAndLongPlaceNames",
    "WanderUITests/FeedActivityGroupingUITests/testFeedPhotoStackPagesAndReturnsWithoutOpeningProfileOrPlace",
    "WanderUITests/FeedActivityGroupingUITests/testFeedOmitsPhotoStackWhenSaveHasNoPhotos",
]
PRIVACY_SELECTORS = [
    "WanderUITests/MapPlaceCardUITests/testPrivacyRatingsKeepAllThreeSlotsOnAnUnratedPlace",
    "WanderUITests/MapPlaceCardUITests/testPrivacyRatingsRemainReadableAtAccessibilityTextSize",
    "WanderUITests/LiveMigrationAndPrivacyUITests/testPrivateInboxAppSwitcherSnapshotHidesParticipantAndPreview",
    "WanderUITests/LiveMigrationAndPrivacyUITests/testPrivateThreadAppSwitcherSnapshotHidesDraftAndRetainsItOnReturn",
]


def workflow(name):
    source = (ROOT / ".github/workflows" / name).read_text()
    body = source.split("\njobs:\n", 1)[1]
    headers = list(re.finditer(r"(?m)^  ([\w-]+):\n", body))
    jobs = {match.group(1): body[match.end():headers[index + 1].start() if index + 1 < len(headers) else len(body)]
            for index, match in enumerate(headers)}
    return source, jobs


def step(job, name):
    return job.split("      - name: " + name + "\n", 1)[1].split("\n      - ", 1)[0]


def python_body(body, marker):
    return textwrap.dedent(body.split("python3 - <<'" + marker + "'\n", 1)[1].split("          " + marker, 1)[0])


def worker_runs(job, modes):
    match = re.search(r"(?m)^    if: \$\{\{ (.*?) \}\}$", job)
    if match is None:
        return True
    expression = re.sub(r"inputs\.(\w+)", lambda m: str(modes.get(m.group(1).upper(), False)), match.group(1))
    expression = expression.replace("&&", " and ").replace("||", " or ").replace("!", " not ")
    return eval(expression, {"__builtins__": {}}, {})


class CompactWorkflowIsolationTests(unittest.TestCase):
    def gate(self, name, modes, results, event="workflow_dispatch"):
        _, jobs = workflow(name)
        script = python_body(jobs["native"], "PY_NATIVE_GATE")
        environment = {"EVENT_NAME": event, **{key: str(value).lower() for key, value in modes.items()}, **results}
        with mock.patch.dict(os.environ, environment, clear=True), contextlib.redirect_stdout(io.StringIO()):
            try:
                exec(compile(script, name + ":native-gate", "exec"), {})
            except SystemExit:
                return False
        return True

    def test_workers_are_independent_and_existing_native_name_is_always_evaluated(self):
        for name in (FEED, PRIVACY):
            with self.subTest(workflow=name):
                source, jobs = workflow(name)
                for key, budget in (("native-main", 100), ("native-compact", 60)):
                    self.assertNotIn("    needs:", jobs[key])
                    self.assertIn("    runs-on: macos-26\n", jobs[key])
                    self.assertIn(f"    timeout-minutes: {budget}\n", jobs[key])
                    self.assertNotIn("continue-on-error", jobs[key])
                self.assertIn("    if: ${{ always() }}\n", jobs["native"])
                self.assertIn("    needs: [native-main, native-compact]\n", jobs["native"])
                self.assertIn("    timeout-minutes: 5\n", jobs["native"])
                self.assertNotIn("xcodebuild", jobs["native"])
                self.assertIn("'scripts/test_compact_workflow_isolation.py'", source)
                self.assertIn("python3 -B -m unittest discover -s scripts -p test_compact_workflow_isolation.py", jobs["native-compact"])

    def test_ordinary_pr_and_push_require_both_successful_workers(self):
        states = ("success", "failure", "cancelled", "skipped", "")
        for name, event, main, compact in itertools.product((FEED, PRIVACY), ("pull_request", "push"), states, states):
            with self.subTest(workflow=name, event=event, main=main, compact=compact):
                self.assertEqual(self.gate(name, {}, {"MAIN_RESULT": main, "COMPACT_RESULT": compact}, event),
                                 main == compact == "success")

    def test_feed_modes_match_worker_routing_and_exclusions_cannot_hide_failures(self):
        _, jobs = workflow(FEED)
        for enabled in [None, *FEED_MODES]:
            modes = {key: key == enabled for key in FEED_MODES}
            expected = {"MAIN_RESULT": worker_runs(jobs["native-main"], modes),
                        "COMPACT_RESULT": worker_runs(jobs["native-compact"], modes)}
            results = {key: "success" if needed else "skipped" for key, needed in expected.items()}
            with self.subTest(mode=enabled):
                self.assertTrue(self.gate(FEED, modes, results))
                for key in results:
                    for state in ("success", "failure", "cancelled", "skipped", ""):
                        if state != results[key]:
                            self.assertFalse(self.gate(FEED, modes, {**results, key: state}))
                if enabled is not None:
                    self.assertFalse(self.gate(FEED, modes, results, "pull_request"))
        for values in itertools.product((False, True), repeat=4):
            if sum(values) > 1:
                self.assertFalse(self.gate(FEED, dict(zip(FEED_MODES, values)),
                                          {"MAIN_RESULT": "skipped", "COMPACT_RESULT": "skipped"}))

    def test_privacy_recovery_excludes_only_main_and_still_requires_compact(self):
        _, jobs = workflow(PRIVACY)
        for recovery in (False, True):
            modes = {"COMPACT_PRIVACY_RECOVERY_ONLY": recovery}
            self.assertEqual(worker_runs(jobs["native-main"], modes), not recovery)
            self.assertTrue(worker_runs(jobs["native-compact"], modes))
            expected_main = "skipped" if recovery else "success"
            for main, compact in itertools.product(("success", "failure", "cancelled", "skipped", ""), repeat=2):
                self.assertEqual(self.gate(PRIVACY, modes, {"MAIN_RESULT": main, "COMPACT_RESULT": compact}),
                                 main == expected_main and compact == "success")
            if recovery:
                self.assertFalse(self.gate(PRIVACY, modes, {"MAIN_RESULT": "skipped", "COMPACT_RESULT": "success"}, "pull_request"))

    def test_compact_commands_keep_exact_selectors_device_and_original_deadlines(self):
        for name, title, selectors, device, result in [
            (FEED, "Verify scrolling on a compact phone", FEED_SELECTORS, "SMALL_DEVICE_ID", "small"),
            (PRIVACY, "Repeat native screen flows on compact iPhone 16e", PRIVACY_SELECTORS, "COMPACT_DEVICE_ID", "compact"),
            (PRIVACY, "Verify remaining Inbox and Thread privacy flows on compact iPhone 16e", PRIVACY_SELECTORS[2:], "COMPACT_DEVICE_ID", "compact"),
        ]:
            with self.subTest(workflow=name, step=title):
                _, jobs = workflow(name)
                command = step(jobs["native-compact"], title)
                self.assertEqual(re.findall(r"-only-testing:([^\s]+)", command), selectors)
                self.assertIn('xcodebuild test -quiet -project Wander.xcodeproj -scheme Wander', command)
                self.assertIn('-destination "platform=iOS Simulator,id=$' + device + '"', command)
                self.assertIn('-derivedDataPath "$RUNNER_TEMP/DerivedData" -jobs 2 -parallel-testing-enabled NO', command)
                self.assertIn('-resultBundlePath "$RUNNER_TEMP/' + result + '.xcresult" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- GENERATE_INFOPLIST_FILE=YES', command)
                for forbidden in ("-skip-testing", "-retry-tests", "-test-iterations", "GCC_OPTIMIZATION_LEVEL", "SWIFT_OPTIMIZATION_LEVEL"):
                    self.assertNotIn(forbidden, command)
                if name == PRIVACY:
                    self.assertIn('-test-timeouts-enabled YES -default-test-execution-time-allowance 120', command)
                    self.assertIn('-maximum-test-execution-time-allowance 180', command)
                else:
                    self.assertNotIn('-test-execution-time-allowance', command)
                self.assertNotIn(title, jobs["native-main"])

    def test_compact_device_selection_keeps_original_models_and_runtime_preference(self):
        for name, devices, expected in [
            (FEED, [("iPhone SE (3rd generation)", "se"), ("iPhone 16e", "16e"), ("iPhone 17e", "17e")], "17e-new"),
            (FEED, [("iPhone SE (3rd generation)", "se"), ("iPhone 16e", "16e")], "16e-new"),
            (FEED, [("iPhone SE (3rd generation)", "se")], "se-new"),
            (PRIVACY, [("iPhone 17e", "17e"), ("iPhone 16e", "16e")], "16e-new"),
        ]:
            with self.subTest(workflow=name, expected=expected), tempfile.TemporaryDirectory() as directory:
                _, jobs = workflow(name)
                body = step(jobs["native-compact"], "Generate project and select existing compact simulator")
                script = python_body(body, "PY")
                root = Path(directory)
                rows = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-4":
                    [{"name": model, "udid": key + "-old"} for model, key in devices],
                    "com.apple.CoreSimulator.SimRuntime.iOS-26-5":
                    [{"name": model, "udid": key + "-new"} for model, key in devices]}}
                (root / "devices.json").write_text(json.dumps(rows))
                with mock.patch.dict(os.environ, {"RUNNER_TEMP": str(root), "GITHUB_ENV": str(root / "env")}), \
                        contextlib.redirect_stdout(io.StringIO()):
                    exec(compile(script, name + ":device-selection", "exec"), {})
                variable = "SMALL_DEVICE_ID" if name == FEED else "COMPACT_DEVICE_ID"
                self.assertEqual((root / "env").read_text(), variable + "=" + expected + "\n")

    def test_main_retains_all_stress_and_replay_and_artifacts_remain_separate(self):
        for name in (FEED, PRIVACY):
            _, jobs = workflow(name)
            main, compact = jobs["native-main"], jobs["native-compact"]
            self.assertEqual(len(re.findall(r"--suite import-[\w-]+", main)), 3)
            self.assertEqual(main.count("regression.run_isolated_replay("), 4)
            self.assertNotIn("regression.run_isolated_replay(", compact)
            self.assertNotIn("--suite import-", compact)
            self.assertNotIn("-only-testing:WanderTests", compact)
            self.assertIn("        if: always()", compact)
            if name == FEED:
                self.assertIn("name: feed-checkin-native-evidence", main)
                self.assertIn("name: feed-checkin-compact-evidence", compact)
                self.assertIn("${{ runner.temp }}/small.xcresult", compact)
                self.assertIn("small-summary.json", compact)
                self.assertNotIn("small.xcresult", main)
            else:
                self.assertIn("name: privacy-results", main)
                self.assertIn("name: privacy-compact-results", compact)
                self.assertIn("name: privacy-compact-screens", compact)
                self.assertIn("${{ runner.temp }}/compact.xcresult", compact)
                self.assertIn("compact-summary.json", compact)
                self.assertNotIn("compact.xcresult", main)


if __name__ == "__main__":
    unittest.main()
