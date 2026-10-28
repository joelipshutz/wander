#!/usr/bin/env python3
"""Build a static REC-657 gallery from unchanged native screenshot exports.

Usage:
    python3 scripts/live-totem-gallery.py outputs/rec657/live-totem
    python3 scripts/live-totem-gallery.py /tmp/live-totem --manifest /tmp/results.json

Screenshots must be named REC-657-*.png. Optional compact-phone screenshots
belong in compact/. The video is live-totem-walkthrough.mp4. Only the output
HTML is written; source images and video are never copied or altered. Keep the
capture directory and generated HTML outside Git (for example ignored outputs/).

Optional manifest format:
    {"checks": [{"name": "Native unit suite", "status": "passed",
                 "details": "Recorded result details"}]}
Statuses: passed, failed, pending, not_run. A gallery does not infer test results
from screenshots or from a successful export. No third-party modules are needed.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import html
import json
import os
from pathlib import Path
import re
import struct
from urllib.parse import quote


BASELINE = "aa2182a8c0"
SCENARIOS = {
    "01-live-with-feed": ("overview", "Live, with the feed", "The Totem markers in the existing Live layout."),
    "02-all-states-map": ("overview", "Eight states, one map", "The fictional fixture places together on native MapKit."),
    "03-you-been-persistent-list": ("states", "Your Been · in a list", "Coral solid rail and the persistent list marker."),
    "04-you-wanna-list": ("states", "Your Wanna · in a list", "Coral dotted rail and the persistent list marker."),
    "05-social-been": ("states", "Social Been", "Blue solid rail for a readable social save."),
    "06-social-wanna": ("states", "Social Wanna", "Blue dotted rail for a readable social save."),
    "07-mixed-one-place": ("states", "Mixed saves · one place", "Personal and social status share one category tile."),
    "08-list-only": ("states", "List membership only", "A list marker with no invented personal or social status."),
    "09-list-over-featured": ("states", "List membership takes precedence", "Current readable list membership suppresses the green fallback."),
    "10-featured-only": ("states", "Featured only", "Solid green is the fallback when no authorized save or list state applies."),
    "11-colored-people-options": ("filters", "People, in color", "Personal coral and social blue in the People choices."),
    "12-green-scope-option": ("filters", "Featured scope", "The green Featured choice in the scope menu."),
    "12a-only-friends-map": ("filters", "Only Friends", "The map after applying the Friends audience filter."),
    "12b-only-me-map": ("filters", "Only Me", "The map after applying the personal audience filter."),
    "13-lists-activity-option": ("filters", "Lists activity", "The Lists choice in the activity menu."),
    "14-lists-filter-map": ("filters", "Lists on the map", "The map with the Lists activity filter applied."),
    "15-list-addition-preview": ("persistence", "A list addition", "The selected place preview for list activity."),
    "16-old-membership-recent-filter": ("persistence", "An older membership, a recent window", "Review the list marker independently from the visible activity window."),
    "17-place-profile-navigation": ("journey", "Into the place", "Native place navigation from the selected map preview."),
    "18-live-return": ("journey", "Back to Live", "The map after returning from the place."),
    "19-save-featured-as-wanna": ("journey", "Save Featured as Wanna", "The native save flow for the Featured fixture place."),
    "20-featured-becomes-wanna": ("journey", "Featured becomes your Wanna", "Review the resulting coral dotted status after saving."),
}
SECTIONS = [
    ("overview", "01", "Live, in context", "Start with the full surface, then inspect the map with all eight fixture states."),
    ("states", "02", "One place. Its current meaning.", "Eight selected-place captures show category, ownership, saved status, and list membership."),
    ("filters", "03", "The controls speak the same language", "People, scope, and activity choices alongside their map results."),
    ("persistence", "04", "Membership outlasts an event", "List membership is current place state. A narrower event window should not erase its marker."),
    ("journey", "05", "From discovery to a saved place", "Place navigation, the return to Live, and the Featured-to-Wanna transition."),
    ("compact", "06", "On a smaller phone", "Separate compact-device captures, shown at their original aspect ratios."),
    ("additional", "07", "Additional native captures", "Appearance, density, and other recorded views."),
]


def escape(value: object) -> str:
    return html.escape(str(value), quote=True)


def local_url(path: Path, output: Path) -> str:
    return quote(Path(os.path.relpath(path, output.parent)).as_posix(), safe="/")


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as source:
        header = source.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"Not a valid PNG header: {path.name}")
    width, height = struct.unpack(">II", header[16:24])
    if width == 0 or height == 0:
        raise ValueError(f"Invalid PNG dimensions: {path.name}")
    return width, height


def natural_key(value: str) -> list[tuple[int, object]]:
    return [(0, int(part)) if part.isdigit() else (1, part.casefold())
            for part in re.split(r"(\d+)", value)]


def scenario(path: Path, captures: Path) -> tuple[str, str, str]:
    key = path.stem.removeprefix("REC-657-")
    section, title, note = SCENARIOS.get(
        key, ("additional", key.replace("-", " ").replace("_", " ").capitalize(),
              "Additional capture from the native app; inspect the original for detail."))
    # Exporters may append an attachment identifier or device dimensions.
    if key not in SCENARIOS:
        for slug, description in SCENARIOS.items():
            if key.startswith(slug + "-") or key.endswith("-" + slug):
                section, title, note = description
                break
    if any("compact" in part.casefold() for part in path.relative_to(captures).parts):
        section = "compact"
    return section, title, note


def card(path: Path, captures: Path, output: Path, title: str, note: str) -> str:
    width, height = png_dimensions(path)
    url = escape(local_url(path, output))
    name = escape(path.relative_to(captures).as_posix())
    return f'''<article class="capture-card">
<header><h3>{escape(title)}</h3><p>{escape(note)}</p></header>
<a class="capture" href="{url}" target="_blank" rel="noopener"
   aria-label="Open original screenshot: {escape(title)}">
  <img src="{url}" width="{width}" height="{height}" loading="lazy" decoding="async"
       alt="Native Astir simulator capture with fictional fixtures: {escape(title)}">
</a>
<div class="capture-meta"><span>{width:,} × {height:,} px</span><a href="{url}" target="_blank" rel="noopener">Open original ↗</a></div>
<details class="filename"><summary>Source PNG</summary><code>{name}</code></details>
</article>'''


def validation_markup(manifest: Path | None, output: Path) -> str:
    if manifest is None:
        return '''<div class="validation-note"><span class="tag pending">Results not supplied</span>
<p>No validation manifest was supplied. These screenshots document visible states; they do not establish that tests passed.</p></div>'''
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("checks"), list):
        raise ValueError("Manifest must be an object containing a checks array.")
    labels = {"passed": "Passed", "failed": "Failed", "pending": "Pending", "not_run": "Not run"}
    rows = []
    for check in data["checks"]:
        if not isinstance(check, dict) or not isinstance(check.get("name"), str):
            raise ValueError("Every manifest check needs a string name.")
        status = check.get("status", "pending")
        if status not in labels:
            raise ValueError(f"Unsupported manifest status: {status!r}")
        details = check.get("details", "")
        if not isinstance(details, str):
            raise ValueError("Manifest check details must be a string.")
        rows.append(f'<li><div><strong>{escape(check["name"])}</strong>'
                    f'<p>{escape(details)}</p></div><span class="tag {status}">{labels[status]}</span></li>')
    if not rows:
        rows.append('<li>No check results were recorded in this manifest.</li>')
    return ('<p class="section-copy">Results below are recorded by the supplied manifest. '
            'The gallery generator does not run or infer checks.</p>'
            f'<ul class="checks">{"".join(rows)}</ul>'
            f'<a class="source-link" href="{escape(local_url(manifest, output))}">Open validation manifest ↗</a>')


def build(captures: Path, output: Path, manifest: Path | None) -> int:
    paths = sorted((path for path in captures.rglob("REC-657-*.png") if path.is_file()),
                   key=lambda path: natural_key(path.relative_to(captures).as_posix()))
    groups: dict[str, list[str]] = defaultdict(list)
    for path in paths:
        section, title, note = scenario(path, captures)
        groups[section].append(card(path, captures, output, title, note))
    sections = []
    navigation = []
    for key, number, title, description in SECTIONS:
        if key in {"compact", "additional"} and not groups[key]:
            continue
        navigation.append(f'<a href="#{key}">{escape(title if key == "overview" else {"states": "Eight states", "filters": "Filters", "persistence": "Membership", "journey": "Place journey", "compact": "Compact", "additional": "More"}[key])}</a>')
        content = ('<div class="capture-grid">' + "\n".join(groups[key]) + '</div>') if groups[key] else (
            '<p class="pending-capture">Capture pending · no matching exported PNG is present.</p>')
        sections.append(f'''<section id="{key}" aria-labelledby="{key}-title">
<div class="section-heading"><span class="section-number">{number}</span><div>
<h2 id="{key}-title">{escape(title)}</h2><p class="section-copy">{escape(description)}</p></div></div>
{content}</section>''')
    video = captures / "live-totem-walkthrough.mp4"
    if video.is_file():
        video_url = escape(local_url(video, output))
        video_markup = f'''<div class="video-layout"><video controls playsinline preload="metadata">
<source src="{video_url}" type="video/mp4">Your browser cannot play this video. <a href="{video_url}">Open the walkthrough.</a>
</video><div><h3>The native interaction sequence</h3><p>Review the map, filters, selection, and place flow in motion. The walkthrough uses fictional fixture content.</p>
<a class="source-link" href="{video_url}" target="_blank" rel="noopener">Open original MP4 ↗</a></div></div>'''
    else:
        video_markup = '<p class="pending-capture">Walkthrough pending · live-totem-walkthrough.mp4 is not present.</p>'
    replacements = {
        "__BASELINE__": BASELINE,
        "__COUNT__": str(len(paths)),
        "__NAV__": "".join(navigation),
        "__SECTIONS__": "\n".join(sections),
        "__VIDEO__": video_markup,
        "__VALIDATION__": validation_markup(manifest, output),
    }
    document = TEMPLATE
    for token, value in replacements.items():
        document = document.replace(token, value)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(document, encoding="utf-8")
    return len(paths)


TEMPLATE = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light"><title>Astir · Live Totem review · REC-657</title>
<style>
:root{--paper:#f7f5ef;--surface:#fffdf8;--ink:#262722;--muted:#686b62;--line:#dadcd2;--coral:#f05a3c;--coral-text:#b83c24;--blue:#69b8d7;--green:#6fb985}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
a{color:inherit;text-underline-offset:4px;text-decoration-thickness:1px}a:focus-visible,summary:focus-visible{outline:3px solid var(--coral-text);outline-offset:5px}h1,h2,h3,p{margin:0}img{display:block;height:auto;max-width:100%}
.shell{width:min(1440px,calc(100% - 88px));margin:auto}.masthead{display:flex;align-items:center;justify-content:space-between;gap:20px;padding:25px 0;border-bottom:1px solid var(--line)}.brand{font-size:30px;line-height:1;letter-spacing:-1.6px;font-weight:800;text-decoration:none}.brand span{color:var(--coral)}.issue{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}
.hero{display:grid;grid-template-columns:1.4fr 1fr;align-items:end;gap:70px;padding:57px 0 40px}.eyebrow{font-size:10px;letter-spacing:.14em;text-transform:uppercase;font-weight:700;color:var(--coral-text)}h1{font:400 clamp(48px,5.7vw,78px)/1.05 Georgia,"Times New Roman",serif;letter-spacing:-2.7px;margin-top:12px}h1 em{font-weight:400;color:var(--coral-text)}.lede{font-size:16px;line-height:1.75;color:var(--muted);max-width:650px;margin-top:23px}.hero-note{border-left:2px solid var(--coral);padding-left:24px;max-width:420px}.hero-note strong{font-weight:650}.hero-note p{font-size:13px;color:var(--muted)}.hero-note p+p{margin-top:13px}.hero-note strong{color:var(--ink)}
.provenance{display:flex;flex-wrap:wrap;justify-content:space-between;gap:10px 28px;font-size:11px;color:var(--muted);padding:15px 0;border-block:1px solid var(--line)}code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.95em}.legend{display:flex;flex-wrap:wrap;gap:15px 30px;padding:23px 0;font-size:12px}.legend-item{display:inline-flex;gap:9px;align-items:center}.rail{display:inline-block;width:25px;height:0;border-top:4px solid;flex-shrink:0}.rail.coral{border-color:var(--coral)}.rail.blue{border-color:var(--blue)}.rail.green{border-color:var(--green)}.rail.dotted{border-top:4px dotted var(--ink)}.list-mark{width:25px;text-align:center;font-size:18px;font-weight:700;line-height:1}
.page-nav{display:flex;flex-wrap:wrap;gap:7px 20px;padding:15px 0 19px;border-bottom:1px solid var(--line);font-size:12px}.page-nav a{padding-block:5px;text-decoration:none}.page-nav a:hover{text-decoration:underline}
section{padding:48px 0 50px;border-bottom:1px solid var(--line);scroll-margin-top:15px}.section-heading{display:flex;gap:17px;align-items:baseline;margin-bottom:28px}.section-number{font-size:10px;letter-spacing:.1em;font-weight:700;color:var(--coral-text)}h2{font:400 34px/1.18 Georgia,"Times New Roman",serif;letter-spacing:-.8px}.section-copy{font-size:13px;color:var(--muted);max-width:780px;margin-top:11px;line-height:1.75}
.capture-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(245px,1fr));gap:35px 28px;align-items:start}.capture-card{min-width:0;max-width:390px;width:100%;margin-inline:auto}.capture-card header{min-height:101px;padding-bottom:18px}.capture-card h3{font-size:17px;font-weight:650;line-height:1.35;letter-spacing:-.3px}.capture-card header p{font-size:12px;color:var(--muted);margin-top:8px;max-width:340px;line-height:1.65}.capture{display:block;background:white;box-shadow:0 8px 27px #292b2012;outline:1px solid #d5d8ce;text-decoration:none}.capture img{width:100%}.capture:hover{outline-color:#969d8d}.capture-meta{display:flex;justify-content:space-between;gap:10px;font-size:10px;color:var(--muted);margin-top:12px}.filename{font-size:10px;color:var(--muted);margin-top:9px}.filename summary{cursor:pointer;padding-block:3px}.filename code{display:block;margin-top:6px;overflow-wrap:anywhere}.pending-capture{padding:28px;border:1px dashed #b8bdb0;border-radius:12px;font-size:13px;color:var(--muted);background:#edeee6}
.video-layout{display:grid;grid-template-columns:minmax(220px,380px) 1fr;gap:38px;align-items:center}.video-layout video{display:block;width:100%;max-height:760px;background:var(--ink);border:1px solid var(--line)}.video-layout h3{font:400 29px/1.25 Georgia,"Times New Roman",serif;letter-spacing:-.5px}.video-layout p{max-width:490px;font-size:14px;color:var(--muted);margin-top:15px;line-height:1.8}.source-link{display:inline-block;font-size:12px;margin-top:20px}.validation-note{display:flex;gap:24px;align-items:center;padding:25px;background:#edeee6;border-radius:12px}.validation-note p{font-size:13px;color:var(--muted);max-width:800px}.tag{display:inline-block;flex-shrink:0;border-radius:100px;padding:5px 11px;font-size:10px;font-weight:650;white-space:nowrap;background:#e6e7dd;color:#4f5548}.tag.passed{background:#d8eadc;color:#275e38}.tag.failed{background:#f5ded7;color:#94371f}.tag.pending,.tag.not_run{background:#e6e7dd;color:#4f5548}.checks{padding:0;list-style:none;max-width:930px;margin:24px 0 0}.checks li{display:flex;justify-content:space-between;gap:25px;align-items:start;padding:17px 0;border-bottom:1px solid var(--line)}.checks strong{font-size:13px;font-weight:650}.checks p{font-size:12px;color:var(--muted);margin-top:5px;white-space:pre-line}.footer{display:flex;justify-content:space-between;gap:20px;padding:25px 0 35px;font-size:11px;color:var(--muted)}
@media(min-width:1250px){#overview .capture-grid{grid-template-columns:repeat(2,minmax(0,1fr));max-width:900px}#overview .capture-card{max-width:370px}}
@media(max-width:900px){.shell{width:calc(100% - 44px)}.hero{gap:32px}.hero-note{padding-left:18px}h1{font-size:56px}.capture-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:32px 23px}.capture-card header{min-height:110px}.video-layout{gap:28px;grid-template-columns:minmax(200px,320px) 1fr}}
@media(max-width:600px){.shell{width:calc(100% - 36px)}.masthead{padding:23px 0}.issue{font-size:9px;letter-spacing:.05em}.hero{grid-template-columns:1fr;gap:25px;padding:36px 0 28px}h1{font-size:53px;letter-spacing:-2px}.lede{font-size:14px;margin-top:19px}.hero-note{max-width:none}.hero-note p{font-size:12px}.provenance{display:block}.provenance span{display:block}.provenance span+span{margin-top:5px}.legend{gap:14px 23px;font-size:11px}.page-nav{gap:6px 17px;font-size:11px}section{padding:34px 0 37px}.section-heading{gap:12px}h2{font-size:29px}.section-copy{font-size:12px}.capture-grid{grid-template-columns:1fr;gap:33px}.capture-card{max-width:350px}.capture-card header{min-height:0;padding-bottom:17px}.capture-card h3{font-size:18px}.capture-card header p{font-size:12px}.video-layout{grid-template-columns:1fr;gap:23px}.video-layout video{max-width:350px;margin-inline:auto;max-height:none}.video-layout h3{font-size:25px}.video-layout p{font-size:13px}.validation-note{align-items:start;flex-direction:column;gap:13px;padding:20px}.footer{display:block;font-size:10px}.footer span{display:block}.footer span+span{margin-top:7px}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}@media print{body{background:white}.shell{width:100%}.page-nav,video{display:none}.capture-grid{grid-template-columns:repeat(3,minmax(0,1fr))}.capture-card{break-inside:avoid}.capture{box-shadow:none}section{break-before:auto}.hero{padding-top:20px}}
</style>
</head>
<body><div class="shell">
<header class="masthead"><a class="brand" href="#top">astir<span>.</span></a><span class="issue">REC-657 · Native Live review</span></header>
<main id="top">
<div class="hero"><div><span class="eyebrow">Totem · production integration</span><h1>A place, with<br><em>meaning.</em></h1>
<p class="lede">The approved Totem direction, brought into Live. Category leads. Personal and social saves keep their color. Current list membership stays visible.</p></div>
<aside class="hero-note"><p><strong>Actual native SwiftUI + MapKit.</strong> Simulator screenshots exported from the UI test result bundle, using fictional, memory-only fixtures.</p><p>This is a visual review of the integration. Test outcomes appear only when a validation manifest is supplied.</p></aside></div>
<div class="provenance"><span>Integration baseline · latest main <code>__BASELINE__</code></span><span>__COUNT__ native PNG captures · original source pixels preserved</span></div>
<div class="legend" aria-label="Totem visual language"><span class="legend-item"><i class="rail coral" aria-hidden="true"></i>Your saves</span><span class="legend-item"><i class="rail blue" aria-hidden="true"></i>Social saves</span><span class="legend-item"><i class="rail" aria-hidden="true"></i>Been</span><span class="legend-item"><i class="rail dotted" aria-hidden="true"></i>Wanna</span><span class="legend-item"><b class="list-mark" aria-hidden="true">☷</b>In a list</span><span class="legend-item"><i class="rail green" aria-hidden="true"></i>Featured fallback</span></div>
<nav class="page-nav" aria-label="Review sections">__NAV__<a href="#walkthrough">Walkthrough</a><a href="#validation">Validation</a></nav>
__SECTIONS__
<section id="walkthrough" aria-labelledby="walkthrough-title"><div class="section-heading"><span class="section-number">▶</span><div><h2 id="walkthrough-title">See the sequence</h2><p class="section-copy">Recorded native interactions, with playback under your control.</p></div></div>__VIDEO__</section>
<section id="validation" aria-labelledby="validation-title"><div class="section-heading"><span class="section-number">↳</span><div><h2 id="validation-title">Recorded validation</h2></div></div>__VALIDATION__</section>
</main><footer class="footer"><span>Astir · REC-657 · fictional fixture content</span><span>Static local gallery · no scripts, external fonts, image edits, or network assets</span></footer>
</div></body></html>
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("captures", type=Path, help="Directory containing REC-657-*.png exports")
    parser.add_argument("--output", type=Path, help="Output HTML path; defaults to captures/index.html")
    parser.add_argument("--manifest", type=Path, help="Optional JSON with recorded validation checks")
    args = parser.parse_args()
    captures = args.captures.resolve()
    output = (args.output or captures / "index.html").resolve()
    manifest = args.manifest.resolve() if args.manifest else None
    if not captures.is_dir():
        parser.error(f"Capture directory does not exist: {captures}")
    if output.suffix.casefold() != ".html":
        parser.error("Output must have an .html extension.")
    try:
        count = build(captures, output, manifest)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"Wrote {output} ({count} original PNG captures)")


if __name__ == "__main__":
    main()
