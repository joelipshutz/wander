#!/usr/bin/env python3
"""Record generated C options for a dedicated Debug Replay build."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shlex


def need(condition, category):
    if not condition:
        raise ValueError(category)


def regular_bytes(path, root, limit):
    need(path.is_file() and not path.is_symlink()
         and path.resolve().is_relative_to(root.resolve()), "owned_regular_file")
    need(path.stat().st_size <= limit, "file_size")
    with path.open("rb") as stream:
        raw = stream.read(limit + 1)
    need(len(raw) <= limit, "file_size")
    return raw


def collect(derived_data: Path, products: Path, candidate: str) -> dict:
    need(re.fullmatch(r"[0-9a-f]{40}", candidate) is not None, "checkout_commit")
    need(derived_data.is_dir() and not derived_data.is_symlink()
         and products.is_dir() and not products.is_symlink(), "build_directories")
    base = derived_data / "Build/Intermediates.noindex"
    need(base.is_dir() and not base.is_symlink()
         and base.resolve().is_relative_to(derived_data.resolve()), "compiler_response_root")
    paths = sorted(base.rglob("*-common-args.resp"))
    need(0 < len(paths) <= 128, "compiler_response_count")
    rows = []
    for path in paths:
        raw = regular_bytes(path, base, 262144)
        relative = path.relative_to(base).as_posix()
        match = re.fullmatch(
            r"([A-Za-z0-9_.-]+)\.build/Debug-iphonesimulator/"
            r"([A-Za-z0-9_.-]+)\.build/Objects-normal/arm64/"
            r"[A-Za-z0-9_-]+-common-args\.resp", relative)
        need(match is not None, "compiler_response_configuration")
        tokens = shlex.split(raw.decode("utf-8"))
        flags = [x for x in tokens if re.fullmatch(r"-O(?:[0-3szg]|fast)?", x)]
        rows.append({"project": match[1], "target": match[2],
                     "relativeResponse": relative,
                     "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw),
                     "optimizationFlags": flags, "debugDefine": "-DDEBUG=1" in tokens})
    need(any(r["project"] == "PostHog" and r["target"] == "phlibwebp" for r in rows),
         "phlibwebp_response_missing")
    need(all(r["optimizationFlags"] == ["-Os"] and r["debugDefine"] for r in rows),
         "actual_c_optimization_not_verified")

    info = regular_bytes(products / "Info.plist", products, 1048576)
    entries = plistlib.loads(info).get("Tests")
    need(isinstance(entries, list) and 0 < len(entries) <= 16, "product_configurations")
    configurations = {}
    for entry in entries:
        need(isinstance(entry, dict) and isinstance(entry.get("xctestrun"), str),
             "product_configuration")
        relative = entry["xctestrun"]
        need(re.fullmatch(r"[A-Za-z0-9_./-]+\.xctestrun", relative) is not None
             and not Path(relative).is_absolute() and ".." not in Path(relative).parts,
             "product_configuration_path")
        raw = regular_bytes(products / relative, products, 4194304)
        configurations[relative] = hashlib.sha256(raw).hexdigest()
    return {"schema": 1, "purpose": "dedicated-replay-compiler-options",
            "checkoutCommit": candidate, "configuration": "Debug",
            "platform": "iphonesimulator", "architecture": "arm64",
            "requestedCOptimization": "s", "observedCFlagsVerified": True,
            "requestedSwiftOptimization": "-Onone", "swiftCompilerCommandObserved": False,
            "treatmentScope": "all C-family targets in the dedicated Replay build",
            "responses": rows, "productInfoSHA256": hashlib.sha256(info).hexdigest(),
            "configurationSHA256": configurations, "binaryIntegrityClaimed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--test-products", type=Path, required=True)
    parser.add_argument("--checkout", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    receipt = collect(args.derived_data, args.test_products, args.checkout)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as stream:
        stream.write(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
