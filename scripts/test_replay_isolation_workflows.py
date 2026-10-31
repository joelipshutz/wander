"""Replay isolation inventory and workflow execution contracts; no native work."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import re
import tempfile
import textwrap
from types import SimpleNamespace
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("parent_regression", ROOT / "scripts/run-parent-regression.py")
regression = importlib.util.module_from_spec(spec)
spec.loader.exec_module(regression)

WORKFLOWS = ["feed-checkin-validation.yml", "privacy-validation.yml",
             "contact-discovery-validation.yml", "app-clip-validation.yml"]
EXTRA = {
    "replay-feed": "WanderTests/FeedScreenScrollingPerformanceTests/testPerformanceMountedFeedScrollWith600EventsAndActualReplay",
    "replay-masked-scroll": "WanderTests/PostHogReplayPerformanceTests/testPerformanceActualReplayMaskedScroll",
}


def steps(name):
    source = (ROOT / ".github/workflows" / name).read_text()
    return source, re.findall(r"^      - name: ([^\n]+)\n(.*?)(?=^      - |^  [a-zA-Z]|\Z)",
                             source, flags=re.M | re.S)


def python_body(block):
    match = re.search(r"python3 - <<'([A-Z_]+)'\n(.*?)\n          \1(?:\n|$)", block, re.S)
    if not match:
        raise AssertionError("Missing bounded Python workflow dispatch")
    return textwrap.dedent(match[2])


class ReplayWorkflowIsolationTests(unittest.TestCase):
    def test_allowlist_has_exactly_four_sdk_methods_and_keeps_pure_cases_ordinary(self):
        self.assertEqual(regression.REPLAY_METHODS, {
            "replay-private": "WanderTests/ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage",
            "replay-credentials": "WanderTests/ReplayMaskingTests/testReadableContentAndCredentialMaskingInActualReplayImage",
            **EXTRA,
        })
        output = io.StringIO()
        with mock.patch("sys.argv", ["runner", "--suite", "unit", "--list-only"]), \
                contextlib.redirect_stdout(output), mock.patch.object(regression.subprocess, "run", side_effect=AssertionError("No native work")):
            self.assertEqual(regression.main(), 0)
        import json
        isolated = json.loads(output.getvalue())["isolatedTestSuites"]
        for suite, identifier in EXTRA.items():
            self.assertEqual(isolated[identifier], suite)
        for identifier in ["WanderTests/FeedScreenScrollingPerformanceTests",
                           "WanderTests/FeedScreenScrollingPerformanceTests/testPerformanceMountedFeedScrollWith600Events",
                           "WanderTests/PostHogReplayPerformanceTests",
                           "WanderTests/PostHogReplayPerformanceTests/testPerformanceActualSDKLayoutCallbacksInsideThrottleWindow",
                           "WanderTests/PostHogReplayPerformanceTests/testActualSDKThrottleCoalescesConcurrentBurstsAndAdmitsNewSubscriber"]:
            self.assertNotIn(identifier, isolated)

    def test_every_sdk_method_uses_the_shared_admission_before_fixture_work(self):
        helper = (ROOT / "WanderTests/ReplayFixtureHostAdmission.swift").read_text()
        self.assertEqual(helper.count("func admitReplayFixtureHostIfRequested"), 1)
        for contract in [".advanced(by: .seconds(10))", "!ReplayFixtureHostPolicy.ordinaryRootMounted",
                         'attachment.name = "Replay host admission"', '"limit_ms": 10_000',
                         "guard admitted else", "XCTFail("]:
            self.assertIn(contract, helper)
        sources = {}
        for identifier in regression.REPLAY_METHODS.values():
            _, case, method = identifier.split("/")
            source = (ROOT / "WanderTests" / (case + ".swift")).read_text()
            sources[case] = source
            body = source.split("func " + method + "()", 1)[1]
            self.assertIn("guard await admitReplayFixtureHostIfRequested() else { return }", body[:250])
            self.assertNotIn("func admitReplayFixtureHostIfRequested", source)
        self.assertEqual(sum(source.count("PostHogSDK.with(config)") for source in sources.values()), 4)
        ordinary_feed = sources["FeedScreenScrollingPerformanceTests"].split(
            "func testPerformanceMountedFeedScrollWith600Events()", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("admitReplayFixtureHostIfRequested", ordinary_feed)
        callbacks = sources["PostHogReplayPerformanceTests"].split("func testPerformanceActualReplayMaskedScroll", 1)[0]
        self.assertNotIn("admitReplayFixtureHostIfRequested", callbacks)

    def test_every_workflow_builds_dedicated_verified_debug_replay_products_only(self):
        for name in WORKFLOWS:
            with self.subTest(workflow=name):
                source, blocks = steps(name)
                builds = [body for title, body in blocks if title in
                          ["Build dedicated Replay products", "Prepare isolated Replay test products once"]]
                self.assertEqual(len(builds), 1)
                build = builds[0]
                for value in ["-configuration Debug", '"$RUNNER_TEMP/ReplayDerivedData"',
                              '"$RUNNER_TEMP/Replay.xctestproducts"', "GCC_OPTIMIZATION_LEVEL=s SWIFT_OPTIMIZATION_LEVEL=-Onone",
                              "scripts/record-replay-compiler-flags.py", "replay-compiler-flags.json"]:
                    self.assertIn(value, build)
                self.assertIn("-only-testing:WanderTests/ReplayMaskingTests", build)
                for identifier in EXTRA.values():
                    self.assertIn("-only-testing:" + identifier, build)
                self.assertEqual(source.count("GCC_OPTIMIZATION_LEVEL=s"), 1,
                                 "C optimization must not leak into ordinary unit builds")
                self.assertIn("'WanderTests/ReplayFixtureHostAdmission.swift'", source)
                self.assertIn("'scripts/test_replay_isolation_workflows.py'", source)
                if name != "app-clip-validation.yml":
                    for identifier in EXTRA.values():
                        self.assertEqual(source.count("-skip-testing:" + identifier), 1)
                    self.assertNotIn("-skip-testing:WanderTests/FeedScreenScrollingPerformanceTests\n", source)
                    self.assertNotIn("-skip-testing:WanderTests/PostHogReplayPerformanceTests\n", source)

    def test_feed_privacy_contact_execute_all_four_exact_methods_and_keep_native_failure(self):
        for name in WORKFLOWS[:3]:
            source, blocks = steps(name)
            dispatches = [(title, body) for title, body in blocks if "regression.run_isolated_replay(" in body]
            self.assertEqual(len(dispatches), 4, name)
            seen = []
            for title, body in dispatches:
                with self.subTest(workflow=name, step=title), tempfile.TemporaryDirectory() as directory:
                    self.assertIn("!cancelled() && steps.replay-products.outcome == 'success'", body)
                    self.assertNotIn("continue-on-error", body)
                    captured = []
                    module = SimpleNamespace(run_isolated_replay=lambda **kwargs: captured.append(kwargs) or 65)
                    fake_spec = SimpleNamespace(loader=SimpleNamespace(exec_module=lambda unused: None))
                    environment = {"RUNNER_TEMP": directory, "LARGE_DEVICE_ID": "device", "PRO_DEVICE_ID": "device",
                                   "TEST_DEVICE_ID": "device", "REPLAY_DEVICE_ID": "device"}
                    with mock.patch.dict(os.environ, environment), \
                            mock.patch.object(importlib.util, "spec_from_file_location", return_value=fake_spec), \
                            mock.patch.object(importlib.util, "module_from_spec", return_value=module):
                        with self.assertRaises(SystemExit) as stopped:
                            exec(compile(python_body(body), name, "exec"), {})
                    self.assertEqual(stopped.exception.code, 65)
                    self.assertEqual(len(captured), 1)
                    call = captured[0]
                    suite = call["suite"]
                    seen.append(suite)
                    command = call["command"]
                    self.assertEqual([x for x in command if x.startswith("-only-testing:")],
                                     ["-only-testing:" + regression.REPLAY_METHODS[suite]])
                    self.assertFalse(any(x.startswith(("-skip-testing", "-test-iterations", "-retry-tests")) for x in command))
                    self.assertEqual(command[:3], ["xcodebuild", "test-without-building", "-quiet"])
                    self.assertEqual(call["products"], Path(directory) / "Replay.xctestproducts")
                    self.assertEqual(call["receipt"], Path(directory) / (suite + "-host.json"))
                    self.assertEqual(call["result_bundle"], Path(directory) / (suite + ".xcresult"))
                    if name != "feed-checkin-validation.yml" or suite in EXTRA:
                        allowance = ("600", "900") if name == "feed-checkin-validation.yml" else ("120", "180")
                        self.assertEqual(command[command.index("-default-test-execution-time-allowance") + 1], allowance[0])
                        self.assertEqual(command[command.index("-maximum-test-execution-time-allowance") + 1], allowance[1])
            self.assertCountEqual(seen, regression.REPLAY_METHODS)
            for suite in seen:
                for suffix in [".xcresult", "-host.json", "-host"]:
                    self.assertIn("${{ runner.temp }}/" + suite + suffix, source)

    def test_parent_transports_separate_products_and_requires_each_case_with_receipt(self):
        source, blocks = steps("app-clip-validation.yml")
        self.assertIn("name: parent-replay-test-products", source)
        self.assertIn("Replay.xctestproducts replay-compiler-flags.json", source)
        self.assertIn("receipt['checkoutCommit']", source)
        found = []
        for title, body in blocks:
            match = re.search(r"--suite (replay-[a-z-]+)\n", body)
            if not match:
                continue
            found.append(match[1])
            self.assertIn("(success() || failure()) && matrix.suite == 'unit'", body)
            self.assertIn('--test-products "$RUNNER_TEMP/Replay.xctestproducts"', body)
            self.assertIn("--replay-fixture-host inert --replay-host-receipt", body)
            self.assertNotIn("continue-on-error", body)
        self.assertCountEqual(found, regression.REPLAY_METHODS)
        gate = dict(blocks)["Summarize and require all replay proofs"]
        self.assertIn("always() && matrix.suite == 'unit'", gate)
        for suite in regression.REPLAY_METHODS:
            self.assertIn('("' + suite + '",', gate)
        self.assertIn("regression.validate_replay_result", gate)


if __name__ == "__main__":
    unittest.main()
