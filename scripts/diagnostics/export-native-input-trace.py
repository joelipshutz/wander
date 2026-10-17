#!/usr/bin/env python3
"""Export only the opt-in synthetic input trace from the selected CI Simulator."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import stat
import time


def main():
    key, name = os.environ["TRACE_DEVICE_KEY"], os.environ["TRACE_NAME"]
    if (key, name) not in {("LARGE_DEVICE_ID", "map-pan"), ("SMALL_DEVICE_ID", "compact-filter"),
                          ("LARGE_DEVICE_ID", "onboarding-overview")}:
        raise ValueError("Unexpected diagnostic case")
    device = os.environ[key]
    if re.fullmatch(r"[0-9A-Fa-f-]{36}", device) is None:
        raise ValueError("Invalid Simulator identifier")
    target = Path(os.environ["RUNNER_TEMP"]) / "rec636-diagnostic" / (name + "-input.json")
    if not target.parent.is_dir() or target.exists() or target.is_symlink():
        raise ValueError("Preserve prior diagnostic exports")
    result = subprocess.run(
        ["xcrun", "simctl", "get_app_container", device, "com.grayline.wander", "data"],
        capture_output=True, check=True, timeout=30,
    )
    container = Path(result.stdout.decode().strip())
    base = Path.home() / "Library/Developer/CoreSimulator/Devices" / device / "data/Containers/Data/Application"
    if container.is_symlink() or not container.resolve().is_relative_to(base.resolve()):
        raise ValueError("App container is outside the selected Simulator")
    source = container / "Library/Caches/rec636-native-pan-diagnostic.json"
    if source.is_symlink() or not source.resolve().is_relative_to(container.resolve()):
        raise ValueError("Trace escapes the selected app container")
    if not source.is_file():
        raise ValueError("Missing or unbounded synthetic trace")
    fd = os.open(source.resolve(), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 8 * 1024 * 1024:
            raise ValueError("Invalid trace owner/type/size")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(8 * 1024 * 1024 + 1)
        if len(data) > 8 * 1024 * 1024:
            raise ValueError("Trace exceeded the bound while reading")
    finally:
        os.close(fd)
    value = json.loads(data)
    trace = value.get("trace", {})
    expected = {"map-pan": "map-performance", "compact-filter": "live-demo",
                "onboarding-overview": "onboarding-map-overview"}[name]
    if trace.get("schema") != 2 or trace.get("fixture") != expected:
        raise ValueError("Trace is not the requested synthetic fixture")
    started = float((target.parent / (name + "-start.txt")).read_text())
    if not started <= trace.get("startedUnixSeconds", 0) <= time.time():
        raise ValueError("Trace is from another native invocation")
    with target.open("xb") as stream:
        stream.write(data)
    print(json.dumps({"case": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                      "nativeOutcomeUnchanged": True}))


if __name__ == "__main__":
    main()
