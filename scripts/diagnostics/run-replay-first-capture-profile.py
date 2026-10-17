#!/usr/bin/env python3
"""One canonical private Replay method with one bounded first-capture profile."""
from pathlib import Path
from collections import Counter
from urllib.parse import urlparse, parse_qs, unquote
import argparse, hashlib, json, os, plistlib, re, runpy, selectors, signal, subprocess, sys, time

CASES = [
    ("private", "replay-private", "WanderTests/ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage"),
]
METHOD = CASES[0][2]
URL = "test://com.apple.xcode/Wander/" + METHOD
BUNDLE_ID = "com.grayline.wander"
BASE_HEAD = "22e7c6d9efd4ac0957ed25cd60e8cc26a05bc7f7"
SDK_REVISION = "ee5b5705b0038f0c44646cde5fe972bb65387596"
REPLAY_SHA = "d7ddd82f2f64b3d25fe75dce286240921580e09893601c50a8509bc0132ca4f9"
HOST_SHA = "57c1964ea064f7d2c45007415c3d9efaa6366708e2828f13051f16e1ace2779d"
SOURCE_PROOF_SHA = "88a7e3b59601638ce86d8c204dfa39f858f130250c929eb3710e4810db85f4ac"
RUN_PARENT_SHA = "035266352ba22eb567dd8f8ee4febdfcc949fa80eea26a990609aa2d08dae245"
SDK_FILES = {
    "PostHog/PostHogSDK.swift": "ceeeaf0bf964cc3ca2ba7f6f99067eda375a6802c488d67f64164dce9a1f84b3",
    "PostHog/Replay/PostHogReplayIntegration.swift": "5da5f38816fce2582bddc5cfef80f4ae7e6f51b55b48c268e60b03b69f517d2b",
    "PostHog/Replay/RRWireframe.swift": "f8066ccf8e2b58dda09978d303d1c4ece7df44e0c97f069f411fbbea9a25d704",
    "PostHog/Replay/PostHogGraphicsImageRenderer.swift": "5e82a7e8d528ae0384471c967a4af79b45b81c7c4be19726c930b2d8609bae78",
    "PostHog/Utils/UIImage+WebP.swift": "fac7c87eaa4c0ffd0096881a1495c4bc31457f95e78d887909486146e2cf4876",
}
ROOT = Path.cwd().resolve()
OUT = None
PROFILE = None
CURRENT_ROW = None
NATIVE_RC = None
CURRENT_ADMISSION = None
STOP_CATEGORY = None
PROFILE_HELPER_PATH = "scripts/diagnostics/sample-first-capture.py"
PROFILE_HELPER_SHA = "cb19e89bdd77f139deaf9d986da7d21da986f2c155a9578cfefed0a46f437c26"
OVERALL_DEADLINE = None
class AncillaryExportFailure(RuntimeError): pass

def need(ok, code):
    if not ok: raise RuntimeError(code)


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path): return json.loads(path.read_text())


def save(path, value):
    with path.open("x") as f: json.dump(value, f, indent=2, sort_keys=True); f.write("\n")


def nodes(value, kind):
    if isinstance(value, dict):
        if value.get("nodeType") == kind: yield value
        for child in value.values(): yield from nodes(child, kind)
    elif isinstance(value, list):
        for child in value: yield from nodes(child, kind)


def unwrap(value):
    if isinstance(value, dict):
        if "_value" in value: return value["_value"]
        if "_values" in value: return [unwrap(x) for x in value["_values"]]
        return {k: unwrap(v) for k, v in value.items() if k != "_type"}
    if isinstance(value, list): return [unwrap(x) for x in value]
    return value


def group_exists(process):
    process.poll()  # Reap only our direct child before inspecting its group.
    try: os.killpg(process.pid, 0); return True
    except ProcessLookupError: return False


def cleanup(process, facts):
    if group_exists(process): os.killpg(process.pid, signal.SIGTERM); facts["term"] = True
    deadline = time.monotonic() + 10
    while group_exists(process) and time.monotonic() < deadline: process.poll(); time.sleep(.1)
    if group_exists(process): os.killpg(process.pid, signal.SIGKILL); facts["kill"] = True
    process.wait(timeout=5)
    deadline = time.monotonic() + 5
    while group_exists(process) and time.monotonic() < deadline: time.sleep(.1)
    need(not group_exists(process), "owned_group_cleanup_unconfirmed")
    return {**facts, "cleanupConfirmed": True, "groupGone": True, "leaderExit": process.returncode}


def command(argv, folder, operation, timeout=120, collect=True, input_data=None):
    """Bounded owned group; raw command/environment/stderr are never persisted."""
    need(input_data is None or isinstance(input_data, bytes) and 0 < len(input_data) <= 1024 * 1024, "process_input_bound_exceeded")
    process = subprocess.Popen(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True, **({"stdin": subprocess.PIPE} if input_data is not None else {}))
    began = time.monotonic(); deadline = min(began + timeout, OVERALL_DEADLINE)
    selector = selectors.DefaultSelector()
    for stream, name in [(process.stdout, "stdout"), (process.stderr, "stderr")]:
        os.set_blocking(stream.fileno(), False); selector.register(stream, selectors.EVENT_READ, name)
    input_offset = 0
    if input_data is not None:
        os.set_blocking(process.stdin.fileno(), False); selector.register(process.stdin, selectors.EVENT_WRITE, "stdin")
    input_facts = {} if input_data is None else {"inputBytes": len(input_data), "inputSHA256": hashlib.sha256(input_data).hexdigest()}
    hashes = {k: hashlib.sha256() for k in ["stdout", "stderr"]}
    sizes = Counter(); data = bytearray(); tail = b""; infra = False; denial = False
    try:
        while selector.get_map():
            need(time.monotonic() <= deadline, "owned_process_watchdog_timeout")
            for key, _ in selector.select(min(.5, max(0, deadline - time.monotonic()))):
                if key.data == "stdin":
                    try: input_offset += os.write(key.fileobj.fileno(), input_data[input_offset:input_offset + 65536])
                    except BrokenPipeError: raise RuntimeError("process_input_rejected") from None
                    if input_offset == len(input_data): selector.unregister(key.fileobj); key.fileobj.close()
                    continue
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk: selector.unregister(key.fileobj); continue
                name = key.data; hashes[name].update(chunk); sizes[name] += len(chunk)
                need(sum(sizes.values()) <= 64 * 1024 * 1024, "process_output_bound_exceeded")
                lower = (tail + chunk).lower(); tail = lower[-4096:]
                infra |= any(s in lower for s in [b"test crashed", b"early unexpected exit", b"restarting after unexpected exit", b"lost connection to the test runner", b"failed to establish communication"])
                denial |= any(s in lower for s in [b"permission to save", b"permission denied", b"operation not permitted"])
                if collect and name == "stdout": data.extend(chunk)
        process.wait(timeout=max(.1, deadline - time.monotonic()))
        need(not group_exists(process), "owned_group_still_active")
    except BaseException as error:
        save(folder / (operation + "-process.json"), {"operation": operation,
             "exitCode": process.returncode, "completed": False,
             "category": str(error) if isinstance(error, RuntimeError) else type(error).__name__,
             "errno": getattr(error, "errno", None),
             "elapsedSeconds": time.monotonic() - began, "rawOutputPersisted": False,
             "outputBytes": dict(sizes), "outputSHA256": {k: v.hexdigest() for k, v in hashes.items()}, **input_facts})
        facts = {"ownedGroup": process.pid, "term": False, "kill": False}
        if isinstance(error, PermissionError):
            save(folder / (operation + "-cleanup.json"), {**facts, "cleanupAttempted": False,
                 "cleanupConfirmed": False, "groupGone": None, "leaderExit": process.returncode,
                 "category": "PermissionError", "errno": error.errno})
            raise  # No additional signal or group probe after an observed denial.
        try: facts = cleanup(process, facts)
        except BaseException as cleanup_error:
            save(folder / (operation + "-cleanup.json"), {**facts, "cleanupAttempted": True,
                 "cleanupConfirmed": False, "groupGone": None, "leaderExit": process.returncode,
                 "category": str(cleanup_error) if isinstance(cleanup_error, RuntimeError) else type(cleanup_error).__name__,
                 "errno": getattr(cleanup_error, "errno", None)})
            raise
        save(folder / (operation + "-cleanup.json"), {**facts, "cleanupAttempted": True})
        raise
    finally:
        selector.close()
        if process.stdin is not None and not process.stdin.closed: process.stdin.close()
        process.stdout.close(); process.stderr.close()
    receipt = {"operation": operation, "exitCode": process.returncode,
               "elapsedSeconds": time.monotonic() - began, "outputBytes": dict(sizes),
               "outputSHA256": {k: v.hexdigest() for k, v in hashes.items()},
               "rawOutputPersisted": False, "infrastructureMarker": infra,
               "permissionDenialMarker": denial, **input_facts}
    save(folder / (operation + "-process.json"), receipt)
    need(not denial, "process_permission_denial")
    return process.returncode, bytes(data), receipt


def checked(argv, folder, operation, timeout=120):
    rc, data, _ = command(argv, folder, operation, timeout)
    need(rc == 0, operation + "_failed")
    return data


def tree(products):
    links = {str(p.relative_to(products)): os.readlink(p) for p in products.rglob("*") if p.is_symlink()}
    need(links == {"Tests/0/Debug-iphonesimulator": "../../Binaries/0/Debug-iphonesimulator"}, "unexpected_product_alias")
    need(all((products / name).resolve().is_relative_to(products) for name in links), "product_alias_escape")
    return {str(p.relative_to(products)): sha(p) for p in products.rglob("*") if p.is_file() and not p.is_symlink()}


def parse_listapps(raw, folder, operation):
    """Normalize simctl's JSON or native plist in memory; never persist inventory."""
    need(isinstance(raw, bytes) and 0 < len(raw) <= 1024 * 1024, "listapps_input_bound_exceeded")
    try: rows = json.loads(raw)
    except (ValueError, UnicodeError):
        rc, converted, _ = command(["/usr/bin/plutil", "-convert", "json", "-o", "-", "--", "-"],
                                   folder, operation + "-plist-conversion", timeout=15, input_data=raw)
        need(rc == 0, "listapps_plist_conversion_failed")
        need(0 < len(converted) <= 4 * 1024 * 1024, "listapps_converted_output_bound_exceeded")
        try: rows = json.loads(converted)
        except (ValueError, UnicodeError): raise RuntimeError("unrecognized_listapps_shape") from None
    need(isinstance(rows, dict), "unrecognized_listapps_shape")
    return rows


def reset_owned_app(device, products, folder):
    def installed(op):
        raw = checked(["xcrun", "simctl", "listapps", device], folder, op)
        rows = parse_listapps(raw, folder, op)
        return rows.get(BUNDLE_ID)
    app = installed("listapps-before")
    if app is not None:
        need(app.get("CFBundleIdentifier") == BUNDLE_ID and app.get("ApplicationType") == "User", "unowned_installed_app")
        value = app.get("Path")
        if not value:
            url = urlparse(app.get("Bundle", "")); need(url.scheme == "file", "unknown_installed_app_path")
            value = unquote(url.path)
        path = Path(value).resolve(); need(path.name == "Wander.app", "unexpected_installed_app")
        source = products / "Binaries/0/Debug-iphonesimulator/Wander.app"
        for name in ["Wander", "Wander.debug.dylib", "Info.plist"]:
            need((path / name).is_file() and sha(path / name) == sha(source / name), "installed_app_not_current_owned_product")
        checked(["xcrun", "simctl", "uninstall", device, BUNDLE_ID], folder, "uninstall-owned-app")
    need(installed("listapps-after") is None, "owned_app_not_absent")
    save(folder / "startup.json", {"appPresentBefore": app is not None, "absentBeforeXCTestInstall": True,
        "scope": "Only current CI-owned synthetic app; keychain/system caches not reset.", "retries": 0})


def legacy_reports(legacy, rc, source):
    """Reconcile any available legacy report even when another export failed."""
    need(rc in {0, 65}, "legacy_unknown_native_exit")
    failed = int(rc == 65); result = "Failed" if failed else "Passed"
    need(len(legacy["actions"]) == 1, "legacy_action_count")
    root = legacy.get("issues") or {}; action = legacy["actions"][0]
    stages = {name: action[name].get("issues") or {} for name in ["build", "test"]}
    issue_counter = lambda issues: Counter((k, json.dumps(v, sort_keys=True)) for k, rows in issues.items() for v in rows)
    need(issue_counter(root) == issue_counter(stages["build"]) + issue_counter(stages["test"]), "legacy_root_stage_mismatch")
    need(all(not rows or k in {"testFailureSummaries", "testWarningSummaries", "warningSummaries"} for k, rows in root.items()), "unknown_legacy_issues")
    for metrics in [legacy.get("metrics") or {}, action["test"].get("metrics") or {}]:
        need(int(metrics.get("testsCount", -1)) == 1 and int(metrics.get("testsFailedCount", 0)) == failed and int(metrics.get("testsSkippedCount", 0)) == 0, "legacy_metrics_mismatch")
    old = []
    for row in root.get("testFailureSummaries", []):
        name = row.get("testCaseName", "").removesuffix("()").replace(".", "/", 1)
        url = urlparse(row.get("documentLocationInCreatingWorkspace", {}).get("url", "")); fragment = parse_qs(url.fragment)
        need("WanderTests/" + name == METHOD and url.scheme == "file" and unquote(url.path).endswith("/WanderTests/ReplayMaskingTests.swift"), "unknown_legacy_failure")
        start = int(fragment.get("StartingLineNumber", ["-2"])[0]); end = int(fragment.get("EndingLineNumber", ["-2"])[0]); need(start == end, "unexpected_failure_range")
        line = start + 1; message = row.get("message")
        need(1 <= line <= len(source) and re.search(r"\b(?:XCTAssert\w*|XCTUnwrap|XCTFail)\s*\(", source[line-1]), "legacy_failure_not_at_source_assertion")
        need(isinstance(message, str) and re.match(r"^(?:XCTAssert\w*|XCTUnwrap|XCTFail)\b", message), "legacy_native_nonassertion_failure")
        old.append((line, message))
    need(bool(old) == bool(failed), "legacy_failure_outcome_mismatch")
    warnings = []
    for category in ["testWarningSummaries", "warningSummaries"]:
        for row in root.get(category, []):
            need(isinstance(row.get("issueType"), str) and bool(row["issueType"]), "unknown_warning_type")
            name = row.get("testCaseName")
            if name: need("WanderTests/" + name.removesuffix("()").replace(".", "/", 1) == METHOD, "unknown_warning_case")
            need(category != "testWarningSummaries" or bool(name), "runtime_warning_case_missing")
            warnings.append({"category": category, "metadataSHA256": hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest(), "nativeCaseResult": result if name else None})
    return old, warnings


def account(summary, tests, legacy, rc, device, source):
    cases = list(nodes(tests, "Test Case")); need(len(cases) == 1, "case_count_mismatch")
    case = cases[0]; need(case.get("nodeIdentifier") == METHOD.split("/", 1)[1] + "()" and case.get("nodeIdentifierURL") == URL, "case_identity_mismatch")
    result = case.get("result"); need(result in {"Passed", "Failed"}, "skip_or_unknown_case")
    failed = int(result == "Failed")
    need({k: summary.get(k) for k in ["result", "totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"]} ==
         {"result": result, "totalTestCount": 1, "passedTests": 1-failed, "failedTests": failed, "skippedTests": 0, "expectedFailures": 0}, "summary_count_mismatch")
    need(rc == (65 if failed else 0), "native_exit_or_infrastructure_failure")
    configs = summary.get("devicesAndConfigurations"); need(isinstance(configs, list) and len(configs) == 1, "device_count_mismatch")
    need(all(configs[0].get(k) == v for k, v in {"passedTests": 1-failed, "failedTests": failed, "skippedTests": 0, "expectedFailures": 0}.items()), "configuration_counts_mismatch")
    actual = configs[0]["device"]
    need(actual.get("deviceId") == device["deviceID"] and actual.get("platform") == "iOS Simulator" and actual.get("architecture") == "arm64" and
         actual.get("modelName") == device["deviceModel"] and actual.get("osVersion") == "26.5" and actual.get("osBuildNumber") == device["runtimeBuild"], "device_mismatch")
    need(tests.get("devices") == [actual], "tests_device_mismatch")
    full = []
    for row in nodes(case, "Failure Message"):
        m = re.fullmatch(r"ReplayMaskingTests\.swift:(\d+): (.+)", row.get("name", ""), re.S)
        need(m, "unknown_failure_location"); line = int(m[1]); message = m[2]
        need(1 <= line <= len(source) and re.search(r"\b(?:XCTAssert\w*|XCTUnwrap|XCTFail)\s*\(", source[line-1]), "failure_not_at_source_assertion")
        need(re.match(r"^(?:XCTAssert\w*|XCTUnwrap|XCTFail)\b", message), "native_nonassertion_failure")
        full.append((line, message))
    need(bool(full) == bool(failed), "failure_messages_missing")
    reported = []
    for row in summary.get("testFailures", []):
        need(row.get("testIdentifierURL") == URL and row.get("targetName") == "WanderTests", "unknown_summary_failure")
        reported.append(row.get("failureText"))
    need(bool(reported) == bool(failed) and not (Counter(reported) - Counter(m for _, m in full)), "summary_not_truthful_failure_subset")
    old, warnings = legacy_reports(legacy, rc, source)
    need(Counter(old) == Counter(full), "full_failures_disagree")
    return {"result": result, "testURL": URL, "device": actual, "failureEntries": [{"line": l, "message": m} for l, m in full], "warnings": warnings, "warningsPreserved": True}


def available_reports(exports, rc, device, source):
    """Missing exports cannot conceal a known identity, outcome or source mismatch."""
    def valid_device(actual):
        need(actual.get("deviceId") == device["deviceID"] and actual.get("platform") == "iOS Simulator" and
             actual.get("architecture") == "arm64" and actual.get("modelName") == device["deviceModel"] and
             actual.get("osVersion") == "26.5" and actual.get("osBuildNumber") == device["runtimeBuild"], "available_device_mismatch")
    observed = {}; full = []
    if "summary" in exports:
        summary = exports["summary"]; result = summary.get("result")
        need(result in {"Passed", "Failed"}, "available_summary_unknown_result"); failed = int(result == "Failed")
        expected = {"totalTestCount": 1, "passedTests": 1-failed, "failedTests": failed, "skippedTests": 0, "expectedFailures": 0}
        need(all(summary.get(k) == v for k, v in expected.items()) and rc == (65 if failed else 0), "available_summary_counts_or_exit_mismatch")
        configs = summary.get("devicesAndConfigurations"); need(isinstance(configs, list) and len(configs) == 1, "available_summary_device_count")
        need(all(configs[0].get(k) == v for k, v in expected.items() if k != "totalTestCount"), "available_configuration_counts_mismatch")
        actual = configs[0]["device"]; valid_device(actual); observed["summary"] = (result, actual)
        failures = summary.get("testFailures", []); need(bool(failures) == bool(failed), "available_summary_failures_missing")
        need(all(x.get("testIdentifierURL") == URL and x.get("targetName") == "WanderTests" for x in failures), "available_summary_case_mismatch")
        need(all(isinstance(x.get("failureText"), str) and re.match(r"^(?:XCTAssert\w*|XCTUnwrap|XCTFail)\b", x["failureText"]) for x in failures), "available_summary_native_nonassertion_failure")
    if "tests" in exports:
        tests = exports["tests"]; cases = list(nodes(tests, "Test Case")); need(len(cases) == 1, "available_tree_case_count")
        case = cases[0]; need(case.get("nodeIdentifier") == METHOD.split("/", 1)[1] + "()" and case.get("nodeIdentifierURL") == URL and case.get("result") in {"Passed", "Failed"}, "available_tree_case_mismatch")
        devices = tests.get("devices"); need(isinstance(devices, list) and len(devices) == 1, "available_tree_device_count")
        valid_device(devices[0]); observed["tests"] = (case["result"], devices[0])
        need(rc == (65 if case["result"] == "Failed" else 0), "available_tree_exit_mismatch")
        for row in nodes(case, "Failure Message"):
            m = re.fullmatch(r"ReplayMaskingTests\.swift:(\d+): (.+)", row.get("name", ""), re.S)
            need(m, "available_unknown_failure_location"); line = int(m[1]); message = m[2]
            need(1 <= line <= len(source) and re.search(r"\b(?:XCTAssert\w*|XCTUnwrap|XCTFail)\s*\(", source[line-1]) and re.match(r"^(?:XCTAssert\w*|XCTUnwrap|XCTFail)\b", message), "available_native_nonassertion_failure")
            full.append((line, message))
        need(bool(full) == (case["result"] == "Failed"), "available_tree_failures_missing")
    if len(observed) == 2:
        need(observed["summary"] == observed["tests"], "available_summary_tree_disagreement")
        need(not (Counter(x["failureText"] for x in exports["summary"].get("testFailures", [])) - Counter(m for _, m in full)), "available_summary_failure_not_subset")
    if "legacy" in exports:
        old, _ = legacy_reports(exports["legacy"], rc, source)
        if "tests" in exports: need(Counter(old) == Counter(full), "available_legacy_tree_failures_disagree")
        if "summary" in exports:
            need(not (Counter(x["failureText"] for x in exports["summary"].get("testFailures", [])) - Counter(m for _, m in old)), "available_summary_legacy_failure_not_subset")


def source_guard(out, proof, phase):
    folder = out / phase; folder.mkdir()
    need(sha(ROOT / "scripts/diagnostics/first-capture-profile-source-proof.json") == SOURCE_PROOF_SHA, "canonical_source_proof_changed")
    need(proof.get("baseHead") == BASE_HEAD and proof.get("SDKRevision") == SDK_REVISION and proof.get("runParentSHA256") == RUN_PARENT_SHA, "canonical_source_proof_identity")
    need(proof.get("profileHelperPath") == PROFILE_HELPER_PATH and proof.get("profileHelperSHA256") == PROFILE_HELPER_SHA, "profile_helper_proof_identity")
    helper = ROOT / PROFILE_HELPER_PATH
    need(helper.is_file() and not helper.is_symlink() and sha(helper) == PROFILE_HELPER_SHA, "profile_helper_source_drift")
    rows = proof.get("files"); need(isinstance(rows, list) and len(rows) == 7, "source_proof_row_count")
    expected = {("sdk", p): h for p, h in SDK_FILES.items()}
    expected.update({("host", "Wander/App/WanderApp.swift"): HOST_SHA, ("test", "WanderTests/ReplayMaskingTests.swift"): REPLAY_SHA})
    need(len({(r["role"], r["path"]) for r in rows}) == 7 and {(r["role"], r["path"]): r["proposedSHA256"] for r in rows} == expected, "source_proof_rows_mismatch")
    need(all(r["originalSHA256"] == r["proposedSHA256"] for r in rows if r["role"] != "test"), "unexpected_host_or_SDK_patch")
    sdk = out / "SourcePackages/checkouts/posthog-ios"
    for row in rows:
        path = (sdk if row["role"] == "sdk" else ROOT) / row["path"]
        need(path.is_file() and not path.is_symlink() and sha(path) == row["proposedSHA256"], "source_drift")
    need(checked(["git", "-C", str(sdk), "rev-parse", "HEAD"], folder, "sdk-head").decode().strip() == SDK_REVISION, "canonical_SDK_revision_mismatch")
    need(not checked(["git", "-C", str(sdk), "status", "--porcelain", "--untracked-files=all"], folder, "sdk-clean").strip(), "canonical_SDK_not_clean")
    maps = proof.get("sourceMaps"); need(isinstance(maps, dict) and set(maps) == {"swift", "buildInputs", "tooling"}, "source_maps_missing")
    for key, count in [("swift", 448), ("buildInputs", 150), ("tooling", 2)]:
        mapping = maps[key]; need(isinstance(mapping, dict) and len(mapping) == count, "source_map_count")
        for name, expected_sha in mapping.items():
            rel = Path(name); path = ROOT / rel
            need(not rel.is_absolute() and ".." not in rel.parts and path.resolve().is_relative_to(ROOT) and path.is_file() and not path.is_symlink() and re.fullmatch(r"[a-f0-9]{64}", expected_sha) and sha(path) == expected_sha, "source_map_drift")
    roster = checked(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.swift"], folder, "swift-roster").decode().split("\0")
    need(set(filter(None, roster)) == set(maps["swift"]), "extra_or_missing_Swift_source")
    need(maps["swift"]["WanderTests/ReplayMaskingTests.swift"] == REPLAY_SHA and maps["swift"]["Wander/App/WanderApp.swift"] == HOST_SHA and maps["buildInputs"]["scripts/run-parent-regression.py"] == RUN_PARENT_SHA, "canonical_source_map_binding")
    save(folder / "completed.json", {"canonicalSDKRevision": SDK_REVISION, "canonicalSDKClean": True, "sourceCounts": {k: len(v) for k, v in maps.items()}, "sourceProofSHA256": sha(ROOT / "scripts/diagnostics/first-capture-profile-source-proof.json"), "allSourcesMatch": True})

def export_arm(folder, device, source, rc, source_sha256):
    bundle = folder / "result.xcresult"; info = bundle / "Info.plist"; need(info.is_file(), "incomplete_result")
    before = sha(info); exports = {}; errors = []; attachments_exported = False
    def exported(argv, operation):
        code, data, _ = command(argv, folder, operation)
        if code: raise AncillaryExportFailure(operation + "_export_failed")
        return data
    for kind in ["summary", "tests"]:
        try:
            raw = exported(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle), "--compact"], kind)
            exports[kind] = json.loads(raw); save(folder / (kind + ".json"), exports[kind])
        except AncillaryExportFailure as error: errors.append(str(error))
    try:
        raw = exported(["xcrun", "xcresulttool", "get", "object", "--legacy", "--path", str(bundle), "--format", "json"], "legacy")
        full = unwrap(json.loads(raw)); selected = {"issues": full.get("issues"), "metrics": full.get("metrics"), "actions": []}
        for row in full.get("actions", []):
            selected["actions"].append({name: {k: row.get(key, {}).get(k) for k in ["issues", "metrics"]} for name, key in [("build", "buildResult"), ("test", "actionResult")]})
        save(folder / "legacy-selected.json", {"rawSHA256": hashlib.sha256(raw).hexdigest(), "selected": selected})
        exports["legacy"] = selected
    except AncillaryExportFailure as error: errors.append(str(error))
    try:
        exported(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--test-id", URL, "--output-path", str(folder / "attachments")], "attachments")
        attachments_exported = True
    except AncillaryExportFailure as error: errors.append(str(error))
    if attachments_exported:
        manifest = load(folder / "attachments/manifest.json")
        need(isinstance(manifest, list) and len(manifest) == 1 and manifest[0].get("testIdentifierURL") == URL, "attachment_case_mismatch")
        rows = []
        for attachment in manifest[0].get("attachments", []):
            name = attachment["exportedFileName"]; path = folder / "attachments" / name
            need(Path(name).name == name and path.is_file() and not path.is_symlink(), "invalid_attachment_path")
            rows.append({"file": name, "sha256": sha(path), "bytes": path.stat().st_size})
        save(folder / "attachments-receipt.json", {"testIdentifierURL": URL, "manifestSHA256": sha(folder / "attachments/manifest.json"), "files": rows})
    need(sha(info) == before, "result_Info_changed")
    save(folder / "exports.json", {"InfoBeforeSHA256": before, "InfoAfterSHA256": sha(info), "sourceSHA256": source_sha256, "errors": errors, "retries": 0})
    available_reports(exports, rc, device, source)
    if errors:
        need(("tests" in exports or "legacy" in exports) if rc == 65 else bool(exports), "no_metadata_to_classify_native_outcome")
        return {"result": "Unverified", "nativeExitCode": rc, "InfoSHA256": before,
                "requiredExportFailures": errors, "nativeOutcomeInferred": False}
    review = account(exports["summary"], exports["tests"], selected, rc, device, source)
    return {**review, "InfoSHA256": before}


def profile_valid(profile):
    return isinstance(profile, dict) and profile.get("diagnosticStatus") == "Profiled" and profile.get("profileOverlapValid") is True and profile.get("pidIdentityVerified") is True and profile.get("stopRequired") is False


def main(args):
    global OUT, OVERALL_DEADLINE, METHOD, URL, PROFILE, CURRENT_ROW, NATIVE_RC, CURRENT_ADMISSION
    OVERALL_DEADLINE = time.monotonic() + 3300
    out = args.out.resolve(); products = args.products.resolve()
    need(os.environ.get("GITHUB_ACTIONS") == "true" and out.is_relative_to(Path(os.environ["RUNNER_TEMP"]).resolve()) and products.is_relative_to(out), "CI_owned_scope_required")
    need(out.is_dir() and not args.out.is_symlink() and not args.products.is_symlink(), "invalid_owned_paths")
    admission = load(out / "admission.json"); CURRENT_ADMISSION = admission
    need(admission["deviceID"] == args.device and admission["deviceModel"] == "iPhone 17 Pro" and admission["runtime"] == "iOS26.5" and admission["runtimeBuild"] == "23F77" and admission["diagnosticOnly"] is True and admission["releaseAcceptance"] is False and admission["retries"] == 0 and admission["xcode"] == "Xcode 26.6\nBuild version 17F113", "device_or_toolchain_admission_mismatch")
    need(re.fullmatch(r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", args.device), "invalid_device")
    need(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip() == admission["dispatchSHA"] and subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip() == admission["tree"], "checkout_mismatch")
    proof_path = ROOT / "scripts/diagnostics/first-capture-profile-source-proof.json"
    proof = load(proof_path); proof_sha = sha(proof_path)
    expected = load(out / "diagnostic-build-fingerprints.json")
    need(expected["sourceHashesStillMatch"] is True and tree(products) == expected["productFiles"], "compiled_product_drift")
    config = products / "Tests/0/Wander.xctestrun"; original = config.read_bytes(); parsed = plistlib.loads(original)
    need(parsed["WanderTests"]["CommandLineArguments"] == [], "unexpected_original_host_arguments")
    for name in ["private", "validation-started.json", "validation.json", "validation-stopped.json", "configuration-restoration.json", "profile-summary.json", "source-before", "source-after"]:
        need(not (out / name).exists() and not (out / name).is_symlink(), "existing_attempt_preserved_no_retry")
    OUT = out
    save(out / "validation-started.json", {"head": admission["dispatchSHA"], "tree": admission["tree"], "deviceID": args.device, "sourceProofSHA256": proof_sha, "scriptSHA256": sha(Path(__file__)), "originalConfigurationSHA256": hashlib.sha256(original).hexdigest(), "order": [x[0] for x in CASES], "sameProducts": True, "configurationChanged": False, "retries": 0})
    source_guard(out, proof, "source-before")
    results = []; source = (ROOT / "WanderTests/ReplayMaskingTests.swift").read_text().splitlines()
    namespace = runpy.run_path(str(ROOT / PROFILE_HELPER_PATH), run_name="rec636_first_capture_profile")
    observer_type = namespace.get("Observer"); need(isinstance(observer_type, type), "profile_observer_API_missing")
    try:
        for name, suite, METHOD in CASES:
            URL = "test://com.apple.xcode/Wander/" + METHOD
            folder = out / name; folder.mkdir()
            need(sha(proof_path) == proof_sha and config.read_bytes() == original and tree(products) == expected["productFiles"], "pre_case_product_or_config_drift")
            source_guard(folder.parent, proof, name + "-source-before")
            reset_owned_app(args.device, products, folder)
            save(folder / "dispatch.json", {"suite": suite, "identifier": METHOD, "deviceID": args.device, "sourceSHA256": REPLAY_SHA, "configurationSHA256": sha(config), "defaultTestExecutionTimeAllowance": 600, "maximumTestExecutionTimeAllowance": 900, "parallelTesting": False, "retries": 0})
            observer = observer_type(out, products, args.device, command, cleanup)
            native_error = None
            try:
                observer.start()
                rc, _, process = command([sys.executable, "scripts/run-parent-regression.py", "--suite", suite, "--test-products", str(products), "--destination", args.device, "--result-bundle", str(folder / "result.xcresult"), "--selection-file", str(folder / "selection.json")], folder, "native", timeout=1500, collect=False)
                NATIVE_RC = rc
            except BaseException as error:
                native_error = error
                raise
            finally:
                try:
                    PROFILE = observer.finish()
                    need(isinstance(PROFILE, dict), "profile_observer_result_invalid")
                except BaseException as error:
                    PROFILE = {"diagnosticStatus": "Gap", "gap": type(error).__name__, "stopRequired": True, "profileOverlapValid": False}
                    save(folder / "profile-finish-failure.json", {"state": "stopped", "category": type(error).__name__, "nativeFailureCategory": type(native_error).__name__ if native_error is not None else None, "retries": 0})
            need(rc in {0, 65} and not process["infrastructureMarker"], "native_infrastructure_or_unknown_exit")
            selection = load(folder / "selection.json")
            need(selection.get("suite") == suite and selection.get("identifiers") == [METHOD] and selection.get("isolatedTestSuites") == {}, "selection_mismatch")
            review = export_arm(folder, admission, source, rc, REPLAY_SHA)
            need(sha(proof_path) == proof_sha and config.read_bytes() == original and tree(products) == expected["productFiles"], "post_case_product_or_config_drift")
            source_guard(out, proof, name + "-source-after")
            row = {"suite": suite, "identifier": METHOD, "nativeExitCode": rc, "configurationSHA256": sha(config), **review, "retries": 0}
            save(folder / "completed.json", row); results.append(row); CURRENT_ROW = row
            need(not PROFILE.get("stopRequired", False), "profile_unknown_completion_or_boundary")
    finally:
        need(config.read_bytes() == original and tree(products) == expected["productFiles"], "final_product_or_config_drift")
        need(sha(proof_path) == proof_sha, "source_proof_drift")
        source_guard(out, proof, "source-after")
        save(out / "configuration-restoration.json", {"restoredExactly": True, "configurationNeverChanged": True, "configurationSHA256": sha(config), "allProductHashesMatchBuild": True})
    counts = Counter(x["result"] for x in results)
    result = "Unverified" if counts["Unverified"] else "Failed" if counts["Failed"] else "Passed"
    save(out / "validation.json", {"state": "one-private-profile-validation-completed", "result": result, "executions": 1, "passed": counts["Passed"], "failed": counts["Failed"], "unverified": counts["Unverified"], "skipped": 0, "retries": 0, "cases": results, "historicalFailuresCleared": False, "specificCauseProven": False, "fullProcessQuiescenceClaimed": False, "releaseAcceptance": False, "profileDiagnosticStatus": PROFILE.get("diagnosticStatus"), "profileOverlapValid": PROFILE.get("profileOverlapValid"), "profileEvidenceComplete": profile_valid(PROFILE)})
    return 2 if counts["Unverified"] else 65 if counts["Failed"] else 0 if profile_valid(PROFILE) else 2

def emit_profile_summary():
    """One bounded authored log record; no raw process/profile/header output."""
    profile = PROFILE if isinstance(PROFILE, dict) else {}
    row = CURRENT_ROW if isinstance(CURRENT_ROW, dict) else {}
    admitted = CURRENT_ADMISSION if isinstance(CURRENT_ADMISSION, dict) else {}
    result = row.get("result")
    counts = {"executions": 1, "passed": int(result == "Passed"), "failed": int(result == "Failed"), "unverified": 0} if result in {"Passed", "Failed"} else {"executions": None, "passed": None, "failed": None, "unverified": None}
    warning_count = len(row["warnings"]) if "warnings" in row else None
    hashes = {"sourceProofSHA256": SOURCE_PROOF_SHA, "ReplaySourceSHA256": REPLAY_SHA, "profileHelperSHA256": PROFILE_HELPER_SHA}
    for key in ["profileSHA256", "rawProfileSHA256"]:
        value = profile.get(key)
        if isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value): hashes[key] = value
    if OUT is not None:
        for key, relative in {"InfoSHA256": "private/result.xcresult/Info.plist", "summarySHA256": "private/summary.json", "testsSHA256": "private/tests.json", "legacySelectedSHA256": "private/legacy-selected.json"}.items():
            path = OUT / relative
            if path.is_file() and not path.is_symlink(): hashes[key] = sha(path)
        legacy = OUT / "private/legacy-selected.json"
        if legacy.is_file() and not legacy.is_symlink():
            value = load(legacy).get("rawSHA256")
            if isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value): hashes["legacyRawSHA256"] = value
    status = profile.get("diagnosticStatus", "observer_unavailable")
    if status == "Gap":
        gap = profile.get("gap")
        status = "Gap:" + (gap if isinstance(gap, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,95}", gap) else "unclassified")
    if STOP_CATEGORY is not None: status = "Stopped:" + STOP_CATEGORY + ";" + status
    record = {"schema": 1, "diagnosticOnly": True, "head": admitted.get("dispatchSHA"), "sourceProofSHA256": SOURCE_PROOF_SHA,
        "case": CASES[0][2], "nativeExitCode": NATIVE_RC, "nativeResult": result, "counts": counts,
        "failureLines": [x["line"] for x in row["failureEntries"]] if "failureEntries" in row else None,
        "officialWarningCount": warning_count, "markerStatus": profile.get("markerStatus"), "gate": profile.get("gate"),
        "sample": profile.get("sample"), "profileOverlapValid": profile.get("profileOverlapValid"),
        "pidIdentityVerified": profile.get("pidIdentityVerified"), "processCPUSeconds": profile.get("processCPUSeconds"),
        "processCPUValid": profile.get("processCPUValid"), "topSymbols": profile.get("topSymbols"), "hashes": hashes,
        "exportComplete": result in {"Passed", "Failed"} if row else None, "diagnosticStatus": status, "acceptanceClaimed": False}
    compact = json.dumps(record, separators=(",", ":"), sort_keys=True, ensure_ascii=True)
    while len((compact + "\n").encode()) > 8192 and record["topSymbols"]:
        record["topSymbols"] = record["topSymbols"][:-1]
        compact = json.dumps(record, separators=(",", ":"), sort_keys=True, ensure_ascii=True)
    need(len((compact + "\n").encode()) <= 8192, "authored_profile_summary_bound")
    if OUT is not None:
        with (OUT / "profile-summary.json").open("x") as summary: summary.write(compact + "\n")
    print("REC636_FIRST_CAPTURE_PROFILE_V1 " + compact, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path); parser.add_argument("--products", required=True, type=Path); parser.add_argument("--device", required=True)
    def interrupted(_signal, _frame): raise InterruptedError("owner_interrupted")
    signal.signal(signal.SIGTERM, interrupted)
    try: exit_code = main(parser.parse_args())
    except BaseException as error:
        category = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        STOP_CATEGORY = category if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,95}", category) else type(error).__name__
        if OUT is not None and not (OUT / "validation-stopped.json").exists():
            save(OUT / "validation-stopped.json", {"state": "stopped-preserved-no-retry", "category": str(error) if isinstance(error, RuntimeError) else type(error).__name__, "nextCaseAllowedAfterUnknownFailure": False})
        raise
    finally:
        emit_profile_summary()
    sys.exit(exit_code)
