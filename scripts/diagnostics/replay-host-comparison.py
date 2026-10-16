#!/usr/bin/env python3
"""CI-owner diagnostic: one private Replay process per root mode, one build."""
from pathlib import Path
from collections import Counter
from urllib.parse import urlparse, parse_qs, unquote
import argparse, copy, hashlib, json, os, plistlib, re, selectors, signal, subprocess, sys, time

METHOD = "WanderTests/ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage"
URL = "test://com.apple.xcode/Wander/" + METHOD
FLAG = "-WanderReplayHostDiagnostic"
BUNDLE_ID = "com.grayline.wander"
ROOT = Path.cwd().resolve()
OUT = None
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

def group_exists(pid):
    try: os.killpg(pid, 0); return True
    except ProcessLookupError: return False
def cleanup(process):
    facts = {"ownedGroup": process.pid, "term": False, "kill": False}
    if group_exists(process.pid): os.killpg(process.pid, signal.SIGTERM); facts["term"] = True
    deadline = time.monotonic() + 10
    while group_exists(process.pid) and time.monotonic() < deadline: process.poll(); time.sleep(.1)
    if group_exists(process.pid): os.killpg(process.pid, signal.SIGKILL); facts["kill"] = True
    process.wait(timeout=5)
    deadline = time.monotonic() + 5
    while group_exists(process.pid) and time.monotonic() < deadline: time.sleep(.1)
    need(not group_exists(process.pid), "owned_group_cleanup_unconfirmed")
    return {**facts, "groupGone": True, "leaderExit": process.returncode}

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
        need(not group_exists(process.pid), "owned_group_still_active")
    except BaseException as error:
        facts = cleanup(process)
        save(folder / (operation + "-cleanup.json"), facts)
        save(folder / (operation + "-process.json"), {"operation": operation,
             "exitCode": process.returncode, "completed": False,
             "category": str(error) if isinstance(error, RuntimeError) else type(error).__name__,
             "elapsedSeconds": time.monotonic() - began, "rawOutputPersisted": False,
             "outputBytes": dict(sizes), "outputSHA256": {k: v.hexdigest() for k, v in hashes.items()}, **input_facts})
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

def source_guard(out, proof):
    sdk = out / "SourcePackages/checkouts/posthog-ios"
    for row in proof["files"]:
        path = (sdk if row["role"] == "sdk" else ROOT) / row["path"]
        need(path.is_file() and not path.is_symlink() and sha(path) == row["proposedSHA256"], "source_drift")

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

def host_observation(folder):
    manifest = load(folder / "attachments/manifest.json")
    need(isinstance(manifest, list) and len(manifest) == 1 and manifest[0].get("testIdentifierURL") == URL, "host_attachment_case_mismatch")
    matches = [a for row in manifest for a in row.get("attachments", []) if a.get("suggestedHumanReadableName", "").startswith("Replay host root diagnostic")]
    need(len(matches) == 1, "host_observation_missing_or_duplicate")
    name = matches[0]["exportedFileName"]; need(Path(name).name == name, "attachment_path_escape")
    path = folder / "attachments" / name; need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4096, "invalid_host_observation")
    pairs = [line.split("=", 1) for line in path.read_text().splitlines()]; keys = [x[0] for x in pairs]
    expected = {"host_diagnostic_enabled", "host_requested_normal", "host_requested_dormant", "host_test_configuration_present", "host_expected_bundle", "host_xctest_class_present", "host_uses_dormant_root", "host_ordinary_root_mounted", "host_dormant_root_mounted"}
    need(len(keys) == len(set(keys)) == 9 and set(keys) == expected and all(v in {"true", "false"} for _, v in pairs), "unknown_host_observation")
    flags = {k: v == "true" for k, v in pairs}; dormant = folder.name == "dormant"
    need(flags["host_diagnostic_enabled"] and flags["host_test_configuration_present"] and flags["host_expected_bundle"] and flags["host_requested_dormant"] == dormant and flags["host_requested_normal"] != dormant and flags["host_uses_dormant_root"] == dormant and flags["host_dormant_root_mounted"] == dormant and flags["host_ordinary_root_mounted"] != dormant, "requested_effective_root_mismatch")
    return {"hostObserved": flags, "hostAttachmentSHA256": sha(path)}

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
    need(sha(info) == before, "result_Info_changed")
    save(folder / "exports.json", {"InfoBeforeSHA256": before, "InfoAfterSHA256": sha(info), "sourceSHA256": source_sha256, "errors": errors, "retries": 0})
    available_reports(exports, rc, device, source)
    host = host_observation(folder) if attachments_exported else {}
    if errors:
        return {"result": "Unverified", "nativeExitCode": rc, "InfoSHA256": before,
                "requiredExportFailures": errors, "nativeOutcomeInferred": False, **host}
    review = account(exports["summary"], exports["tests"], selected, rc, device, source)
    return {**review, **host, "InfoSHA256": before}

def main(args):
    global OUT, OVERALL_DEADLINE
    OVERALL_DEADLINE = time.monotonic() + 3300
    out = args.out.resolve(); products = args.products.resolve()
    need(os.environ.get("GITHUB_ACTIONS") == "true" and out.is_relative_to(Path(os.environ["RUNNER_TEMP"]).resolve()) and products.is_relative_to(out), "CI_owned_scope_required")
    need(out.is_dir() and not args.out.is_symlink() and not args.products.is_symlink(), "invalid_owned_paths")
    admission = load(out / "admission.json"); need(admission["deviceID"] == args.device and admission["diagnosticOnly"] is True and admission["releaseAcceptance"] is False, "device_admission_mismatch")
    need(re.fullmatch(r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", args.device), "invalid_device")
    need(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip() == admission["dispatchSHA"], "checkout_mismatch")
    proof = load(ROOT / "scripts/diagnostics/source-proof.json"); source_guard(out, proof)
    expected = load(out / "diagnostic-build-fingerprints.json"); need(expected["sourceHashesStillMatch"] is True and tree(products) == expected["productFiles"], "compiled_product_drift")
    config = products / "Tests/0/Wander.xctestrun"; original = config.read_bytes(); parsed = plistlib.loads(original)
    need(parsed["WanderTests"]["CommandLineArguments"] == [], "unexpected_original_host_arguments")
    for name in ["normal", "dormant", "comparison-started.json", "comparison.json", "comparison-stopped.json", "configuration-restoration.json"]:
        need(not (out / name).exists() and not (out / name).is_symlink(), "existing_attempt_preserved_no_retry")
    OUT = out
    save(out / "comparison-started.json", {"head": admission["dispatchSHA"], "deviceID": args.device, "sourceProofSHA256": sha(ROOT / "scripts/diagnostics/source-proof.json"), "scriptSHA256": sha(Path(__file__)), "originalConfigurationSHA256": hashlib.sha256(original).hexdigest(), "order": ["normal", "dormant"], "sameProducts": True, "retries": 0})
    results = []; source = (ROOT / "WanderTests/ReplayMaskingTests.swift").read_text().splitlines()
    try:
        for mode in ["normal", "dormant"]:
            folder = out / mode; folder.mkdir(); source_guard(out, proof)
            need(tree(products) == expected["productFiles"], "pre_arm_product_drift")
            reset_owned_app(args.device, products, folder)
            variant = copy.deepcopy(parsed); variant["WanderTests"]["CommandLineArguments"] = [FLAG, mode]
            raw = plistlib.dumps(variant); need(plistlib.loads(raw) == variant, "configuration_serialization_changed")
            config.write_bytes(raw)
            permitted = dict(expected["productFiles"]); permitted["Tests/0/Wander.xctestrun"] = hashlib.sha256(raw).hexdigest()
            need(tree(products) == permitted, "unexpected_configuration_delta")
            save(folder / "configuration.json", {"mode": mode, "configurationSHA256": sha(config), "originalSHA256": hashlib.sha256(original).hexdigest(), "onlySemanticDelta": "WanderTests.CommandLineArguments fixed mode pair", "signedProductBytesUnchanged": True})
            try:
                rc, _, process = command([sys.executable, "scripts/run-parent-regression.py", "--suite", "replay-private", "--test-products", str(products), "--destination", args.device, "--result-bundle", str(folder / "result.xcresult"), "--selection-file", str(folder / "selection.json")], folder, "native", timeout=1500, collect=False)
                need(rc in {0, 65} and not process["infrastructureMarker"], "native_infrastructure_or_unknown_exit")
                selection = load(folder / "selection.json"); need(selection.get("suite") == "replay-private" and selection.get("identifiers") == [METHOD], "selection_mismatch")
                review = export_arm(folder, admission, source, rc, sha(ROOT / "WanderTests/ReplayMaskingTests.swift"))
                need(tree(products) == permitted, "post_arm_product_drift"); source_guard(out, proof)
                row = {"mode": mode, "nativeExitCode": rc, "configurationSHA256": sha(config), **review, "retries": 0}
                save(folder / "completed.json", row); results.append(row)
            finally:
                config.write_bytes(original)
                need(config.read_bytes() == original, "configuration_restore_failed")
    finally:
        config.write_bytes(original)
        need(config.read_bytes() == original and tree(products) == expected["productFiles"], "final_product_or_config_restore_failed")
        source_guard(out, proof)
        save(out / "configuration-restoration.json", {"restoredExactly": True, "configurationSHA256": sha(config), "allProductHashesMatchBuild": True})
    counts = Counter(x["result"] for x in results)
    result = "Unverified" if counts["Unverified"] else "Failed" if counts["Failed"] else "Passed"
    save(out / "comparison.json", {"state": "diagnostic-pair-completed", "result": result, "executions": 2, "passed": counts["Passed"], "failed": counts["Failed"], "unverified": counts["Unverified"], "skipped": 0, "retries": 0, "arms": results, "uniqueCoverageAdded": 0, "historicalFailuresCleared": False, "specificCauseProven": False, "fullProcessQuiescenceClaimed": False})
    return 2 if counts["Unverified"] else 65 if counts["Failed"] else 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path); parser.add_argument("--products", required=True, type=Path); parser.add_argument("--device", required=True)
    def interrupted(_signal, _frame): raise InterruptedError("owner_interrupted")
    signal.signal(signal.SIGTERM, interrupted)
    try: exit_code = main(parser.parse_args())
    except BaseException as error:
        if OUT is not None and not (OUT / "comparison-stopped.json").exists():
            save(OUT / "comparison-stopped.json", {"state": "stopped-preserved-no-retry", "category": str(error) if isinstance(error, RuntimeError) else type(error).__name__, "BAllowedAfterUnknownFailure": False})
        raise
    sys.exit(exit_code)
