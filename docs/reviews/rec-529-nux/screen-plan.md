# Astir · Post-onboarding NUX plan

> Latest direction: remove the quote screen; Map rings slide into the user's
> actual Feed. Focus a real people tile, clear, center and fully unblur the latest
> activity tile with “Keep up with their moments,” then clear and return to Feed
> top. Both Feed beats have Next. The primary NUX ends there. First + has nearby
> search and Instagram/TikTok/Google Maps import annotations. First profile keeps
> its focus/glimmer with “Places you wanna go.” Lists and scheduled later NUX are
> retired. Earlier alternatives below are historical; see README.md for current flow.


**Latest September 18 revision:** remove the Feed scroll experiment. C02 now
focuses a real people tile (“Connect with your circle”), clears briefly, then
focuses a visible recent activity tile (“Keep up with the happenings of your
people”). The stationary two-stage lesson takes 5.65 seconds once targets are
ready, only on first entry. C04 focus is extended to 3.5 seconds and its one
button glimmer to 1.4 seconds. These supersede the earlier Feed and C04 timing
references preserved below. Starter-list entry remains deferred.

Prepared September 17, 2026 from **REC-529 Native onboarding review**, Joe + Ryan's September 16 recordings, the original numbered screen archive, and the existing task ledger. This pass starts after signup/profile/permission screens, at the first Map visit.

**Direction:** a short, animated Map demonstration → a connection-focused ending over that Map → a usable app. Feed, Lists, Plus and place-profile guidance appear when the person chooses those surfaces.

This is a planning and reference document. Archive entries below identify superseded tutorial presentations; retain their original captures, copy and IDs. The ordinary save, search and import features remain available.

**September 18 selections override the original comparisons below:** slide/fade;
the original N25 quote for five seconds with Enjoy; More trim on the dropdown
only. C04 now focuses the profile with three seconds of moderate blur behind
sharp static annotations and the real floating buttons, with no Next/Skip,
followed by one diagonal glimmer per button. Starter-list entry is deferred.
The optional Feed reveal is recorded separately in the local `REVIEW.md` index.

## Source material

- [Detailed transcript-backed brief](brief.md).
- [Full T05: Map, motion, navigation and Feed](transcripts/T05.txt).
- [Full T04: finale, Lists, handwritten annotations and return visits](transcripts/T04.txt).
- [Verified Wispr entry metadata](transcripts/README.md).
- [Current implementation and handoff status](README.md).

The original numbered screenshot archive remains on Joe's local review server at `http://127.0.0.1:8766/`. The table below preserves its exact screen numbers and titles; that localhost address is not a hosted artifact available on Ryan's machine.

T02/T05 and T03/T04 are duplicate transcript pairs. T05 and T04 retain raw detail; repetition is not a second approval. The recordings do not identify each speaker consistently, so excerpts below are attributed jointly to Joe/Ryan.

## What the recording settles

> “No, we just do your location and we do a demo map view” — T05

> “It's almost like a fucking video, honestly, but it's not because you can next and it like jump to that part of the fucking experience.” — T05

> “You're done. You can just start using the map.” — T05

> “I don't think we need to do a forced feed pass right now.” — T05, later conclusion after exploring both options

> “When you click plus, we need to show them the nearby places section.” — T04

> “it should be on the place profile itself. That's where you click the check-in and wanna buttons.” — T04

> “And we just like circle them, not animated, just like stable, and then they can next out or dismisses in like five seconds and it doesn't block the UI.” — T04

## Original screens to archive from the active NUX

These **13 numbered presentations** are the removal set. Image links open the original captures. Archiving a coach does not remove its underlying app screen or action.

| Original ID | Original title / capture | Replacement or treatment |
|---|---|---|
| N13 | Saving a place | Fold the brief + explanation into M05. |
| N14 | Finding a park near you | Remove the forced search demonstration; N14 is explicitly named for removal in T05. |
| N15 | Have you been here before? | Explain the distinction briefly in M06 and on the actual place actions in C04. |
| N16 | A date makes it a memory | Retire the forced date-field lesson. |
| N17 | Leave a note for future you | Retire the forced note lesson. |
| N18 | A rating helps future you | Retire the forced rating lesson. |
| N19 | Add the detail you’ll remember | Retire the forced More Options lesson. |
| N20 | Why this place fits | Retire the forced questions lesson. |
| N21 | Tag it for later | Retire the forced tags lesson. |
| N22 | Ready to save | Remove the required tutorial save. |
| N23 | One more shortcut | Remove the second forced + visit. |
| N24 | Bring saves with you | Mention imports in M05 without opening or requiring the import flow. |
| N26 | Return visit · Import | Retire the scheduled later-launch import lesson. T04: “we'll kill twenty six.” |

**Keep and revise N25:** replace the separate sendoff treatment with an ending over the current Map; preserve the original for comparison. **Keep N27:** the real setup guide, with Action Button, Share extension and widget demonstrations as a separate pass.

**Hold N28/N29 for a product decision:** the discussion understood them as redundant success acknowledgments. Source inspection shows conditional notification requests after a new save or follow, suppressed while both OS authorization and Astir push delivery are enabled. Retiring those requests is a distinct choice. N30 location access and N31–N33 denied/empty states remain; accepted wording for N31–N33 stays.

## Replacement journey, using the existing review IDs

The six Map beats below are a proposed review order already represented in native source. The transcript settles the controls, but leaves exact ordering of Search, Plus and pin explanation open.

| ID | What the person sees | Task reference |
|---|---|---|
| M01 · Featured | A populated demo Map near their location; Ocean Park fallback. Emphasize Featured and explain it briefly. | OB17–OB19 |
| M02 · Friends | Change the example places visibly when Friends is emphasized. Explain places saved by people they follow. | OB17–OB19 |
| M03 · More | Open the real filter panel, demonstrate its contents at a readable pace, then collapse it. | OB17–OB19 |
| M04 · Search | Emphasize the real search field. No forced search or keyboard. | OB18–OB19 |
| M05 · Plus | Emphasize +. One or two lines explain saving and supported imports; leave the import flow closed. | OB18–OB19 |
| M06 · Pin meanings | Briefly show actual solid Check In and dotted Wanna ring examples. | OB18–OB19 |
| N25 · Finish | A short connection/rootedness ending over the same Map, with immediate top-right Skip, then usable Map. | OB22 |
| C01 · First voluntary Plus | Handwritten arrow/circle on **Nearby Places**. Replace the current Import-targeted hint. | OB24 |
| C02 · First voluntary Feed | Try the requested fast scroll through real available items, decelerating into usable Feed; explain Feed and People. | OB20; coordinate OB15/OB21 |
| C03 · First voluntary Lists | One block: share recommendations, organize personal places, keep imports together. Four localized starter lists are a separate content dependency. | OB23 |
| C04 · First eligible place profile | Handwritten annotations on **Check In / Wanna** in their actual positions. Replace the current Directions/Call/Website/Reservation hint. | OB25 |

**Map behavior:** keep the Map visible and undimmed. Use native components with temporary demonstration data separated from personal saves and real social activity. Present two coach entrance/exit treatments for review: pop-and-settle versus short slide/fade, with a brief cue on the target. Advance automatically at a readable pace; top-right Next immediately skips to the next beat. Exact durations and visual treatment remain proposals.

**Contextual behavior:** marks settle and stay still; white in dark mode, black in light mode. Next or approximately five seconds dismisses them. Actual controls stay tappable; a real tap exits the annotation and performs the action. Drag-dismissal remains open. Do not force Feed, Lists, a profile, a save or list creation.

**Truthful content:** Featured is broader than friends alone. Pin line style describes status; color can describe ownership. Use real available Feed content, with useful short/empty/error fallbacks. Do not fabricate activity or seed personal data merely to fill the demo.

## Build order and review checkpoints

1. **Map + handoff (OB17–OB19, OB22).** Complete the location-aware demo, Featured/Friends transition, real More expansion/collapse, top-right Next, and two coach motion treatments. Run M01 → M06 → N25 → usable Map as one continuous native journey. Review the six beats individually and as a recording. Compare the existing finale with direct connection-oriented alternatives; compare four versus six seconds without treating either as selected.
2. **Contextual guidance (OB23–OB25).** Correct C01 Nearby Places and C04 Check In/Wanna. Replace C03's tab explanation with the three requested Lists purposes. Verify voluntary entry, dismissal and ordinary actions. Propose the four starter lists separately; location fallback, names, contents and ownership need selection before population.
3. **Feed experiment (OB20).** Build C02's real native reveal as a removable experiment. Use up to roughly 20 available items, settle into the normal Feed, keep the People/follow unit useful, and allow immediate interaction. Check empty/short/slow/error states. Coordinate existing Feed performance and follow work rather than assuming the earlier server-performance hypothesis is proven.
4. **Device guide and permission decision (OB27–OB30).** Keep N27's working guide; prepare actual Action Button/share/widget demonstrations, confirming calendar-widget capability before promising it. Present N28/N29 with their real eligibility and decide retain/consolidate/remove. Preserve location and accepted recovery copy.

## Historical planning snapshot — before this PR

**For current implementation state, use [the handoff](README.md). The paragraph below is the original pre-implementation assessment.**

The REC-529 review worktree was inspected at **b7ff1f4** for this plan. Its existing source contains M01–M06, Map/sendoff routing, contextual eligibility, a six-second N25, suppression of the forced save tutorial and N26 retirement. Earlier focused test results are historical evidence, not a fresh test run for this plan.

Direct source checks still show the three mismatches: **C01 targets Import; C03 explains My Lists/Friends/Collabs tabs; C04 targets Directions/Call/Website/Reservation.** Next is still inside the coach. The ledger marks the Feed reveal as an HTML exploration; the location-aware Map demo, full motion treatments, handwritten annotations, starter lists and device-feature demos remain to build or verify.

Implementation should preserve per-account completion, dismissal, reset and migration behavior. Returning accounts must not be re-enrolled accidentally. Use the existing production views for captures, and clearly distinguish native evidence from HTML studies.

**Acceptance:** new account reaches a usable Map without making a save; no N13–N24/N26 interruption; Next is responsive; each contextual hint appears only on eligible voluntary entry; taps still work; completion survives relaunch/account switching correctly. Check light/dark, compact phone, Dynamic Type, VoiceOver, Reduce Motion, background/resume, permissions and empty data. Recheck the broader Map timing/selection failures recorded in REC-529 before calling integration ready. Any native builds/tests use the workspace iOS helper.

**Review delivery:** retain stable N/M/C IDs, transcript excerpts, current copy, entrance/exit states, screenshots and actual Swift recordings in the existing review room. The old baseline remains evidence. Coordinate [REC-393](https://linear.app/recme/issue/REC-393), whose older scope improves the superseded long save tutorial, before implementing conflicting requirements.

Remaining review items are exact pin placement, whether to keep the Feed
experiment, and N27's visual treatment. Starter lists will be entered later.
Motion and N25 wording/timing/button were selected on September 18 as recorded
above; the older comparison instructions preserve the planning history.
