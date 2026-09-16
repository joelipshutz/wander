# Events review canvas

Open `../astir-events-flowchart.html` in a browser. The page is self-contained: camera controls, screen markup, every image and the motion preview are embedded. `../astir-events-linear.html` preserves the prior linear review.

Drag empty space or a screen to pan. Two-finger scrolling pans; pinch/Ctrl+scroll zooms at the pointer. Click a preview to expand it in place; double-click a screen to focus. Search accepts exact screen numbers or names. Fit all, Fit stage, Focus screen and the minimap change the camera without leaving the board. Keyboard controls are listed in the help button. This is a review canvas, not a collaborative editor; changing the view does not edit approved flows or persist product decisions.

The ten guest stages run left to right. Offline door, private-home location rules and Astir console are separate supporting groups. Chain lanes keep their existing arrow labels; alternative cases retain their branch brackets. The earlier graph model has only 165 screens and must not be used to reconstruct the current 172-screen content.

## Maintain the artifact

`build-canvas.py` reads the preserved linear HTML, `continuous-layout.json`, `canvas.css`, `canvas-camera.js` and `canvas-review.js`, then writes the canonical flowchart HTML. It extracts current cards and assets rather than generating new product wording. Intrinsic image and video dimensions are extracted from the embedded bytes so lazy loading cannot move the board.

From the artifact directory:

```sh
python3 flowchart/build-canvas.py
```

Product/content changes should first update the linear source and grouping model coherently. Rebuild, then check all card IDs/content/assets, the supporting branches, camera math, syntax and actual browser interactions. Refresh the publication hashes and validation record when publishing a changed artifact.

## Validation limits

All 172 screen contents and embedded media are preserved. Source syntax, camera gesture math and static peer checks passed. Static review caught and fixed collapse-selection changes and unreserved lazy-image geometry. No browser or screenshot pass is claimed: standalone gstack lacked its Chromium runtime, and the built-in browser blocked local file URLs under its security policy. No alternate route was attempted after that rejection. The preserved linear artifact retains its earlier browser evidence.
