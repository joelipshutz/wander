# REC-278 Map UI layout options

Reference: Joe's August 16 map screenshot. The shared hierarchy is filters at
the top, the map as the dominant canvas, place context above a bottom search
dock, and the tab bar last.

## Recommendation

Choose **Option C**. It is the clearest translation of the reference without
changing how filters, search, places, or navigation work. Option A is the safest
fallback if this should remain a pure rearrangement.

| Option | Depth | What changes | Tradeoff |
| --- | --- | --- | --- |
| A | Rearrangement only | Moves existing filters to the top and existing search/add controls to the bottom. | Lowest implementation risk, but the filter row remains visually heavy. |
| B | Compact hierarchy | Keeps A and shrinks filter visuals to their content while retaining 44 pt hit targets. | Better map-to-chrome ratio with almost no behavior change. |
| C | Polished utility layout | Keeps B, uses text-only source filters, turns More into a compact icon, neutralizes recenter, adds a passive result count, and makes the utility row adapt to the selected card's height. | Strongest hierarchy and closest to the reference; introduces one new informational element. |

## Option A — rearrangement only

![Option A — rearrangement only](option-a-rearrangement.png)

Checkpoint: `1c3bcca0`

## Option B — compact filters

![Option B — compact filters](option-b-compact-filters.png)

Checkpoint: `8035e745`

## Option C — polished utility row

![Option C — polished utility row](option-c-utility-row.png)

The same layout on the smaller iPhone 16e. The utility row is laid out above
the card instead of using a fixed offset, so a wrapped place title cannot cause
an overlap.

![Option C on iPhone 16e](option-c-utility-row-small.png)

Native iOS 26 glass rendering was also checked on an isolated iPhone 16 Plus
simulator.

![Option C on iOS 26](option-c-ios26.png)

## Preserved behavior

- Featured, Friends, You, and More keep their existing selection/filter logic.
- More filters still opens beneath the top row and keeps its current sections.
- Search focus, typeahead, add, recenter, place selection, walkthrough targets,
  tab navigation, and map data are unchanged.
- Every interactive control retains at least a 44 pt hit target.

