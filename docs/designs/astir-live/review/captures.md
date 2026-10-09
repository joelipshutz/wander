# Native review captures

REC-636 · October 9, 2026 · Fictional data in the standalone SwiftUI app

These are native iPhone simulator captures, selected after visual inspection. Large: iPhone 17 Pro. Compact: iPhone SE (3rd generation). Both run iOS 26.5. JPEG copies preserve the complete screen, reduced only to a maximum 1600-pixel edge for repository storage. The original PNGs and test results remain in the issue-specific evidence directory documented in [validation](validation.md).

Use the [native prototype](../../../../preview/rec-636-live/README.md) to evaluate motion, scrolling and navigation. Stills cannot establish gesture or accessibility behavior. Profile is a structural continuity representation with sample data; these images do not propose a new Profile design.

## Map and activity

| Map + activity — large | Map + activity — compact |
|---|---|
| ![Large phone with native map above a recent activity drawer](captures/large-01-live-map-and-activity.jpg) | ![Compact phone with the same map and activity structure](captures/compact-01-live-map-and-activity.jpg) |

| Full activity — large | Full activity — compact |
|---|---|
| ![Expanded Feed with person, place and timestamp hierarchy](captures/large-02-live-full-feed.jpg) | ![Expanded Feed on compact phone, with Map return above tabs](captures/compact-02-live-full-feed.jpg) |

Inspection: controls, bottom navigation and map attribution are visible. The compact half state exposes less activity and supports expanding to read it. Dense map pills overlap in this prototype; production clustering/collision behavior is a required engineering task. The floating Map action can cover a small portion of scrolling content; content remains scrollable, and its final production placement should be reviewed at large text sizes.

## Profile continuity

| Existing section order | Your Map and calendar remain in Profile |
|---|---|
| ![Profile identity, social counts, save streak and recent activity](captures/large-03-profile-identity-social-streak-activity.jpg) | ![Retained Your Map preview and calendar below recent activity](captures/large-04-profile-your-map-calendar.jpg) |

| Your Map — large | Your Map — compact |
|---|---|
| ![Personal map, status selector and saved places with Map and Patterns modes](captures/large-05-profile-your-map.jpg) | ![Compact personal map with the same Map and Patterns navigation](captures/compact-05-profile-your-map.jpg) |

![Patterns remains within Your Map, with illustrative sample copy](captures/large-06-profile-your-map-patterns.jpg)

Inspection: the map stays inside Profile navigation and retains a Back to Profile entry. Patterns remains a mode of Your Map. Advanced production lenses, computed analytics, share generation and Snapshot creation are intentionally outside the fixture app.

## Gentle transition and sparse states

| Optional transition | Quiet week |
|---|---|
| ![Dismissible transition says Your Feed now has a map and Your Map stays in Profile](captures/large-07-optional-transition-after-first-memory.jpg) | ![Sparse Feed retains useful recent activity without fabricated people](captures/large-17-sparse-activity.jpg) |

| Simulated offline | Empty activity |
|---|---|
| ![Saved activity with an explicit offline notice](captures/large-08-offline-saved-activity.jpg) | ![Empty Feed with an Add a place action](captures/large-09-empty-activity.jpg) |

Inspection: the transition follows the first memory instead of blocking launch. Sparse, empty and offline are explicit local review scenarios. The offline fixture does not test networking or production cache authorization.

## Dark appearance and circle controls

| Map peek — large | Draw area — compact |
|---|---|
| ![Dark map peek with a labelled way to expand the drawer](captures/large-15-dark-map-peek-reduced-motion.jpg) | ![Dark compact circle editor with radius alternatives, Cancel and Apply](captures/compact-16-dark-draw-area-controls.jpg) |

![Large dark circle editor with geographic preview and map attribution](captures/large-16-dark-draw-area-controls.jpg)

Inspection: radius alternatives and Apply/Cancel stay reachable on both sizes; map attribution remains above the drawer. These captures use the prototype Reduce Motion override. D4 still decides whether geographic drawing is the intended circle-control behavior.

## Accessibility text

| Large phone | Compact phone |
|---|---|
| ![Feed at accessibility text size 2 on a large phone](captures/large-10-accessibility-text-feed.jpg) | ![Feed at accessibility text size 2 on a compact phone](captures/compact-10-accessibility-text-feed.jpg) |

Inspection: primary text wraps and content scrolls. The scope rail scrolls horizontally; the compact frame does not show every scope at once. These captures do not prove VoiceOver reading order or focus. Those and real-device gesture behavior remain validation gates.

## Local connection and planning previews

| Demo plan | Demo inbox |
|---|---|
| ![Local plan-created confirmation explicitly identified as a demo](captures/large-12-local-plan-created.jpg) | ![Contextual reply saved in a demo inbox with a not-sent label](captures/large-13-contextual-local-inbox.jpg) |

Plans and replies are session-local demonstrations. No message, invitation or notification is delivered. Production invitation reuse and private messaging are separately scoped in the engineering plan.
