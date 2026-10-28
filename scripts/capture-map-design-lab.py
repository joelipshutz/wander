#!/usr/bin/env python3
"""Capture the real Astir Map in an already-booted, dedicated iOS simulator."""
import argparse
from pathlib import Path
import subprocess
import time

PINS = ("porcelain", "signal", "bookmark", "ticket", "compass")
MAPS = ("quiet", "atlas", "night", "dimension", "hybrid")
BASE = [
    "-WanderMapCapture", "-WanderUseStorefrontFixtures",
    "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
    "-WanderMapCaptureMode", "friends",
]


def simctl(*args):
    subprocess.run(["xcrun", "simctl", *args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compact", action="store_true")
    parser.add_argument("--only", help="Capture one filename stem, e.g. map-dimension")
    parser.add_argument("--settle", type=float, default=8)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    simctl("install", args.device, str(args.app))
    simctl("status_bar", args.device, "override", "--time", "9:41",
           "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
           "--batteryState", "charged", "--batteryLevel", "100")

    captures = [("baseline", [], "light")]
    for pin in PINS:
        for state in ("overview", "selected"):
            flags = ["-WanderPinDesign", pin, "-WanderMapDesign", "quiet"]
            if state == "selected":
                flags += ["-WanderMapPlace", "Hearthline Coffee"]
            captures.append((f"pin-{pin}-{state}", flags, "light"))
    for style in MAPS:
        captures.append((f"map-{style}",
                         ["-WanderPinDesign", "porcelain", "-WanderMapDesign", style],
                         "dark" if style == "night" else "light"))
    if args.compact:
        captures = [("compact-porcelain", ["-WanderPinDesign", "porcelain"], "light")]
    if args.only:
        captures = [capture for capture in captures if capture[0] == args.only]
        if not captures:
            parser.error("Unknown capture name")

    for name, flags, appearance in captures:
        simctl("ui", args.device, "appearance", appearance)
        simctl("launch", "--terminate-running-process", args.device,
               "com.grayline.wander", *BASE, *flags)
        time.sleep(args.settle)
        simctl("io", args.device, "screenshot", str(args.output / f"{name}.png"))
        print(f"Captured {name}", flush=True)
    simctl("ui", args.device, "appearance", "light")


if __name__ == "__main__":
    main()
