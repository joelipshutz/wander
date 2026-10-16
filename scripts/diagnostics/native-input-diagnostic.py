#!/usr/bin/env python3
"""One-shot REC-636 diagnostics; never a release acceptance runner."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

BASE = "22e7c6d9efd4ac0957ed25cd60e8cc26a05bc7f7"
SDK = "ee5b5705b0038f0c44646cde5fe972bb65387596"
CASES = {
    "selected-pan": "MapFilterInteractionUITests/testPerformanceFixtureMeasuresSelectedPinPanCPUAndAnnotationWork",
    "drawer": "LiveDrawerAndFilterUITests/testEveryDrawerDetentAndNativeMapPanKeepTheLoadedActivity",
    "combined": "LiveDrawerAndFilterUITests/testCombinedFiltersApplyCancelAndResetKeepMapAndFeedInAgreement",
    "search": "LiveReviewContinuityUITests/testLiveSearchNotificationsAndAddCancelReturnToSameSurface",
    "warm": "MapFilterInteractionUITests/testPerformanceFixtureKeepsWarmSourceSwitchesResponsive",
    "film": "OnboardingUITests/testFilmExplorationsAutoAdvanceToInteractiveAccount",
}
TRACES = (
    "rec636-native-pan-diagnostic.json",
    "rec636-onboarding-diagnostic-film.json",
    "rec636-onboarding-diagnostic-film-type.json",
)


def read(*command):
    return subprocess.check_output(command, text=True).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    if path.exists():
        raise RuntimeError("Do not replace previous diagnostic evidence: " + str(path))
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def fingerprint_sources():
    names = read("git", "ls-files", "--", "*.swift").splitlines()
    return {name: sha(Path(name)) for name in names}


def admit(out):
    out.mkdir(parents=True, exist_ok=False)
    head = read("git", "rev-parse", "HEAD")
    assert head == os.environ["GITHUB_SHA"]
    subprocess.run(["git", "merge-base", "--is-ancestor", BASE, head], check=True)
    xcode = read("xcodebuild", "-version")
    assert xcode == "Xcode 26.6\nBuild version 17F113", "Unexpected diagnostic toolchain"
    runtimes = json.loads(read("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    matches = [r for r in runtimes if r.get("isAvailable") and r.get("version") == "26.5" and "iOS" in r["identifier"]]
    assert len(matches) == 1 and matches[0]["buildversion"] == "23F77"
    runtime = matches[0]
    available = json.loads(read("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"][runtime["identifier"]]
    def choose(names):
        for name in names:
            rows = [d for d in available if d["name"] == name and d.get("isAvailable")]
            if rows:
                assert len(rows) == 1
                return rows[0]
        raise RuntimeError("Exact diagnostic simulator selection unavailable")
    large = choose(["iPhone 17 Pro"])
    compact = choose(["iPhone 17e", "iPhone 16e", "iPhone SE (3rd generation)"])
    assert large["udid"] != compact["udid"]
    save(out / "admission.json", {
        "head": head, "tree": read("git", "rev-parse", "HEAD^{tree}"), "base": BASE,
        "toolchain": xcode, "runtime": {k: runtime[k] for k in ("identifier", "version", "buildversion")},
        "large": large, "compact": compact, "retries": 0,
        "diagnosticOnly": True, "releaseAcceptance": False,
        "priorFullShardSequenceReproduced": False,
    })
    save(out / "source-before.json", fingerprint_sources())
    with open(os.environ["GITHUB_ENV"], "a") as f:
        f.write("DIAG_LARGE=" + large["udid"] + "\nDIAG_COMPACT=" + compact["udid"] + "\n")


def verify_build(out, products, packages):
    expected = json.loads((out / "source-before.json").read_text())
    assert fingerprint_sources() == expected, "Build changed diagnostic source"
    sdk = packages / "checkouts/posthog-ios"
    assert read("git", "-C", str(sdk), "rev-parse", "HEAD") == SDK
    assert read("git", "-C", str(sdk), "status", "--porcelain", "--untracked-files=all") == ""
    assert (products / "Info.plist").is_file()
    for name in ("Wander.app", "WanderUITests-Runner.app"):
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(products / "Binaries/0/Debug-iphonesimulator" / name)], check=True)
    save(out / "build-proof.json", {"sourceUnchanged": True, "sdkRevision": SDK, "sdkClean": True,
        "products": {str(p.relative_to(products)): sha(p) for p in sorted(products.rglob("*")) if p.is_file() and not p.is_symlink()}})


def export_case(bundle, case, target):
    if not (bundle / "Info.plist").is_file():
        save(target / "exports.json", {"state": "bundle-missing", "releaseAcceptance": False})
        return False
    before = sha(bundle / "Info.plist")
    receipts = []
    for kind in ("summary", "tests", "test-details", "activities"):
        cmd = ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle), "--compact"]
        if kind in ("test-details", "activities"):
            cmd += ["--test-id", "test://com.apple.xcode/Wander/WanderUITests/" + case]
        with (target / (kind + ".json")).open("wb") as stdout, (target / (kind + "-errors.log")).open("wb") as stderr:
            result = subprocess.run(cmd, stdout=stdout, stderr=stderr, timeout=180)
        receipts.append({"kind": kind, "exitCode": result.returncode})
    with (target / "attachments-export.log").open("wb") as log:
        result = subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
            "--output-path", str(target / "attachments")], stdout=log, stderr=subprocess.STDOUT, timeout=180)
    receipts.append({"kind": "attachments", "exitCode": result.returncode})
    after = sha(bundle / "Info.plist")
    save(target / "exports.json", {"InfoBeforeSHA256": before, "InfoAfterSHA256": after,
        "InfoUnchanged": before == after, "exports": receipts, "noRetry": True})
    return before == after and all(r["exitCode"] == 0 for r in receipts)


def run_cases(out, products, role, followup=False):
    admitted = json.loads((out / "admission.json").read_text())
    device = admitted[role]["udid"]
    labels = list(CASES) if role == "large" else ["drawer", "combined", "search"]
    if followup:
        labels = ["combined", "warm"] if role == "large" else ["drawer", "combined"]
    rows = []
    for label in labels:
        target = out / (role + "-" + label)
        target.mkdir(exist_ok=False)
        bundle = target / "result.xcresult"
        started = time.time()
        cmd = ["xcodebuild", "test-without-building", "-quiet", "-testProductsPath", str(products),
            "-destination", "platform=iOS Simulator,id=" + device,
            "-jobs", "2", "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
            "-default-test-execution-time-allowance", "600", "-maximum-test-execution-time-allowance", "900",
            "-only-testing:WanderUITests/" + CASES[label], "-resultBundlePath", str(bundle)]
        capture_configuration = {"mode": "original"}
        originals = {}
        if label == "selected-pan":
            # Match this case's original Parent runner capture configuration.
            # Restore the job-owned configurations byte-for-byte for other cases.
            originals = {p: p.read_bytes() for p in products.rglob("*.xctestrun") if p.is_file() and not p.is_symlink()}
            assert originals
            spec = importlib.util.spec_from_file_location("parent_regression", Path(__file__).resolve().parents[1] / "run-parent-regression.py")
            regression = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(regression)
        try:
            if originals:
                regression.prepare_ui_performance_products(products)
                capture_configuration = {"mode": "original-parent-performance", "configurations": {
                    str(p.relative_to(products)): {"before": hashlib.sha256(data).hexdigest(), "during": sha(p)}
                    for p, data in originals.items()}}
            with (target / "native.log").open("wb") as log:
                native = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
        finally:
            for path, data in originals.items():
                path.write_bytes(data)
            if originals:
                capture_configuration["restoredExactly"] = all(path.read_bytes() == data for path, data in originals.items())
                assert capture_configuration["restoredExactly"]
        row = {"case": "WanderUITests/" + CASES[label], "device": device,
            "nativeExitCode": native.returncode, "startedUnix": started, "endedUnix": time.time(),
            "retryCount": 0, "diagnosticOnly": True, "releaseAcceptance": False,
            "selectionMode": "native-followup" if followup else "original-observations",
            "captureConfiguration": capture_configuration}
        # Read only the explicit synthetic-fixture trace files, after native input ends.
        lookup = subprocess.run(["xcrun", "simctl", "get_app_container", device, "com.grayline.wander", "data"],
                                capture_output=True, text=True)
        trace_rows = []
        if lookup.returncode == 0:
            cache = Path(lookup.stdout.strip()) / "Library/Caches"
            for name in TRACES:
                source = cache / name
                if source.is_file() and not source.is_symlink():
                    copied = target / name
                    shutil.copyfile(source, copied)
                    trace_rows.append({"name": name, "sha256": sha(copied),
                        "modifiedUnix": source.stat().st_mtime, "writtenDuringThisCase": source.stat().st_mtime >= started})
        row["traceLookupExitCode"] = lookup.returncode
        row["traces"] = trace_rows
        required_traces = set(TRACES[1:]) if label == "film" else {TRACES[0]}
        row["observationsComplete"] = required_traces.issubset({r["name"] for r in trace_rows if r["writtenDuringThisCase"]})
        save(target / "process.json", row)
        row["exportsComplete"] = export_case(bundle, CASES[label], target)
        rows.append(row)
    save(out / (role + "-results.json"), {"executions": rows, "releaseAcceptance": False})
    return 0 if all(r["nativeExitCode"] == 0 and r["exportsComplete"] and r["observationsComplete"] for r in rows) else 65


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("admit", "verify-build", "run"))
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--products", type=Path)
    parser.add_argument("--packages", type=Path)
    parser.add_argument("--role", choices=("large", "compact"))
    parser.add_argument("--followup", action="store_true", help="Run only the four changed native follow-up observations")
    args = parser.parse_args()
    if args.action == "admit":
        admit(args.out)
    elif args.action == "verify-build":
        assert args.products and args.packages
        verify_build(args.out, args.products, args.packages)
    else:
        assert args.products and args.role
        return run_cases(args.out, args.products, args.role, args.followup)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
