# Events decision-tree canvas

Open `../astir-events-flowchart.html` in a browser. The HTML embeds all current screen markup, media and controls. `../astir-events-linear.html` preserves the earlier linear review.

Read each stage from top to bottom. A diamond asks a question; its outgoing connectors state Yes, No or the actual account/booking/permission result. The destination screen is visible on the board. Cross-stage handoffs include a repeated preview when the exact screen is known. Ambiguous runtime states route to another decision instead of inventing a screen. Amber nodes are open product/design choices; reference nodes are comparisons, not required guest actions.

Drag or two-finger scroll to pan. Pinch/Ctrl+scroll zooms around the pointer. Click a preview to expand it in place; double-click a decision to frame its branches or a screen to focus. Clicking a node highlights its immediate connections. Search, stage navigation and the minimap move the camera; they do not hide the other screens. Original stage notes remain in a disclosure under each heading. This is a local review canvas, not a collaborative editor or working Events app.

## Sources and build

`decision-tree.json` owns conditions and edges. `continuous-layout.json` and the preserved linear HTML own the 172 canonical screens. The older 165-screen `flowchart-data.json` is historical and must not replace them. A graph screen node appears exactly once; cross-stage screen copies are display-only previews of the same screen.

`build-canvas.py` embeds those sources, the unchanged camera module, `canvas-review.js`, `decision-layout.js` and CSS into the HTML. The layout measures actual cards, puts decisions and outcomes on layers, and reserves separate connector tracks. Labels are placed on their own connectors, including retries and long connections. Expansion recalculates geometry. Media dimensions reserve space before loading.

From this artifact directory:

```sh
python3 flowchart/build-canvas.py
python3 flowchart/verify-decision-tree.py
bun flowchart/verify-decision-layout.js
```

Edit approved content in the linear source and grouping model first; edit conditional routing in the decision tree. Keep unknown/loading/failed lookup separate from proven no booking. Keep RSVP, download, admission, historical completion and current post/visit existence independent. Review open clauses before encoding a new policy.

## Validation limits

The static verifier checks exact original cards, assets/video, screen coverage, edge labels/endpoints, target screens and acyclic forward routing. The synthetic layout check covers every stage with compact, varied and expanded dimensions, asserting nodes and labels do not overlap and every label stays on its own connector. Source syntax and peer review cover initialization and inline expansion.

No browser/screenshot pass is claimed. The built-in browser blocked local-file access, and the prior headless runtime was unavailable. No alternate browser route was attempted after the security rejection. Browser interaction and visual review remain unverified; earlier browser evidence applies only to the preserved linear view. Synthetic geometry is not a browser rendering test.
