# Astir onboarding motion handoff

September 16, 2026 · Joe + Ryan review · **Proposal, not app implementation**

Open [the interactive motion room](motion-lab.html). It contains six playable studies with large review tabs, paired welcome variants, persistent Play/Pause/Next/Replay controls, and Full screen. Read [the transcript audit](transcript-audit.md) for all decisions and source pairs, and [brand context](brand-context.md) for the recovered identity and voice work.

This handoff preserves what to make, why it moves, and what remains open. The timings below are **concrete prototype timings**, not claims that the speakers chose exact durations. No native source, account, permission or backend state is changed by these studies.

## Sources and design boundaries

- **T07**: welcome awareness/desire sequence, delayed explanation versus immediate explanation, UI benefit slides, Events preview, login timing, account/icon/profile direction.
- **T01/T06**: duplicate cleaned/raw versions; location and people primers, notification concept, “a local experiment” ticker ending.
- **T02/T05**: duplicate versions; map-first overview, transitional coach treatments, Feed experiment and performance hypothesis, pin legend.
- **T03/T04**: duplicate versions; finale, static contextual annotations, Lists, removal of N26, N27 device demonstrations. T04 explicitly says the existing setup guide is on the website.
- **Approved brand files**: `../brand.json`, and the supplied untouched Signal wordmark PNG in `../brand-assets/`. Signal `#F05A3C`, warm lettering `#E6DDCD`, splash black `#080A09`. Page/UI uses production warm paper `#F2E9DB`, raised paper `#FBF6ED`, ink `#141714` with editorial serif and Avenir Next.
- The approved wordmark does not glimmer or flicker. New motion belongs to onboarding content and UI. Stone icon proposals are a separate design study, not a reason to change approved flat lettering.
- Native baseline crops come from `../screenshots/welcome-1.png`, `welcome-2.png`, and `signup-component.png`. They demonstrate existing UI, not a claim that the new surrounding copy is already implemented.
- The existing map tutorial captures contain the old gray veil. The new map study uses an explicitly labeled illustrated sample map instead of pretending a veiled capture is the requested new state. Production must use the actual interactive map.

## 01 — Welcome A/B

Evidence: T07; T01/T06. Audit A07–A13, A19, A33.

**Purpose:** emotional awareness first, then a plain description of value, then real UI. The request was to compare whether a moment of anticipation helps. It was not to spend an arbitrary long time on an unskippable brand animation.

Both variants run together so timing can be compared directly. Same static supplied wordmark; same ticker; same subsequent UI. The difference is descriptor arrival.

| Time | Both variants | A · Immediate | B · Delayed |
|---|---|---|---|
| 0–1.4s | “A life full of” + “places.” | Descriptor present | Descriptor withheld |
| 1.4–2.8s | Word rolls to “people.” | Descriptor stays | Descriptor slides up in 550ms |
| 2.8–4.4s | Word rolls to “plans.” | Descriptor stays | Descriptor stays |
| 4.4–6s | Whole line becomes “A local experiment.” | Descriptor stays | Descriptor stays |
| 6–10s | Entire scene slides to native place-diary UI crop + proposed benefit text | Same | Same |
| 10–14s | Entire scene slides to native social-card crop + “Keep up with the people you love.” | Same | Same |
| 14–18s | Existing native create-account component appears | Same | Same |

Ticker roll: 480ms, ease-out curve `(0.2, 0.8, 0.2, 1)`. Feature transition: 500ms horizontal slide, same ease-out family. No blinking or rapid flashing.

**New placeholder copy**, explicitly labeled in the room:

- Stable phrase / ticker: “A life full of places / people / plans.”
- Descriptor: “Keep your places close. Keep your people closer.”
- Personal slide: “Remember everywhere you’ve been.” / “All the places that become part of your life.”
- Social slide: “Keep up with the people you love.” / “Your people. Their places. More reasons to get out.”

The exact original stable phrase and word list could not be recovered from the transcripts. Do not describe this placeholder as a recovered or approved line. “A local experiment” is a transcript candidate; raw T06 also says “the local experiment.”

**Before native implementation:** choose A or B, finalize actual copy and word list, add an actual UI-backed Make Plans slide if retained, and decide where coming-soon Events belongs. This study intentionally tests only the opening rhythm, then two captured benefit examples. The baseline create-account capture may contain older copy/controls; it is a reference, not the final proposed account state. Root's revision room covers the broader screen/copy decisions.

**Acceptance:** no animated wordmark; no forced replay for returning people; an accessible login path survives; current candidate introduces a login affordance on the social beat, reflecting the discussed slide 3/4 timing. Proposed early login and automatic account arrival need native routing rather than merely text inside the capture. Preserve native buttons, account recovery and system accessibility settings. The blanket no-skip idea was not settled.

## 02 — Map overview / coach comparison

Evidence: T02/T05. Audit A36–A44.

**Purpose:** orient someone on a populated map without requiring them to perform a fake place save. Map stays visible and clear, with no gray veil. Production map is at user location, with Ocean Park fallback. The prototype uses sample pins and labels.

Eight beats, **4 seconds per beat / 32 seconds total**:

1. **Featured:** sample café/park/spot pins. Draft coach: “Featured / Recommendations from your community, shaped by your taste.” Root verified the community/taste behavior; final wording remains a proposal.
2. **Friends:** visible pins change to sample people. “All the places from people you follow.”
3. **More opens:** an illustrative category/rating/distance menu opens; coach sits below the menu so it remains readable.
4. **More closes:** menu recollapses and attention returns to map.
5. **Search:** the real search region is the attention target in the eventual app.
6. **Plus + imports:** one compact explanation: save a place; find Instagram, TikTok and Google Maps imports here. No import flow opens automatically.
7. **Pin meanings:** your coral pins use a solid outline for Check In and a dotted outline for Wanna. In production use exact real pin vocabulary and rendering.
8. **End on map:** “Your map, from here.” End with the same map available; no save occurred and no forced Feed/Lists/Profile navigation.

**Treatment A — Soft pop:** 400ms from 91% scale / +10px into place, light overshoot. During final 260ms of a beat, coach visibly exits with a 220ms upward/shrink/opacity treatment. Target control briefly warms to Signal/white and returns.

**Treatment B — Paper slide:** 380ms from +19px with opacity; flat editorial note with Signal left edge. Exit slides up 15px / fades in 220ms. Same target emphasis and timings so presentation style can be compared independently.

Top-right **Next** always advances. Global Next stops automatic playback at the next beat for discussion; Play resumes there. Individual step chips allow direct jumps. The More menu and example filter controls are interactive within the study.

**Acceptance:** target remains visible; coach does not overlap the target or menu; no grayscale/scrim; no forced save/import; no fake writes; Next is perceivable and accessible despite the request for a subtle control. Pacing should be tested on device with real copy length. The spoken bleed-into-search transition is an alternative idea, not chosen by this two-treatment study.

## 03 — First voluntary Feed entry

Evidence: T02/T05. Audit A44–A48.

**Purpose:** convey the value of people being out in the world. The later direction says **no forced Feed pass now**. Feed is entered deliberately with the “Open Feed” control in this study.

- 0–4.2s: sample card strip travels across 20 entries, using cubic ease-out `1 - (1 - progress)^3` to start briskly and decelerate.
- At 4.2s: settle at the same list position, remove the animated transform and permit ordinary scrolling.
- 4.2–5.2s: short Feed + People explanatory note appears.
- After 5.2s: no further automatic movement.

People and place names, activity, media shapes and cards are labeled **sample content**. They are not live account data or assertions that a real person checked in. The real app should use available actual feed content; a Joe/Ryan fallback was discussed but still needs data/ownership rules. A blank, slow or error state should use a useful static fallback rather than spinning through fabricated real activity.

**Acceptance:** voluntary entry; one-time eligibility policy; no repeated animation on every tab visit; no forced scroll after the user interacts; full Reduce Motion bypass to settled state; interruption cancels movement; low-network / empty / network-failure states tested. The suspected expensive feed server transaction is a separate measurement task, not a diagnosis established by this animation.

**Current prototype limitation:** the normal sample feed can be scrolled after settling; it is not connected to the app, and this page does not implement persistence or a real first-visit eligibility flag. Native interaction cancellation must be implemented against real touch/scroll events.

## 04 — N25 closing moment

Evidence: T03/T04. Audit A49–A51. Brand-context N25 option B.

Compare **4s** versus **6s** without leaving the current map. The original sentence **“Life happens between us.”** is a proposal, not a sourced quotation. Other reviewed closing lines remain available in the copy deck.

450ms opacity entrance; modest 5px backdrop blur with a very quiet static texture made from underlying ink/paper colors. The map stays recognizable. No whole-app flicker, scene switch or renewed intro. **Skip** at top right and **Have fun** both dismiss immediately. Automatic expiry returns to precisely the same sample map composition.

Reduce Motion presents the note statically until manually dismissed. The four-/six-second comparison reflects the transcript's 3–4 versus 5–6 second discussion; neither is final. Production should also respect system transparency/contrast settings.

**Acceptance:** same live underlying map/feed state; no scroll/camera reset; keyboard/VoiceOver escape and focus restoration; quote attribution only if using a real quote; no invented attribution for original copy. A shorter exit dissolve can be explored; current study removes the overlay on expiry.

## 05 — Contextual notes

Evidence: T03/T04, particularly raw T04's “as long as they can next out.” Audit A56–A58.

Two **user-triggered** contexts:

- **Plus / Nearby:** a single static drawn circle around nearby places, arrow and “Your nearby places will show up here.”
- **Place profile / Check In + Wanna:** separate static circles around the real controls, arrows and “Places you’ve been.” / “Places you want to go.”

The Plus page must not falsely point to Check In / Wanna controls that only exist on the place profile. Repeating their explanation after the map legend was accepted. Drawn marks use black on light surfaces and white on dark. Text uses a handwritten family with legibility fallback. Geometry is measured from the displayed targets so circles resize with the study.

Start static, no drawing animation. **5-second** timer is the concrete prototype of “like five seconds.” **Next**, timeout, or clicking an underlying action removes the note. Overlay pointer events are off except the dismissal control. Buttons remain usable; the study confirms a click with a demo-only label and does not create data. Dark/light toggle is included.

**Acceptance:** actual screen targets; pointer/touch does not get captured by markup; no modal/scrim; correct theme color; text remains legible at accessibility size; clicked action continues after dismissal; do not duplicate a save. Drag behavior was not settled—decide whether any interaction or just tap should dismiss. Reduce Motion removes the automatic expiry and waits for a deliberate dismiss.

## 06 — N27 device demo storyboards

Evidence: T03/T04. Audit A59–A60.

N26's scheduled second-launch import lesson is removed from the proposed journey. N27 still gets richer device education. The speakers refer to a real setup guide **on the website**. Root located the live [setup guide](https://getrec.me/extensions), which still uses old rec.me branding; use its actual flow and bring branding current before making production footage.

Three distinct illustrated storyboards, each **3 × 3-second beats**. All three explicitly say storyboard, not hardware recording:

| Story | Beat 1 · physical/context trigger | Beat 2 · transition | Beat 3 · payoff |
|---|---|---|---|
| Action Button | Tight view of finger/Action Button. Current drawing marks the button. | Match-cut into real app at the device trigger. | Nearby places flow into the phone, then settle as usable real UI. |
| Share extension | A useful place in a supported source app. | Real system share sheet, select Astir. | Actual import result and place in Astir. |
| Widgets / calendar | Actual Home Screen and installed calendar widget. | Tap widget; match visual continuity into app. | The real linked information / nearby utility. |

The current diagrams are composition/timing aids. They do not prove any feature is configured or available; the page does not configure device settings. Labels such as one press / import result must be validated against actual feature behavior and setup prerequisites. Final film requires real device captures, readable fingers/button framing, accurate supported actions, rights-cleared external app footage, and true success/error states. Do not use a fake capability recording.

**Acceptance:** accurate setup guide linked; supported-device conditions clear; recording shows actual mechanism; no unsupported promise; fallback for unavailable Action Button/widget; optional user-initiated viewing; no new modal forced into first-run path by this study.

## Playback, interruption and accessibility

- One `requestAnimationFrame` timeline, never a stack of timeout chains. Pause cancels it; Replay resets it.
- Tab switch cancels the previous study, resets elapsed time and renders its new first beat. Old studies cannot mutate the new study later.
- Backgrounding the tab and page hide stop the timeline. Coming back leaves it paused.
- Reduce Motion follows the system preference by default and has an explicit checkbox. It cancels automatic playback and disables CSS animation/transition. Play becomes a manual Next beat action.
- Timeline never loops forever. All studies end at finite duration. The small Action Button attention mark animates only while the timeline is playing, and is disabled under Reduce Motion.
- Play/Pause/Next/Replay remain pinned to the window bottom. Large top tabs are visible in the normal TV layout. Space and Right Arrow operate playback when focus is outside an interactive element.
- The paused frame is visually complete; it must not freeze entrance animations before words are on screen.
- The page uses local assets and has no analytics, network writes, account calls, permissions, recording or upload function.

## Validation and remaining review

JavaScript syntax is checked with the local Node runtime. The room was opened in Chrome for visual inspection; the initial paused ticker issue was found and fixed. Asset paths use the real local approved package and captured screenshots. Chrome interaction checks passed: switching away from a playing welcome resets Map to 0.0s; More opens with all three menu labels visible; a click on an underlying Nearby row dismisses the annotation and confirms that action; Reduce Motion opens Feed directly at the settled 5.2s state. Complete paired welcome layout was visually checked at 1494 × 775, with persistent playback controls. The temporary browser check was returned to the opening study. Native-device timing and production accessibility remain implementation checks, not claimed as completed here.

Review the experience in Full screen on the TV. Select timing and treatments there, then annotate using study/variant/beat (for example, “Map B, beat 6” or “Welcome delayed, 1.4 seconds”). Bring those decisions back into the copy/task ledger. Do not replace a source screen with a conceptual sketch and call it an updated native capture.
