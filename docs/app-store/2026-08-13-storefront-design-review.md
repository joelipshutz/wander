# rec.me App Store storefront design review

Reviewed: 2026-08-13

Scope: the approved six-panel 6.9-inch App Store storyboard in `concepts/v1/`, evaluated as one conversion story at actual export resolution.

## Verdict

**Ship this direction. Overall: 8.8/10.**

The set is more ownable than the category's two common lanes: utilitarian map screenshots and high-energy social collage. rec.me feels warm, editorial, and native while showing real product proof. The first frame is the strongest asset and should remain first:

> Your people. Their places. One map.

The remaining work is final-pixel production, not a new concept: recapture the exact 1.0 release candidate with a public-safe fictional graph, remove any accidental private or stale fixture content, and inspect every panel at App Store thumbnail scale before upload.

## Sequence review

| Frame | Score | What works | What makes it a 10 |
|---|---:|---|---|
| 1. Your people. Their places. One map. | 9.5 | Understandable in under two seconds; the map is dense enough to prove utility; the terracotta/sky pin system feels distinct | Use the final 1.0 map state and verify every visible label and tile is public-safe |
| 2. See where your friends actually went. | 8.8 | Converts the social promise into visible people, places, notes, and activity | Keep the lead card fully visible at thumbnail size and avoid any name/photo that resembles a real tester |
| 3. Find a place that fits right now. | 8.1 | Shows rec.me's sharpest functional differentiator: natural-language search over trusted experience | Seed two or three credible matches so the lower half does not read as unfinished while keeping the query/result relationship obvious |
| 4. Remember every place worth returning to. | 8.7 | Strong memory loop and useful rating context; feels like a product, not a marketing mock | Land the crop on the highest-value memory proof and keep small metadata legible after App Store scaling |
| 5. Save it before you lose it. | 8.6 | Communicates immediate solo value and broad import utility | Use release-candidate content with no transient empty-state banner competing with the add sheet |
| 6. Make plans together. | 9.0 | Ends on expansion value and visually rich lists without turning into a feed collage | Confirm all list titles/photos are fictional or licensed and keep the best two cards above the fold |

## Ten-dimension audit

| Dimension | Score | Assessment | Biggest leverage fix |
|---|---:|---|---|
| Typography hierarchy | 9.5 | The serif promise and small terracotta wordmark form a consistent, recognizable system | Protect the current headline size and line breaks during final recapture |
| Spacing rhythm | 9.2 | Headline, whitespace, and device placement repeat cleanly across the set | Preserve exact shared geometry across final exports |
| Color hierarchy | 9.3 | Cream, sky, sun, and terracotta create rhythm without becoming a rainbow | Recheck text contrast after the final screenshots are composited |
| Touch targets | 8.5 | The underlying UI presents large native controls in the visible proof states | Revalidate the exact 1.0 candidate on small and large phones; static storefront art cannot prove interaction |
| Loading, empty, error states | 8.0 | The storefront mostly shows successful product states, which is correct for conversion | Remove the empty-state banner from frame 5; it weakens the save promise |
| Accessibility | 8.3 | Headline contrast and size are strong; several in-app labels become small at thumbnail scale | Inspect at real App Store card size and enlarge or crop the smallest proof points |
| Animation discipline | 8.0 | Not directly assessable in static exports; no animation-dependent claim appears in the story | Confirm no key meaning disappears when Reduce Motion is on during candidate QA |
| iOS idiom alignment | 9.2 | Real native UI, familiar navigation, sheets, maps, and controls build trust | Keep the final pixels sourced from the signed candidate, not recreated mock UI |
| Information density | 8.4 | The story moves from broad map to focused search, detail, capture, and lists | Give frame 3 more credible result density and simplify frame 5's competing map state |
| AI-slop check | 9.8 | No generic gradients, fake device chrome, stock lifestyle imagery, or invented feature claims | Keep the restraint; do not add stickers, floating captions, or collage clutter |

## Competitive recommendation

- Borrow Beli's instant clarity and proof that friends' experiences matter, but keep rec.me broader than restaurants and avoid making ranking the hero.
- Borrow Corner's emotional confidence, but keep the visual language quieter and the UI legible instead of leaning on collage or cultural signaling.
- Borrow Mapstr's immediate solo utility, but make the trusted-social layer visible from frame one rather than presenting another generic saved-place map.
- Keep the six-frame arc: trusted map → social proof → situational search → memory → capture/import → shared planning. It explains both day-one utility and compounding network value.

## Release gate

This design direction is approved. Final upload assets remain gated on an exact 1.0 release-candidate recapture because the current panels are concepts made from pre-candidate fixture captures. No competing art direction is needed.
