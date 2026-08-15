# Tight Composer source prompts

These are the built-in image-editing prompts used to simplify the four selected
map directions before importing them into Apple Icon Composer. The original
map-first PNGs were edit targets; no production icon asset was overwritten.

## AH — Close neighborhood

```text
Use case: precise-object-edit
Asset type: 1024px iOS app icon source artwork for Apple Icon Composer
Input images: Image 1 is the edit target.
Primary request: zoom the map artwork in about 1.45× so the streets and park shapes are larger and there is substantially less background detail. Reduce the scene to exactly two coral location pins: one cafe pin and one park/tree pin. Remove the bicycle and book pins cleanly and simplify excess minor streets.
Composition/framing: square full-bleed map; the black lowercase wordmark "rec.me" must remain optically and geometrically centered on the exact canvas center, unchanged in size, spelling, proper book-serif style, color, and horizontal baseline.
Style/medium: preserve the same warm paper-map illustration, cream land, sage parks, pale blue water, coral accents, subtle tactile texture. Keep this source mostly matte; Apple Icon Composer will add the liquid-glass material.
Constraints: change only crop/zoom and background complexity/pin count; keep "rec.me" exactly once and perfectly centered; keep 1024×1024 square; no baked rounded corners; no extra text; no watermark.
Avoid: busy street detail, more than two pins, off-center wordmark, altered typography, glossy or glass effects baked into the raster.
```

## AI — Close folded crossing

```text
Use case: precise-object-edit
Asset type: 1024px iOS app icon source artwork for Apple Icon Composer
Input images: Image 1 is the edit target.
Primary request: zoom the folded city map in about 1.4× around the river crossing and simplify the background so it reads as one close city neighborhood rather than a whole city. Keep exactly two coral location pins connected by one short simple coral route. Remove the third lower pin and reduce the visible fold lines to one or two broad folds.
Composition/framing: square full-bleed map; preserve the black lowercase "rec.me" wordmark exactly once at the exact visual and geometric center of the icon, unchanged in spelling, scale, proper book-serif styling, color, and baseline.
Style/medium: preserve the cream paper map, sage parks, blue river, coral pins, subtle folded-paper texture. Keep this source matte; Apple Icon Composer will provide glass.
Constraints: change only zoom/crop, map complexity, fold count, and pin count; exactly two pins; centered wordmark; 1024×1024 square; no baked rounded corners; no extra text; no watermark.
Avoid: three pins, dense street grid, off-center type, altered wordmark, heavy 3D, liquid glass baked into source.
```

AI received one targeted follow-up:

```text
Reduce only the black lowercase "rec.me" wordmark to about 82% of its current width and height, preserving its exact proper book-serif typography, spelling, color, and baseline. Place the resized wordmark exactly at the geometric and optical center of the 1024×1024 canvas so it has generous left and right breathing room after Apple Icon Composer refraction. Preserve the folded map, river, two pins, route, colors, texture, folds, and every other visual detail exactly.
```

## AJ — Close park route

```text
Use case: precise-object-edit
Asset type: 1024px iOS app icon source artwork for Apple Icon Composer
Input images: Image 1 is the edit target.
Primary request: zoom in about 1.5× on the park peninsula and river so the land and water shapes are broad and graphic with much less going on. Keep exactly two coral category pins: one coffee/cafe pin and one tree/park pin, joined by a short restrained dotted coral route. Remove the hiking boot pin and simplify minor paths, trees, and surrounding street blocks.
Composition/framing: square full-bleed map; keep the black lowercase wordmark "rec.me" exactly once, unchanged and locked to the exact optical and geometric center of the canvas.
Style/medium: preserve the same warm vintage paper-map illustration, sage park, bright soft-blue water, cream roads, coral route, proper black book-serif wordmark. Keep the raster matte; Apple Icon Composer will add liquid glass.
Constraints: only two pins; fewer, larger map shapes; exact centered "rec.me"; 1024×1024 square; no baked icon mask or rounded corners; no extra text; no watermark.
Avoid: dense trees, tiny roads, three pins, off-center or misspelled wordmark, baked gloss/glass.
```

## AK — Close hero pin

```text
Use case: precise-object-edit
Asset type: 1024px iOS app icon source artwork for Apple Icon Composer
Input images: Image 1 is the edit target.
Primary request: zoom in about 1.35× on the oversized central coral location marker so it becomes the dominant simple shape behind the wordmark. Keep only that large central marker plus exactly one smaller coffee pin in the upper-left. Remove the other tree, boot, restaurant, and bicycle pins and simplify surrounding map streets and park details.
Composition/framing: square full-bleed map; keep "rec.me" exactly once, black lowercase proper book-serif, centered on the exact horizontal and vertical center of the icon and fully legible across the center of the large marker.
Style/medium: preserve the warm cream paper map, sage land, pale blue water, coral marker, subtle paper texture. Keep this source matte; Apple Icon Composer will add liquid glass.
Constraints: exactly two pins total; strong close crop; very quiet background; exact centered wordmark unchanged; 1024×1024 square; no baked rounded corners; no extra text; no watermark.
Avoid: pin constellation, more than two markers, background clutter, off-center wordmark, baked liquid glass.
```

## AM — Zoomed-out in-app emojis

The zoomed-out AH source is a direct copy of the original Neighborhood Grid
artwork. AM used the following precise edit to swap only the pin-center glyphs:

```text
Use case: precise-object-edit
Asset type: square iOS app icon source for later Apple Icon Composer treatment
Input images: Image 1 is the exact base artwork and edit target.
Primary request: Replace only the four black inner glyphs inside the existing terracotta map-pin medallions with the exact colorful native Apple-style emoji characters used by the app:
- upper-left pin: "☕️"
- upper-right pin: "🌳"
- lower-left pin: "🚲"
- lower-right pin: "📚"
Composition/framing: Preserve the exact square 1:1 canvas and the existing zoomed-out neighborhood-map composition.
Text (verbatim): "rec.me"
Typography: Preserve the existing lowercase black serif wordmark exactly as it appears, in exactly the same size and centered position.
Constraints: Change only the four black glyphs inside the cream circular centers of the four existing pins. Keep every pin's terracotta outline, cream center, location, scale, perspective, and shadow unchanged. Keep the full map, streets, parks, water, coral roads, paper texture, colors, lighting, and wordmark unchanged. Center each emoji cleanly inside its original pin center at a readable size. Use each requested emoji exactly once. Exactly four pins total. No additional icons, text, pins, routes, labels, borders, baked gloss, rounded-square mask, watermark, or redesign. Full-bleed square output.
```

## AN — Santa Monica coast

```text
Use case: compositing
Asset type: square iOS app icon source for Apple Icon Composer
Input images:
- Image 1: exact rec.me visual-style reference. Preserve its warm cream paper-map illustration, pale gray fine streets, sage parks, pale blue water, terracotta map pins with cream circular centers, colorful native Apple-style emojis, subtle tactile paper texture, soft pin shadows, and exact centered black lowercase book-serif wordmark.
- Image 2: location/map-geometry reference only. Use only its underlying coastal street, beach, ocean, and park arrangement. Do not copy its colors, labels, road names, place names, existing map icons, arrows, UI, or typography.
Primary request: Create a new full-bleed square rec.me icon in Image 1's warm illustrated style, but redraw the map backdrop to follow Image 2's Santa Monica coastal geometry: a diagonal ocean and sandy beach edge running along the left/lower-left side, a rotated urban street grid inland, a broad diagonal avenue through the city, one prominent green park in the upper-right corresponding to Hotchkiss Park, and smaller coastal green park shapes near the beach.
Pins: Use exactly four existing-style terracotta map pins with cream centers and native colorful emoji:
- "🌳" centered on the prominent upper-right park at the Hotchkiss Park location.
- "🍽️" in the upper-left/upper-middle inland location corresponding to Cobi's.
- "🥐" in the lower-right inland location corresponding to Bread + Butter.
- "🏖️" along the sandy beach edge on the left/lower-left.
Text (verbatim): "rec.me"
Typography: black lowercase proper book-serif, exactly once, large and locked to the exact geometric and optical center of the square canvas, matching Image 1.
Composition/framing: top-down map, zoomed-out enough to show the recognizable diagonal coast, beach, street grid, and both main park zones. Keep all four pins clear of the centered wordmark. Preserve generous breathing room around the wordmark.
Color palette/material: warm ivory paper land, muted gray-beige streets, coral/terracotta major avenues and pins, sage parks, soft sandy beach, pale coastal blue ocean. Matte source; Apple Icon Composer will add Liquid Glass.
Constraints: Use Image 2 only for map layout and geographic relationships. No place names, no street names, no neighborhood names, no business names, no text other than "rec.me". Exactly four pins and exactly four requested emojis, each once. No additional points of interest, labels, route arrows, dots, badges, UI overlays, logos, borders, baked gloss, rounded-square mask, or watermark. Do not copy Image 2's dark theme or visual styling. Full-bleed 1:1 square.
```
