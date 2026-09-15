# Astir Events — source cross-check

Historical 76-screen snapshot. See [the current requirement audit](requirements.md) for corrected findings, remaining proposals and current verification.
Read-only requirement audit, September 14, 2026. This document does not approve a design, change scope, or authorize implementation.

## Evidence and limits

- **T1 — raw user transcript:** original competitor/event discussion (local authoring source; authority retained in the requirements ledger).
- **U1 — raw direct user message in this task:** the message beginning “THIS IS ALL INSTRUCTIONS FOR speccing new events feature,” including the continuation beginning “Then, so the hard” and the event/place discussion. Now independently recovered as M005 in E below.
- **T2 — raw user transcript:** post-event check-in discussion (local authoring source; authority retained in the requirements ledger).
- **W — prior decision mapping:** [working product record](../working-product-record.md). Its D-choice summaries are secondary records of earlier questions and answers. Quotations attributed to W remain record excerpts, not verbatim user statements.
- **E — recovered discussion evidence:** [discussion-evidence.json](discussion-evidence.json). Root recovered stable M001–M056 source IDs plus the latest timing/audit requests. This audit subsequently checked the complete D2–D34 questions against their matching user answers and checked D35's linked option document with M047. The mapping index below records those sources.
- **M — current wireframe content:** flow-model.json (local authoring source; authority retained in the requirements ledger), inspected as 76 screens in 16 groups; modification time `2026-09-14 08:05:17` local; SHA-256 `809389875769009f4dd3fa4f493b36759f8aaffa8ce501c320444a199cf95f2c`.

This compares requirements with screen content, labels, and declared transitions. It is not a rendered visual audit. A requirement described only in a note is distinguished from an illustrated action. An absent engineering detail is not automatically a missing product decision.

**Status:** Covered = explicit screen content; Partial = a note, incomplete route, or insufficient visual evidence; Gap = no complete illustration; Proposed = behavior has not been approved; Superseded/deferred = preserve the later decision instead of restoring the earlier idea.

## The sequence the sources actually support

For a new guest: event link → event detail in App Clip, with equivalent browser fallback → Apple/Google account sign-in → missing name/phone and SMS verification → confirmed RSVP → event texts while installation remains optional → deliberate later download before arrival → recover the same reservation through shortened setup → entry QR and recorded door admission → published-recap invitation → explicit personal event check-in → protected recap → place memory/map.

The user explicitly described Apple/Google first, then the phone number. D17 adds verification before confirmation; it does not replace provider sign-in with phone-only signup. Download is mandatory for entry, not for RSVP confirmation or event texts. The recent correction in M now represents this distinction. Neither the exact download-reminder moment nor A/B optional-profile placement has been separately approved.

## Raw-source requirements that are easy to lose

Each row has one narrow requirement or unresolved boundary. Brief quotations retain the transcript's wording. Later D decisions control where the raw discussion explored alternatives.

| ID | Exact short source excerpt | Requirement or boundary | Current model evidence / status |
| --- | --- | --- | --- |
| S01 | T1: “full immersive splash image with the text overlaid” | Event detail should sell the event through immersive imagery with overlaid text. | `event-detail` exists, but the model alone cannot verify the composition. **Partial — rendered review needed.** |
| S02 | T1: “guest list which is all super glassy and native” | Preserve the intended native/glass treatment where appropriate; this is visual direction, not permission to replace the event with a generic form. | `full-guest-list` exists. Material/treatment cannot be verified from M. **Partial.** |
| S03 | T1: “Social proof right at the top.” | Social proof belongs high in event detail, with a face pile/count. | `event-detail` includes the count and hook note. Exact placement needs rendered review. **Partial.** |
| S04 | T1: “you can scroll the buttons are floating” | Primary event actions remain accessible while the immersive detail scrolls. | RSVP/Share are modeled. Floating/sticky behavior is not described as a distinct requirement in M. **Partial.** |
| S05 | T1: “RSVP is a primary running action So is share” | RSVP and Share must be prominent event actions. | `event-detail` primary RSVP, secondary Share. **Covered.** |
| S06 | T1: “we can discuss whether or not we want to save” | A separate Save event action is unresolved; observing a competitor's Save button did not approve it. | No Save action in M. That absence is not an approved scope cut; W/draft retain it for review. **Proposed boundary.** |
| S07 | T1: “big splashy title one sentence description and subtitle text then time and date” | Include event title, concise explanatory copy, subtitle/context, and date/time. | `event-detail` heading/body/status/location. **Covered in content; hierarchy requires rendered review.** |
| S08 | T1: “if the code is required you have to enter it and then continue” | An event can require a separate access code; valid entry is a gate before reservation completion. | Only `codeinvalid` illustrates it. No initial code-required route or successful return is linked. **Gap.** |
| S09 | T1: “We probably don't need another checkout screen.” | Do not insert a payment-like extra checkout into the selected free RSVP journey. | No checkout; D20 later settles free RSVP. **Covered.** |
| S10 | T1: “there's a confirmation screen and there's a event screen in the state that you've already RSVP'd” | Show both successful confirmation and the persistent confirmed event detail. | `rsvp-confirmed`, `noapp-confirmed-detail`, `member-confirmed`, `confirmed-detail`. **Covered.** |
| S11 | T1: “You get an add to calendar notification.” | Provide calendar access after confirmation; retain RSVP if that action is unavailable. | Add to calendar appears; completion/failure is not illustrated. The failure rule is a draft proposal. **Partial.** |
| S12 | T1: “a whole tab just for tickets. We're not going to have that.” | Entry QR belongs with the event/Events navigation, without a separate Tickets tab. | Events links to ticket; proposed five-tab shell has no Tickets tab. **Covered.** |
| S13 | T1: “There's one where you have the app downloaded, and the other one where you don't” | Cover installed and no-install entry separately while retaining equivalent event functionality. | Both main no-install route and `existing-member`/`member-confirmed` exist. Some reused links switch channel labels; see F02. **Partial.** |
| S14 | T1: “surely there's a truncated onboarding for that path” | A returning RSVP guest needs shortened, event-preserving app setup. | Recovery and A/B examples are present. Exact step placement remains proposed. **Covered direction; proposed details.** |
| S15 | T1: “We give value, then we get them.” | Introduce the gathering first and reveal Astir progressively; general onboarding cannot become an unexplained early hurdle. | Event-first main path and deferred education are present. **Covered direction.** |
| S16 | T1: “we don't even make them download or upsell download until the end” | Do not treat immediate full-app installation as a prerequisite for early RSVP value. Later statements settle the hard gate at entry, not after-event-only installation. | `texts-before-install` now explicitly separates confirmation/texts from later entry preparation. **Covered; previous sequencing problem corrected.** |
| S17 | T1: “it shows you an example notification” | The requested notification-value treatment demonstrates what the user will receive, rather than merely requesting a permission. | `notification-primer` has a generic permission explanation, with no sample notification content in M. **Gap in captured visual direction.** |
| S18 | U1: “within this rsvp screen you'll sign up via apple or google” | Offer Apple/Google signup within RSVP. | `rsvp-auth` shows both, within App Clip/fallback context. **Covered.** |
| S19 | U1: “then we have to give a phone number” | Phone collection follows account signup; it is not a second competing signup method. | `rsvp-auth` → `rsvp-phone` → `rsvp-code`. D17 separately settles verification. **Covered.** |
| S20 | U1: “get updates from astir about this event and others.” | This was the original combined consent checkbox, not the final consent structure. | D19 supersedes it with event-text explanation plus a separate unchecked future-event opt-in. **Superseded correctly.** |
| S21 | U1: “text, text, text, up to the event” | Maintain the RSVP-to-event relationship through texts while the guest may still lack the app. | Confirmation and reminder screens precede installation. **Covered.** |
| S22 | U1: “you have to have the app downloaded and your QR code to get in” | Full-app installation and entry QR form the hard admission gate; D25 later supplies the limited QR-loading exception. | `entry-download`, ticket, scanner, installed-app fallback, unsupported-phone state. **Covered.** |
| S23 | U1: “in the app in the events tab” | The entry QR must be findable inside Events. | `events-list` → event/ticket. **Covered.** |
| S24 | U1: “that event detail screen with the splash. social proof” | The splash is the event detail's presentation, not an extra blocking launch screen or tour. | `event-detail` is the content screen. No separate branded splash gate. **Covered.** |
| S25 | U1: “And then it also lives within the app.” | The same applicable event experience exists in App Clip/fallback and in the full app. | Equivalent detail states exist; reused channel transitions remain inconsistent. **Partial.** |
| S26 | U1: “confirmed events at the top if they exist” | Events puts confirmed events first and otherwise offers a simple nearby event list. | `events-list` captures this. **Covered.** |
| S27 | U1: “coming soon coming soon let's just leave that simple for now” | Empty nearby Events should stay simple. The preceding city-waitlist suggestion is ambiguous; W explicitly does not approve silently adding a full city-waitlist product. | `events-empty` adds a city-interest “Join the event waitlist” action under an Approved label. **Unsupported as settled; see F01.** |
| S28 | U1: “notice for your content and a text check-in to see the content” | Post-event notification/text leads to the required content-unlock check-in. | `after_text` → `after_composer`; D26 controls publication timing. **Covered.** |
| S29 | U1: “we don't need to spec that right this second” | Reconnection/contacting a person met at the event was initially parked, not silently selected. | No reconnection UI. T2 revisits the idea, but D7 subsequently defers it again. **Deferred correctly.** |
| S30 | U1: “we're putting a new primitive into this app, which is, which is events” | Treat events as their own product concept, associated with places; do not reduce them to a renamed place visit. | Dedicated detail, RSVP, admission, recap and history states. **Covered at product level.** |
| S31 | U1: “every event has a place. Not all places have events. There can be many events at a place.” | Each event has exactly one linked place; one place may have multiple or no events. | `map_place_history` illustrates multiple events at one venue. Earlier reversed/one-to-one phrasing is corrected by this explicit summary. **Covered.** |
| S32 | U1: “the person that owns the house or is renting the house should give us consent” | Home venues require appropriate resident/owner/renter consent. | `console-event` note requires consent; no home-specific capture/preview illustration. Capture mechanics remain proposed. **Partial.** |
| S33 | U1: “only certain people can see certain events and be pinned on the map” | Place association must not accidentally grant all event, location or map rights. Later D decisions specify the actual audiences. | Separate location, guest-list, recap and public-post states. **Covered direction.** |
| S34 | U1: “Not only the happy path. but the other wonky paths” | The spec/review must follow exceptional and interrupted paths, not merely list a happy sequence. | Many alternatives are now present; code, conversation, approval and missed-scan completion remain incomplete. **Partial.** |
| S35 | T2: “you're effectively making a post, your own personal” | Event check-in creates the attendee's personal post, distinct from a door scan and a shared comment. | `after_composer`/`after_post` vs scanner/recap. **Covered.** |
| S36 | T2: “I don't think we even have a public rating” | No public event/venue rating in the personal check-in; separate private feedback. Later D34 resolves the private fields. | Public post has no rating; composer has private optional stars/comment. **Covered.** |
| S37 | T2: “then you land on this host event experience” | Successful personal check-in lands on the attendee recap, before the later map progression. | `after_composer` → `after_recap`. **Covered.** |
| S38 | T2: “First party photos and videos Third party photos and videos” | Shared recap includes both Astir-provided and attendee-provided photos/videos. Do not silently cut videos. | Recap media, `gallery-add`, and immediate posted result include photos/videos. Host contribution is only implicit in console recap preview. **Mostly covered.** |
| S39 | T2: “We've got a comment section right at the top” | Comments/conversation need prominent recap placement. | `after_recap` lists comments first. **Covered in content.** |
| S40 | T2: “everybody's comments are in there like back and forth, liking all that” | Shared conversation is participatory, with back-and-forth/liking direction; it is separate from each attendee's personal note. | Displayed comments and “Leave a comment” exist, but no write/post/reply/like/result flow is illustrated. **Gap.** |
| S41 | T2: “And then there's all the check-ins” | Recap exposes personal event check-ins, not only its media and shared comments. | Only “Your check-in” is shown in recap, plus a separate personal post. Other attendee check-ins/activity remain unillustrated. **Partial.** |
| S42 | T2: “Somehow they have to be able to get back to the screen” | Place profile/history must provide a lasting route back to an eligible old event recap. | `map_place_history` links to old events with appropriate access. **Covered.** |
| S43 | T2: “a special pin so it shouldn't probably be that way forever” | Special map treatment is temporary; event history survives it. | Map/history and console window controls. **Covered.** |
| S44 | T2: “You can add pictures from either your role or the like event role.” | Both own photos and gallery photos are desired sources, but their timing requires a coherent unlock sequence. | D6/D28 settle own media before check-in and gallery photos afterward on the same post. **Superseded into explicit sequence correctly.** |
| S45 | T2: “I think if you are a friend of somebody who went to the event You can see the event” | Friend/second-degree discovery was brainstorming, later broadened by D3. | Nonattendee preview is available across Astir. **Earlier narrower idea superseded.** |
| S46 | T2: “People you met You can misconnect” | T2 renewed reconnection brainstorming; that does not override the later explicit D7 deferral. | No reconnection UI. **Deferred correctly.** |

The isolated T2 phrase “no photos” is inconsistent with its repeated note/photos direction and later D2/D6/D28 answers; it is not treated as a later authoritative removal of photos.

## Decision mappings that control the latest version

The quotations in the requirement table are **W excerpts**, not verbatim user speech. A short answer such as “A” establishes meaning only when joined to the exact question/options from its turn. The following recovered pairs now independently confirm the choice mappings; they do not promote every later draft default into an approved choice.

| Decisions | Original option source in E | Original user answer source in E | Short exact user excerpt |
| --- | --- | --- | --- |
| D1 | M008/M009 question; T2 via M010 answers in detail | T2 | “you're effectively making a post, your own personal” |
| D2–D4 | M016 | M017; event-led presentation clarified in M018 | “2A 3A” and “4A” |
| D5–D7 | M019 | M020 | “5A 6A for 7 we're going to talk thru it.” |
| D8–D10 | M021 | M022 | “8D” / “9C” / “10A we should have console to control the viz of this” |
| D11–D13 | M023 | M024 | “11 A 12A 13B but changeable via console” |
| D14–D16 | M025 | M026; launch clarified in M030 | “should work on tf or public”; “assume app store will be launched” |
| D17–D19 | M031 | M032 | “A A A” |
| D20–D22 | M033 | M034 | “A C 22 A for now with option to do B on our end” |
| D23–D25 | M035 | M036 | “A A A” |
| D26–D28 | M037 | M038 | “A A A but dont explain reuse pls” |
| D29–D31 | M039 | M040 | “A B and it should be a hook and A” |
| D32–D34 | M041; linked document in M044 | M045 | “32 A 33 A 34 A” |
| D35 | [question-35.md](../question-35.md) linked in M046 | M047 | “A” |

M051 authorizes “ok go design review gstack,” not full acceptance of the draft. M054–M055 request the whole wireframe flows and options; they do not select A/B. `U-0914-TIMING` asks to double-check app/browser identity and later download timing; it does not approve switching to phone-only signup. `U-0914-AUDIT` requests a complete internal line-by-line requirements check. These are workflow/clarity instructions, not new feature approvals.

| Decision | Short W excerpt | Atomic requirement carried forward | Model result |
| --- | --- | --- | --- |
| D1 | “an event-specific, personal check-in post” | Personal post, not a bare attendance acknowledgment or shared recap comment. | Covered: separate composer, post, admission, comments. |
| D2A | “All fields optional.” | Empty explicit Check in is valid; note/photos/private feedback are individually optional. | Covered by composer fields and note. Empty-result illustration remains implicit. |
| D3A | “Preview across Astir.” | Nonattendees get preview; full gallery/conversation require eligible event check-in. | Covered: locked preview uses placeholders, not readable protected comments. |
| D4A | “an event-labeled Been/place visit without a venue rating” | One event-led logical visit, linked to place; do not overwrite independent ratings or audiences. | Covered in post/map/history and notes. |
| D5A | “eligibility requires admission recorded at the door” | Staff may correct a missed scan; RSVP/self-report cannot unlock recap. | Help is shown, but staff correction and guest return are not. Partial. |
| D6A | “own photos before check-in; event-gallery photos can be added after unlock” | Prevent circular access and edit the same personal post afterward. | Covered. |
| D7 | “for their next joint discussion” | Defer reconnection and “solo, single, or private”; no current behavior/release promise. | Preserved. |
| D8 custom | “Do not apply the earlier "hide the whole home place profile" proposal.” | Home can remain discoverable approximately; protect exact location across surfaces. | Covered by before/revealed/expired examples. |
| D9C | “everyone in Astir is the default audience” | Small eye indicator now; preserve existing restrictions; expanded profile/check-in privacy later. | Covered in composer/post; no expanded chooser added. |
| D10A | “discoverable upcoming/recent event” | Special pin means event availability, not only the viewer's attendance/memory. | Covered in map note. |
| D11A | “on/off, display start/end, style presets, and preview” | Internal controls, without inventing a full custom icon/color/animation editor. | Covered in console controls summary. |
| D12A | “special event pin opens the event view” | Primary pin destination is event, with a place-profile route. | Covered. |
| D13B | “24 hours before event start for confirmed guests” | Configurable reveal; eligible late confirmations receive address immediately. | Window is illustrated; late-confirmation branch only in W, not M. Partial. |
| D14A | “equivalent browser RSVP if the App Clip cannot open” | Preserve event/account/reservation across fallback and later app entry. | Browser state exists; shared links incorrectly inherit Clip labels in places. Partial. |
| D15A | “disclose it before RSVP” | Supported phone/full app required for admission; browsing device is not necessarily admission device. | Covered via event requirement and unsupported-device alternative. |
| D16 amended | “assume public app release precedes live Events” | Specify live public journey and TestFlight testing separately; do not claim a current released Clip. | Public handoff is illustrative. TestFlight is a testing dependency, not a required extra guest screen. |
| D17A | “SMS verification before RSVP confirmation” | Separate provider authentication from verified phone; reuse a verified matching number. | Covered main sequence and existing-member state. Recovery mostly in notes. |
| D18A | “keep it optional” | Strong profile-photo prompt during setup, no RSVP/ticket/post gate. | Covered; A/B positioning remains proposed. |
| D19A | “separate optional, unchecked future-event opt-in” | Event texts are explained separately; verification does not imply future marketing consent. | Captured in phone-screen note; rendering must preserve unchecked state. |
| D20A | “free RSVP only for the first release” | No paid checkout/payment/refund flow. | Covered. |
| D21C | “a waitlist for full events” | Astir selects available-spot recipients; this does not approve a city mailing-list product. | Full-event flow covered; empty Events action overclaims approval. |
| D22A amended | “automatic confirmation” / “enable manual approval” | Default automatic, internal manual mode, explicit pending state. | Pending and console controls present; operator decision/result path missing. Partial. |
| D23A | “offer that requires their acceptance” | Default 24-hour offer expiry configurable; an offer is not a confirmed RSVP. | Offer/expiry/accept → confirmation shown. Holds/return-to-waitlist are proposed defaults. |
| D24A | “self-cancellation until event start” | Guest may cancel; release spot consistently. | Confirmation/result present. Exact invalidation details remain draft proposals. |
| D25A | “confirmed booking” / “when the QR will not load” | Staff verify an installed-app guest, then record admission; not an unsupported/no-app waiver. | Covered by QR failure, lookup and admission. |
| D26A | “publishes the recap as ready” | Publication succeeds before attendee invitation, not an automatic end-time unlock. | Console publication/result and attendee text covered. |
| D27A | “immediately visible to eligible gallery viewers” | Eligible uploads appear without universal prior approval; uploader removal and Astir moderation. | Gallery upload/result/removal covered; operator moderation only stated. |
| D28A amended | “Omit the reuse explanation entirely from this UI.” | Gallery photos can appear in public Astir check-ins; no reuse explainer, extra consent step or substitute approval. | Correctly preserved; ordinary audience/private labels remain. |
| D29A | “24-hour and 2-hour reminders” | Automatic confirmation/reminders/important changes/published-recap invitation, console configurable. | Covered at screen/console summary level. Failure/opt-out handling remains proposed. |
| D30B amended | “deliberately presented as a hook” | Face pile/count before confirmation; full guest list only after confirmed RSVP, not pending/waitlisted/offered. | Covered. Full-list shared channel correctly avoids requiring installation. |
| D31A | “protect canceled/released spaces” | While waitlist exists, new guests waitlist instead of taking released capacity automatically. | Stated on cancellation result and console selection; no contrary automatic-promotion claim. |
| D32A | “remove that photo from the gallery and every personal event check-in referencing it” | Source removal propagates but preserves other media/text/visit. | Covered by gallery management and source-removal result. |
| D33A | “preserves historical completion for recap access” | Delete personal post/visit without relocking otherwise-eligible recap or erasing independent history. | Covered by deletion result; independent explicit saves are not shown but remain in W. |
| D34A | “optional 1–5 stars and an optional private comment” | Independent optional fields, no preset rating, Astir-only feedback, no venue rating. | Covered. |
| D35A | “24 hours after the event ends for all guests” | Configurable exact-address/navigation expiry; approximate place/history persists; independent rights separate. | Covered. |

## Concrete findings against the current board

### F01 — City-interest waitlist is presented as approved without a clear approval

`events-empty` says “Join the event waitlist,” with copy about future events arriving nearby, and uses `Approved behavior; proposed layout`. T1/U1 do not clearly settle a city-interest signup: U1 mentions it then simplifies to coming soon. W explicitly separates D21's full-event waitlist from the empty-city experience. This is **not evidence of an explicit user rejection**, but it is insufficient support for an Approved label. Restore the simple coming-soon state, or clearly mark the city-interest action as a proposal pending provenance/review. Do not use D21 as its authorization.

### F02 — Some shared links still switch App Clip/browser/full-app context

The main journey is now corrected, but M still routes:

- `browserfallback` (Browser) → `rsvp-auth` (App Clip).
- `existing-member` or `wrongaccount` (installed app) → `rsvp-auth` (App Clip).
- `cancel-confirm` uses a shared channel but “Keep my RSVP” always targets `confirmed-detail` (installed app).
- `full-guest-list` correctly uses a shared channel, but its fixed return always targets `noapp-confirmed-detail` even when opened from the full app.

These reused screens need context-preserving labels and return destinations, or explicit per-channel variants. This is a diagram contradiction, not a newly discovered platform constraint. The model's `surface` and `surfaceName` also disagree on several alternatives; the renderer may choose one, but the content source should be unambiguous.

### F03 — Required event code is an error island

`codeinvalid` has no incoming required-code branch, no declared successful continuation, and no initial code-entry state. Main RSVP proceeds from provider sign-in through SMS code directly to confirmation. Add the conditional access-code path with valid and invalid outcomes, clearly distinct from SMS verification. Which precise step owns it remains a proposed layout; requiring it when configured is raw user direction.

### F04 — Shared conversation is displayed but not walked through

`after_recap` includes visible comments and “Leave a comment,” but no linked compose/send/result, reply or like interaction. T2 explicitly wants back-and-forth/liking and comments near the top. A personal check-in note is not a substitute. The recap also illustrates only the viewer's check-in; show the requested route to other attendees' event check-ins. This is a whole-flow omission, not a request to introduce reconnection.

### F05 — Missed-scan correction stops at “Ask Astir to check”

`recap_missing_admission` appropriately does not unlock content, but has no help-result, operator correction, or corrected guest return. The door-time `stafffindguest` flow is a different circumstance. Show the minimal correction outcome returning an eligible guest to composer/recap, without staff creating their personal post. The exact case-management controls can remain proposed.

### F06 — Manual approval stops before the operator's decision and guest result

`manualpending` and `console-guests` establish the mode, but “Review requests” has no decision path. The board cannot yet demonstrate approve → confirmed or decline → clearly unconfirmed. Reuse existing confirmation rather than add redundant screens; keep capacity conflicts and rejection copy explicitly proposed. An operator approve action is not a waitlist offer acceptance.

### F07 — Notification-value and event-detail visual direction need explicit verification

The original source specifically calls for an example notification and immersive overlaid event imagery, social proof high on the page, and floating actions. M preserves several as notes but does not carry an example notification in `notification-primer`. Do not mistake a generic permission primer for the requested value preview. Root should verify the actual rendered hero/action treatment before labeling it missing. The exact later permission trigger remains proposed.

### F08 — Mixed approval labels obscure what is still a proposal

Several screens say `Approved behavior; proposed layout` while their action policy is itself proposed: `event-canceled`, `location-primer`, `location-denied`, `notification-primer`, and parts of event draft publication. A/B ticket/profile placement is also pending, although its notes say proposed. Group summaries help, but a screen-level label should distinguish approved baseline rules from proposed operating/default behavior. This is an **approval-label risk**, not evidence the user approved the full draft. D-choice answers do not approve every later proposed default.

### F09 — Some exceptional paths remain notes, not illustrated states

SMS wrong/expired code and resend recovery, canceled provider sign-in, successful required-code entry, late-confirmed home-address reveal, and failure while loading an already-unlocked recap are chiefly absent or in notes. These are lower priority than F03–F06, but the board should not be described as literally exhaustive. The original request calls for relevant wonky paths. Add only the states needed to demonstrate their consequences; do not open new product-question rounds for routine retry mechanics.

### F10 — A stale subsection in W can reintroduce settled questions

W's older post-event transition table still calls content publication timing and gallery reuse rules “open,” despite later D26/D28/D32 mappings. Other original-source exploration, such as friend-only discovery and renewed reconnection, is also superseded by later decisions. A downstream extraction must resolve chronology rather than promote every occurrence of “open” into a new decision. Root owns reconciliation of the master record; this audit does not edit it.

## What should not be changed based on this audit

The recent RSVP/text/download correction is supported. Apple/Google plus separate verified phone remains the selected flow unless the user now changes it. Empty personal check-in is valid; private stars/comment are not a public rating. Staff-recorded admission remains separate from check-in completion. Full guest-list access depends on confirmed RSVP, while the protected recap needs valid attendance and personal check-in. No reuse explanation, reconnection implementation, expanded privacy chooser, paid checkout, or automatic waitlist promotion should be added. The public-launch prerequisite and TestFlight testing scope remain recorded assumptions, not verified deployed capabilities.

The corrected board is substantially more complete than the initial 53-screen version. This audit records remaining gaps and source boundaries, not final design acceptance.
