# NUX: a quick introduction, then help when you need it

Joe + Ryan · September 16 transcript · rechecked September 17

**Owner update, September 18:** Joe explicitly assigned NUX to Ryan. This document remains the transcript/reference handoff; the opening/account-setup task must not execute this NUX work order. See [T18 in the task ledger](../TASKS.md).

**The brief:** demonstrate the Map quickly, leave people on a usable Map, and introduce other surfaces when they choose to open them. Native Swift throughout. The long required save-form lesson is removed.

This document separates transcript decisions, proposed implementation, and gaps in the current build. T02/T05 and T03/T04 are duplicate pairs, not separate votes. The raw T05 and T04 wording takes precedence where the cleaned version lost detail.

## What you actually said

**Map — [T05, opening](../transcripts/T05.txt):**

> If it's map, we give like a super quick level overview. Like your plus buttons here, you can import in there. You can search here, you can filter up here

> No, we just do your location and we do a demo map view

> it's not grayed out, showing you the whole map, but the thing is still popping out in front of it

**Pacing and motion — [T05](../transcripts/T05.txt):**

> It's almost like a fucking video, honestly, but it's not because you can next and it like jump to that part of the fucking experience.

> put the next in the top right

> they need to not just like appear, they need to like do something like to appear. There needs to be like a transitional state to make them come in and come out

**Where it ends — [T05, later conclusion](../transcripts/T05.txt):**

> You're done. You can just start using the map.

> I don't think we need to do a forced feed pass right now.

**Contextual annotations — [T04, after Lists](../transcripts/T04.txt):**

> When you click plus, we need to show them the nearby places section.

> the check-in and wanna that you're explaining with that with that draw hand drawn anime should be it should be on the place profile itself. That's where you click the check-in and wanna buttons. It's not on the plus button.

> it should be white in dark mode and black in white and white mode. And we just like circle them, not animated, just like stable, and then they can next out or dismisses in like five seconds and it doesn't block the UI.

> If they still click a button like it just automatically breaks out of it.

## 1 · Short Map demonstration

**Settled direction:** use the real native Map components with a populated demonstration around the user's location; Ocean Park is the fallback. Demonstration places must not become personal saves or invented friend activity. Keep the map visible and undimmed. Show the change between Featured and Friends, open More, demonstrate its controls briefly, then close it. Search and Plus get short explanations. Explain imports in one or two lines without opening the import flow or forcing a save.

**Proposed review sequence** — the transcript names these controls but does not settle every position:

| Beat | Visible UI and behavior | Copy to review; not verbatim approved wording |
|---|---|---|
| M01 · Featured | Briefly emphasize Featured; show its example places. | “A place to start.” Explain what Featured actually ranks, rather than promise only friends' places. |
| M02 · Friends | Emphasize Friends and visibly change the example places. | “See where your people go.” / “Places saved by people you follow.” |
| M03 · More | Open the real filter panel, move through it at a readable pace, collapse it. | “Make the map your own.” / “Filter by category, people, Check Ins or Wanna Go.” |
| M04 · Search | Emphasize the real search field; avoid a keyboard unless the user taps. | “Find the place you have in mind.” |
| M05 · Plus | Point to +; keep it closed during the automatic demo. | “Save a place or bring in saves from another app.” Mention supported import sources only where accurate. |
| M06 · Pin meaning | One brief legend over the map. | “Solid rings: Check Ins. Dotted rings: Wanna Go.” Signal color, using the actual native ring styles. |

**Motion proposals for review, not transcript-approved numbers:** two treatments maximum: (A) small upward pop and settle with a brief target pulse; (B) short slide and fade with a temporary target highlight. Both include an entrance, readable hold and visible exit. No continuous shaking. Next stays top-right, subtle but readable, and skips immediately to the next beat. Automatic timing follows copy length; Reduce Motion uses static emphasis and manual advancement.

**Still open:** a separate pin beat versus pin explanation overlapping Search. The transcript explicitly explores a “bleed” into Search; the table above is the simpler review baseline.

## 2 · Finish inside the app

N25 stays over the page the person just learned, with that page's colors and a light blur or restrained texture. It must not feel like returning to a separate splash screen. A top-right Skip works immediately. After dismissal, the underlying Map is usable.

The intended emotional finish is connection, belonging and feeling rooted in a neighborhood. The existing quote was defended by one speaker and challenged by the other; it is **not rejected or final**. Present the existing quote alongside more direct connection-oriented alternatives. Quote-only versus a short “Enjoy”/“Have fun” action is open. Four versus six seconds is open; compare both rather than call either approved.

## 3 · First-use guidance

| Trigger | Transcript-backed behavior | Boundary / open choice |
|---|---|---|
| First voluntary Feed visit | Explore a quick scroll through roughly 20 real feed items, decelerate, settle into usable native Feed, then explain Feed and People. Keep the people/follow unit useful for a small network. | This is an experiment, not forced navigation. Use available real content; fewer items or an empty feed needs a truthful fallback. The Joe/Ryan fallback discussed in the transcript is not permission to invent their activity. |
| First voluntary Lists visit | One text block explains sharing recommendations, organizing your own places, and keeping imported places together. | Four useful localized starter lists were requested, with LA/Ocean Park fallback. Names, contents and ownership remain open. Do not force list creation. |
| First voluntary Plus visit | A clear handwritten arrow/circle points to **Nearby Places**: “Your nearby places will show up here.” | Static annotation after entrance, white in dark mode and black in light mode. Location-denied and empty states must stay truthful. |
| First eligible place-profile visit | Annotate the actual **Check In** and **Wanna** actions: places you've been versus places you want to go. | These annotations belong on the place profile, not Plus, Directions or Website. Show the controls in their real native positions. |

For the Plus/place annotations: Next dismisses; approximately five seconds auto-dismisses; actual controls remain tappable; tapping an action dismisses the annotation and performs that action. Drag-dismissal was explicitly left ambiguous, so it remains a review choice. No continuously animated handwriting.

## 4 · Remove, retain, verify

- Remove the long forced N13–N24 save/check-in lesson. Briefly explaining pin meaning does not bring it back.
- Remove N26's scheduled second/third-launch import lesson. Teach at voluntary entry instead.
- Keep N27's actual website setup guide. Build separately reviewable native/device demonstrations for Action Button, Share extension and widgets, including the calendar widget. Their final visual treatment was not selected.
- Inspect N28/N29 before deletion. In the conversation these were understood as redundant success acknowledgments; current permission requests for an ungranted capability are a different state. Show trigger and purpose before deciding to remove either.
- Retain location requests in onboarding and contextually when needed. N31/N32 denial and N33 empty-state copy was accepted; refresh their UI.
- N36 describes finding/following people through Contacts at a high level, not inviting them. Keep the explanation truthful and consistent with the actual implementation and review requirements.

## September 18 status correction

The transcript decisions above remain the brief. The implementation snapshot below is historical and is superseded by current draft [PR #663](https://github.com/joelipshutz/wander/pull/663), head `32f1ede0351a2f67c380897efbbf07466b5634f1`.

That draft now has the actual populated Map tour, native finale/motion alternatives, static Nearby Places and Check In/Wanna annotations, optional native Feed reveal, and Lists’ sharing/organizing/imports explanation. Those are implemented for review, not merged. Four localized starter lists, N27 device-feature demos, N28/N29 policy and final design choices remain open. Focused checks pass; two data-performance thresholds and complete final validation remain unresolved. The approved Signal opening shipped separately in PR #668 and must be preserved when reconciling the draft.

Account-setup refinements from the broad review archive also remain separate: profile preview/photo policy, location and notification presentation, and Contacts/member matching/follow work. Main retains its existing post-auth setup sequence. Do not equate the shipped opening with completion of the complete onboarding transcript.

## Current native build: what is actually complete

Source inspected: REC-529 worktree, base handoff `565bc0d`. The prior ledger overstated several NUX items by mixing HTML explorations with native completion.

**Already native:** short Map control sequence and its routing; no required save; on-Map finale with six-second timeout and Skip; contextual eligibility and dismissal; N26 retirement. These have earlier focused tests, not fresh clearance for this pass.

**Gaps to build or verify:** the location-aware populated Map demonstration; top-right Next placement; complete coach entrance/exit alternatives; Feed scroll reveal; Lists' three-purpose explanation and starter content; static handwritten Nearby Places annotation; Check In/Wanna annotations on the place profile; finale alternatives; N27's device-feature motion. The current Plus hint points to imports, the current place hint to Directions/Call/Website/Reservation, and the Lists hint explains tabs. Those do not satisfy the corresponding transcript requests.

## Work order and review delivery

1. Correct and verify the Map demonstration and its exit on the real native screens. Compare two coach motions; inspect one beat at a time and the continuous sequence.
2. Build the two contextual annotation treatments and the Lists explanation. Verify voluntary triggers, Next, timeout, real taps, permissions, small screens and both appearances.
3. Build the voluntary Feed reveal as a removable experiment. Keep empty/short feeds usable and measure the actual loading behavior.
4. Present N25 quote/timing alternatives, curated-list proposals and N27 device demonstrations as separate review items. Keep unresolved content explicitly open.

Deliver screenshots plus Swift recordings in the existing pan/zoom review room, with stable screen/line IDs, relevant transcript above the spec, current copy, and clear state-in/state-out behavior. A mock, a saved task entry or a passing logic test is not a native visual delivery.
