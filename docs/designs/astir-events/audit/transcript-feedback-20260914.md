# Astir Events — September 14 transcript amendments

Source-ledger update only. This document does not edit the product baseline, builder, or app. Later explicit clarifications control over earlier exploration in the same review.

## Sources and authority

- **I:** inline review transcript (local authoring reference; see the requirements ledger), saved verbatim by root.
- **T3:** first continuation (local authoring source; authority retained in the requirements ledger).
- **T4:** second continuation (local authoring source; authority retained in the requirements ledger).
- **C:** user's subsequent direct clarification, relayed by root during this audit. Key excerpt: “the gate for those other things: manage, view guest list. those are just rsvp or just rsvp gate”. Root also relayed “i think we don't have to download it until you're showing your qr at the event.” The full clarification turn is not independently saved in this subtask; retain root's original message as provenance when adding it to the master evidence file.
- **Prior baseline:** [working product record](../working-product-record.md) and its D1–D35 decisions; [earlier source audit](source-crosscheck.md).

**Confirmed direction** means a direct request or a clear concluding instruction in these sources. **Exploration** means a suggested variant, number, timing, or unanswered implementation question. **Derived acceptance** spells out a necessary consequence without presenting it as a new user-selected policy.

## Material changes and resolved conflicts first

1. **No-app access conflict is resolved by C.** I initially suggests “download to view guest list and rsvp”; T3 then requests parity between app, Clip and browser for confirmed/unconfirmed event states. C confirms the existing RSVP gate: a recognized account with a confirmed RSVP may manage that reservation and view the full guest list without installing. Download upsell is optional; full-app entry/QR remains the hard admission requirement. Do not retain the early download gate or mark this clarification pending. A trailing speculative fragment does not select another policy.
2. **Apple/Google is unchanged.** I briefly questions whether signup should be text-first, then explicitly says “3 is unchanged.” D17's SMS verification remains separate from provider authentication.
3. **Pin tap now presents a collapsed event card on the normal map.** This refines D12's event destination and replaces the board's direct full-screen event jump. The event remains linked to its place; use the ordinary map/card interaction pattern rather than a new large Open event CTA.
4. **Remove the invented nearby-discovery step.** T4 explicitly removes old screen 31 and Explore nearby on old screen 30. This supersedes that proposed event-to-recommendations step, not Astir's ordinary map/place discovery features.
5. **Name and username are part of admission readiness.** T4 makes a full account at least name + username part of the gate. Photo remains optional, consistent with D18. Installed-but-incomplete onboarding must be its own state.
6. **New concrete capabilities:** event-configured tag options, optional generated invitation codes with capped/uncapped usage, followed-guest prioritization and mutuals, explicit map-filter rules, and a simple authenticated web console with a web scanner.
7. **Next deliverable is a Swift front-end prototype.** The users request visually accurate, isolated Swift screens with mock data and simulator screenshots, with no backend connection. They also require a complete end-to-end exit acceptance suite for the eventual build. A visual prototype is not evidence that backend acceptance tests pass.

## Original screen references

These are references to the board the users were reviewing. Preserve the stable IDs below when screens are added or removed; do not reinterpret their feedback using newly assigned numbers.

| Original reference | Stable ID | Meaning in this feedback |
| --- | --- | --- |
| 03 | `rsvp-auth` | Apple/Google signup remains. |
| 04 | `rsvp-phone` | Name/phone and future-event checkbox; remove trailing period from checkbox copy. |
| 06 | `rsvp-confirmed` | Reservation success; optional download upsell, not a forced transition. |
| 07 / 08 | `confirmation-text` / `pre-event-text` | Both use the same canonical View event link. |
| **09** | **`noapp-confirmed-detail`** | Expand into the complete event-detail surface/identity/RSVP state matrix, not just one no-app confirmed screen. |
| 18 | `events-list` | Upcoming event/ticket prominence discussion; “like an hour before” is not a selected cutoff. |
| 24 | `recap-notice` | Content-ready notice, including the reinstall/return case. |
| **25** | **`after_composer`** | Bring the event check-in closer to the standard check-in visual pattern; add event tag options. |
| **29** | **`map_special_event`** | Standard map, special event pin, collapsed event card and filter rules. |
| **30** | **`map_place_history`** | Standard place profile with event history; remove the invented large bottom CTA and Explore nearby. |
| **31** | **`map_recommendations`** | Remove this proposed extra step. |
| Later reference to accepting a waitlist offer | `offer` | Identify by the described action, not the changing display number. Acceptance is still required. |

## Atomic amendment ledger

### Entry, identity, reservation and surfaces

| ID | Source excerpt | Current requirement / amendment | Status and prior relationship |
| --- | --- | --- | --- |
| F001 | I: “it should be telling us that” | Every illustration clearly identifies full app, App Clip or browser. | Confirmed; strengthens earlier surface-clarity request. |
| F002 | I: “3 is unchanged.” | Keep Apple and Google signup; do not switch to phone-only signup. | Confirmed; earlier question in I is superseded by its conclusion. |
| F003 | I: “name, and phone number” | Account creation still includes name/phone, with the existing SMS verification requirement before confirmed RSVP. | Reaffirms D17 and original RSVP requirements. |
| F004 | I: “get rid of the period” | Remove the trailing period from the future-event-text checkbox label. | Confirmed copy edit; D19's separate unchecked opt-in remains. |
| F005 | I: “that's the end of that journey” | Reservation confirmation ends the initial RSVP task; subsequent texts continue the relationship. | Confirmed; installation is not required to finish RSVP. |
| F006 | I: “once your spot is confirmed, you get a text” | Send confirmation and later reminder texts after a successful RSVP. | Reaffirms D29, independent of installation. |
| F007 | I: “we're not making them; we're just upselling it” | A confirmation download prompt is optional and must explain its value. | Confirmed distinction; exact banner treatment is a proposal. |
| F008 | I: “download to view guest list and rsvp” | Preserve this only as an earlier explored access gate. | **Superseded by C**; do not implement as the final rule. |
| F009 | C: “manage, view guest list” / “just rsvp gate” | Confirmed RSVP, not download, unlocks full guest list and management in Clip/browser. | Confirmed clarification; consistent with D14/D30. Pending/waitlisted/unaccepted-offer states still do not qualify. |
| F010 | C: “showing your qr at the event” | Full app is required for entry/QR; early optional download does not change that deadline. | Confirms D15/D25. Precise upsell/reminder timing remains unselected. |
| F011 | T3: “seven and eight should say view event” | Label event links consistently as View event. | Confirmed copy/action direction. |
| F012 | T3: “all these view event links are the same” | Initial invitation, confirmation text and reminders use the same canonical event destination. | Confirmed; route by recipient state rather than assuming the original recipient's RSVP. |
| F013 | T3: “this link could get shared around” | A forwarded confirmation/reminder link must also work for someone who has never RSVPed. | Confirmed; no booking identity or privileges inherited from the sender. |
| F014 | T3: “User has the app, user can load app clip, user can't load app clip” | Cover installed app, no-app Clip-capable, and no-app browser-fallback entry. | Confirmed three-surface routing requirement; D14 remains. |
| F015 | T3: “logged in and not logged in” | Model authentication/recognition separately from installation and RSVP status on every surface. | Confirmed; not one combined “new user” boolean. |
| F016 | T3: “show you the entire event details” | An unrecognized/non-RSVPed visitor can see the permitted event detail before being required to authenticate for RSVP. | Confirmed, subject to event/private-location visibility rules. |
| F017 | T3: “has the app and has RSVPed” | Recognized installed guests with a reservation open the event in that reservation state. | Confirmed; no unnecessary onboarding/download or duplicate RSVP. |
| F018 | T3: “has the app has not RSVPed” | Installed guests without a reservation see the unreserved event detail and may begin the normal RSVP flow. | Confirmed; applicable privacy/access-code/capacity rules remain. |
| F019 | T3: “remembering the user when the user comes back” | Returning Clip/browser guests need an identity-recognition/recovery path to their existing reservation. | Confirmed product outcome; persistence mechanism is an engineering question. |
| F020 | T3: “we don't know you've RSVPed” | Unknown identity does not prove no reservation exists. Distinguish unknown from known-not-RSVPed. | Confirmed; account recovery must not silently create another booking. |
| F021 | T3: “both in the RSVPed and not in RSVPed state” | App Clip and browser reproduce applicable single-event functionality in both states. | Confirmed; C settles guest-list/management access. Full-app admission/check-in/media exceptions remain explicit. |
| F022 | T3: “just for that specific event” / “it doesn't have tabs” | Clip remains scoped to one event, without the full app's global tabs/navigation. | Confirmed; do not confuse functional parity with identical app chrome. |
| F023 | T3: “web experience should mimic” | Browser fallback should feel visually consistent with the app/Clip event experience. | Confirmed; not a separate reduced-quality RSVP product. |
| F024 | T3: “I want to see those side by side” | Present app, Clip and browser × confirmed, unreserved and unknown states together. | Confirmed review deliverable. Include signed-in/out distinctions where they change behavior. |
| F025 | T3: “a flowchart, decision tree” | Build a decision tree explaining how the system knows the state and link every outcome to its screen. | Confirmed review deliverable; screen order alone is insufficient. |
| F026 | T3: “like an hour before the event” | Consider ticket prominence as arrival approaches. | **Exploration**; neither a one-hour availability cutoff nor a new confirmation rule was selected. |
| F027 | T3: “It should be view or change RSVP.” | Use View/change RSVP as the event's management action instead of a blunt Cancel RSVP CTA. | Confirmed presentation amendment; D24 cancellation remains within management. |
| F028 | T4: “app is installed” / “haven't finished onboarding yet” | Explicitly cover an installed app with incomplete account/setup. | Confirmed missing-state requirement. |
| F029 | T4: “Part of that gate of getting into the event is having a full account.” | Admission requires a complete account, not installation alone. | Confirmed; strengthens the earlier proposed minimal-identity step. |
| F030 | T4: “at least name, username” | Name and username are required for that account/readiness gate. | Confirmed; do not allow an optional-photo Skip action to bypass missing required identity. Exact QR readiness presentation remains design work. |
| F031 | T4: “I don't think it's necessarily photo” | Profile photo remains optional despite the stronger account gate. | Confirmed in context and consistent with D18; no mandatory-photo amendment. |

### Post-event check-in, recap and sharing

| ID | Source excerpt | Current requirement / amendment | Status and prior relationship |
| --- | --- | --- | --- |
| F032 | T3: “a notifications program baked in here as well” | Include an explicit notification program alongside the SMS program in the flowchart. | Confirmed program scope; exact push cadence/permission/delivery details still require design, while D29 settles SMS cadence. |
| F033 | T3: “you should be able to upload photos” | Let eligible attendees contribute media from the post-event event/recap page. | Reaffirms D27; separate from selecting gallery media for a personal post. |
| F034 | T3: “You should be able to do both” | Support own media in check-in and shared-gallery contribution afterward. | Reaffirms D2/D6/D27; do not collapse the two operations. |
| F035 | T3: “you can't upload photos to the event without” / “having the app” | Event-media upload remains full-app functionality. | Confirmed carveout from the earlier broad Clip/browser parity language. |
| F036 | T3: “You can't even check in.” | Required post-event check-in also needs the installed full app. | Confirmed; no browser-only content-unlock path. |
| F037 | T3: “they could have deleted the app” | Handle an attendee who uninstalled after entry, then opens a recap text/link. | Confirmed recovery case: explain download, recover the same account/attendance and return to the requested check-in/recap. Do not repeat admission. |
| F038 | T3: “25 should look a little more like our standard check-in” | Align the event composer visually with the existing check-in pattern. | Confirmed visual amendment; event identity, no public rating and private feedback distinctions remain. |
| F039 | T3: “generate some tags for the event” | Event creation/configuration includes event-specific tag options. | Confirmed new capability; managed by Astir in the console. |
| F040 | T3: “default options within our tag system for the event” | Those configured tags appear as default choices in the event check-in tag UI. | Confirmed integration direction; do not invent a required tag-selection gate. |
| F041 | T3: “like ten tags” | Ten is a suggested scale, not a selected exact count or maximum. | Exploration; generation method, selection limits and taxonomy persistence are not settled. |
| F042 | T3: “needs a splash image. Needs to be rich.” | Give the event recap rich header/cover imagery. | Confirmed visual requirement. |
| F043 | T3: “similar to our the place card” / “but event focus” | Use the existing full place-profile visual structure as a reference for the event recap, with event-focused content. | Confirmed direction; not a mandate to copy unrelated place features. |
| F044 | T3: “functionally the same as our our comments right now” | Reuse the existing comments interaction pattern and controls. | Confirmed; preserve prominent conversation and avoid inventing a separate discussion system. |
| F045 | T3: “a nice juicy plus” | Put a clear add-media affordance in the recap's photos/videos section. | Confirmed; uploading and photo reuse remain separate. |
| F046 | T3: “share button needs to be on the event” / “upper right” | Place Share at the upper right of the event experience. | Confirmed placement request, including the recap context under review. |
| F047 | T3: “share what to your like Instagram” | Capture possible external/social sharing as a desired exploration. | Payload, destination behavior and permission scope are not defined. Do not infer automatic Instagram publishing or exposure of the protected gallery. |
| F048 | T3: “the color is just slightly different” | Preserve the reported icon/color inconsistency for visual correction. | Direct visual feedback, but the exact icon is not identifiable from text alone; inspect the referenced UI rather than invent the target. |

### Map, place history and filters

| ID | Source excerpt | Current requirement / amendment | Status and prior relationship |
| --- | --- | --- | --- |
| F049 | T3: “look just like the standard map view” | Keep the ordinary map surface for old screen 29. | Confirmed; no separate post-event map product. |
| F050 | T3: “it opens the collapse card for that event” | Tapping the special pin opens an event-led collapsed card over the map. | Confirmed refinement of D12; replaces a direct full-screen jump/large mock CTA. |
| F051 | T4: “Astir 001 at Hotchkis Park” | Explore the pin/card label as event identity plus linked place. | Confirmed content direction; example names are illustrative, not a rename of the sample event/venue. |
| F052 | T4: “the at like smaller” | Visually subordinate “at” within the event/place label. | Confirmed hierarchy detail; accommodate long event/place names. |
| F053 | T4: “We need explorations of that pin.” | Produce pin alternatives, including considered shape, glow and motion approaches. | Confirmed exploration task; no specific shape/color/pulse was selected. |
| F054 | T4: “squared versus rounded” / “pulsing in and out” | Square/round/glow/pulse are candidates, not a final design instruction. | Exploration. D11's preset controls remain; no custom animation editor was authorized. |
| F055 | T3: “some ephemeral time period that we set on our console” | Special event treatment runs for a configurable period. | Reaffirms D10/D11; “always showing” in T4 is interpreted within the active treatment window, not forever. |
| F056 | T4: “in featured, it will show to everybody” | The Featured filter exposes the active event treatment to permitted app viewers generally. | Confirmed filter rule; preserve private-location restrictions and any applicable event visibility. |
| F057 | T4: “you tab and you went to the event” | The You filter includes that event treatment for the attendee. | Confirmed filter intent. The exact attendance-versus-completed-visit predicate needs an explicit mapping; do not silently alter D4/D5. |
| F058 | T4: “friends tab and your friends win” | The Friends filter includes event treatment when relevant friends attended. | Confirmed intent from the transcribed “win”/went context. Use the existing social graph semantics; exact eligibility mapping remains to specify. |
| F059 | T4: “What about second degree?” / “just show it to everybody” | Second-degree expansion was raised, then the discussion concluded on broad Featured visibility. | No separate approval to change Friends into a second-degree social filter. |
| F060 | T4: “a switch for that on the console” | Operators can control an event's Featured/map promotion. | Confirmed control amendment; distinguish promotion settings from private-address and recap access. |
| F061 | T4: “It shouldn't be just a big CTA at the bottom” | Keep the standard place-profile interaction structure for event history; remove the invented dominant bottom event CTA. | Confirmed visual amendment to `map_place_history`. A normal event-history row/card still navigates to the event. |
| F062 | T4: “Get rid of thirty one” | Remove `map_recommendations` as an extra step in this journey. | Confirmed removal of a proposal; ordinary map discovery stays intact. |
| F063 | T4: “get rid of the explore nearby on thirty” | Remove Explore nearby from `map_place_history`. | Confirmed paired removal; clean up incoming and return links rather than leaving a dead step. |
| F064 | T4: “The visual isn't quite right yet.” | Events-tab direction is accepted broadly, but current styling is not approved. | Confirmed review feedback; retain tab, confirmed ordering and event access. |

### Internal operations, codes and guests

| ID | Source excerpt | Current requirement / amendment | Status and prior relationship |
| --- | --- | --- | --- |
| F065 | T4: “a web view which we log into on our end” | The internal console is an authenticated web interface. | Confirmed surface choice. |
| F066 | T4: “It's not in the app.” | Do not place the operational console inside the guest app. | Confirmed correction to any native-console implication. |
| F067 | T4: “Very simple, very bare bones.” | Keep console UI simple and practical. | Confirmed quality direction; do not delete required controls to simplify its appearance. |
| F068 | T4: “not go into code and like fucking change shit” | Event operations/settings are editable by the internal team without code changes. | Confirmed operational outcome. |
| F069 | T4: “We put our photos up first party.” | Console supports Astir's first-party event media as well as event creation/settings/post-event experience management. | Confirmed capability; complements attendee uploads and D26 recap publication. |
| F070 | T4: “my code should come in in the text message” | Enabled invitation codes can accompany the original invite/text shared with guests. | Confirmed direction; distinguish invitation/access codes from SMS identity-verification codes. |
| F071 | T4: “Generate codes” | Console can generate invitation codes. | Confirmed expansion beyond merely accepting one configured event code. |
| F072 | T4: “cap code usage if we want, or uncap it” | Generated codes support optional usage limits and an unlimited setting. | Confirmed. What counts as a use, cancellation restoration and concurrent redemption need engineering/product rules. |
| F073 | T4: “All this needs to be optional.” | Code requirements/usage controls can be disabled; they are not mandatory for every event. | Confirmed. |
| F074 | T4: “we probably won't use any of that functionality” / “make sure that it is there” | Keep code functionality in the intended design even if early events leave it off. | Confirmed; do not silently defer the capability because initial usage is optional. |
| F075 | T4: “Well, actually no no no sorry” / “they have to accept” | Waitlist selection sends an offer; the recipient accepts before confirmation. | Explicit correction reaffirms D23. Do not restore automatic promotion from the preceding sentence. |
| F076 | T4: “a per event waitlist” | The full-event waitlist remains distinct from a possible out-of-area/city-interest list. | Clarification, not approval to add a new city waitlist. The brief doubt about needing waitlists does not revoke D21. |
| F077 | T4: “a very simple QR scanner web view” | Staff scanning can be a minimal web view within the console, with admission action. | Confirmed surface/simplicity direction; D25 fallback and D5 recorded attendance still apply. |
| F078 | T4: “let's have it” | Retain scanner capability despite speculation that staff might not use it initially. | Confirmed scope retention. Casual operational speculation does not waive recorded admission or full-account entry. |
| F079 | T4: “bump up people you follow” | Prioritize followed people in the full guest list. | Confirmed social ordering requirement; D30/C's confirmed-RSVP gate remains. |
| F080 | T4: “show mutuals. Like four mutuals.” | Show mutual-connection information alongside guest entries. | Confirmed feature direction; example count is illustrative and data must be truthful. |

### Delivery and acceptance

| ID | Source excerpt | Current requirement / amendment | Status and prior relationship |
| --- | --- | --- | --- |
| F081 | T3: “high fidelity mockups, which we should do next” | Move beyond the low-fidelity board into visually accurate screen exploration. | Confirmed next deliverable. |
| F082 | T3: “putting them in. Sim and screenshotting them” | Run the screen prototype in the simulator and capture screenshots. | Confirmed validation/delivery method, not static HTML alone. |
| F083 | T4: “actual mocks in Swift of all this shit” | Build Swift front-end mockups of the affected flows. | Confirmed technology/deliverable. |
| F084 | T4: “Front end only” / “not plugged in” | Keep the prototype isolated with mocked state; do not connect real backend behavior. | Confirmed scope boundary. |
| F085 | T3: “just do it in a sandbox” / “Don't do any back end.” | Use a lightweight sandbox/prototype rather than shipping production event logic. | Confirmed; “Ship all this first” does not authorize backend integration/deployment contrary to this explicit boundary. |
| F086 | T4: “get through the designs first” | Finish these design corrections before deciding engineering/core-development sequencing. | Confirmed order; concerns about implementation time are not permission to cut requested scope. |
| F087 | T4: “a full set of like exit tests” | Define a comprehensive, traceable exit acceptance suite for the eventual implementation. | Confirmed engineering-handoff requirement. |
| F088 | T4: “starting from all these different states and actually working end to end” | Tests must cover every relevant receiver/entry state through completion, not only individual screen rendering. | Confirmed completeness standard; see acceptance inventory below. |
| F089 | T4: “that'll be like our exit criteria” | Use passing acceptance scenarios as explicit implementation exit criteria. | Confirmed; prototype-only evidence must not be described as live end-to-end passing. |
| F090 | T4: “Just list out what you're going to do and then do it” | Present the concrete action list, then execute the authorized prototype/design work. | Confirmed workflow instruction; no new permission checkpoint required for that scope. |

## Existing decisions preserved or amended

- **D1–D6:** personal post, empty valid submission, attendee recap gate, one event/place visit and photo-source sequencing remain. Add configurable event tag choices without restoring a public venue rating or forcing a public contribution.
- **D7:** no new reconnection behavior is approved. Followed-guest ordering and mutual counts are not missed connections, private messaging, or “solo, single, or private.”
- **D8/D13/D35:** private homes retain approximate location outside the eligible exact-address window. Broad Featured visibility and cross-surface event parity do not disclose a home address.
- **D9:** Everyone-in-Astir personal-post audience and small eye indicator remain; no expanded privacy UI is selected.
- **D10/D11:** map filter behavior and web controls become more concrete; special treatment is still temporary/configurable. Shape/glow/motion exploration does not select a custom style editor.
- **D12:** preserve event-first semantics but show the collapsed event card as the immediate pin response; full detail follows the normal card interaction.
- **D14/D15/D17–D19/D30:** confirmed RSVP management/full guest list works without installation; identity must be recognized; Apple/Google plus verified phone remain; photo stays optional; marketing opt-in stays separate.
- **D18 plus F029–F030:** name and username now explicitly belong to account readiness for entry. Do not force the optional photo or unrelated permissions to satisfy that requirement.
- **D20–D25:** free RSVP, internal manual-approval option, per-event waitlist, explicit offer acceptance, cancellation before start and verified QR-loading fallback remain. Change RSVP is the management entry label, not removal of cancellation.
- **D26–D29/D32–D34:** publish-before-invitation, immediate eligible uploads, removal propagation, retained recap completion and optional private feedback remain. No reuse explanation has been restored. Notification planning now explicitly accompanies the SMS program.
- **Prior proposed recommendations step:** F062/F063 remove this invented branch. A requirement ledger should mark that prior proposal superseded, not leave it “shown” against a deleted screen.

## Acceptance inventory required by the new feedback

These are **derived acceptance categories to enumerate and test**, not claims that tests have run. Cross the relevant dimensions without treating impossible combinations as valid user states.

1. Canonical original/confirmation/reminder link opened directly or forwarded; routing resolves the current receiver rather than inheriting the sender's booking.
2. Installed signed-in, installed signed-out, installed incomplete profile, Clip-capable, Clip-unavailable/browser and lost-session return.
3. Recognized confirmed RSVP, known-no-RSVP, unknown booking ownership, pending approval, waiting, offered, canceled and no-show; unknown never silently means no booking.
4. Apple/Google success/cancel/failure, missing or verified phone, invalid/expired SMS code, and account switching with/without an existing reservation.
5. Event-code disabled, valid, invalid, capped/exhausted and uncapped; combine with event capacity/manual approval without confusing invitation codes with SMS verification.
6. Confirmed no-app guest viewing/managing RSVP and full guest list; attempted early optional download; delayed entry download; return to the same account/event.
7. Account readiness at entry: name/username complete or missing, optional photo present/skipped/failed, and unrelated permission denial.
8. Normal QR scan, installed guest QR failure, duplicate/invalid booking, staff correction of a missed scan and the preserved distinctions among RSVP/admission/check-in.
9. Published/unpublished/unavailable recap; attended/no recorded attendance; complete/incomplete/deleted personal check-in; attendee who uninstalled before opening the recap link.
10. Empty personal check-in, event tags, optional public fields/private feedback, shared photo/video upload, editing/reuse/removal and repeated/retried actions without duplicate visits or leaked protected content.
11. App/Clip/browser event parity with explicit full-app-only post-event actions; returning to the same surface and identity after management, guest-list or authentication detours.
12. Normal map + event pin + collapsed card + full event/place history, including Featured/You/Friends eligibility, configured promotion off/on/expired and private-home approximation/reveal/expiry.
13. Web-console event/media/tag/code/promotion/message operations, recap publication/invitation sequencing and simple scanner views, using mocked state during the prototype phase.
14. Notifications and SMS with permission/opt-in/opt-out/delivery states kept distinct; returned links still resolve current event/account state.
15. No remaining route into removed old screen 31/Explore nearby; long event/place labels, configured tags, mutual counts and alternate states remain readable in simulator screenshots.

## Still unselected details — do not invent approval

The exact arrival-time switch for prominent Show ticket; visual/download-upsell treatment; exact tag count/generation/selection rules; invitation-code redemption accounting; pin shape/glow/motion; precise You/Friends attendance predicates; external share payload/destinations; notification cadence and delivery mechanics; and the unidentified icon-color target remain design/engineering details to resolve or label as proposals. The confirmed-RSVP no-app access question is **not** on this list: C resolved it.
