# REC-95 List Map Design Review

Date: 2026-07-18
Issue: REC-95 — Redesign the list map and place-tile interaction
Status: FINAL AUDIT COMPLETE

## Scope And Inputs

This review treats the map preview in list detail and the full-screen list map as one continuous experience. It is an extension of the existing warm, map-first Wander design language in `DESIGN.md`, not a new visual direction.

Reviewed inputs:

- Current list-detail, full-map rail, and selected-place simulator states on a large and small iPhone.
- `DESIGN.md` color, spacing, type, motion, pin, card, and accessibility rules.
- REC-93 compact list-photo decision: show only viewer-visible visit media, otherwise use a stable category fallback.
- REC-99 pin decision: reuse the shared aggregate save-outline vocabulary instead of deriving pin ownership from Been/Wanna status.
- Existing production Map and place-profile presentation vocabulary.

Out of scope:

- Lists-home photo covers from REC-93.
- A global Map-screen redesign.
- Adding places, collaboration, or list-management changes.
- New backend photo queries or place-provider image loading.

## Current Versus Target

| Current | Target |
|---|---|
| List detail shows a decorative gradient pretending to be a map. | Preview uses the same real coordinates, framing, and pin semantics as the full map. |
| Full-map title sits in one oversized translucent capsule that obscures geography. | Separate 44pt close control and compact title/count surface respect the top safe area. |
| Annotation labels overlap and compete with the map. | Pins are unlabeled on-map; the focused rail card carries the place name and context. |
| Status is incorrectly used as a proxy for pin ownership in the list map. | Shared REC-99 outlines represent current-user and visible social saves; Been/Wanna remains a distinct fill/pattern signal. |
| Tapping a pin replaces the rail with an intermediate profile sheet, then requires another tap to open the place. | Pin tap focuses the matching rail card. The card opens the place directly on its first tap. |
| The bottom rail is a large nested panel with a redundant heading and clipped second card. | A shallow safe-area rail shows one complete compact card plus a deliberate next-card peek. |
| Production `VisiblePlace` values are flattened into mock IDs and hard-coded location/owner values. | The card and destination preserve canonical place identity, media, saves, ownership, and social context. |
| Compact cards always show category emoji. | A 62pt viewer-visible visit photo may replace the category fallback when available; layout never changes. |

## Approved Mock

### List Detail Preview

```text
┌─────────────────────────────────────┐
│ Sunday coffee                      │
│ 8 places                            │
│                                     │
│ ┌────────── real map ─────────────┐ │
│ │        ●          ◌             │ │
│ │              ◉                  │ │
│ │                     Maps Legal │ │
│ ├──────────────────────────────────┤ │
│ │ View map              8 places › │ │
│ └──────────────────────────────────┘ │
│                                     │
│ Places                              │
└─────────────────────────────────────┘
```

- The map is geographically accurate and disables pan/zoom inside list detail.
- Tapping the map body or the separate “View map” row opens full screen. A
  narrow native attribution strip remains independently tappable, so MapKit’s
  Apple Maps/Legal controls are never covered or disabled.
- The action row carries “View map,” the mapped count, and a chevron outside
  the map canvas.
- Preview pins use the same semantic halo/status treatment as the full map, without labels.
- The transition opens the full map with the same fitted region so places do not visibly jump.
- With no mapped places, the same frame shows “No places to map yet” and no fake pin.

### Full-Screen Map And Rail

```text
┌─────────────────────────────────────┐
│ [×]  Sunday coffee                  │
│      8 places                       │
│                                     │
│       ●                  ◌          │
│                 ◎                   │
│            [ 3 ]                    │
│                                     │
│                                     │
├─────────────────────────────────────┤
│ 8 places              Swipe to browse│
│ ┌───────────────────────────────┐ ┌─│
│ │[photo] Maru Coffee          › │ │ │
│ │        Coffee · Los Feliz     │ │ │
│ │        You + 2 · Been         │ │ │
│ └───────────────────────────────┘ └─│
└─────────────────────────────────────┘
```

- The map remains the dominant surface.
- The top controls and bottom rail use bone/raised surfaces, espresso text, hairline borders, and restrained shadow from the existing system.
- The rail is not a card inside another decorative card. It is a single safe-area surface containing a lightweight label row and horizontal cards.
- One primary card is fully legible; 24–32pt of the next card is visible as a swipe cue.
- The focused pin gains a neutral espresso selection ring and slight elevation. This ring supplements rather than replaces its semantic REC-99 outline.

### Focused Interaction

```text
pin tap ──> focus/snap matching rail card ──> card tap ──> place profile
   ▲                    │                                      │
   └──── rail swipe updates focused pin <──── back preserves ──┘
```

There is no intermediate selected-place sheet. Pin focus is an exploration state; opening the compact place card is an explicit first-tap navigation action.

## Visual And Interaction Contract

### Map Framing

- Fit coordinates into the unobscured map viewport, accounting for the top controls and bottom rail rather than using symmetrical screen padding.
- One place uses a neighborhood-scale camera; it must not zoom to a building-level or world-level extreme.
- Dispersed places fit within the usable viewport with comfortable geographic padding.
- Closely overlapping places consolidate into a neutral count cluster. Cluster tap zooms to its members; it never opens an arbitrary place.
- At maximum useful zoom, coincident places remain reachable through their rail cards.
- Do not display MapKit place-name labels attached to custom annotations.

### Pin Hierarchy

1. Unfocused individual pin.
2. Focused individual pin with neutral selection ring and foreground z-order.
3. Neutral count cluster.
4. User-location/system map chrome, if present.

Pin meaning follows the shared Map contract:

- Current-user save: terracotta semantic outline.
- Viewer-visible social saves: sky semantic outline.
- Mixed Been/Wanna saves: shared REC-99 split-outline treatment.
- Been versus Wanna go: existing fill/pattern treatment; color is never the only distinction.
- The focused state must not recolor or hide these meanings.

### Rail Card

Information order:

1. Compact media or category fallback.
2. Place name, up to two lines.
3. Category and useful locality, truncated to one line.
4. Canonical ownership/status/social summary.
5. Chevron indicating direct navigation.

Examples of truthful context include “You · Wanna go,” “Maya + 2 · Been,” or a mixed summary derived from viewer-visible saves. Production cards must not synthesize “You,” Los Angeles, visibility, IDs, or social counts when those values are absent.

Compact media follows REC-93:

- Fixed 62×62pt media frame with an 8pt radius.
- Source order: pending local current-user visit photo, first uploaded viewer-visible visit photo, then category fallback.
- Never load Google/provider place photos for this compact surface.
- Never issue one photo RPC per rail card.
- Loading, error, and offline all retain the category fallback; no skeleton changes card geometry.
- When a valid image becomes available, crossfade it over 180–240ms.

### Navigation And State Preservation

- Tapping the list-detail preview opens the full map.
- Tapping a pin focuses and scrolls to the corresponding card without opening a sheet.
- Swiping the rail updates pin focus. It should not repeatedly recenter the camera unless the focused place is outside the usable viewport.
- Tapping any part of a card opens the canonical place profile on the first tap.
- Returning from place profile restores camera, focused place, and rail position.
- Closing the full map returns to the same list-detail position.
- Motion uses native short transitions. Reduce Motion removes pin scaling and animated camera/rail travel.

## State Matrix

| State | Map | Rail / Message | Interaction |
|---|---|---|---|
| 0 places | Default local region; no pins | “No places to map yet” with one short explanation | Close remains available; no disabled fake card |
| 1 place | Neighborhood-scale framing | One full card, no forced swipe cue | Pin focuses card; card opens place |
| Clustered | Count clusters where pins collide | Cards remain individually browsable | Cluster zooms; rail can reach every member |
| Dispersed | Fit all points inside unobscured viewport | Standard horizontal rail | Focus does not cause disorienting camera jumps |
| Loading, no cache | Quiet map base | Inline progress and “Loading places…” | Close remains available |
| Error, no cache | Quiet map base | “Couldn’t load these places” with close/pull-to-refresh guidance | Close remains available |
| Offline, cached | Cached pins remain visible | Compact “Showing saved places” notice; category fallbacks remain | Existing places still open from local data |
| Partial | Render every resolved coordinate | “Some places aren’t on the map yet” | Resolved cards work normally |
| Resolved without coordinates | No fake pin | “No map location · browse below” plus the real card | Card still opens the place |
| Long names | No annotation label | Two-line title; metadata truncates before chevron | Entire card remains one button |
| Small phone | Same hierarchy with reduced card width | One card plus a small deliberate peek | Rail clears home indicator |
| Large Dynamic Type | Pins unchanged; map retains useful height | Card grows vertically; title and context remain readable | No clipped text or overlapping controls |

If the current repository cannot distinguish network error from offline state, the presentation model should expose those states without inventing connectivity. Cached content is always preferable to replacing the map with an error.

## Dimensions And Tokens

| Element | Specification |
|---|---|
| Screen margins | 16pt |
| Base spacing | 8pt scale; use 8, 12, 16, and 24pt here |
| Map-preview canvas | 168pt plus a 52pt action row; may grow for accessibility text |
| Preview corner radius | 16pt |
| Top close control | 44×44pt minimum |
| Top title surface | Up to two lines plus count; three title lines at accessibility sizes; clears close control and trailing margin |
| Pin/cluster hit target | 44×44pt minimum, even when the drawn mark is smaller |
| Rail surface | Safe-area inset; 12pt top and 16pt horizontal padding |
| Rail card | Viewport minus 48–64pt; 12pt radius; 12pt internal spacing |
| Rail media | 62×62pt, 8pt radius |
| Card title | 16–18pt semibold, two lines maximum at standard sizes |
| Metadata/context | 12–14pt, one predictable line each |
| Motion | 150–250ms for focus/rail changes |

Use `surface.bone`/`surface.raised`, `text.ink`/`text.muted`, `border.hairline`, terracotta, sky, and existing category colors from `DESIGN.md`. Do not introduce glass-heavy chrome, generic travel blue, or an all-beige treatment.

## Accessibility And Responsive Rules

- Every close, pin, cluster, preview, and card control has a 44pt minimum target.
- Preview accessibility label: list title, mapped count, and “View map.”
- Pin accessibility label: place name, category, and truthful ownership/status summary. Hint: “Shows this place in the list.”
- Cluster accessibility label states the number of places and that activation zooms in.
- Card accessibility label preserves name, category/locality, and social/status context; activation says “Open place.”
- Decorative map details and fallback artwork do not duplicate VoiceOver output.
- Dynamic Type may increase the preview and rail/card height; do not scale fonts from viewport width or shrink below text styles.
- At accessibility sizes, supporting metadata may wrap before it is removed; the chevron never overlaps text.
- Color-independent status patterns and readable accessibility values preserve Been/Wanna and ownership meaning.
- The rail, top controls, and modal transitions respect the notch, home indicator, and VoiceOver escape gesture.
- Native Apple Maps/Legal attribution stays visible and tappable above the rail
  and inside the preview map canvas.
- Reduce Motion disables decorative pin scaling and long camera animation.

## Implementation-Ready Acceptance Criteria

- [ ] List detail renders a real, noninteractive map preview using the same coordinate projection and semantic pin builder as the full map.
- [ ] Preview and full-map framing account for their overlays and behave correctly for 0, 1, clustered, and dispersed coordinates.
- [ ] MapKit attribution remains unobscured and tappable in list detail and full screen.
- [ ] REC-99 shared aggregate save outlines are reused; save status is never treated as ownership.
- [ ] Pin tap focuses the matching rail card and does not present an intermediate profile sheet.
- [ ] Rail swipe updates focused pin; card tap opens the canonical place profile on its first tap.
- [ ] Production `VisiblePlace`, place ID, owner, saves, visit media, and visibility are preserved through the list-map presentation layer.
- [ ] Rail cards use a stable 62pt REC-93 compact-media slot with category fallback and no provider-photo/per-card query behavior.
- [ ] Empty, loading, error, cached-offline, and partial states have honest, non-destructive presentation.
- [ ] Long names, accessibility text sizes, iPhone small-phone safe areas, and Reduce Motion pass visual QA.
- [ ] Simulator evidence covers list detail and full map on the current large target and one smaller iPhone.
- [ ] Unit coverage locks region fitting, projection fidelity, focus/direct-open behavior, and compact media fallback decisions where those are expressible below the view layer.

Design gate: implementation may proceed without another visual-direction decision. Any new data query, global Map behavior change, or compact-photo source outside the REC-93 contract requires a separate review.

## Final Design Audit

Status: DONE

- Findings: 8.
- Fixes applied and visually verified: 8.
- Best-effort or reverted fixes: 0.
- Deferred visual findings: 0.
- Design score (reviewer judgment): C → A-.
- AI-slop score (lower is better): 4/10 → 1/10.
- Evidence: iPhone 17 Pro list detail and full map; iPhone 17e full
  map, resolved-unmapped state, and Accessibility Extra Large long-name state.
- Apple Maps/Legal attribution remains visible and tappable in both map
  presentations.
- Independent final review found no remaining blocking or non-blocking issues.

PR summary: Design review found 8 issues and fixed all 8; design score improved
from C to A-, and AI-slop score improved from 4/10 to 1/10.
