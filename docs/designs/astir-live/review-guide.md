# Review Astir Live

REC-636 · October 10, 2026 · **Implementation in progress**

Review the integrated `Wander` app against the accepted direction. Its map is SwiftUI `Map`/`MapReader`, its drawer embeds the existing Feed, and its pins/filters currently use authorized **loaded** Feed records. The final V4 build passed **2,770 unit tests** and **all 11 Live UI journeys on each phone size**, including the final map-controls inset and accessible drawing labels. Fourteen current captures are available in the gallery. The earlier full native suite is not green, and actual messaging snapshot/replay and hosted delivery remain unverified. Use the [integrated validation report](review/integrated-validation.md) for exact candidate and final results; no hosted pass is claimed here.

## Run the integrated review

1. Open this branch's `Wander.xcodeproj` in Xcode.
2. Select the shared **Live Experience Review** scheme and an available iPhone Simulator, then Run.
3. Confirm **Live / Lists / Profile**. The scheme builds the normal `Wander` target and enables isolated authenticated demo fixtures, Live, the Feed fixture and initial `.discover` selection. It disables walkthroughs and includes a dated received invitation for the Upcoming journey.
4. Open Messages to review the fixture inbox/thread. The app must display **Demo messages · nothing is delivered** and mark fixture acknowledgements **Simulated**.
5. Use Test with the scheme for its configured `WanderTests`/`WanderUITests` targets, or run the focused `LiveExperienceUITests` from Xcode's test navigator. Record the actual destination/build/results; configuration is not a pass.

The scheme is defined in `project.yml` and the generated shared scheme; use XcodeGen for project regeneration. It provides integrated UI review without claiming a hosted Live query or messaging service is ready. Ordinary activation uses registered `.unifiedLiveV1`, default off, through the existing flag platform. An explicit Off remains authoritative outside the isolated review path.

The separate `preview/rec-636-live` app, fictional records, simulated actions and prior captures are **historical design evidence**. They do not depict or validate the current integrated build. The current scheme's fixture messages also do not demonstrate real delivery, RLS, hosted grants or source revocation.

## Accepted direction

- **Live / Lists / Profile** are locked. Add stays an action; search and notifications remain reachable, with private conversations separate from notifications.
- D2/D3 query presets and defaults are explicitly accepted. Local city-centered 5/25 km, category/person and 24-hour controls are integrated; complete server filtering/paging, current-location centering and eligible discovery remain pending. Local controls and the final map layout are covered by the V4 unit/UI checks on both phone sizes.
- Keep Recent activity exactly as the existing Feed: cards, grouping and actions, with **Invite people to Astir → People worth following → Activity** in the current order.
- Profile keeps identity/social, streak, recent activity, Your Map and calendar. **Only drawing is reused.** Other map/history/lens/Patterns/Snapshot/share tools and routes stay in Profile.
- Remove redundant Live, “place memories” and “your people” header copy. Wanna pins use a muted outlined bookmark distinct from Check-ins. Initial camera responds to authorized density; subsequent user pan is respected.
- Move the drawer by direct drag; remove the extra arrow. Keep accessible alternatives, reachable map/tab exits and keyboard-safe content.
- D6/D7 approve **production mutual-only private messaging**. Wanna → plan uses the actual existing invitation flow. A demo action or public comment does not substitute for those contracts.
- D9 migration and D10 separate Upcoming plans/events are accepted. Existing Events interest registration stays truthful until full Events is available.

## Current implementation and remaining gates

| Item | Current state | Review consequence |
|---|---|---|
| Map/Feed | Integrated SwiftUI map and existing embedded Feed; local projection of visible loaded groups | Visible count is “N updates shown”; accessibility label is “N loaded updates”. An empty filtered page retains continuation; no complete-area claim |
| Drawer | Peek/half/full; tabs visible at every detent; handle drag and VoiceOver adjustable action | No implemented Map pill or count-tap button. Explicitly review the earlier hidden-peek-tabs/Map-pill target against current behavior |
| Filters | Local selected-city 5/25 km, loaded category/person facets, 24-hour/7-day/30-day/all-time ranges; staged Apply/Cancel/reset, badge and summary | Verify fixed bounds advance only on Apply/explicit refresh, Nearby starts 5 km, drawn area remains independent, tab return preserves committed selection and Reset retains audience; final local unit/UI checks passed; see the validation report |
| Server-filtered paging | `LiveFeedQuery` and repository APIs exist; [store patch](implementation-drafts/store.patch) unapplied; [SQL](implementation-drafts/live-feed.sql) undeployed draft | Require store integration, query/account generation tests, migration review and hosted smoke before complete-query claims |
| Messaging | Real client repository, ephemeral transport, memory-only state, masked UI and inactive-scene privacy cover; [SQL](implementation-drafts/private-contextual-messages.sql) undeployed draft | Actual snapshot/replay evidence is pending. Require hosted mutual/block/context/idempotency tests, real two-account behavior and operational gates before activation |
| Invitations | Existing Common Ground composer/sharing/repository reused; mutual-person picker for own Wanna and targeted friend-origin resolution | Verify cold-cache recovery, viewer Been + friend Wanna, save recovery, cancellation and actual invitation result |
| D9 teaching | Explicit fresh-orientation acknowledgements, read-only ordinary replay, archived-checkpoint Continue/Not now and root recovery routing | Newest native fresh-account/recovery/rollback evidence is pending. Guide is not an anchored spotlight tour |
| D10 Upcoming / Events | Conditional Upcoming invitations entry and separate max-three sheet reuse the shared recipient inbox; existing eligible Events interest entry remains | Current/future dated matches from the latest 100 received invitations, not all plans/sent invitations. Final Upcoming recipient/inbox UI checks passed on both phone sizes; no Event inventory, booking, RSVP or Event-link contract is claimed |
| Drawing shape/confirmation | Freehand + explicit Apply is an unanswered optional default | Exercise preview/redraw/Apply/Cancel and visible-area alternative; no claim of current Zillow UI parity |
| Drawing persistence | Account-session retention is an unanswered optional default | Verify tab/detail return and account reset; no durable/cross-device persistence |
| D11 cache lease | **Unanswered product gate**, proposed 15-minute new Live social display lease | Existing shared-cache/Profile policy remains; no new lease or expiry guarantee is implemented |

D2/D3 are accepted decisions, not recommendations awaiting approval. Their local controls filter authorized loaded rows; the initial time/type/polygon RPC draft still lacks radius/category/person parameters. Current-location centering and eligible discovery remain separate implementation work. The settled tab, Profile and messaging choices do not require another product decision for work to continue.

## Review order

1. [Product specification](product-spec.md): accepted scope, exact Feed/Profile continuity and required journeys.
2. [Engineering plan](engineering-plan.md): actual files/APIs, current runtime versus pending store/SQL drafts and validation gates.
3. Integrated app launched with the scheme above, or the exact authenticated candidate build recorded by the implementation owner. State which data/repository mode was used.
4. [Integrated validation report](review/integrated-validation.md) and [integrated capture gallery](review/integrated-captures.md): current candidate, test results, visible review evidence and gaps. The [earlier validation record](review/validation.md) and [capture gallery](review/captures.md) only prove the builds they explicitly identify.
5. [Earlier prototype instructions](../../../preview/rec-636-live/README.md) and [earlier design review](review/design-review.md): historical reference; accepted decisions in this guide/spec supersede resolved choices.

## Focused native review script

| Journey | Required observation |
|---|---|
| Live landing → drag → full Feed → Map → restore | Density framing, user-pan preservation, no duplicate header/arrow, tab/map exits and accessible controls |
| Existing Feed modules/cards | Exact actions/layout/order; loading/retry/empty/refresh/pagination; no summary-card replacement |
| Pin → activity choice → Show in Feed / Open place → return | Original source IDs, retained context, every loaded overlapping activity reachable; bounded chooser remains scrollable |
| Audience/type/time/area with few matches and another page | Existing audience semantics, honest loaded count, continuation after filtered-empty page; no inferred total |
| Filter edits → Cancel; edits → Reset → Apply | Cancel preserves all committed choices; Reset keeps selected audience; Apply synchronizes map/Feed projection and active-count badge |
| Draw → preview → Cancel; redraw → Apply → pan → Clear | Previous committed area preserved; no refilter on pan; invalid/wide/date-line geometry and accessible visible-area alternative |
| Profile → Your Map → old save → Patterns → calendar | Existing hierarchy/history/tools and return; Live drawing does not mutate Profile state |
| Own/friend Wanna → person/shared-source check → invitation | Correct partner; viewer Been + friend Wanna; explicit recovery without a shared save; no create/send on selection; original Wanna intact |
| Mutual reply → inbox/thread → send/retry | Fixture mode visibly Simulated; hosted mode requires separate real delivery/access evidence; correct recipient and no false receipt claim |
| Message/plan sheet → background → foreground | Preserve mounted draft; no unexpected root reset or duplicate send |
| Live modal → notification/import/list/profile/activity → return | Wait for physical dismissal; preserve full payload; account changes/new handoff cannot replay old queue |
| First ordinary entry → Not now / Show me → Settings replay | Correct first-visit/returning copy and actual-render counting; explicit first-visit Next/Done advances only represented map/feed teaching. Not now/Close and ordinary full-guide replay do not mutate legacy progress |
| Pending checkpoint → Continue / Not now → Settings resume | Original archive retained; explicit guide acknowledgements advance only represented progress; opening/cancelling a real flow is not completion; dismissing the old reminder does not discard a draft |
| Retained save / import / contact / device lesson | Existing commit evidence before reopening a submitted draft; no automatic save/send/permission request; contact selection retained; device Got it completes only its lesson |
| Historical checkpoint missing a form, list ID or accessible place | Explicit Add/Lists/Profile recovery; no fabricated form, exact editor restoration or action success |
| New account / interrupted upgrade / explicit route / rollback | Explicit intent precedes teaching; captured accounts keep their recovery bridge. Fresh acknowledgements preserve partial progress and refuse changed accounts/unreadable recovery; no real action or lesson is completed. Newest native evidence remains pending |
| Upcoming invitations → row / View inbox | Separate sheet, max three ascending suggested dates, undated/past excluded, honest latest-100 received scope; wait for physical dismissal before existing recipient/full-inbox route, preserve guarded read transition; account/reset/failure clears or hides stale state. Final recipient/inbox route checks passed on both phone sizes |
| Events entry / later Event discovery | Existing eligibility/interest semantics; no fabricated inventory or RSVP; upcoming Event dates remain separate from past activity |
| Small/current phone, dark/light, VoiceOver, large text, Reduce Motion | Stacked accessible controls, no clipped chooser/keyboard, safe map attribution and non-drag alternatives |

Still captures do not prove drag/scroll arbitration, routing, authorization, delivery or replay privacy. Record actual build/commit, destination, mode, interaction/command, result and unresolved gaps. Do not relabel old prototype captures as current evidence.

## Completion and release

Implementation continues on accepted scope while optional D4 drawing defaults remain unanswered. Server paging requires applied store integration and a reviewed/deployed/verified additive RPC. Production messaging requires the real access/delivery/privacy and operational gates, including actual snapshot/replay evidence. D9 fresh-orientation semantic acknowledgements and host recovery are integrated; final native fresh-account/recovery/rollback validation remains before ordinary activation. Archive-before-clear is logical storage ordering, not a filesystem crash-durability claim. D11 is a separate decision; it does not authorize changing shared-cache/Profile behavior.

Release readiness requires current native and applicable hosted tests, reviewed device evidence, analytics/replay checks, route/NUX/rollback coverage and the ordinary release workflow. This review package does not itself activate hosted services, send invitations, deploy schema or release a build.
