# REC-214 image-generation prompts

Tool path: built-in image generation, using the current canonical 1024 px app
icon as the edit target. The curved-horizon direction received one targeted
refinement after the first result introduced road-like lines.

## Direction A — tilted plane

```text
Use case: logo-brand
Asset type: square iOS app icon concept exploration, Direction A — tilted map plane
Input image: edit target and strict brand reference. Preserve its full-bleed warm canvas, terracotta pin style, black editorial serif wordmark, restrained flat graphic language, and generous spacing.
Primary request: Keep the pin and the exact lowercase wordmark "rec.me". Remove only the wide oval landing ring beneath the pin. Redraw the pin's lower shaft so it tapers into a clean, unmistakable downward point. Align that point precisely into the round dot between "rec" and "me", making the dot read as the exact place being pinned.
Add a compact map-like surface beneath and slightly behind the wordmark, viewed from about a 35–45 degree angle. Direction A should feel like one smooth, shallow, tilted plane receding backward in perspective, with a gently curved far edge. It should occupy only the lower quarter to lower third of the icon and leave ample warm negative space. The wordmark remains fully legible in the foreground as if it sits at the marked point on that surface.
Style/medium: minimal vector-friendly 2.5D brand mark; flat colors with at most one subtle two-tone depth cue; strong silhouette; elegant and editorial, not illustrative.
Color palette: preserve warm canvas #F3DFCA, terracotta #D46F4D, solid black wordmark. Any map-plane tone must stay within this warm cream/terracotta family.
Text (verbatim): "rec.me" — exactly r-e-c, period, m-e; no other text.
Composition: centered vertical lockup; circular pin head and its small inner hole remain recognizable; pointed pin tip touches/enters the dot; angled surface flows behind the wordmark without obscuring letters.
Constraints: no oval ring at the bottom of the pin; no folded corner or folded map sheet; no road lines; no pencil; no literal continents; no blue/green globe; no extra lower-right object; no border; no rounded-corner mask baked in; no photorealism; no mockup; no watermark. Keep every element bold and readable at small app-icon sizes.
```

## Direction B — curved horizon

Base generation:

```text
Use case: logo-brand
Asset type: square iOS app icon concept exploration, Direction B — curved map horizon
Input image: edit target and strict brand reference. Preserve its full-bleed warm canvas, terracotta pin style, black editorial serif wordmark, restrained flat graphic language, and generous spacing.
Primary request: Keep the pin and the exact lowercase wordmark "rec.me". Remove only the wide oval landing ring beneath the pin. Redraw the pin's lower shaft so it tapers into a clean, unmistakable downward point. Align that point precisely into the round dot between "rec" and "me", making the dot read as the exact place being pinned.
Add a compact map/Earth surface beneath and behind the wordmark, seen from a low 45-degree angle. Direction B should feel like the upper edge of a gently curved world or map horizon: a shallow warm arc/oval slice with subtle curvature, not a full globe. It should occupy only the lower quarter to lower third of the icon, remain centered, and leave ample warm negative space. The wordmark remains fully legible in the foreground, anchored at the marked location on the curved surface.
Style/medium: minimal vector-friendly 2.5D brand mark; flat colors with at most one subtle two-tone depth cue; strong silhouette; elegant and editorial, not illustrative.
Color palette: preserve warm canvas #F3DFCA, terracotta #D46F4D, solid black wordmark. The curved surface must stay within warm cream and muted terracotta.
Text (verbatim): "rec.me" — exactly r-e-c, period, m-e; no other text.
Composition: centered vertical lockup; circular pin head and its small inner hole remain recognizable; pointed pin tip touches/enters the dot; the shallow curved surface passes behind the entire wordmark without obscuring letters.
Constraints: no oval ring at the bottom of the pin; no full globe; no continents; no blue or green; no folded corner or folded map sheet; no road lines; no latitude/longitude grid; no pencil; no extra lower-right object; no border; no rounded-corner mask baked in; no photorealism; no mockup; no watermark. Keep every element bold and readable at small app-icon sizes.
```

Targeted refinement:

```text
Use case: precise-object-edit
Asset type: square iOS app icon concept, targeted refinement of Direction B
Input image: edit target.
Primary request: Change only the curved map/Earth surface behind and below the "rec.me" wordmark. Remove every road-like white line, parcel line, and internal pattern from that surface. Make it one completely clean, smooth, solid warm curved horizon with no markings. Reduce its height substantially so it occupies only the lower 22–28 percent of the square, with generous warm background below and around it. Preserve a low 35–45 degree perspective and a subtle convex Earth-like curvature, but keep it a shallow abstract surface—not a full globe.
Invariants: keep the exact "rec.me" wordmark unchanged and fully legible; keep the terracotta pin unchanged; keep its sharp point precisely touching the dot; keep the warm full-bleed background and centered composition unchanged.
Color palette: warm canvas #F3DFCA, terracotta #D46F4D, solid black wordmark; curved surface should be one slightly darker warm cream or muted terracotta tone.
Constraints: no roads, no lines, no grid, no continents, no extra texture, no folded map, no extra objects, no text other than exact "rec.me", no border, no rounded-corner mask, no watermark.
```

## Direction C — floating terrain

```text
Use case: logo-brand
Asset type: square iOS app icon concept exploration, Direction C — compact floating terrain surface
Input image: edit target and strict brand reference. Preserve its full-bleed warm canvas, terracotta pin style, black editorial serif wordmark, restrained flat graphic language, and generous spacing.
Primary request: Keep the pin and the exact lowercase wordmark "rec.me". Remove only the wide oval landing ring beneath the pin. Redraw the pin's lower shaft so it tapers into a clean, unmistakable downward point. Align that point precisely into the round dot between "rec" and "me", making the dot read as the exact place being pinned.
Add a compact map-like surface beneath and slightly behind the wordmark, viewed from about a 40-degree angle. Direction C should be a single smooth floating terrain slice with a softly organic, curved perimeter and a very thin visible side edge for depth—more like a small abstract place-surface than a paper sheet. It must occupy only the lower quarter of the icon, stay centered with wide margins, and never fill the canvas. The wordmark remains fully legible in front, visually anchored to the marked point.
Style/medium: minimal vector-friendly 2.5D brand mark; flat colors, crisp edges, restrained one-step depth; strong silhouette; elegant and editorial.
Color palette: preserve warm canvas #F3DFCA, terracotta #D46F4D, solid black wordmark. Surface top is a slightly darker warm cream and the thin side edge may be muted terracotta.
Text (verbatim): "rec.me" — exactly r-e-c, period, m-e; no other text.
Composition: centered vertical lockup; circular pin head and its small inner hole remain recognizable; pointed pin tip touches/enters the dot; compact terrain slice flows behind the wordmark without obscuring letters.
Constraints: no oval ring at the bottom of the pin; no rectangular paper map; no folded corner or folded map sheet; no road lines; no contour lines; no grid; no literal continents; no full globe; no blue or green; no pencil; no extra lower-right object; no border; no rounded-corner mask baked in; no photorealism; no mockup; no watermark. Keep every element bold and readable at small app-icon sizes.
```
