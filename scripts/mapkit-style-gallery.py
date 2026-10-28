#!/usr/bin/env python3
"""Package named, unmodified XCTest screenshots into a local comparison gallery."""
import argparse
import html
import json
from pathlib import Path
import shutil

OPTIONS = [
    ("paper", "Paper", "Muted · Light", "Calmer roads keep your places in focus. My daytime pick."),
    ("atlas", "Atlas", "Standard · Light", "Stronger streets, parks and geographic detail. Current Live baseline."),
    ("ink", "Ink", "Muted · Dark", "Restrained night cartography with clear pin contrast. My night pick."),
    ("midnight", "Midnight", "Standard · Dark", "More geographic detail against a dark background."),
    ("aerial", "Aerial", "Hybrid · Light", "Labeled satellite imagery for parks and coastal context. Visually busiest."),
]
GRAYSCALE_OPTIONS = [
    OPTIONS[0],
    ("graphite", "Grayscale Light", "Exploratory grayscale · Light",
     "A grayscale treatment of the light map. Compare street detail and pin contrast with native Paper."),
    OPTIONS[2],
    ("graphite-dark", "Grayscale Dark", "Exploratory grayscale · Dark",
     "A grayscale treatment of the dark map. Compare geographic detail and selected-place contrast with native Ink."),
]
STATES = ["overview", "selected", "draw-review"]
GRAYSCALE_STATES = ["overview", "selected"]
EXPERIMENT_KEYS = {"graphite", "graphite-dark"}


def export_named(source, destination, device, overlays=None, states=STATES,
                 options=OPTIONS, experiments=None):
    manifests = {}
    for style, *_ in options:
        for state in states:
            if style in EXPERIMENT_KEYS:
                state_source = experiments
            else:
                state_source = overlays if overlays and state == "draw-review" else source
            if state_source not in manifests:
                manifests[state_source] = json.loads((state_source / "manifest.json").read_text())
            manifest = manifests[state_source]
            name = f"REC661-{style}-{state}"
            matches = [a for test in manifest for a in test["attachments"]
                       if name in a["suggestedHumanReadableName"]
                       and a["exportedFileName"].endswith(".png")]
            if len(matches) != 1:
                raise ValueError(f"Expected one {device}/{name}, found {len(matches)}")
            shutil.copyfile(state_source / matches[0]["exportedFileName"],
                            destination / f"{device}-{style}-{state}.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--large", type=Path, required=True)
    parser.add_argument("--compact", type=Path, required=True)
    parser.add_argument("--large-overlays", type=Path)
    parser.add_argument("--compact-overlays", type=Path)
    parser.add_argument("--grayscale-review", action="store_true",
                        help="Compare Paper and Ink with exploratory grayscale light and dark captures.")
    parser.add_argument("--large-experiments", type=Path)
    parser.add_argument("--compact-experiments", type=Path)
    parser.add_argument("--states", choices=STATES, nargs="+",
                        help="Capture states to include; grayscale review supports overview and selected only.")
    parser.add_argument("--validation-note", default="See the REC-661 handoff for validation results and limits.")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.grayscale_review:
        if not args.large_experiments or not args.compact_experiments:
            parser.error("--grayscale-review requires --large-experiments and --compact-experiments")
        if args.states and "draw-review" in args.states:
            parser.error("--grayscale-review supports only overview and selected states")
    gallery_options = GRAYSCALE_OPTIONS if args.grayscale_review else OPTIONS
    default_states = GRAYSCALE_STATES if args.grayscale_review else STATES
    states = list(dict.fromkeys(args.states or default_states))
    initial_state = states[0]
    args.output.mkdir(parents=True, exist_ok=True)
    for device in ["large", "compact"]:
        export_named(getattr(args, device), args.output, device,
                     overlays=getattr(args, device + "_overlays"), states=states,
                     options=gallery_options, experiments=getattr(args, device + "_experiments"))
    cards = []
    capture_description = "isolated MapKit preview" if args.grayscale_review else "native SwiftUI map"
    for number, (key, name, config, description) in enumerate(gallery_options, 1):
        cards.append(f'''<article><div class="eyebrow">0{number} / {html.escape(config)}</div>
<h2>{name}</h2><p>{html.escape(description)}</p><a class="capture" href="large-{key}-{initial_state}.png">
<img data-style="{key}" src="large-{key}-{initial_state}.png" alt="{name} {capture_description} screenshot"></a></article>''')
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PAGE_TITLE</title><style>
*{box-sizing:border-box}body{margin:0;background:#f2e9db;color:#141714;font:16px -apple-system,BlinkMacSystemFont,sans-serif}
header,main,footer{max-width:1800px;margin:auto;padding:32px}header{padding-bottom:18px}
.eyebrow{font-size:12px;text-transform:uppercase;letter-spacing:.12em;color:#605e56}h1{font:52px Georgia,serif;margin:15px 0}
header p{max-width:900px;line-height:1.55}h2{font:32px Georgia,serif;margin:8px 0}article p{font-size:14px;line-height:1.5;min-height:62px}
main{display:grid;grid-template-columns:repeat(OPTION_COUNT,minmax(0,1fr));gap:24px;padding-top:14px}img{width:100%;height:auto;display:block;border-radius:22px;box-shadow:0 9px 30px #14171420}
nav{display:flex;flex-wrap:wrap;gap:18px;margin-top:20px}label{font-size:13px;font-weight:600}select{display:block;margin-top:7px;padding:10px 32px 10px 12px;border:1px solid #aaa398;border-radius:9px;background:#fffaf2;font:inherit;color:inherit}
footer{font-size:14px;line-height:1.6;border-top:1px solid #cfc6b8}a{color:inherit}a:focus-visible,select:focus-visible{outline:3px solid #b23620;outline-offset:5px}
@media(max-width:1100px){main{grid-template-columns:repeat(MID_COLUMNS,minmax(0,1fr))}}@media(max-width:700px){h1{font-size:38px}main{grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}header,main,footer{padding:22px}}@media(max-width:420px){main{grid-template-columns:1fr}}
</style><header><div class="eyebrow">Astir / native map review / REC-661</div><h1>PAGE_HEADING</h1>
<p>PAGE_INTRO</p>
<nav aria-label="Screenshot comparison controls"><label>Phone<select id="device"><option value="large">iPhone 17 Pro</option><option value="compact">iPhone 17e</option></select></label>
<label>State<select id="state"><option value="overview">Map overview</option><option value="selected">Selected place</option><option value="draw-review">Area overlay</option></select></label></nav></header><main>'''
    page += "\n".join(cards)
    page += '''</main><footer><strong>FOOTER_TITLE</strong> REVIEW_CONTEXT
<p>VALIDATION_NOTE Native POI taps, real-device performance and battery/bandwidth parity are not established by these captures. REVIEW_NOTES</p>
<p>Apple references: <a href="https://developer.apple.com/design/human-interface-guidelines/maps">Maps design guidance</a> · <a href="https://developer.apple.com/documentation/mapkit/mapstyle">MapStyle</a> · <a href="https://developer.apple.com/videos/play/wwdc2022/10035/">Configuration and overlays</a>.</p></footer>
<script>const device=document.querySelector('#device'),state=document.querySelector('#state');function update(){document.querySelectorAll('img[data-style]').forEach(img=>{const path=`${device.value}-${img.dataset.style}-${state.value}.png`;img.src=path;img.parentElement.href=path;});}device.addEventListener('change',update);state.addEventListener('change',update);</script></html>'''
    labels = {"overview": "Map overview", "selected": "Selected place", "draw-review": "Area overlay"}
    options = ''.join(f'<option value="{state}">{labels[state]}</option>' for state in states)
    old_options = ''.join(f'<option value="{state}">{labels[state]}</option>' for state in STATES)
    page = page.replace(old_options, options)
    if args.grayscale_review:
        title = "Astir — exploratory grayscale map comparison"
        heading = "Grayscale, beside the native fallbacks."
        intro = ("Compare Paper and Ink with exploratory grayscale light and dark treatments "
                 "in an isolated in-app MapKit preview, using the same fixture pins and camera. "
                 "Paper and Ink were captured afresh in that preview with the grayscale overlay switched off. "
                 "They remain the native fallback options. "
                 "Review the map overview and selected-place state on each phone; click any capture for the original PNG.")
        footer_title = "Isolated MapKit preview, unchanged screenshots."
        review_context = ("iOS 26.5 simulator; synthetic demo places. The preview hosts a native MKMapView "
                          "in SwiftUI and reuses the fixture pins. All four comparisons use the same preview "
                          "camera and chrome, including freshly captured Paper and Ink states. "
                          "No production default has changed.")
        review_notes = ("Grayscale is an experiment, not a new production default. "
                        "Live integration and its complete interaction set remain unvalidated. "
                        "Paper and Ink remain the supported native fallbacks.")
    else:
        title = "Astir — five native MapKit options"
        heading = "Five ways to see your places."
        intro = ("Real screenshots from the current SwiftUI Live screen. Same places, same camera, same interactions. "
                 "Paper and Ink are my everyday picks; Aerial is a useful optional view. "
                 "Click any capture for the original PNG.")
        footer_title = "Native maps, unchanged screenshots."
        review_context = ("iOS 26.5 simulator; synthetic demo places. This review uses current main's pins, "
                          "separate from the pending Totem pin refinement. Light and dark options show matching "
                          "app appearance. All retain native POIs, flat elevation, controls and Apple attribution. "
                          "No production default has changed.")
        review_notes = "Hybrid imagery is visually busier and should remain optional."
    for marker, value in [("PAGE_TITLE", title), ("PAGE_HEADING", heading),
                          ("PAGE_INTRO", intro), ("FOOTER_TITLE", footer_title),
                          ("REVIEW_CONTEXT", review_context), ("REVIEW_NOTES", review_notes)]:
        page = page.replace(marker, html.escape(value, quote=False))
    page = page.replace("OPTION_COUNT", str(len(gallery_options)))
    page = page.replace("MID_COLUMNS", "2" if args.grayscale_review else "3")
    page = page.replace('VALIDATION_NOTE', html.escape(args.validation_note))
    (args.output / "index.html").write_text(page)
    image_count = len(states) * len(gallery_options) * 2
    print(f"Created gallery with {image_count} original screenshots: {args.output / 'index.html'}")


if __name__ == "__main__":
    main()
