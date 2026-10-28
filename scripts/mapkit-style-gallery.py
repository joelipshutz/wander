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
STATES = ["overview", "selected", "draw-review"]


def export_named(source, destination, device, overlays=None, states=STATES):
    for style, *_ in OPTIONS:
        for state in states:
            state_source = overlays if overlays and state == "draw-review" else source
            manifest = json.loads((state_source / "manifest.json").read_text())
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
    parser.add_argument("--states", choices=STATES, nargs="+", default=STATES)
    parser.add_argument("--validation-note", default="See the REC-661 handoff for validation results and limits.")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    states = list(dict.fromkeys(args.states))
    initial_state = states[0]
    args.output.mkdir(parents=True, exist_ok=True)
    for device in ["large", "compact"]:
        export_named(getattr(args, device), args.output, device, getattr(args, device + "_overlays"), states)
    cards = []
    for number, (key, name, config, description) in enumerate(OPTIONS, 1):
        cards.append(f'''<article><div class="eyebrow">0{number} / {html.escape(config)}</div>
<h2>{name}</h2><p>{html.escape(description)}</p><a class="capture" href="large-{key}-{initial_state}.png">
<img data-style="{key}" src="large-{key}-{initial_state}.png" alt="{name} native SwiftUI map screenshot"></a></article>''')
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Astir — five native MapKit options</title><style>
*{box-sizing:border-box}body{margin:0;background:#f2e9db;color:#141714;font:16px -apple-system,BlinkMacSystemFont,sans-serif}
header,main,footer{max-width:1800px;margin:auto;padding:32px}header{padding-bottom:18px}
.eyebrow{font-size:12px;text-transform:uppercase;letter-spacing:.12em;color:#605e56}h1{font:52px Georgia,serif;margin:15px 0}
header p{max-width:900px;line-height:1.55}h2{font:32px Georgia,serif;margin:8px 0}article p{font-size:14px;line-height:1.5;min-height:62px}
main{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:24px;padding-top:14px}img{width:100%;height:auto;display:block;border-radius:22px;box-shadow:0 9px 30px #14171420}
nav{display:flex;flex-wrap:wrap;gap:18px;margin-top:20px}label{font-size:13px;font-weight:600}select{display:block;margin-top:7px;padding:10px 32px 10px 12px;border:1px solid #aaa398;border-radius:9px;background:#fffaf2;font:inherit;color:inherit}
footer{font-size:14px;line-height:1.6;border-top:1px solid #cfc6b8}a{color:inherit}a:focus-visible,select:focus-visible{outline:3px solid #b23620;outline-offset:5px}
@media(max-width:1100px){main{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:700px){h1{font-size:38px}main{grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}header,main,footer{padding:22px}}@media(max-width:420px){main{grid-template-columns:1fr}}
</style><header><div class="eyebrow">Astir / native map review / REC-661</div><h1>Five ways to see your places.</h1>
<p>Real screenshots from the current SwiftUI Live screen. Same places, same camera, same interactions. Paper and Ink are my everyday picks; Aerial is a useful optional view. Click any capture for the original PNG.</p>
<nav aria-label="Screenshot comparison controls"><label>Phone<select id="device"><option value="large">iPhone 17 Pro</option><option value="compact">iPhone 17e</option></select></label>
<label>State<select id="state"><option value="overview">Map overview</option><option value="selected">Selected place</option><option value="draw-review">Area overlay</option></select></label></nav></header><main>'''
    page += "\n".join(cards)
    page += '''</main><footer><strong>Native maps, unchanged screenshots.</strong> iOS 26.5 simulator; synthetic demo places. This review uses current main's pins, separate from the pending Totem pin refinement. Light and dark options show matching app appearance. All retain native POIs, flat elevation, controls and Apple attribution. No production default has changed.
<p>VALIDATION_NOTE Native POI taps, real-device performance and battery/bandwidth parity are not established by these captures. Hybrid imagery is visually busier and should remain optional.</p>
<p>Apple references: <a href="https://developer.apple.com/design/human-interface-guidelines/maps">Maps design guidance</a> · <a href="https://developer.apple.com/documentation/mapkit/mapstyle">MapStyle</a> · <a href="https://developer.apple.com/videos/play/wwdc2022/10035/">Configuration and overlays</a>.</p></footer>
<script>const device=document.querySelector('#device'),state=document.querySelector('#state');function update(){document.querySelectorAll('img[data-style]').forEach(img=>{const path=`${device.value}-${img.dataset.style}-${state.value}.png`;img.src=path;img.parentElement.href=path;});}device.addEventListener('change',update);state.addEventListener('change',update);</script></html>'''
    labels = {"overview": "Map overview", "selected": "Selected place", "draw-review": "Area overlay"}
    options = ''.join(f'<option value="{state}">{labels[state]}</option>' for state in states)
    old_options = ''.join(f'<option value="{state}">{labels[state]}</option>' for state in STATES)
    page = page.replace(old_options, options)
    page = page.replace('VALIDATION_NOTE', html.escape(args.validation_note))
    (args.output / "index.html").write_text(page)
    print(f"Created gallery with {len(states) * 10} original screenshots: {args.output / 'index.html'}")


if __name__ == "__main__":
    main()
