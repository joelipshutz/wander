#!/usr/bin/env python3
"""Build the small REC-589 gallery from native XCUITest attachment exports.

Export with: xcrun xcresulttool export attachments --path RESULT --output-path DIR
Supply repeatable --large/--compact dirs in run order; later captures win.
Screenshots are resized/encoded only, never redrawn. Originals stay with xcresults.
"""
import argparse
import html
import json
from pathlib import Path
import subprocess

SCENARIOS = [
    ("checkIn-initial", "First check-in: initial viewport"),
    ("checkIn-silent", "First check-in: Silent on"),
    ("repeatCheckIn-silent", "Repeat check-in"),
    ("historical-silent", "Historical: Silent default"),
    ("wanna-silent", "First Wanna"),
    ("repeatWanna-silent", "Repeat Wanna"),
    ("sourceSave-silent", "Save from a person"),
    ("discover-quick-wanna-dialog", "Discover quick-save choice"),
    ("listPicker-silent", "One place to lists"),
    ("multiListPicker-silent", "Several places to lists"),
    ("new-list-inherits-silent", "New list inherits Silent"),
    ("list-direct-dialog", "List-detail suggestion"),
    ("list-addPlaces-dialog", "Add Places suggestion"),
    ("list-search-dialog", "List search result"),
    ("checkIn-staged-list-picker", "Staged picker: parent owns Silent"),
    ("checkIn-parent-silent", "Parent check-in and lists"),
    ("edit-existing-no-silent-control", "Content-only edit"),
    ("editWithLists-staged-list-picker", "Edit: stage new memberships"),
    ("editWithLists-parent-silent", "Edit with new lists: Silent"),
    ("sharedVisit-silent", "Accept shared check-in"),
    ("friends-silent", "Explicit invitation exception"),
    ("import-one-native-choice", "One-place import confirmation"),
    ("import-ten-first-three", "Import ten: select first three"),
    ("import-ten-native-choice", "Import ten: first Save confirmation"),
    ("import-ten-later-seven", "Import ten: later seven saved"),
    ("import-consumed-no-new-prompt", "Consumed import: no second prompt"),
    ("import-inline-details", "Inline import details"),
    ("checkIn-dark-accessibility-text", "Dark and accessibility text"),
]


def captures(directories):
    found = {}
    for directory in directories:
        root = Path(directory)
        manifest = json.loads((root / "manifest.json").read_text())
        for test in manifest:
            for item in test.get("attachments", []):
                name = item.get("suggestedHumanReadableName", "")
                if name.startswith("REC589-"):
                    key = name.removeprefix("REC589-").split("_0_")[0]
                    found[key] = (root / item["exportedFileName"], test["testIdentifier"])
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--large", action="append", required=True)
    parser.add_argument("--compact", action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sources = {"large": captures(args.large), "compact": captures(args.compact)}
    missing = [f"{size}/{key}" for size, entries in sources.items()
               for key, _ in SCENARIOS if key not in entries]
    if missing:
        raise SystemExit("Missing native captures: " + ", ".join(missing))
    args.output.mkdir(parents=True, exist_ok=True)
    cards, evidence = [], []
    for key, title in SCENARIOS:
        images = []
        for size, entries in sources.items():
            source, test = entries[key]
            relative = f"{size}/{key}.jpg"
            target = args.output / relative
            target.parent.mkdir(exist_ok=True)
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "65",
                            "--resampleWidth", "480", str(source), "--out", str(target)],
                           check=True, stdout=subprocess.DEVNULL)
            images.append(f'<figure><a href="{relative}"><img loading="lazy" src="{relative}" alt="{html.escape(title)} — {size}"></a><figcaption>{size.capitalize()} iPhone · iOS 26.5</figcaption></figure>')
            evidence.append({"scenario": key, "size": size, "image": relative, "test": test})
        cards.append(f'<section id="{key}"><h2>{html.escape(title)}</h2><div class="pair">{"".join(images)}</div></section>')
    style = "body{font:16px system-ui;background:#f3f1ed;color:#222;margin:0;padding:32px;max-width:1160px;margin:auto}h1{font-size:32px}p{line-height:1.6;max-width:800px}nav{display:flex;gap:10px;flex-wrap:wrap;margin:24px 0}nav a{color:#333;background:white;padding:8px 12px;border-radius:8px}.pair{display:flex;align-items:flex-start;gap:24px}section{padding:16px 0 32px;border-top:1px solid #ccc;scroll-margin:20px}figure{margin:0;flex:1;max-width:420px}img{width:100%;border-radius:14px;border:1px solid #ddd}figcaption{margin:8px 0;font-size:14px}a{color:#9c3428}@media(max-width:600px){body{padding:16px}.pair{gap:12px}h2{font-size:20px}}"
    nav = "".join(f'<a href="#{key}">{html.escape(title)}</a>' for key, title in SCENARIOS)
    document = f'<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>REC-589 native Silent controls</title><style>{style}</style><h1>Sender Silent controls</h1><p>Real Astir SwiftUI screens with isolated sample data. Open the <strong>Sender Silent Review</strong> Xcode scheme to interact with every scenario. Silent suppresses notifications while preserving the existing audience and Feed visibility.</p><p>These images are native simulator captures, resized only for review. Read the <a href="README.md">placement guide</a> and <a href="../../plans/rec589-sender-notification-testing.md">manual device checklist</a>. Actual APNs delivery requires signed-device testing.</p><nav>{nav}</nav>{"".join(cards)}</html>'
    (args.output / "index.html").write_text(document)
    (args.output / "captures.json").write_text(json.dumps(evidence, indent=2) + "\n")
    total = sum(p.stat().st_size for p in args.output.rglob("*") if p.is_file())
    print(f"{len(evidence)} native captures; gallery {total / 1024:.0f} KiB")


if __name__ == "__main__":
    main()
