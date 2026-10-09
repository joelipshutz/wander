# Experience review findings

October 9, 2026 · REC-636 · Proposal review with native simulator evidence; pending human product decisions

## Scope challenge

The smallest complete change is a shared map/feed surface that preserves capture, personal history, lists, search, privacy and routes. Private conversational messaging, new event lifecycle work, itineraries and a map-provider switch are not prerequisites to validate it. They remain part of the destination journey where relevant, with separate implementation gates.

The proposed Feed/tab navigation is a material change; Profile is a continuity boundary. Keep its identity/social header, save streak, recent activity, full Your Map entry/experience and calendar in their current order. Patterns stays inside Your Map, with its existing Map/Patterns switch. Profile → Your Map must not become a Feed-tab redirect. D5 now reviews individual features for possible Feed reuse or a specifically chosen relocation; until selected, their current entries remain. A Feed owner scope or Snapshot equivalent is optional, and neither substitutes for the full Profile map.

## Seven design passes

| Pass | Finding and resolution in the proposal | Remaining evidence |
|---|---|---|
| Information architecture | Current source has Map/Feed/optional Events/Lists/Profile. Proposed Live/Lists/Profile changes Feed and primary tabs while preserving current Profile hierarchy and full Your Map. D5 is a selective feature inventory, not a screen migration. | Three-tab decision; explicit per-feature reuse decisions; Profile continuity and route tests before implementation |
| State coverage | Spec includes loading, pagination failure, sparse/empty, offline, denied location, access revocation, keyboard, new activity and flag rollback. | Prototype is a subset; production state tests still required |
| Journey | Adoption uses a dismissible once-per-account/version card, preserves explicit intent and says Your Map remains in Profile. The social loop is activity → context → connection/plan. | Moderated existing-user task review; unchanged Profile tasks tested separately from optional Feed shortcuts; no retention uplift claimed |
| Visual clarity | One map and one activity drawer; person/time/place hierarchy; restrained controls. Avoid a dashboard of decorative cards or a stale “here now” impression. | Small/large phone and full/half/peek captures are in the gallery; real-device interaction remains a gate |
| Design-system alignment | Adaptive ink/paper, Signal accent, serif titles, Avenir body and localized materials. Existing historical shell copy is treated separately from the current visual override. | Opaque secondary colors measured; dark/light screenshots inspected; map attribution now reserved above drawer |
| Accessibility | 44pt controls, button alternatives for drag/draw, accessible radius controls, large-type list fallback and Reduce Motion are specified. | Simulator AX text, keyboard and core navigation checked; spoken VoiceOver/focus and real-device gestures remain |
| Unresolved choices | D1–D11 explicitly distinguish recommendations from approvals. Circle-drawing interpretation and breadth of full-journey review are optional questions. | Record human answers; do not infer approval from elapsed time |

Two source-based review passes corrected snapshot completeness/image parity, collection and legacy activity mapping, interrupted NUX, offline revocation wording, owner/member Patterns continuity, exact route payloads and root-versus-modal tab behavior. The current scope correction removes wholesale Profile-map relocation, a new direct Profile Patterns entry and a new Profile commitments section. Existing Your Map Snapshot stays available. If a Feed capture equivalent is selected, its proposed flow freezes query/camera/membership and renders a complete preview before confirmation. The native prototype omits that production capture operation rather than imitating it with a paged subset.

This review combines source-based proposal review with native simulator inspection. It does not claim moderated usability testing or production accessibility certification. See the [capture gallery](captures.md) and [validation record](validation.md).

## Engineering risks surfaced by the design

- **Map/list parity:** paginated content and viewport counts need a shared query and explicit loaded-count wording. A pretty populated map is not proof of coverage.
- **Different meanings of Friends:** current Map means followed people; current Feed's Only Friends means mutuals. Proposed labels must not conflate them.
- **History versus recency:** owner places cannot be truncated to the feed window. Imported historical visits must retain occurrence timestamps.
- **Independent navigation:** Profile → Your Map remains within Profile. Any optional Feed owner scope must not mutate Profile's lens, camera, selection, Patterns or calendar/history route; component reuse must preserve distinct state owners.
- **Existing plan capability versus messages:** invitation creation/inbox exists; a private chat delivery service was not found. Demo replies are explicitly simulated.
- **Privacy and replay:** new private compositions must not inherit readable replay without an explicit content-masking review.
- **Events readiness:** current app has an interest teaser; production event content cannot be fabricated to fill the new feed.
- **Map technology:** the app already uses MapKit. Muted standard emphasis, point-of-interest filtering and custom annotations should be tested first. Those controls are supported in Apple's [MapStyle documentation](https://developer.apple.com/documentation/mapkit/mapstyle/standard(elevation:emphasis:pointsofinterest:showstraffic:)). They do not establish arbitrary map restyling.
- **Sheet interaction:** Apple supports background interaction through specified presentation detents; whether it meets this app's tabs/detail/gesture layout still needs a spike. See [PresentationBackgroundInteraction](https://developer.apple.com/documentation/swiftui/presentationbackgroundinteraction).

## Preserved strengths

Reuse canonical place identities and visit history, the tested audience contracts, existing list sharing/collaboration, current place-card/full-profile components, successful capture/retry behavior, the feature-flag platform and the existing plan invitation boundary. The redesign should expose these more coherently rather than recreate them behind new labels.

## Remaining high-risk design decisions

These are actionable review findings, not claims that the fixture prototype proves production behavior. They do not block completing the review package.

| Priority | Risk / decision | Required next action and evidence |
|---|---|---|
| P1 | **Profile continuity can still be lost through reuse.** Replacing the Your Map route or sharing mutable Feed state would violate the scope even if the preview remains. | Keep the full route and current section order. Run owner and member journeys through Map/Patterns, filters, Snapshot/share, place detail and calendar, then return after changing Feed. Compare before/after screenshots and state; any removed entry needs its own explicit D5 decision. |
| P1 | **Drawer navigation may hide escape routes.** Peek hides tabs while map gestures, detail, keyboard and scroll all compete for space. | Spike native half/full/peek on small/large phones. Require labelled Expand and Map actions, reachable Add/search, safe map attribution, correct VoiceOver focus and exact detent/camera restoration after detail. If these fail, revise containment before polishing gestures. |
| P1 | **Recent activity may still read as presence.** The name Live plus person pins can imply current location even with relative timestamps. | Keep action and actual occurrence time visible in pin labels, cards and detail; avoid presence dots/pulses or “here now” copy for old records. Test comprehension with historical imports, Yesterday and distant friends. Resolve D2/D3 from sparse and dense examples, not the populated fixture alone. |
| P1 | **Nearby membership is ambiguous for ungeocoded records.** A collection or legacy record with no permitted coordinate cannot be asserted to fall inside a circle. | In the query-contract review, define unknown-location behavior: exclude it from geographically constrained results/counts unless a permitted area attribution proves membership; offer unfiltered Following access with honest copy. Test list-created, missing-place and approximate-location cases. Never infer the actor's home or a withheld coordinate. |
| P2 | **Selective Feed features can turn into another overloaded personal map.** Your places, advanced lenses, drawing and Snapshot each add controls to the core activity journey. | Review D5 one feature at a time: show its specific user task, Feed placement and preserved Profile entry. Start with the smallest useful subset; do not move Patterns or reproduce every lens by default. |
| P2 | **Partial browsing and complete capture are different jobs.** A selected Feed Snapshot equivalent may include more places than the browsing page displays. | Keep it absent until selected. Then validate complete preview/image/list membership under 20-of-100 loaded, mixed status, pan after circle, deletion during preview and enumeration failure. Existing Your Map Snapshot remains usable independently. |
| P2 | **The offline lease trades privacy staleness for utility.** D11's 15-minute proposal is not measured user tolerance and must not be presented as instant remote recall. | Show offline, expired and reconnect states in review; distinguish retained owner history from unavailable people. Decide the lease before production and test clock/foreground/revalidation behavior. |
| P2 | **Events and replies can create false completion.** Teaser eligibility is not real inventory; an invitation is not acceptance; a demo private reply is not delivery. | Keep each card/action tied to an available contract and label simulated outcomes locally. Preserve current interest registration while Events is incomplete. Validate real recipient and delivery states only in their later implementation slices. |

The written package and native prototype are prepared for product review. The final simulator outcomes and inspected captures are recorded separately; spoken VoiceOver, real-device testing, moderated usability and production validation remain required before implementation/release claims.
