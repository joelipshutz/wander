# Astir Live — accepted direction and implementation contract

REC-636 · October 11, 2026 · **Implementation in progress; release validation pending**

## 1. The change we are making

Astir should answer **“What are my people up to, and what could we do together?”** on its first screen. The home combines an activity map and a draggable feed. A check-in, Wanna, plan, or event gives someone a concrete reason to connect. Saved places remain useful long after that activity is recent.

This is a change to the Feed and primary-tab journey: entry, activity discovery, capture, connection, and return. The Live destination combines the current Map-tab and Feed jobs. Profile keeps its existing identity/social header, save streak, recent activity, full Your Map experience and calendar in their current order. Area drawing is the only Your Map capability selected for reuse in Live. All other Your Map tools, history and navigation stay in Profile; no full-screen relocation or additional owner-map workspace is in scope.

The accepted direction authorizes implementation of Live / Lists / Profile, the preserved Feed experience, D2/D3 query presets and defaults, existing plan invitations and production private messaging with a mutual-only baseline. It does not authorize a public people directory, continuous location sharing, automatic invitations, paid access or broader visibility. Implementation and validation are underway; hosted activation and release have not been established by these documents. Current integrated evidence and remaining reruns are recorded in the [integrated validation report](review/integrated-validation.md), maintained separately from the earlier prototype evidence.

### Inputs and their authority

- The supplied [October 8 strategy discussion](https://docs.google.com/document/d/1sZ91bbrizaCViuXEkwppY7MhOwIb4x3EZOK5I9IR8uM/edit?tab=t.0) and appended earlier Live discussion establish the activity-first direction, map/drawer interaction, nearby/following perspectives, future plans, contextual replies, and the need to handle sparse networks. This specification contains product conclusions, not the private transcript or unrelated business discussion.
- `docs/product/2026-09-24-astir-live-discussion.md` preserves the original interaction proposal. Its original recommendations remain historical; the decision register below distinguishes Ryan’s later accepted choices from still-unanswered defaults.
- The current source and tests establish compatibility requirements. The initial source audit used `2800caaba`; this review branch is based on fetched integration head `d9f827353648bab91a17187721b5ea41e65e1a42`. An implementation branch must reconcile later drift.
- `DESIGN.md` supplies the current Astir visual override. Its older tab descriptions are not the current shell contract.
- `docs/designs/astir-events/engineering-handoff.md` remains the authority for the separate Events lifecycle work. Integrating its discovery does not approve its outstanding choices.

## 2. Outcomes and non-goals

### Outcomes

1. A returning user can understand recent activity and move between Feed's map and list while finding personal history through the familiar Profile → Your Map route.
2. Moving between list and map does not change the subject, filters, selection, or content unexpectedly.
3. Existing users recognize their saves, people, lists, activity, and plans after the redesign. Profile's hierarchy and complete Your Map route remain intact. No content changes audience because its navigation moved.
4. A Wanna can open the actual existing plan-invitation flow; an activity can open a private conversation under the approved mutual-only messaging baseline.
5. A user with no nearby network gets an honest, useful next action.

### Current implementation boundary

The integrated `Wander` app contains `LiveScreen`, a **SwiftUI Map/MapReader** surface and custom drawer, with the existing `FeedScreen` embedded. Live derives its pins and filtered cards from `store.visibleFeedActivityGroups`. Committed audience/time/type/area/radius/category/person selections now drive the additive Live query through the store and repository. The matching SQL remains an undeployed draft, so server completeness is not yet verified. Loaded counts, empty states and pagination stay truthful. Profile's complete history and Your Map remain independent.

| Present in the implementation | Boundary / required verification |
|---|---|
| Three-tab shell behind registered `.unifiedLiveV1`, default off; existing Add/search/notifications and compatibility routes | Hosted flag registration and final route/rollback evidence |
| Existing Feed cards/actions/module order, local map/filter projection, drawing draft/Apply/Cancel and camera policy | Final gesture/accessibility/device validation; no complete-area or server-total claim |
| `LiveFeedQuery` and additive `FeedRepository.liveFeed`/`SupabaseFeedRepository.liveFeed` APIs | Store/query integration is implemented; [Live RPC SQL](implementation-drafts/live-feed.sql) is packaged and still needs hosted execution |
| Private-message inbox/thread UI, memory-only state, real repository, ephemeral transport and inactive-scene privacy cover | [Messaging SQL](implementation-drafts/private-contextual-messages.sql) is an undeployed draft; hosted mutual/source/block/idempotency and operational gates remain. Focused replay and switcher results are recorded in the [validation report](review/integrated-validation.md#focused-v13-privacy-evidence) |
| Existing invitation composer/repository reached through Live's plan picker | Own/friend Wanna and real create/share/open/inbox verification |
| Inline introduction, explicit first-visit semantic acknowledgements and archived checkpoint recovery | Recovery, account-change and rollback validation; historical missing payloads retain explicit fallback routes |
| D10 Upcoming invitations entry and separate sheet, plus existing eligible Events interest entry | Current/future dated received invitations only, at most three visible from the latest 100; full Events discovery is separate |

The [integrated validation report](review/integrated-validation.md) is the single authority for candidate identity, test results, captures and outstanding checks. This specification defines the behavior to validate; implemented source does not establish a passing full suite or hosted readiness. SQL is packaged; deployment and execution remain outstanding.

The **Live Experience Review** scheme runs this integrated target with isolated Simulator fixtures; use the [review guide](review-guide.md). Its message demo explicitly says nothing is delivered and shows Simulated acknowledgements. A demo is not hosted delivery evidence. The separate `preview/rec-636-live` app and captures remain historical design evidence only.

The requirements below describe accepted behavior and acceptance targets; they are not a completion report. Production mutual-only messaging is approved work. Richer group planning, automatic invitations, paid access, walking routes and ongoing location tracking remain outside scope. Events booking/guest/admission/recap stays under its existing program. D11 is approved: a 15-minute display lease applies only to other people’s Live activity; existing shared-cache/Profile history remains unchanged.

## 3. Information architecture

### Accepted navigation

**Live · Lists · Profile** are the locked bottom destinations. Live names the redesigned Feed with its map/drawer interaction. Add stays a prominent action in its header. Search is a Live entry and the existing unified search flow remains available. Notifications remain accessible; a Conversations entry is separate from notifications even if both sit in the same header area. This major Feed/tab change does not redesign Profile or turn its Your Map entry into a tab switch.

The shell must not grow or shrink based on city. Eligible events appear in Live and in a persistent Events filter/entry. An empty event inventory does not create an empty tab. Lists remains a first-class destination because ownership, collaborators, invitations and organization are distinct tasks that a chronological feed does not replace. The root tab-visibility rule applies to Live's three drawer states; full-screen detail, settings, editors and system modals keep their destination-specific navigation contracts.

The three-tab choice is settled. Do not reopen a separate Map, Events or Plans tab while implementing this scope.

### Complete destination mapping

| Current job / entry | Proposed destination | Preservation requirement |
|---|---|---|
| Map tab | Live in map/drawer mode | Source/filters, place lookup, recenter, add, place detail and permissions survive |
| Feed | Live in half or full drawer | Activity IDs, comments, likes, invitations, pagination and inline search survive |
| Featured places | Explicit Places discovery fallback within Live/search | Anonymous place aggregates never become attributed stranger activity |
| Events tab / interest teaser | Live Events entry; canonical teaser until Events ships | Keep eligibility and interest-registration semantics; no invented available events |
| Lists | Lists tab | Existing IDs, links, members, roles, invitations and ordering unchanged |
| Add | Header Add action; existing entry links remain valid | Check-in, Wanna, import/photo/link/manual recovery retained |
| Owner Profile → Your Map | Existing full Your Map within Profile navigation | Preserve preview/Explore, map and Patterns modes, filters, saved lenses, history, camera/detail return and Back to Profile; no redirect to Feed |
| Other profile → Their map | Existing full member map within that profile's navigation | Viewer access enforced; never reuse owner cache; preserve its Patterns/filter context and return to that profile |
| Your Map → Patterns | Existing Map/Patterns switch inside Your Map | Existing data filters remain; no new top-level Profile Patterns destination; do not market decorative curves as measured data |
| Your Map Snapshot | Existing owner Snapshot action and persistent Lists | Retain only in Your Map; no Live Snapshot action is selected |
| Your Map share | Existing map card / profile link | Retain only in Your Map; no Live share-map action is selected; the link does not serialize the lens |
| Profile identity/social, streak, activity and calendar | Existing Profile sections and order | Preserve edit/settings, social graph, activity/history, dates and compact private progress |
| People search, graph lists, invites | Search / Profile / contextual activity attribution | Preserve follow, mutual, block and contact permission behavior |
| Place, activity, list, plan and event deep links | Canonical destination inside the new shell | Explicit intent outranks default Live landing and migration teaching |

### Accepted Your Map boundary — D5

Only area drawing is reused in Live. Profile keeps its current identity/social header, streak, recent activity, Your Map entry and calendar in the existing order. Owner/member Your Map keeps Map/Patterns, all filters, complete history, session lenses, Snapshot, sharing and detail/return behavior. Live does not add Your places, owner-history, Patterns, Snapshot or map-sharing destinations. Reusing drawing geometry or native map components does not couple Profile and Live state.

## 4. The Live screen

### Layout and states

The integrated map is a SwiftUI `Map` that stays mounted underneath a custom drawer. It does not wrap the legacy `NativeMapView`. The table below describes the current implementation; final native evidence must establish gesture, keyboard and accessibility behavior. The earlier interaction target hid tabs at peek and added a floating Map pill at full height. Neither is implemented: tabs currently stay visible at every drawer detent, and the handle provides the full-drawer escape. Review those differences explicitly rather than treating the earlier target as completed behavior.

| State | Map | Drawer | Tab bar | Available escape |
|---|---|---|---|---|
| Half / landing | Visible above the drawer | Heading, invite and people modules; activity continues below | Visible | Drag the handle or use its VoiceOver adjustable action |
| Full feed | Covered by the feed | Scrollable existing Feed; collapse to access filters | Visible | Drag the handle down or use its VoiceOver adjustable action; no Map pill |
| Map / peek | Maximum visible area | Always-visible grab handle and count | Visible | Drag the handle up or use its VoiceOver adjustable action |
| Activity detail | Context visible where practical | Person-first detail layered over selected item | According to parent shell | Close returns to identical query, card position and camera |
| Search / form | Existing navigation/form surface | Keyboard-safe | Appropriate to destination | Cancel preserves Live state |

“Live” is the accepted tab name. It does **not** mean the person is currently there. Pins and cards show the actual activity time, such as “4h ago” or “Yesterday,” not “here now.” **Map** was the label proposed for the unimplemented floating escape pill. Do not add a redundant Live title or the subtitles “place memories” or “your people” above the map. The current drawer moves by direct handle drag or its VoiceOver adjustable action; no separate drawer arrow or count-tap button is implemented.

Initial camera framing responds to the density of authorized loaded activity: keep a dense network local and widen for a sparse one without changing audience or claiming nearby presence. Framing is presentation only; after the user pans, new pages must not repeatedly recenter it. The initial drawer is half height at every text size; accessible controls stack as needed and the handle can expand the list. On smaller phones, the map/drawer ratio responds to usable height rather than fixed screenshot geometry. The handle's VoiceOver adjustable action is the implemented alternative to dragging. Verify that focus never remains on hidden map controls in full-feed mode.

### One query, one result set

Within Live, the drawer and pins must derive from the same authorized loaded projection. Toggling presentation does not refetch with different defaults. A map cannot quietly show the first page as if it represents every result in the area. This parity contract does not replace the existing Profile/Your Map projection or couple its state to Feed.

The integrated store uses the typed Live repository query, resetting its cursor when committed filters change and fencing late account/query responses. The additive Live RPC remains an undeployed draft; hosted verification is required before enabling ordinary accounts. Pins correspond to loaded geocoded results. The visible drawer count is **“N updates shown”**, with **“N loaded updates”** as its accessibility label; it counts matching loaded activity records, which may be grouped into fewer cards or pins. Feed's **Load more** remains available in the expanded drawer and updates the shared loaded projection; the collapsed peek does not expose that button. No exact total is displayed unless the server supplies a count for that exact query. Items without eligible coordinates remain in their existing Feed card position and are excluded from pins; do not redesign or reorder the Recent cards into a new group. Later bounded spatial paging may improve coverage, but must preserve visible parity and honest counts.

The selected activity remains selected while changing presentation. The current client filter reprojects loaded data and clears selection if excluded. The server-query integration resets its cursor on committed semantic filter changes; it never leaves a private or out-of-scope detail visible. In-flight requests are cancelled or discarded using a query/account generation key. Existing Your Map Snapshot and full history remain independent of Feed pagination.

### Scope controls — integrated query and pending database verification

The current compact controls show **Following · Nearby**. Following removes the radius constraint; an independently drawn boundary remains until explicitly cleared. Nearby opens staged controls for a public `HomeMetro` city center and starts at **5 km**, with **25 km** available only through explicit selection. The profile home metro is shown as the initial selected city when available; Apply is required, and this does not change the account's home city or request device location. The radius circle and loaded results use that committed center; panning does not move it. **D2/D3 are explicitly accepted product decisions.** The complete query is integrated in native source, while its SQL is packaged; deployment and execution remain outstanding. Current device-location centering is not implemented; selected-city centers work. Separately eligible discovery remains distinct work. No Your places scope is added. Profile and Live retain independent camera, lens and selection state.

| Preset | Audience | Geography | Default time / result kind |
|---|---|---|---|
| Following | Viewer plus currently authorized followed people; mutual-only refinement available | Everywhere | Past 7 days, activity records |
| Nearby | The same permitted people; separately eligible public event/place discovery remains future work | Implemented: 5 km around an explicitly selected public city center, expandable to 25 km. Granted-location centering remains pending | Past 7 days, activity records; future discovery modules separately labelled |
| A person's map — existing Profile route | Only records this viewer can access for that person | Their visible places | Full existing member-map experience, not a new Feed preset or owner scope |

Default home is **Following**, with local framing if relevant activity exists. When a user chooses Nearby, widening from 5 km to 25 km is offered explicitly. Distant activity is offered as **See Following everywhere**, never silently called nearby. The existing Feed audience selection retains its current semantics; a person refinement narrows authorized content only.

### Filters

Current controls expose the existing Feed audience through `store.selectFeedAudience`, Everything/Check-ins/Wannas, **24 hours/7 days/30 days/All activity**, city/radius, categories and selected people. Category/person options come only from authorized loaded activity, before local refinements; they do not enumerate a new directory or private taxonomy. The large scrollable filter sheet stages these fields and removal of a drawn area until **Apply**; **Cancel** discards edits. Applying an audience change retains the existing Feed refresh behavior. The active count and drawer summary describe committed filters. Time bounds stay fixed during pagination and tab/detail return; Apply or explicit pull-to-refresh advances them. Native query/store integration and the full SQL predicates and cursor binding are implemented. SQL is packaged; deployment and execution remain outstanding; hosted completeness is unverified.

The RPC draft accepts time, type, polygon, radius, category and selected-person parameters and applies them before the page limit. Events/Plans are admitted only when corresponding data is available. No owner-lens controls are being moved from Your Map. Your Map retains all current facets; its controls remain independent.

Collection updates remain included in All activity; a separate collection-only filter is proposed and is not currently implemented. Owner and member Your Map/Patterns retain their existing **All time**, **This month** and **This year** calendar ranges and session-only saved lenses; Feed's rolling windows do not replace or expand Profile controls by default. The existing Profile Map/Patterns switch carries the same person and lens. No direct Profile → Patterns shortcut is introduced. Member Patterns remains available only over viewer-authorized records and never uses owner totals. Durable cross-device lens storage is not implicitly promised.

**Reset filters** stages Following everywhere, Everything, Past 7 days, no category/person refinement and removal of the drawn area while retaining the selected audience; it takes effect only on Apply. Drawing has its own draft/Apply/Cancel interaction and intersects a committed radius when both are active. Contradictory filters produce a recoverable loaded-results empty state with existing pagination. The drawer now exposes a concise committed summary and accessible value. This Feed interaction does not change the existing Your Map filter sheet as a side effect.

The old prototype used local search. The integration reuses current unified search, with explicit submitted search and the existing parser/fallback behavior. A query containing a city does not silently discard a manually drawn area: ask the user to use the searched place or keep the current area.

### Ordering and content types

- **Recent activity remains the existing Feed experience exactly:** reuse its cards, layout, display grouping, list badges and Like/Comment/Save/Share/place/profile actions. Keep the existing **Invite people to Astir → People worth following → Activity** order, including current loading, retry, empty, refresh and pagination behavior. Filtering may select records but must not redesign the cards. Check-in time comes from the visit, not upload/import/edit time; repeats retain engagement IDs.
- Upcoming: separately labelled and ordered by suggested/start time, outside historical activity. The integrated invitation slice uses a compact entry and separate sheet. An undated Wanna stays a Wanna until the user makes a plan. Never insert tomorrow's plan among past check-ins with an ambiguous relative time.
- Pins expose the loaded activities at each eligible place. The selected pin wins overlap, then newest eligible item; overlapping items have a reachable list/chooser. No inference of relationship strength is necessary for v1.
- Collection updates remain a supported activity type in Following. Existing `list_created` records are list-only when they lack a place; `list_item_added` uses its accessible place coordinate when present. Display grouping retains every underlying engagement identity, and an overlapping-pin chooser makes each item reachable. Collection updates are enabled in the default activity feed; independent filtering remains proposed; they do not become extra places in owner history.
- No popularity leaderboard, fabricated live presence, or global stranger activity.

| Current Feed kind | New representation | Identity / geography |
|---|---|---|
| `place_been` | Check-in | Original event and visit IDs; occurrence time; pin when place is accessible/geocoded |
| `place_want_to_go` | Wanna | Original event/Wanna IDs; no invented plan date; pin when geocoded |
| `place_saved` | Existing legacy Been/Wanna ticket presentation | Preserve original event identity and existing `resolvedTicketKind` status classification; include in All and the matching Check-ins/Wannas filter; do not create a new visit |
| `list_created` | Collection created | Original list/event IDs; list-only if no single eligible coordinate |
| `list_item_added` | Added to a collection | Original event/list/place IDs; eligible place pin or list-only fallback |

Existing grouped cards retain list badges, destinations, distinct visits and per-event engagement IDs. Grouping is presentation, not deletion or a new authoritative activity identity.

## 5. Drawing an area

Reusing area drawing from the Profile map is accepted. The working interaction is freehand selection with explicit **Apply/Cancel**, retaining the committed area for the account session. No durable or cross-device filter persistence is promised.

The drawing reference is the interaction concept: Zillow's [official draw-your-own-search description](https://www.zillow.com/news/new-draw-your-own-search-on-zillow-com/) describes choosing Draw and tracing an area with a finger, alongside filtered map/list results; Zillow's [current Rentals App Store listing](https://apps.apple.com/us/app/zillow-rentals/id538946076) also lists custom map boundaries. These sources do not establish the exact current iOS Apply or multiple-shape controls. Astir uses the drawing contract above; no exact Zillow UI parity is claimed.

1. **Draw area** enters a visible drawing mode. Pause normal map pan only while drawing; keep Cancel reachable and prevent the drawer from hiding the drawing controls.
2. The working default traces a freehand boundary through the real map projection, then previews it. Provide a non-drawing alternative such as **Use visible area** with the same explicit confirmation.
3. **Apply** commits the draft; **Cancel** restores the previous committed area and camera. **Clear area** removes only geography. Do not issue a server request on every pointer update.
4. Panning after Apply moves the camera without changing the committed area or audience. Retaining an area on tab/detail return is the session-only working default; account change clears it. Relaunch persistence is not approved.
5. Drawing never creates a list or relocates Snapshot, lenses, sharing, Patterns or history from Profile.

Validate boundary closure, invalid/degenerate shapes, map projection, date line, camera rotation, gesture cancellation and accessible alternatives. No coordinates, vertices or raw search phrase enter analytics. The existing circle demo is historical prototype evidence, not the current geometry decision.

## 6. End-to-end journeys

### J1 — Existing user finds their map

**Current implementation:** a once-per-account/version card offers **Show me** and **Not now**. Returning-user copy is “Your Feed now has a map”; eligible first visits receive “Welcome to Live.” Show me opens a six-step optional guide, also available from Settings → **What's changed** while Live is enabled. The guide explains the map/feed, drawing, unchanged activity cards, search/people, Add and the retained Profile Your Map. It is a readable guide, not an implemented anchored spotlight tour.

The first ordinary entry after activation opens Live. The card says **“Explore your people's activity in the Feed or on its map. Your Map is still in Profile.”** There is no forced tour or forced save. Profile retains its current Your Map preview/Explore entry and full destination throughout the transition. In-context highlighting of the map/feed control and direct drawer drag remains part of the fuller orientation target.

The card appears only once per account and experience version after actually rendering. Dismissing it persists. It does not interrupt a deep link, notification, editor, pending invite or incomplete authentication. Settings provides **What's changed** for replay. Users retain existing saves, lists, visibility, following, calendar, streaks and current drafts.

The root gates teaching on the active surface, validated account and existing route/modal/save blockers. For a pending old checkpoint, the integrated migration store archives the original before removing its active legacy slot and offers **Continue / Not now**. Settings → **What's changed** retains the continuation. Guide Next/Done acknowledges only represented semantics and advances existing progress without rewinding it. Opening or cancelling an actual Add, save, import or invitation flow never counts as completing that action. An explicit **Dismiss this old tutorial step** resolves only its reminder; saved drafts, permissions and invitations stay unchanged.

Recovery uses the existing ordinary destinations after registered modal dismissal and rechecks account/record identity. Valid full save drafts retain their fields and use existing commit evidence before reopening; a proven committed save is confirmed rather than submitted again. Contacts retain selection and existing permission decisions; device-guide acknowledgment completes only that lesson. Captured accounts retain the recovery bridge if Live is disabled, so their archives do not enter the old coordinator's forced-retirement path. Archive-before-clear is logical UserDefaults write ordering, not a claim of filesystem crash durability.

Historical payload limits are explicit: a save checkpoint without a valid full form opens Add with the previous place name when available, without reconstructing date, note or photos. List/detail/editor checkpoints without a list ID open Lists. A missing or inaccessible saved place opens Profile with an explanation. Those handoffs do not claim exact restoration or action success, and the archived reminder remains available until resolved or explicitly dismissed.

Fresh first visits now pass an explicit orientation context to the optional guide. Next/Done records only the map/feed teaching semantics represented by each page and advances existing progress contiguously, without rewinding it. Partial or skipped teaching remains incomplete; ordinary Settings/full-guide replay, Not now and Close write no semantic progress. Each acknowledgement requires the original account to remain authenticated and current and refuses any active or unreadable checkpoint/recovery record. It creates no synthetic checkpoint and completes no save, import, invitation or device lesson. Never rerun a native permission request or mark onboarding finished merely because its tab disappeared.

### J2 — Activity becomes a reason to connect

Open a pin or card → person, action, timestamp, place and shared context → existing Like/Comment/Save actions → **Reply privately** for an eligible mutual friend. The composer quotes only content the sender may currently access and explicitly names the recipient. Send requires an explicit tap. Production send must use the private-message repository and truthful pending/sent/failed states. The older prototype’s local Demo reply is not delivery evidence.

The integrated client uses `PrivateMessageRepository`, memory-only inbox/thread state and an account-fenced ephemeral transport. It preserves a stable client ID for unconfirmed retries, displays Sending/Not confirmed/Sent, and does not claim delivered/read. Private content has replay masking in source; release evidence must include actual replay and two-account hosted checks. No durable offline outbox, message push delivery or completed message deletion/retention policy is claimed.

D6/D7 approve production private messaging with **mutual friends only** as the baseline. Existing comments remain available to their existing authorized audience. Creation, reads and sends must enforce eligibility, blocking and source access, with retry/idempotency and privacy rules validated before internal activation. The first rollout requires explicit server-side account enablement for both participants; device/global enablement alone is insufficient. Broader availability additionally requires message reporting and approved soft-delete retention/export rules. Message push delivery is not part of this initial slice. Broader message requests are outside this baseline. An existing activity comment cannot be relabelled a private reply.

### J3 — A Wanna becomes a plan

Open an own Wanna → **Make a plan** → choose date/time and an eligible person, optional note → review recipient and deliberately shared details → create invitation → explicit share/send action → return with the original Wanna intact. Creating a plan is not a check-in, RSVP, message delivery or acceptance. A later cancellation never deletes the original saved place.

A friend’s Wanna keeps that actor as the intended partner. If its direct cached Common Ground match is absent, resolve authorized shared-place evidence before offering the existing invitation; viewer Been plus friend Wanna must remain supported. If no eligible shared save exists, offer explicit recovery through the existing place/save flow rather than an invitation that cannot succeed.

Reuse the actual existing In Common/place-plan invitation composer and repository; do not simulate success or build a parallel planning system. It already creates a deliberate shareable invitation and has a received-invitations surface. Multi-person RSVP states, private chat threads, itinerary stops and rescheduling are extensions, not capabilities to assume it already has. The earlier prototype’s temporary plan state is historical evidence only; the integration must use the existing invitation result and inbox.

**D10 integrated slice:** when the account's authorized inbox contains invitations whose suggested time is now or later, Live shows a 44-point **Upcoming invitations** entry with the matching loaded count. Its separate scrollable sheet shows at most three invitations, earliest suggested date first, plus **View inbox**. The existing RPC returns up to the latest 100 received invitations by creation time; this is not a complete schedule, sent-plan list or RSVP/attendance record. Undated invitations remain in the ordinary inbox and are never inferred from display copy or creation time. The sheet is separate from Recent activity and its pin/count projection. Opening a row waits for physical sheet dismissal, then reuses the existing recipient invitation screen and its authorized read transition. Account/reset clears pending presentation; failed refreshes suppress the projection.

### J4 — Events appear naturally

The current Events entry opens the existing eligible interest screen; it has no populated Event inventory or Events type filter. The separate Upcoming invitations slice above reuses received plan data and does not supply Event discovery. The accepted later journey shows eligible upcoming events as a labelled module and filter; detail opens the existing canonical event/interest destination. No Events tab is required. The persistent Live Events entry, search and future canonical event links provide access even when the recent feed changes. This proposal does not add an upcoming-commitments section to Profile. If the system only supports interest registration, say that; do not display ticket availability or an RSVP success that cannot exist yet.

### J5 — Capture and come back

Add → choose Check-in or Wanna → existing place resolution/details/privacy → successful local save → return to the originating Live context. If the result fits the query, insert with a stable identity and show its sync state. If it does not, confirm the save and offer **View your place**; do not silently loosen filters. Queue retries do not duplicate the save, activity, plan or analytics success.

### J6 — Personal history and Patterns

Open Profile → the existing Your Map preview/Explore → full Your Map. Keep its Map/Patterns switch, complete owner history, advanced filters, session lenses, Snapshot, share and place-detail return. Back returns within Profile as it does today. Member profiles retain their corresponding viewer-authorized map/Patterns route. The Profile calendar keeps its existing day/history destination; it is not redirected through Feed. Profile identity/social, save streak, recent activity and calendar remain in their current order.

Only drawing is shared with Live. Opening or filtering Live must not change the Profile lens, camera, selection or history route. No invented trend line or global comparison is introduced into Patterns.

### J7 — Sparse, remote and offline

No nearby activity: **“No recent activity in this area.”** Offer expand radius, Following everywhere and Add; do not imply friends are nearby. No follows: own saves, Find people, and available public place/event discovery are individually labelled. No location: choose a city or view Following; never require location to use the product. Offline: preserve eligible account-scoped cached results with **Saved earlier** / last refreshed wording; no fresh-presence claim. A locally initiated block, logout/account change, or received access-revocation signal clears affected data and open detail immediately. An offline client cannot detect an unseen remote privacy change.

Approved Live offline policy: other-person content in the new Live cache is displayable for at most 15 minutes after its last successful access validation and is then hidden behind **Reconnect to refresh your people**. Owner content remains available under the existing authenticated offline policy. Foreground reevaluates expiry, and expired social content reappears only after a successful authorized response; a push is only an invalidation hint, not authorization. This bound does not promise zero exposure between a remote change and detection; it makes that window explicit. The lease uses session-only, per-row monotonic authorized-response receipts captured before media work. Device suspension counts toward the 15 minutes; wall-clock changes and cached payload timestamps cannot renew or extend authorization. Paging renews only rows its response authorizes. Profile history and the shared cache retain their existing policy.

## 7. Required state coverage

| Situation | User-facing behavior | Recovery / invariants |
|---|---|---|
| Initial load | Stable map/frame and skeleton drawer | No fake activity pins; cancel stale requests |
| Next-page load/failure | Existing results stay; inline progress/retry | No scroll reset or duplicate rows |
| Zero results | Explain active area/time/person constraints | Clear one constraint; keep current scope |
| Sparse remote network | Name geography honestly | User chooses broader Following; no forced globe zoom |
| Location denied/approximate | Choose area; coarse-location wording | No repeated prompt; device location never published |
| Stale cached data | Label cache freshness | Refresh action; no “now” status |
| Deleted/private/blocked item | Clear card/pin/detail | Neutral unavailable state and return |
| Ungeocoded record | Preserve its existing Feed card position; no map pin | Include it in matching loaded update count; do not alter the existing card solely for Live |
| Long names/content | Wrap or predictable truncation | No collision with actions; detail can reveal full text |
| Keyboard and composer | Scrollable content, visible Send/Cancel | Preserve draft when interrupted; account-scoped reset |
| Dynamic Type / VoiceOver | Expanded list as needed, meaningful reading order | Button alternatives for map/drawer/drawing gestures |
| Reduce Motion | Instant or short fade transitions | No animated fly across continents |
| New activity while reading | **New activity** affordance | Do not jump the feed or move selected pin automatically |
| Flag disabled / older app | Old shell and compatible data | New navigation has no destructive data migration |

## 8. Visual and interaction direction

Use the existing adaptive ink/paper palette and Signal coral for actions and selected state. Major headings use editorial serif; body and controls use Avenir Next with Dynamic Type. Independent floating header controls retain localized glass/material backgrounds; do not add a large shared blur slab. Cards are content objects, not decorative dashboard panels.

Pins must communicate **who, what, when** with accessible labels, status shape/icon and text. Use bounded-size avatars or initials and short recency labels. Wanna pins use a muted **outlined bookmark** with a distinct silhouette from Check-in pins. They remain legible and actionable; muted never means disabled. Selection still has a visible accent/focus treatment. Keep Apple map attribution unobscured. Prefer a muted standard map before changing providers.

Touch targets are at least 44 × 44 pt. At accessibility text sizes, toolbar/drawing controls stack and the drawer still starts half expanded. The drawer exposes a VoiceOver adjustable action and drawing offers Use visible area; neither requires a precision gesture. Map exploration is possible without precision gestures. Light/dark, keyboard, safe areas, a smaller phone and a current larger phone are review requirements, not optional polish.

## 9. Adoption and release strategy

1. **Accepted direction:** implement locked decisions below; use freehand Apply/Cancel, session-retained drawing and the approved 15-minute Live display lease without reopening tab or Profile scope.
2. **Foundation:** introduce typed routes/query contracts and reuse existing projections without changing the visible shell.
3. **Internal flagged Live:** enable the new shell through the shared registered feature-flag platform. Remote/default/device override resolution remains account-scoped and fixed for the full launch.
4. **Small invited cohort:** enable only after real-map, privacy, route and offline proofs. Observe migration comprehension and repeat use; preserve a next-launch rollback.
5. **Expand:** widen only after acceptance and monitoring gates. Do not automatically turn a pilot into a full release because time elapsed.
6. **Connection implementation:** production mutual-only messaging and existing plan-invitation reuse are approved work; activate only after real access/delivery tests. Richer plan lifecycles and Event integration retain their separate contracts.

No destructive migration is needed merely to merge navigation. Do not convert every Wanna to a plan, rewrite visit dates, create follow edges, republish Self content or delete old snapshot lists. A server flag rollback affects the next full launch, not a currently active gesture; the old compatible shell must remain during rollout.

### Proposed success criteria

These are acceptance targets, not measured baselines or statistically proven outcomes.

- In moderated review, at least 4 of 5 existing testers find the unchanged Profile → Your Map route, an old save, Lists and Add without verbal instruction; at least 4 correctly explain that activity is not continuous location. Only drawing is reused in Live; no owner shortcut substitutes for Profile continuity.
- At least 4 of 5 testers move between Feed pins and the corresponding list item, apply/clear an area, and switch between Feed and Profile without changing either surface's prior context.
- Every automated migration/privacy/deep-link acceptance case passes. Any unauthorized visibility or lost save is a release blocker.
- Pilot compares matched observation windows for successful core actions and connection actions per active user, plus day-seven return for matured cohorts. Report actual numerator/denominator; a tiny sample is directional, not proof of uplift.
- No material regression against the measured current app in save success, launch/read latency, crash-free sessions or route completion. Collect baseline before choosing numeric alert thresholds; initial performance budgets are in the engineering plan.

Keep existing success events. Proposed UI events only describe coarse surface, scope, drawer state and outcomes; do not log messages, searches, place notes, coordinates, actor/recipient IDs or filters containing private content. Private-reply composers, conversations and quoted source content must be excluded from readable replay before activation; the current app's readable replay configuration does not establish permission for new private messages. Monetization remains unchanged.

## 10. Decision register

| ID | Status and current contract | Remaining work / boundary |
|---|---|---|
| D1 | **Accepted:** Live / Lists / Profile; contextual Add, search, notifications and conversations | Root/route integration and validation; no redundant Live/place memories/your people header |
| D2 | **Accepted:** Following/Nearby over independent query fields; local city/radius, category/person and time controls are integrated without expanding visibility | Hosted query verification is required. Current device-location centering is not implemented; selected-city centers work; eligible discovery remains distinct work |
| D3 | **Accepted:** Following defaults to past 7 days; local Nearby starts at 5 km around the chosen public city center, with explicit 25 km expansion; full personal history stays in Your Map | Local fixed time bounds advance on Apply/explicit refresh. Server radius support is drafted and wired; hosted verification and granted-location centering remain pending; density framing is separate and no owner-history preset is added |
| D4 | **Drawing reuse accepted.** Freehand + explicit Apply/Cancel and session-only retention are the working contract | Keep draft/commit/cancel and non-drawing alternatives; no durable persistence claim |
| D5 | **Accepted:** only area drawing reused from Your Map | All other Your Map tools and Profile structure stay where they are |
| D6 | **Accepted:** proceed with production connection work, including private messaging and existing invitations | No simulated delivery or invented planning backend; validate actual integration |
| D7 | **Accepted:** production private messaging starts mutual-only | Server eligibility, block/report, replay privacy, retry/deletion/delivery proofs; no broader requests |
| D8 | Retain MapKit and prove the integrated native drawer | No provider switch; direct drawer drag replaces the extra arrow while accessible actions remain |
| D9 | **Accepted:** once/account/version card, optional guide, explicit fresh-orientation semantic acknowledgements, read-only ordinary replay and archived-checkpoint recovery are integrated | Recovery and rollback must preserve ordinary drafts, permissions and explicit routes. Historical missing payloads retain explicit fallback destinations |
| D10 | **Accepted:** separately labelled Upcoming plans/events; Events discovery within Live. Bounded Upcoming invitations entry/sheet is integrated | Latest-100 received scope/max-three display. Events retains its teaser/interest contract; no complete schedule, sent-plan or RSVP/attendance claim |
| D11 | **Accepted:** 15-minute, session-only display lease for other people’s Live rows | Use per-row monotonic authorized-response receipts, starting before media work; owner content and Profile/shared-cache history remain unchanged |

Acceptance of product direction is not a claim of completed implementation, hosted validation or release. Existing Profile/shared-cache policy remains authoritative; D11 only narrows Live display.

## 11. Acceptance checklist / traceability

| Requirement | Acceptance | Evidence to collect |
|---|---|---|
| R01 unified surface | Same IDs, query and selection in map/list | Query unit tests + native interaction |
| R02 drawer | Live root half/full/peek; retained drawer and detail/modal contracts. Current tabs stay visible at all detents; escape uses handle drag/VoiceOver adjustment | UI tests and small/large phone captures; explicitly review the prior hidden-peek-tabs/Map-pill target gap |
| R03 chronology | Historical import does not become recent; repeats retain IDs | Feed/date and grouping regressions |
| R04 scope | Following/mutual/owner/other-user access never broadens | RPC/RLS smoke matrix + cache tests |
| R05 geography | Draw/apply/cancel/clear; pan alone does not refilter | Projection tests + native gestures |
| R06 personal history | Current Profile section order, full owner/member Your Map, Map/Patterns, calendar/history, filters and independent context remain; drawing reuse never mutates Profile context | Existing Profile/YourMap tests + before/after journey and screenshots + selected-feature review |
| R07 snapshots | Existing Your Map Snapshot action and lists retained; no Live Snapshot added | MapSnapshotListTests + existing Your Map UI |
| R08 routes | Existing place/activity/list/plan/widget/import/calendar routes resolve; future event links are separately integrated | Route table integration + cold/warm tests |
| R09 migration | Once/account/version, skip/replay, never intercept intent | State unit tests + account switch |
| R10 capture | Save returns correctly even outside query; retries idempotent | Store tests + offline/retry UI |
| R11 sparse | No forced nearby claim/empty airport trap | Dense/remote/empty fixtures |
| R12 plans | Wanna survives invitation/cancel; explicit sharing | Plan repository + end-to-end invitation |
| R13 replies | Correct recipient, authorization and no false delivery | Production message access/retry/privacy tests + real integration; no demo delivery evidence |
| R14 events | Eligibility and canonical lifecycle remain intact | Events integration contract |
| R15 accessibility | Full task possible with VO, AX type and no drag | Manual native a11y run |
| R16 privacy changes | Block/unfollow/logout clears stale cards and caches | Hosted + account-switch integration |
| R17 performance | Budgets measured against current baseline | Device Instruments / network profiles |
| R18 rollout | Registered flag, explicit Off, restart and rollback | FeatureFlag tests + rollback rehearsal |
| R19 analytics | Real success only, allowlisted content-free events | analytics:check + privacy tests |
| R20 complete review | Plan, prototype, gaps and decisions agree | Cross-review and human sign-off |

Earlier prototype evidence does not validate the current integrated app. Current native, hosted access, messaging, server paging, rollout and Events evidence must be recorded separately as it is actually collected; no completion is implied here.
