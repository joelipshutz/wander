# Astir Live — product specification for review

REC-636 · October 9, 2026 · **Proposal, not production approval**

## 1. The change we are making

Astir should answer **“What are my people up to, and what could we do together?”** on its first screen. The proposed home combines an activity map and a draggable feed. A check-in, Wanna, plan, or event gives someone a concrete reason to connect. Saved places remain useful long after that activity is recent.

This is a change to the Feed and primary-tab journey: entry, activity discovery, capture, connection, and return. The proposed Live destination combines the current Map-tab and Feed jobs. Profile keeps its existing identity/social header, save streak, recent activity, full Your Map experience and calendar in their current order. Selected Your Map features may be reused or moved into Feed only after a feature-by-feature review; moving or removing the full Your Map experience is outside this proposal.

The review package proposes a destination experience and a staged implementation. It does not authorize a public people directory, continuous location sharing, automatic invitations, paid access, or changes to existing visibility. The production app continues to use its current navigation until separate implementation is approved and validated.

### Inputs and their authority

- The supplied [October 8 strategy discussion](https://docs.google.com/document/d/1sZ91bbrizaCViuXEkwppY7MhOwIb4x3EZOK5I9IR8uM/edit?tab=t.0) and appended earlier Live discussion establish the activity-first direction, map/drawer interaction, nearby/following perspectives, future plans, contextual replies, and the need to handle sparse networks. This specification contains product conclusions, not the private transcript or unrelated business discussion.
- `docs/product/2026-09-24-astir-live-discussion.md` preserves the original interaction proposal. Its unresolved questions are answered here as **recommendations to review**, not retroactively recorded approvals.
- The current source and tests establish compatibility requirements. The initial source audit used `2800caaba`; this review branch is based on fetched integration head `d9f827353648bab91a17187721b5ea41e65e1a42`. An implementation branch must reconcile later drift.
- `DESIGN.md` supplies the current Astir visual override. Its older tab descriptions are not the current shell contract.
- `docs/designs/astir-events/engineering-handoff.md` remains the authority for the separate Events lifecycle work. Integrating its discovery does not approve its outstanding choices.

## 2. Outcomes and non-goals

### Outcomes

1. A returning user can understand recent activity and move between Feed's map and list while finding personal history through the familiar Profile → Your Map route.
2. Moving between list and map does not change the subject, filters, selection, or content unexpectedly.
3. Existing users recognize their saves, people, lists, activity, and plans after the redesign. Profile's hierarchy and complete Your Map route remain intact. No content changes audience because its navigation moved.
4. A Wanna becomes an invitation to make a plan; an activity can become a conversation in a later phase with a real messaging contract.
5. A user with no nearby network gets an honest, useful next action.

### Not in this delivery

This delivery is a specification, engineering plan and fixture-based SwiftUI prototype. Production schema, auth, hosted resources, payments, moderation operations, real message delivery and TestFlight distribution are separate implementation work. Walking routes and ongoing location tracking are excluded from the first production slice. A provider switch is not required to validate the experience.

The complete Events booking/guest/admission/recap system is not re-specified here. An event card opens the canonical event experience when available; it never treats an RSVP as attendance or a check-in.

## 3. Information architecture

### Recommended navigation

**Live · Lists · Profile** are the proposed stable bottom destinations. Live is the working name for the redesigned Feed with its map/drawer interaction. Add stays a prominent action in its header. Search is a Live entry and the existing unified search flow remains available. Notifications remain accessible; a future Conversations entry is separate from notifications even if both sit in the same header area. This major Feed/tab change does not redesign Profile or turn its Your Map entry into a tab switch.

The shell must not grow or shrink based on city. Eligible events appear in Live and in a persistent Events filter/entry. An empty event inventory does not create an empty tab. Lists remains a first-class destination because ownership, collaborators, invitations and organization are distinct tasks that a chronological feed does not replace. The root tab-visibility rule applies to Live's three drawer states; full-screen detail, settings, editors and system modals keep their destination-specific navigation contracts.

| Alternative | Benefit | Cost | Review recommendation |
|---|---|---|---|
| Live / Lists / Profile; contextual Add and Inbox | Simplifies the primary journey while preserving collection and identity jobs | Existing Map and Events muscle memory needs a bridge | **Preferred** for the prototype and first implementation |
| Live / Plans / Lists / Profile | Makes repeat planning easier | Adds an underfilled destination before plans are a frequent habit | Revisit only after planning usage supports it |
| Keep Map and Feed, share controls | Lowest initial navigation disruption | Keeps the split mental model and two places to find the same activity | Useful implementation bridge, not the target experience |

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
| Your Map Snapshot | Existing owner Snapshot action and persistent Lists | A Feed overflow equivalent is a candidate for reuse, not an approved removal or relocation of the current action |
| Your Map share | Existing map card / profile link | A Feed equivalent may be reviewed separately; do not claim a shared filter state persists in the link |
| Profile identity/social, streak, activity and calendar | Existing Profile sections and order | Preserve edit/settings, social graph, activity/history, dates and compact private progress |
| People search, graph lists, invites | Search / Profile / contextual activity attribution | Preserve follow, mutual, block and contact permission behavior |
| Place, activity, list, plan and event deep links | Canonical destination inside the new shell | Explicit intent outranks default Live landing and migration teaching |

### Selective Your Map feature inventory — D5

Continuity is the default. The entries below identify candidates for Feed reuse, not an instruction to move the full screen. Component/data-projection reuse may happen underneath both experiences if it preserves each route and its state. Any individual relocation needs an explicit review decision naming the feature, its new entry and the effect on the existing entry; an unresolved decision leaves the current Profile experience available.

| Existing feature | Profile / Your Map baseline | Feed candidate and review test |
|---|---|---|
| Canonical owned places and mixed Check-in/Wanna history | Keep the full Your Map projection and detail history | Optional **Your places** scope; verify it helps activity browsing without replacing Profile history or truncating old places |
| Advanced lens and saved lenses | Keep time/status/category/city/country/tags/rating/repeats and session-only lenses | Reuse only facets useful to the selected Feed scope; do not silently alter a Profile lens |
| Patterns | Keep inside owner/member Your Map with authorized data | No move or new Feed analytics destination proposed; review a specific useful insight separately |
| Snapshot list creation | Keep the current owner Snapshot flow and saved lists | Candidate **Save visible places as list** in Feed overflow; prove complete preview/image/membership parity before adding it |
| Map sharing | Keep the current filtered card/profile link | Candidate share action for a reviewed Feed scope; label the link truthfully |
| Native map, pins and place-card components | Keep current camera, selection and back behavior | Reuse tested implementation pieces while maintaining independent Profile and Feed contexts |

## 4. The Live screen

### Layout and states

The map stays mounted underneath one persistent drawer. Native sheet behavior is the first engineering spike; if tab placement cannot meet the contract, use a contained sheet controller before inventing a gesture system.

| State | Map | Drawer | Tab bar | Available escape |
|---|---|---|---|---|
| Half / landing | Visible above the drawer | Heading and first activity cards | Visible | Drag or labelled Expand/Show map actions |
| Full feed | Covered by the feed | Scrollable list and filters | Visible | Floating **Map** pill lowers drawer to peek |
| Map / peek | Maximum visible area | Always-visible grab handle and count | Hidden | Tap count/Expand results restores half and tabs |
| Activity detail | Context visible where practical | Person-first detail layered over selected item | According to parent shell | Close returns to identical query, card position and camera |
| Search / form | Existing navigation/form surface | Keyboard-safe | Appropriate to destination | Cancel preserves Live state |

“Live” is a working destination name. It does **not** mean the person is currently there. Pins and cards show the actual activity time, such as “4h ago” or “Yesterday,” not “here now.” The floating map button uses **Map** in the prototype to avoid suggesting location streaming; **Live Map** remains a copy decision.

The initial drawer is half height except for accessibility sizes that require an expanded, readable list. On smaller phones, the map/drawer ratio responds to usable height rather than fixed screenshot geometry. Tapping the count is an accessible alternative to dragging. Focus never remains on hidden map controls in full-feed mode.

### One query, one result set

Within Feed, the drawer and pins derive from the same authorized query result. Toggling presentation does not refetch with different defaults. A map cannot quietly show the first page as if it represents every result in the area. This parity contract does not replace the existing Profile/Your Map projection or couple its state to Feed.

The first Feed slice uses one paged canonical result set. Pins correspond to loaded geocoded results; the drawer explicitly says **“20 loaded”** while more pages exist. **Load more** works in both modes. No exact total is displayed unless the server supplies a count for that exact query. Items without eligible coordinates stay in a labelled **Not on map** group and are excluded from the pin count. Later bounded spatial paging may improve coverage, but must preserve visible parity and honest counts.

The selected activity remains selected while changing presentation. Changing a committed filter resets the pagination cursor and selection if excluded; it never leaves a private or out-of-scope detail visible. In-flight requests are cancelled or discarded using a query/account generation key. If D5 adds Save visible places as list to Feed, browsing pagination must not limit that operation: it uses the complete owned-place projection. The existing Your Map Snapshot flow remains available.

### Scope controls

The compact top chooser presents **Following · Nearby**, with **Your places** shown as a D5 candidate in the review prototype. These are understandable presets over independent audience/geography/time/type fields, not new visibility rules. A Feed owner scope does not replace the full Profile map; Profile and Feed retain independent camera, lens and selection state.

| Preset | Audience | Geography | Default time / result kind |
|---|---|---|---|
| Following | Viewer plus currently authorized followed people; mutual-only refinement available | Everywhere | Past 7 days, activity records |
| Nearby | The same permitted people, plus separately eligible public event/place discovery | Explicit area; initial 5 km around granted location or chosen city | Past 7 days, activity records; discovery modules separately labelled |
| Your places — D5 Feed candidate | Viewer only | Everywhere unless an area is explicitly applied | All time, unique saved places with visit history; existing Profile map remains |
| A person's map — existing Profile route | Only records this viewer can access for that person | Their visible places | Full existing member-map experience, not a new Feed preset or owner scope |

Default home is **Following**, with local framing if relevant activity exists. When a user chooses Nearby, widening from 5 km to 25 km is offered explicitly. Distant activity is offered as **See Following everywhere**, never silently called nearby. Choosing a profile owner/person scope resets incompatible audience filters and displays the scope visibly.

### Filters

The Feed filter sheet supports audience refinement (Following/Mutual friends/Only me), activity kind (Check-ins/Wannas/Events/Plans when available), time (24 hours/7 days/30 days/All time), category and selected people. The D5 Your places candidate can reuse selected owner facets from the existing map lens after review. Your Map retains all current facets regardless of the Feed selection. Advanced Feed facets can use progressive disclosure; this does not alter Profile's controls.

Collection updates is an additional activity-kind filter, enabled in All activity. Owner and member Your Map/Patterns retain their existing **All time**, **This month** and **This year** calendar ranges and session-only saved lenses; Feed's rolling windows do not replace or expand Profile controls by default. The existing Map/Patterns switch carries the same person and lens. No direct Profile → Patterns shortcut is introduced. Member Patterns remains available only over viewer-authorized records and never uses owner totals. Durable cross-device lens storage is not implicitly promised.

Feed filter changes are staged until **Apply**; Cancel restores the current query. The button shows active-filter count. A concise summary remains visible outside the sheet. **Reset** returns to the current preset defaults, not a global audience expansion. Contradictory filters produce a recoverable empty state. This new Feed interaction does not change the existing Your Map filter sheet as a side effect.

Search text is local in the prototype. Production reuses current unified search, with explicit submitted search and the existing parser/fallback behavior. A query containing a city does not silently discard a manually drawn area: ask the user to use the searched place or keep the current area.

### Ordering and content types

- Recent activity: descending occurrence time, stable ID tie-breaker. Check-in time comes from the visit, not upload/import/edit time. Repeat visits stay distinct; existing display grouping preserves their engagement IDs.
- Upcoming: a separately labelled section, ascending start time. An undated Wanna stays a Wanna until the user makes a plan. Never insert tomorrow's plan among past check-ins with an ambiguous relative time.
- Your places, if selected as a D5 Feed candidate: grouped by canonical place; status can include both Been and Wanna. Proposed default is most recently visited/saved; opening reveals individual history. This does not change Your Map's existing ordering or controls.
- Pins represent activities in activity mode, places in personal-history mode. Selected pin wins overlap, then newest eligible item; overlapping items have a reachable list/chooser. No inference of relationship strength is necessary for v1.
- Collection updates remain a supported activity type in Following. Existing `list_created` records are list-only when they lack a place; `list_item_added` uses its accessible place coordinate when present. Display grouping retains every underlying engagement identity, and an overlapping-pin chooser makes each item reachable. Collection updates are enabled in the default activity feed and can be filtered independently; they do not become extra places in owner history.
- No popularity leaderboard, fabricated live presence, or global stranger activity.

| Current Feed kind | New representation | Identity / geography |
|---|---|---|
| `place_been` | Check-in | Original event and visit IDs; occurrence time; pin when place is accessible/geocoded |
| `place_want_to_go` | Wanna | Original event/Wanna IDs; no invented plan date; pin when geocoded |
| `place_saved` | Saved place (legacy compatibility) | Preserve legacy identity/copy; do not relabel as a new visit; include in All activity |
| `list_created` | Collection created | Original list/event IDs; list-only if no single eligible coordinate |
| `list_item_added` | Added to a collection | Original event/list/place IDs; eligible place pin or list-only fallback |

Existing grouped cards retain list badges, destinations, distinct visits and per-event engagement IDs. Grouping is presentation, not deletion or a new authoritative activity identity.

## 5. Drawing an area

**Proposed interpretation:** a circle selection tool filters the map and drawer. The user has been asked to confirm whether this means geographic drawing or merely a circular map-view button. Until answered, this remains a prototype assumption.

1. Tap the circular **Draw area** control beside **Filters**. Enter map/peek mode with a clear drawing banner; normal pan gestures pause only during drawing.
2. Press a center and drag to an edge. Convert both points through the actual map projection; render a geographic circle, not a circle of screen pixels after camera changes.
3. Preview the bounded radius and result count if available. Prototype radius is bounded from 100 m to 25 km. Provide **Center here** and a radius picker for VoiceOver and people who cannot draw.
4. **Apply area** commits the circle; **Cancel** preserves the previous query and camera. Clear removes only the spatial constraint. While drawing, do not issue a server request on every drag frame.
5. Panning after Apply leaves the circle/query unchanged. With an unbounded query, **Search this area** explicitly commits the visible rectangle. Area filtering never changes who may see content.
6. If D5 selects an additional Feed action, owner-only overflow **Save visible places as list** preserves the existing snapshot universe: every canonical owned place in the complete filtered owner projection **and** the actual mounted viewport. The existing Snapshot action stays in Your Map. A committed Feed circle is one of those filters; membership is the intersection of lens/circle and viewport, never merely the loaded feed page. Panning changes this capture set while leaving the query/circle unchanged. Resolve the full owner projection before previewing its count. If that complete projection is unavailable, disable creation with a retryable loading/error state; never create a silently truncated list. Before confirmation, freeze the camera, committed query and complete capture membership for this operation, then open a dedicated snapshot preview using that camera/lens and set. If source deletion/access changes invalidate the set, refresh the preview and require confirmation again. Render every captured place in that preview and provide its full count/list; the image, preview list and saved membership must agree even when the browsing map had only one page loaded. Disable confirmation until both enumeration and rendering complete, or show a retryable error. Show the count and “Visible in this map area” before creation. Closing the preview restores the paged Live context unchanged. Drawing alone never creates a list. Saving an entire off-screen circle would be a separate future operation.

Map scale, projection, date line, invalid coordinates, overlapping pins, gesture cancellation and camera rotation belong in validation. No coordinates, polygon, radius center or raw search phrase enters analytics.

## 6. End-to-end journeys

### J1 — Existing user finds their map

The first ordinary entry after activation opens Live. A dismissible inline card says **“Your Feed now has a map.”** Supporting copy: **“Explore your people's activity in the Feed or on its map. Your Map is still in Profile.”** Actions: **Show me** and **Not now**. Show me highlights the map/feed control and activity scopes; it introduces a Your places Feed shortcut only if D5 selected it. There is no forced tour or forced save. Profile retains its current Your Map preview/Explore entry and full destination throughout the transition.

The card appears only once per account and experience version after actually rendering. Dismissing it persists. It does not interrupt a deep link, notification, editor, pending invite or incomplete authentication. Settings provides **What's changed** for replay. Users retain existing saves, lists, visibility, following, calendar, streaks and current drafts.

New users receive the revised in-context Live orientation after the existing identity/permission flow and optional founders welcome, not the returning-user migration card. Map overview steps map to the new half-drawer and scope controls; Feed takeover steps map to expanded Live and the same activity-card teaching. For an interrupted old walkthrough, map the first unfinished semantic step to its new equivalent, keep already completed steps complete, and never rerun a native permission request or mark onboarding finished merely because the tab disappeared. A pending explicit destination is completed first, with optional teaching deferred to the next ordinary Live entry. Feature rollback maps unfinished Live teaching back to its old semantic counterpart without a loop. Exact stored step IDs are resolved in the implementation task, with fixture migrations for every existing state.

### J2 — Activity becomes a reason to connect

Open a pin or card → person, action, timestamp, place and shared context → existing Like/Comment/Save actions → **Reply privately** in the full-journey prototype. The composer quotes only content the sender may currently access and explicitly names the recipient. Send requires an explicit tap. A simulated prototype reply becomes a local conversation marked Demo; it never claims delivery.

For production, existing comments remain in the first slice. Private replies are gated on recipient policy, requests/spam handling, blocking, reporting, delivery/error/retry, notification and deletion rules. The recommended initial eligibility is mutual friends only; expanding to followed strangers needs a separate decision. A public comment cannot be relabelled a private reply.

### J3 — A Wanna becomes a plan

Open an own Wanna → **Make a plan** → choose date/time and an eligible person, optional note → review recipient and deliberately shared details → create invitation → explicit share/send action → return with the original Wanna intact. Creating a plan is not a check-in, RSVP, message delivery or acceptance. A later cancellation never deletes the original saved place.

Reuse the existing In Common/place-plan invitation path where its semantics fit. It already creates a deliberate shareable invitation and has a received-invitations surface. Multi-person RSVP states, private chat threads, itinerary stops and rescheduling are extensions, not capabilities to assume it already has. Prototype plan results are temporary demo state.

### J4 — Events appear naturally

Live shows eligible upcoming events as a labelled module and filter; detail opens the existing canonical event/interest destination. No Events tab is required. The persistent Live Events entry, search and future canonical event links provide access even when the recent feed changes. This proposal does not add an upcoming-commitments section to Profile. If the system only supports interest registration, say that; do not display ticket availability or an RSVP success that cannot exist yet.

### J5 — Capture and come back

Add → choose Check-in or Wanna → existing place resolution/details/privacy → successful local save → return to the originating Live context. If the result fits the query, insert with a stable identity and show its sync state. If it does not, confirm the save and offer **View your place**; do not silently loosen filters. Queue retries do not duplicate the save, activity, plan or analytics success.

### J6 — Personal history and Patterns

Open Profile → the existing Your Map preview/Explore → full Your Map. Keep its Map/Patterns switch, complete owner history, advanced filters, session lenses, Snapshot, share and place-detail return. Back returns within Profile as it does today. Member profiles retain their corresponding viewer-authorized map/Patterns route. The Profile calendar keeps its existing day/history destination; it is not redirected through Feed. Profile identity/social, save streak, recent activity and calendar remain in their current order.

If D5 selects an owner-place scope or another feature for Feed, test it as an additional activity-browsing affordance with independent state. Opening or filtering it cannot change the stored Profile map lens, camera, selection or history route. Internal components and projections can be reused without merging these navigation contexts. No invented trend line or meaningless global comparison is introduced into Patterns.

### J7 — Sparse, remote and offline

No nearby activity: **“No recent activity in this area.”** Offer expand radius, Following everywhere and Add; do not imply friends are nearby. No follows: own saves, Find people, and available public place/event discovery are individually labelled. No location: choose a city or view Following; never require location to use the product. Offline: preserve eligible account-scoped cached results with **Saved earlier** / last refreshed wording; no fresh-presence claim. A locally initiated block, logout/account change, or received access-revocation signal clears affected data and open detail immediately. An offline client cannot detect an unseen remote privacy change.

Proposed Live offline policy for review: other-person content in the new Live cache is displayable for at most 15 minutes after its last successful access validation and is then hidden behind **Reconnect to refresh your people**. Owner content remains available under the existing authenticated offline policy. Reconnect/foreground triggers access revalidation before expired social content reappears; a push is only an invalidation hint, not authorization. This bound does not promise zero exposure between a remote change and detection; it makes that window explicit. D11 must be resolved before production implementation, including whether a separately reviewed shared-cache policy is needed; it does not silently change the existing Profile experience.

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
| Ungeocoded record | List-only, labelled Not on map | Count reflects mapped subset; resolve place where appropriate |
| Long names/content | Wrap or predictable truncation | No collision with actions; detail can reveal full text |
| Keyboard and composer | Scrollable content, visible Send/Cancel | Preserve draft when interrupted; account-scoped reset |
| Dynamic Type / VoiceOver | Expanded list as needed, meaningful reading order | Button alternatives for map/drawer/drawing gestures |
| Reduce Motion | Instant or short fade transitions | No animated fly across continents |
| New activity while reading | **New activity** affordance | Do not jump the feed or move selected pin automatically |
| Flag disabled / older app | Old shell and compatible data | New navigation has no destructive data migration |

## 8. Visual and interaction direction

Use the existing adaptive ink/paper palette and Signal coral for actions and selected state. Major headings use editorial serif; body and controls use Avenir Next with Dynamic Type. Independent floating header controls retain localized glass/material backgrounds; do not add a large shared blur slab. Cards are content objects, not decorative dashboard panels.

Pins must communicate **who, what, when** with accessible labels, status shape/icon and text. Use bounded-size avatars or initials and short recency labels. Own Wanna has an outlined/unfinished treatment that remains legible; it is not disabled or low-contrast. Keep Apple map attribution unobscured. Prefer a muted standard map before changing providers.

Touch targets are at least 44 × 44 pt. At accessibility text sizes, toolbar controls may move to a menu and drawer defaults to full feed. Drawing and dragging always have button equivalents. Map exploration is possible without precision gestures. Light/dark, keyboard, safe areas, a smaller phone and a current larger phone are review requirements, not optional polish.

## 9. Adoption and release strategy

1. **Review:** approve navigation, semantics and transition using the isolated prototype and decision register.
2. **Foundation:** introduce typed routes/query contracts and reuse existing projections without changing the visible shell.
3. **Internal flagged Live:** enable the new shell through the shared registered feature-flag platform. Remote/default/device override resolution remains account-scoped and fixed for the full launch.
4. **Small invited cohort:** enable only after real-map, privacy, route and offline proofs. Observe migration comprehension and repeat use; preserve a next-launch rollback.
5. **Expand:** widen only after acceptance and monitoring gates. Do not automatically turn a pilot into a full release because time elapsed.
6. **Connection extensions:** add private replies and richer plans only after their own backend/safety/delivery decisions and tests. Event integration follows the Events program's readiness.

No destructive migration is needed merely to merge navigation. Do not convert every Wanna to a plan, rewrite visit dates, create follow edges, republish Self content or delete old snapshot lists. A server flag rollback affects the next full launch, not a currently active gesture; the old compatible shell must remain during rollout.

### Proposed success criteria

These are acceptance targets, not measured baselines or statistically proven outcomes.

- In moderated review, at least 4 of 5 existing testers find the unchanged Profile → Your Map route, an old save, Lists and Add without verbal instruction; at least 4 correctly explain that activity is not continuous location. Test any candidate Feed owner shortcut separately rather than using it as a substitute for Profile continuity.
- At least 4 of 5 testers move between Feed pins and the corresponding list item, apply/clear an area, and switch between Feed and Profile without changing either surface's prior context.
- Every automated migration/privacy/deep-link acceptance case passes. Any unauthorized visibility or lost save is a release blocker.
- Pilot compares matched observation windows for successful core actions and connection actions per active user, plus D7 return for matured cohorts. Report actual numerator/denominator; a tiny sample is directional, not proof of uplift.
- No material regression against the measured current app in save success, launch/read latency, crash-free sessions or route completion. Collect baseline before choosing numeric alert thresholds; initial performance budgets are in the engineering plan.

Keep existing success events. Proposed UI events only describe coarse surface, scope, drawer state and outcomes; do not log messages, searches, place notes, coordinates, actor/recipient IDs or filters containing private content. Private-reply content requires an explicit replay-masking decision before production; the current app's readable replay configuration does not establish permission for new private messages. Monetization remains unchanged.

## 10. Review decisions

| ID | Recommendation to review | Alternative / cost | Blocks |
|---|---|---|---|
| D1 | Live / Lists / Profile; Add action | Keep Map temporarily, or add Plans later | Shell implementation |
| D2 | Following default; Nearby is geography over authorized content | Public local people discovery needs opt-in and new access policy | Query contract |
| D3 | Past 7 days default for Feed; All time for a selected Feed owner-scope candidate | 24h is sharper but can look empty; existing Your Map ranges remain | Ranking/count copy |
| D4 | Circle area tool plus Filters in Feed; any additional snapshot action is a separate D5 choice | Circular map toggle only; freehand polygon is more complex | Draw UI |
| D5 | Preserve Profile and full Your Map by default; review the selective feature inventory for Feed reuse or an explicitly chosen individual relocation | Keep all current feature entries; internal component reuse does not require moving a screen; wholesale Your Map removal is excluded | Only the selected feature's Feed entry and continuity tests |
| D6 | Prototype full connection/planning journey; stage production | Narrow review to map/feed only | Scope of next build |
| D7 | Private replies initially mutual-only, later phase | Message requests from broader audiences add moderation work | Messaging implementation |
| D8 | Keep MapKit; native map/drawer feasibility spike | Custom map provider requires evidence and broader cost/accessibility review | Technical spike |
| D9 | Dismissible account-version transition card and replay | Forced tour adds friction; no education risks confusion | Migration release |
| D10 | Upcoming is a labelled section; Events discovery folds into Live | Chronological mixing blurs past vs future | Event/plan presentation |
| D11 | 15-minute maximum display lease for last-authorized Live social cache; owner history remains offline | Hide Live social content immediately offline, or accept longer stale-access exposure; any wider cache-policy change needs explicit scope | Live cache/access implementation |

D4 and D6 were asked as optional scope clarifications during preparation. Until explicitly answered, the prototype follows the stated recommendations only for review. No unanswered item is recorded as approved. Material production choices should be accepted together after seeing the concrete journey.

## 11. Acceptance checklist / traceability

| Requirement | Acceptance | Evidence to collect |
|---|---|---|
| R01 unified surface | Same IDs, query and selection in map/list | Query unit tests + native interaction |
| R02 drawer | Live root half/full/peek; never dismissed; root tabs hidden only at peek; detail/modal contracts preserved | UI tests, small/large phone captures |
| R03 chronology | Historical import does not become recent; repeats retain IDs | Feed/date and grouping regressions |
| R04 scope | Following/mutual/owner/other-user access never broadens | RPC/RLS smoke matrix + cache tests |
| R05 geography | Draw/apply/cancel/clear; pan alone does not refilter | Projection tests + native gestures |
| R06 personal history | Current Profile section order, full owner/member Your Map, Map/Patterns, calendar/history, filters and independent context remain; any Feed reuse keeps mixed Been/Wanna and visits | Existing Profile/YourMap tests + before/after journey and screenshots + selected-feature review |
| R07 snapshots | Existing Your Map Snapshot action and lists retained; any D5 Feed capture is owner-only with complete preview/image/membership parity | MapSnapshotListTests + current UI + optional Feed capture UI |
| R08 routes | Existing place/activity/list/plan/widget/import/calendar routes resolve; future event links are separately integrated | Route table integration + cold/warm tests |
| R09 migration | Once/account/version, skip/replay, never intercept intent | State unit tests + account switch |
| R10 capture | Save returns correctly even outside query; retries idempotent | Store tests + offline/retry UI |
| R11 sparse | No forced nearby claim/empty airport trap | Dense/remote/empty fixtures |
| R12 plans | Wanna survives invitation/cancel; explicit sharing | Plan repository + end-to-end invitation |
| R13 replies | Correct recipient, authorization and no false delivery | Later message tests; prototype simulated |
| R14 events | Eligibility and canonical lifecycle remain intact | Events integration contract |
| R15 accessibility | Full task possible with VO, AX type and no drag | Manual native a11y run |
| R16 privacy changes | Block/unfollow/logout clears stale cards and caches | Hosted + account-switch integration |
| R17 performance | Budgets measured against current baseline | Device Instruments / network profiles |
| R18 rollout | Registered flag, explicit Off, restart and rollback | FeatureFlag tests + rollback rehearsal |
| R19 analytics | Real success only, allowlisted content-free events | analytics:check + privacy tests |
| R20 complete review | Plan, prototype, gaps and decisions agree | Cross-review and human sign-off |

The prototype demonstrates proposed behavior with fixtures. It is not evidence that production APIs, pagination, access policy, messaging, rollout, or event integration pass these criteria.
