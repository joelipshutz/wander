# REC-529 · Native NUX review

This branch implements the post-onboarding review from the full [T05](transcripts/T05.txt) and [T04](transcripts/T04.txt) transcripts. Start with the [brief](brief.md), [screen plan](screen-plan.md), and [implementation review](implementation-review.md). The native review remains separate from production design approval and release.

## Branch and foundation

- Continue `codex/rec-529-nux-playthrough` in [PR #663](https://github.com/joelipshutz/wander/pull/663).
- The fetched [PR #648](https://github.com/joelipshutz/wander/pull/648) foundation at `2c10e7c12` is already an ancestor of this branch. Its existing native signup and identity work is retained.
- Reconcile latest `origin/main` again before a production merge. This review does not merge or upload a TestFlight build.

## Native experience

- **M01–M06:** undimmed native Map with eight detached demonstration places. Featured/Friends changes the example set; More opens, scrolls its real sections and closes; Search stays keyboard-free unless tapped; Plus stays voluntary; the legend uses the actual solid/dotted rings. Demonstration models never enter the persistent store.
- **N25:** a material ending over the same Map, with Enjoy and immediate Skip. Ryan selected the original quote, five seconds with Enjoy, and slide/fade motion.
- **C01:** stationary handwritten marks on Nearby Places; Next, timeout, or actual use dismisses the hint.
- **C04:** first-visit profile focus: three seconds of moderate blur behind sharp static annotations and the real floating Check In/Wanna buttons, no Next/Skip, then one diagonal glimmer on each button. The page returns to normal and the hint does not repeat. Actual actions remain usable; Reduce Motion omits the glimmer.
- **C02:** opt-in native Feed reveal through up to twenty available groups, then back to the full content inset. Dragging, navigation, inactivity and Reduce Motion cancel motion. No activity is invented for production accounts.
- **C03:** one explanation of sharing recs, organizing personal places and keeping imports together.
- **Review controls:** nested Map, first-visit and playback menus; deterministic launch targets for all eleven scenes.
- **Retired:** forced N13–N24 save lesson and N26 scheduled import lesson. Actual save/import features remain usable.

## Follow-up fixes from native inspection

The More animation previously scrolled to an ID that was not attached to any view. The real bottom anchor is now present. A real filter choice immediately takes over from the demo. The Feed reveal now returns to the top including the floating-header inset rather than hiding the first card under that header. Accessibility identifiers belong to the visible guidance rather than a full-screen container, leaving the real controls discoverable and tappable. Late callbacks from a departing coach cannot skip the next beat. The review menu no longer requires one oversized menu of every scene and playback setting. The existing Add navigation contract now expects the requested Nearby Places heading.

See [native-validation.md](native-validation.md) for exact launch/test instructions and current evidence. Simulator media is delivered in the local `outputs/pr663-native-nux/` review package, outside Git; it contains real app captures, not replacement screen renders.

## Decisions still for review

Slide/fade, the original N25 quote and five seconds with Enjoy are selected. The optional Feed reveal remains for review and has its own recording in the local capture index. Starter Lists will be entered later; no population is included in this pass. N27 keeps its working setup guide; device-specific motion demonstrations remain a separate pass. N28/N29 are conditional notification requests, not duplicate success confirmations, so removing them requires a distinct product decision. No list data, hardware setup, permission policy or final creative choice is silently committed by these mocks.
