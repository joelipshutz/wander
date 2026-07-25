# REC-143: Check-in Ticketing Specification

Date: 2026-07-24
Status: Engineering-cleared and simulator/source design-reviewed; real-device
validation pending
Owner: Ryan
Linear: [REC-143](https://linear.app/recme/issue/REC-143/rebrand-been-as-check-in-and-define-repeat-ticketing-system)

## Product decision

Replace the user-facing “Been” concept with “Check-in” throughout rec.me.
Checking in is a repeatable action. Every completed check-in produces one
durable, editable place-memory record. The UI may present that record as a
ticket, but “ticket” is the visual metaphor and object shape, not a second
database entity or the primary verb.

This is a reframe of behavior rec.me already supports:

- `place_visits` already stores multiple visits per saved place.
- the map already routes a saved place’s plus action into “Add visit”;
- ratings, notes, tags, photos, dates, and shared friends are already
  visit-scoped;
- Profile calendar summaries already count repeated visits;
- `user_places` already acts as the per-person/per-place summary row.

The implementation should rename the product surface and make the repeat loop
obvious. It should not duplicate the existing visit model or perform a risky
big-bang rename of persisted `been` values.

## Why this change

“Been” reads like a permanent binary label. It tells someone that a place is in
their history, but it does not invite another action or explain why rec.me can
hold multiple memories for the same place.

“Check in” is an action. “Check-ins” are countable records. A ticket-shaped
check-in makes each visit feel like a collectible memory without turning
rec.me into live location sharing or a competitive check-in game.

The desired loop is:

```text
find or revisit a place
        |
        v
     check in
        |
        v
date + rating + note + tags + photos + friends
        |
        v
 receive one ticket-shaped memory
        |
        +--------> edit this check-in
        |
        +--------> check in again later
```

## Goals

1. Use one clear lexicon across Map, Add, Feed, Discover, imports, Profile,
   calendar, activity, settings, accessibility, notifications, and tests.
2. Make repeat check-ins the default mental model and a first-class action on
   a place already on the user’s map.
3. Give every check-in a ticket-like visual identity while retaining the
   current warm, map-first design system.
4. Preserve all existing visit history, visibility, shared-visit ownership,
   photos, ratings, sync behavior, and backward compatibility.
5. Ship the change incrementally with tests that prove old data still decodes
   and new check-ins remain repeatable and idempotent.

## Non-goals

- No live-location presence, proximity broadcasting, or background check-in.
- No points, leaderboards, streak economy, badges, scarcity, redemption, QR
  scanning, admission, payment, or venue-issued tickets.
- No new `tickets` table, `Ticket` SwiftData model, or parallel ticket
  repository.
- No destructive rename of the production `been` enum/database value in the
  first release.
- No per-check-in privacy control. A check-in continues to inherit the
  containing `user_places.visibility`.
- No change to the four-tab information architecture.
- No redesign of the approved global token system.
- No TestFlight release or build-number change as part of this specification.

## Terminology contract

Use sentence case in prose and the app’s existing lower-case control style
where appropriate.

| Meaning | Approved copy | Avoid |
|---|---|---|
| Action/verb | “Check in” | “Check-in”, “Mark been” |
| Singular record/noun | “Check-in” | “Been”, “Visit” on primary product UI |
| Plural records/noun | “Check-ins” | “Beens”, “Been places” |
| Past-tense activity | “Checked in” | “Been”, “Check-in’d” |
| CTA on a new place | “Check in” | “Save as been” |
| CTA on a saved place | “Check in again” | “Add visit” |
| Edit action | “Edit check-in” | “Edit visit” |
| Delete action | “Delete check-in” | “Remove Been” |
| Historical collection | “Your check-ins” | “Your Been places” |
| Count | “12 check-ins” | “12 been” |
| Place-level summary | “Checked in 3 times” | “Been” |
| Other-person context | “Ryan checked in here” | “Ryan has been” |
| Ticket metaphor | “Check-in ticket” only when explanation is needed | “Ticket” as the primary standalone action |

Keep ordinary English uses of “been” when they are not the product status, such
as “It may have been removed.” The change is semantic, not a blind global
string replacement.

## Audit baseline

The 2026-07-24 source audit found:

- 69 Swift string-literal lines containing product or ordinary-English
  “Been/been” across 17 app files;
- 19 app Swift files that branch on `.been` or serialize `"been"`;
- 13 Swift test files that exercise the persisted `.been` contract;
- 17 Supabase migration files with status checks, feed event mapping, RLS, or
  visit synchronization tied to the persisted value;
- an existing `LocalPlaceVisit` model and `VisitRepository`;
- an existing `place_visits` table with repeat rows, visit photos, indexes,
  RLS, backfill logic, and latest-visit summary synchronization.

### User-facing surfaces

| Surface | Current examples | Required direction |
|---|---|---|
| Map filters and badges | “been” | “check-ins” or compact “checked in” |
| New-place save picker | “save as” → “been” | dual intent: “check in” / “wanna go” |
| Saved-place plus action | “Add visit” | “Check in again” |
| Save/edit sheet | “add/edit/save visit” | “new/edit/save check-in” |
| Place activity | “MY SAVES”, “Edit visit” | “MY CHECK-INS”, “Edit check-in” |
| Profile stats | “84 been” | “84 check-ins” |
| Profile map | “Been places” | “Check-in map” or “Places checked in” |
| Calendar | filled = been | filled = check-in |
| Imports | “Been” / “Mark all Been” | “Check in” / “Check in all” |
| Feed/social copy | event type `place_been` projected as Been | render “checked in” |
| Streak copy | “One Been or Wanna…” | “One check-in or Wanna…” |
| Settings | “Been and Wanna Go places” | “Check-ins and Wanna Go places” |
| Accessibility | “Open been places” | “Open check-ins” |

Mockup-only strings should be updated or explicitly retired so launchable debug
pages do not teach a conflicting vocabulary.

## Existing architecture to preserve

### Data relationship

```text
profiles
   |
   | 1
   v
user_places  ------------------- places
   | one summary per user/place      1
   | status = been | wanna_go        |
   | visibility, latest visit        |
   |                                 |
   | 1                               |
   v                                 |
place_visits <-----------------------+
   | many repeat records
   | visited_at, note, rating, attributes, tags
   |
   +----< visit_photos
   |
   +---- shared_visit_groups / participants
```

### Current write paths

```text
first Check in
  MapPlaceSaveFlowSheet
    -> WanderStore.saveCandidate(status: .been)
      -> user_places upsert
      -> backfilled place_visits row
      -> parent + visit remote sync

Check in again
  PlaceSheetAction.addVisit
    -> MapPlaceSaveContext.addVisit
      -> WanderStore.createVisit(...)
        -> new place_visits row
        -> refresh user_places latest summary
        -> remote visit upsert

edit/delete one Check-in
  activity ticket
    -> updateVisit/deleteVisit
      -> sync place_visits
      -> trigger/store recomputes parent summary
```

The second path is already close to the target behavior. The first path must
change before this ships: a newly created check-in cannot remain a
`backfilled_from_user_place` row because the current RLS contract permits
owners to update only explicit visits. New first and repeat check-ins therefore
use the same explicit visit identity. Backfill remains only as a compatibility
repair for legacy Been rows that have no visit.

The remote write boundary is one authenticated, idempotent transaction:

```text
public.save_own_check_in(place, user_place, visit, attributes)
  -> app.current_user_id() chooses the owner
  -> upsert parent user_places summary
  -> insert/upsert explicit place_visits by client UUID
  -> update attributes and derived parent summary
  -> return parent id + visit id
```

The public wrapper should remain `security invoker`; its narrowly scoped
`app.*` implementation may be `security definer` only with a pinned
`search_path`, no caller-selected user id, explicit grants, metadata
assertions, and hosted smoke coverage. This mirrors the hardened
`save_own_place` boundary without inheriting its backfill behavior.

## Chosen data contract

### Domain language by layer

| Layer | Name/value in first release | Reason |
|---|---|---|
| Product UI | Check-in / Check-ins / Checked in | new product vocabulary |
| Swift UI intent | `checkIn`, `checkInAgain` where newly introduced | avoids extending “Been” into new code |
| Swift persistence | `PlaceStatus.been` | preserves SwiftData and Codable compatibility |
| Visit domain model | `LocalPlaceVisit`, `PlaceVisitDraft` | accurately represents the durable record |
| Supabase parent status | `user_places.status = 'been'` | avoids RLS/RPC/feed migration blast radius |
| Supabase record | `place_visits` | already supports the desired cardinality |
| Feed storage event | legacy `place_been`, now keyed to `place_visits` | stable event contract plus repeat check-in facts |
| Analytics status property | `been` initially, plus versioned UI-action event | preserves historical funnels |

Add a narrow presentation vocabulary boundary instead of renaming persistence:

```swift
extension PlaceStatus {
    var checkInDisplayTitle: String {
        switch self {
        case .been: "check-in"
        case .wannaGo: "wanna go"
        }
    }
}
```

Do not expose `checkInDisplayTitle` as the only grammar API. Copy that needs a
verb, plural, past tense, or count should use a dedicated small formatter so
call sites cannot produce “check-in again” grammar accidentally from a generic
status title.

Recommended presentation API:

```text
CheckInCopy.action                 = "check in"
CheckInCopy.repeatAction           = "check in again"
CheckInCopy.singular               = "check-in"
CheckInCopy.plural(count:)         = "check-in" / "check-ins"
CheckInCopy.pastTense              = "checked in"
CheckInCopy.placeCount(count:)     = "1 place" / "12 places"
```

This can be an enum/namespace in the existing design/domain vocabulary file. It
does not need a service, protocol, repository, dependency injection, or
localization framework.

## Check-in ticket design contract

The ticket is the visual treatment of an existing activity/check-in card.

Each ticket must show:

1. place name and category/emoji;
2. check-in date and, when available, time;
3. rating;
4. note or useful answered detail;
5. visit-scoped tags;
6. photo preview/count;
7. friends on that specific shared check-in;
8. privacy indicator inherited from the place save;
9. edit affordance for the owner.

Ticket behavior:

- one ticket equals one active `place_visits` row;
- repeat check-ins create additional tickets and never overwrite prior ones;
- editing updates only the selected ticket;
- deleting removes only the selected ticket and its photos;
- deleting the final check-in follows the existing place-unsave behavior;
- a Wanna Go can coexist historically with later check-ins through the
  persisted historical-want snapshot;
- remote/shared tickets keep their existing independent ownership model.
- place activity opens with the newest ticket in a compact first viewport;
  oversized map/header chrome must not push the first ticket below the fold;
- the collapsed ticket prioritizes date, rating, and one useful memory detail;
  expanding reveals the remaining visit-scoped content and owner actions.

Sharing remains place-level in v1. Existing shared-visit friend context is
shown when it already exists, but this rebrand does not add a new
per-check-in-share product or privacy model.

Visual direction:

- use the current raised/bone surfaces, terracotta, sage, ink, radii, type, and
  44pt targets from `DESIGN.md`;
- use a subtle perforated/notched edge, date stamp, or compact ticket number
  only when it improves scanability;
- do not use a fake QR code, barcode, price, seat, gate, validity, or redemption
  language;
- the place and memory remain the hierarchy. The ticket treatment is not a
  novelty frame around every piece of content.

The primary green Profile number counts total active check-ins, including
repeat check-ins at one place. Unique places are a secondary explanation such
as “87 check-ins across 52 places.” A binary place count cannot remain labeled
as the primary check-in count.

## User flows

### New place: Check in

1. User selects a place.
2. The choice is “check in” or “wanna go”.
3. Check in opens a form titled “Check in at [place]”. It does not retain the
   existing Visit/Been/Wanna status selector in check-in mode.
4. An early, labeled “When?” field defaults to now and can be changed to a
   past date/time.
5. Submit atomically creates/updates the parent save and exactly one explicit,
   editable check-in using the client-generated visit UUID.
6. The submit control is labeled “Check in”; a checkmark alone is
   insufficient. Feedback says “Checked in” and the place sheet shows the new
   ticket.
7. The primary repeat action becomes “Check in again”.

### Existing place: Check in again

1. User opens a place already on their map.
2. A labeled “Check in again” primary action appears before or with stronger
   hierarchy than Directions. A plus icon alone is insufficient.
3. The form may suggest the latest rating/category answers, but note, personal
   labels, photos, and friends start visit-scoped and intentional.
4. Submit appends exactly one new check-in.
5. Historical tickets remain unchanged and the aggregate rating/calendar
   update.

“Check in” records a memory. It does not assert live presence. All sources
default the visit time to now, allow a past time, reject future times, and do
not require proximity. “I’m here right now” remains the explicit current-
location source.

### Wanna Go → first Check-in

1. Existing want opens “Check in” as the primary completion action.
2. Existing want note may seed the form under current behavior.
3. Submit preserves the historical want snapshot, clears the active plan/date,
   and creates one check-in.
4. The ticket is dated at the check-in time, not the original Wanna save time.

The historical Wanna snapshot must be remotely durable, not only local
SwiftData state. The migration extends the owner-only remote contract with the
historical note, answer JSON, tags, and wanted-at time needed to restore the
plan. Deleting the final check-in calls one atomic owner-scoped RPC that either
restores that Wanna state or unsaves the parent; it must not let a device and
the server choose different outcomes.

### Edit/delete

- “Edit check-in” changes only that check-in’s date, rating, note, tags,
  category answer, visibility inheritance, friends, and photos.
- “Delete check-in” confirms that its visit photos are also removed.
- If another check-in remains, the place stays checked in and its summary uses
  the latest active record.
- If none remains and no active Wanna state remains, the existing unsave rule
  applies.
- A remote deletion is represented by a durable local outbox/tombstone until
  the visit, dependent photos/shared context, Feed fact, and parent transition
  are acknowledged. Relaunch and network restoration retry the same operation.

## State and failure semantics

| Scenario | Required result |
|---|---|
| Offline check-in | ticket appears locally with queued sync state |
| Retry after network failure | same local/remote visit id; no duplicate ticket |
| App killed after local save | ticket restores from SwiftData snapshot |
| Parent unsynced | sync parent before the explicit check-in |
| Atomic parent/check-in RPC fails | keep the local ticket pending; retry the same parent and visit UUID |
| Photo upload fails | check-in remains; photo shows retry state |
| Shared friend invite fails | check-in remains; invite outbox retries |
| Two rapid taps | one submission lock prevents duplicate check-ins |
| Same place checked in repeatedly | every completed submission appends one row |
| Old snapshot has Been but no visits | existing backfill creates one compatibility check-in |
| New first check-in syncs | remote row is explicit and remains editable |
| Old app reads new data | persisted status remains `been`; visit tables stay compatible |
| Offline delete/relaunch | durable delete outbox retries; deleted ticket does not reappear |
| Last check-in deleted | one atomic remote operation restores historical Wanna or unsaves |
| Block/privacy change | existing RLS and shared-visit cancellation remain authoritative |
| Feed history | old `place_been` rows render as “checked in”; future rows identify one live visit |
| Historical/import check-in | Feed may say “added a check-in from [date]”; no follower push |

## Analytics and observability

Preserve stored `status = been`, the `place_been` event value, and historical
`place_saved` funnels. Extend `feed_events` with nullable `visit_id`:

- legacy rows keep `visit_id = null` and project from the parent summary;
- future check-in rows are emitted by `place_visits` insert, carry `visit_id`,
  and project note/rating from that visit;
- `visit_id` references `place_visits(id) on delete cascade`; eligibility also
  rejects a missing or soft-deleted visit;
- the user-place trigger must stop emitting a second `place_been` event for new
  Been parents once the visit trigger owns the fact;
- a partial unique index on `visit_id` makes retries idempotent;
- do not backfill old repeat visits into the live Feed and create a surprise
  burst of historical activity.

Publication semantics are explicit:

- a current-day, user-created first/repeat check-in creates a Feed fact and may
  queue the existing privacy-filtered follower push;
- a historical or imported check-in may create a Feed fact at creation time,
  but exposes the distinct `visited_at` and renders “added a check-in from
  [date]”; it never queues a follower push;
- `backfilled_from_user_place` compatibility rows create neither Feed facts nor
  follower pushes;
- Feed `occurred_at` is the publication/creation time, never a fabricated visit
  time;
- Feed media is omitted in v1. Visit photos live in a private bucket and need
  authorized client hydration/signed URLs; SQL projection must not invent a
  public media URL.

Add versioned action events at the UI boundary:

- `check_in_started`
- `check_in_completed`
- `check_in_failed`
- `check_in_again_started`
- `check_in_edited`
- `check_in_deleted`

Minimum properties:

- `source_type`
- `entry_surface`
- `is_repeat`
- `has_rating`
- `photo_count`
- `friend_count`
- `sync_outcome`

Do not send place names, notes, exact coordinates, photo paths, friend ids, or
other private payloads.

For one release, compare:

- check-in form starts → completions;
- first check-in → repeat check-in;
- duplicate visit rate by client-generated visit id;
- queued/failed visit sync;
- abandonment by form step.

## Rollout plan

### Phase 0: contract tests

- lock the terminology matrix in unit/navigation tests;
- prove old `"been"` payloads and snapshots still decode;
- prove a first check-in creates one explicit, remotely editable visit;
- prove repeat check-ins append;
- prove retries do not duplicate;
- prove durable delete replay and atomic delete-last/Wanna restoration;
- prove current, historical/import, and legacy-backfill publication rules.

### Phase 1: semantic presentation boundary

- introduce `CheckInCopy`;
- replace product-status strings, accessibility labels, and parser-rendered
  copy;
- retain ordinary English “been”;
- update test names where they describe product copy, while leaving storage
  contract tests explicit about `"been"`.

### Phase 2: action and form reframe

- rename “Add visit” to “Check in again”;
- rename save/edit/delete/feedback visit copy to check-in copy;
- make the first save choice action-oriented;
- replace the new-save backfill write with the atomic explicit-check-in RPC;
- emit one visit-keyed Feed event for the first and every repeat check-in;
- add submission-level analytics and duplicate-tap regression coverage.

### Phase 3: ticket treatment

- restyle the existing `PlaceActivityEntry` card rather than adding a parallel
  ticket screen/model;
- update place activity, owner Profile, calendar, Feed, and shared-check-in
  presentation;
- capture real-device screenshots on the current phone and a smaller target;
- validate VoiceOver, Dynamic Type, contrast, long place names, no-photo, and
  many-check-in states.

### Phase 4: compatibility rollout

- ship copy/ticket presentation behind a remote flag if product wants a quick
  visual rollback; the new atomic persistence contract remains active either
  way;
- monitor check-in completion, visit sync, duplicates, and crashes;
- remove only the flag after one stable release;
- defer any persisted enum/event rename to a separate versioned migration after
  old supported clients no longer depend on it.

## Implementation boundaries

Expected implementation areas:

- `Wander/Models/WanderEnums.swift` or a small existing vocabulary file;
- Map filter/action/save/activity code;
- Profile stats, calendar, map, import, and activity copy;
- Feed/Discover projection copy;
- settings, streak, rating explanation, accessibility;
- mockup/debug launch pages that remain supported;
- matching unit/navigation/snapshot tests;
- one additive Feed migration for visit-keyed repeat activity, not for renaming
  `user_places.status`.
- one owner-scoped atomic first-check-in/delete-last contract plus durable
  historical-Wanna fields and a local delete outbox.

Do not modify:

- `PlaceStatus.been.rawValue`;
- existing Supabase status checks/RLS solely for copy;
- `place_visits`/`visit_photos` ownership;
- shared-visit RPC security posture;
- visibility enum semantics;
- app tab structure.

Do not add Feed photo projection, per-check-in sharing/privacy, a new ticket
entity, or server paging/Profile batch APIs in REC-143. Those are separate
product or measured performance changes. The measured performance work is
tracked in [REC-145](https://linear.app/recme/issue/REC-145/measure-and-optimize-profile-check-in-hydration-and-long-history).

## Test topology

```text
                         ┌──────────────────────────────┐
                         │ terminology contract tests   │
                         │ grammar + accessibility copy │
                         └──────────────┬───────────────┘
                                        |
┌──────────────────────┐   ┌────────────v─────────────┐   ┌──────────────────────┐
│ old snapshot / JSON  │-->| WanderStore check-in     |-->| SwiftData relaunch   │
│ status = "been"      │   │ create/edit/delete       │   │ offline queue        │
└──────────────────────┘   └────────────┬─────────────┘   └──────────────────────┘
                                        |
                         ┌──────────────v──────────────┐
                         │ repository + Supabase RLS   │
                         │ idempotency / summary sync  │
                         └──────────────┬──────────────┘
                                        |
                 ┌──────────────────────┼──────────────────────┐
                 |                      |                      |
       ┌─────────v────────┐   ┌─────────v────────┐   ┌────────v─────────┐
       │ place activity    │   │ Profile/calendar │   │ Feed/social copy │
       │ ticket UI         │   │ repeat counts     │   │ visibility      │
       └─────────┬────────┘   └─────────┬────────┘   └────────┬─────────┘
                 |                      |                      |
                 └──────────────────────v──────────────────────┘
                           live-device visual/accessibility QA
```

Test layers:

1. Pure copy/grammar tests for zero, one, and plural check-ins.
2. Store tests for first, repeat, edit, delete, offline restore, Wanna
   conversion, rating aggregation, and client-generated idempotency.
3. Repository encoding/decoding tests proving persisted `been` compatibility.
4. SQL tests for parent/visit invariants and RLS. No schema mutation is needed
   for the copy-only phase.
5. Navigation contracts for Map, import, Profile, calendar, and activity labels.
6. Visual and accessibility QA for current iPhone plus one smaller phone.
7. Hosted smoke test for the new owner check-in RPC, delete/restore path, Feed
   event projection, metadata security posture, and exact production payload.
8. State coverage for loading, empty history, queued/offline success, retryable
   error, and destructive confirmation. Accessibility coverage includes
   VoiceOver ticket summaries/counts, XXL Dynamic Type, Reduce Motion, and
   color-independent status meaning.

## Acceptance criteria

- No user-facing product-status use of “Been/been” remains in supported
  production or debug/mockup screens.
- Ordinary English uses of “been” remain grammatically intact.
- A new place offers “Check in” and creates exactly one check-in.
- A checked-in place offers “Check in again” and appends a distinct check-in.
- “Check in again” is a labeled primary place action and is not subordinate to
  Directions or represented only by a plus icon.
- Check-in forms ask “When?” before detail questions, have a labeled submit
  action, and do not show a redundant Visit/Been/Wanna selector.
- Every check-in ticket can retain its own date, rating, note, tags, photos, and
  friends.
- Place activity shows the newest ticket in the compact first viewport on both
  current and smaller target phones.
- Profile’s primary count is the total active check-in-row count; unique place
  count appears as secondary context.
- Calendar summaries say “check-ins”; selecting a populated date opens that
  day’s tickets and VoiceOver announces the count.
- Import actions say “Check in” and “Wanna go”. “Check in” opens the standard
  date-confirming form and never silently records today.
- Existing `"been"` local and hosted data renders as check-ins with no user
  migration step.
- Old feed rows render “checked in”.
- Offline, retry, edit, delete, shared-friend, and last-check-in behavior match
  the failure table.
- Accessibility uses the same vocabulary and all controls remain at least 44pt.
- Relevant unit, repository, navigation, SQL/smoke, and two-device visual tests
  pass.

## Open implementation detail resolved by this spec

The “ticketing system” is a presentation system over `place_visits`, not a new
business object. This keeps the delightful metaphor while preserving one
source of truth for place memories.

## Engineering review

Review mode: `FULL_REVIEW`
Decision mode: Ryan explicitly delegated every remaining choice to the
review’s recommended option. Each decision below records that selection.

### Step 0: scope challenge

The request necessarily crosses more than eight files: the audit found 69
string-literal lines in 17 app files before tests, Feed storage, and
accessibility. That triggered the complexity gate.

Options considered:

- **A: complete semantic rebrand with compatibility boundaries
  (recommended, selected).** Update every supported surface, centralize
  grammar, reuse visits, and keep persisted `been` values stable.
- **B: Map/Profile copy pilot.** Smaller initial diff, but leaves Feed,
  imports, accessibility, mockups, and search teaching contradictory nouns.

Decision: select A. The file count is caused by a legitimate cross-surface
language change, not by new architecture. Scope is controlled by refusing a
new Ticket model, database status rename, global navigation change, or
unrelated visual redesign.

Search result: Apple frameworks do not supply a domain-language or collectible
ticket abstraction relevant to this feature. Existing SwiftUI components,
SwiftData entities, and Supabase visit rows are the Layer 1 solution. A custom
ticket persistence system would be accidental complexity.

`TODOS.md` contains no deferred item that blocks this work. The existing Map
hit-testing and TestFlight follow-ups remain unrelated.

### What already exists

| Existing capability | Evidence | Review decision |
|---|---|---|
| Repeat records | `LocalPlaceVisit` and `place_visits` | reuse as check-in tickets |
| Repeat action | `PlaceSheetAction.addVisit` | relabel and refine as “Check in again” |
| First visit compatibility | parent save creates a backfilled visit | legacy repair only; new writes become explicit visits |
| Visit edit/delete | `updateVisit` and `deleteVisit` | reuse with check-in copy |
| Visit media | `visit_photos` and upload retry | reuse |
| Shared friends | shared-visit group/participant ownership | reuse |
| Rating aggregation | summary recomputed from active visits | reuse |
| Calendar repeat counts | `ProfileInsightsPresenter` | relabel, do not rebuild |
| Feed copy | Feed already says “checked in at” | keep; fix repeat-event storage |
| Notifications | visit insert already queues follower activity | relabel notification copy |
| Offline/idempotent create | local UUID becomes remote upsert id and survives retry | retain and add explicit regression coverage |

### 1. Architecture review

#### 1. Ticket identity must remain the visit identity

`[P1] (confidence: 10/10) Wander/Models/LocalModels.swift:378 and
supabase/migrations/20260709220000_place_visits_visit_photos.sql:3 — a new
Ticket entity would duplicate an existing many-per-place record.`

Motivating code:

```swift
final class LocalPlaceVisit {
```

```sql
create table if not exists public.place_visits (
```

Selected recommendation: one check-in ticket is one `place_visits` row. Ticket
shape belongs in presentation code. No `TicketRepository`, `tickets` table, or
cross-entity synchronization is added.

Production failure avoided: two sources of truth could disagree after an
offline edit or photo retry, showing one count on Profile and another in the
ticket list. Reusing visits makes that impossible by construction.

#### 2. Repeat check-ins are not currently repeat Feed facts

`[P1] (confidence: 10/10)
supabase/migrations/20260720234500_feed_activity.sql:106-123 — the Feed trigger
records the initial Been parent transition, while later place-visit inserts do
not create Feed events.`

Motivating code:

```sql
if tg_op = 'UPDATE'
  and old.deleted_at is null
  and not (old.status = 'wanna_go' and new.status = 'been') then
  return new;
end if;
```

Selected recommendation: add nullable `feed_events.visit_id`, make future
`place_visits` inserts emit the one `place_been` fact, stop the parent trigger
from double-emitting new Been rows, and project visit-scoped memory content
when `visit_id` is present. Keep legacy event values/rows readable.

Production failure avoided: the second check-in would create a ticket locally
but disappear socially, or a first check-in would appear twice after adding a
visit trigger. A partial unique index on `visit_id` and trigger-ownership test
prevent both.

#### 3. Storage and product language need an explicit seam

`[P1] (confidence: 10/10) Wander/Models/WanderEnums.swift:9-11 and
supabase/migrations/20260602131500_m3_foundation.sql:108 — `"been"` is a
cross-layer persisted contract, not merely copy.`

Motivating code:

```swift
enum PlaceStatus: String, Codable, CaseIterable, Equatable {
    case been
```

```sql
status text not null check (status in ('been', 'wanna_go')),
```

Selected recommendation: retain `PlaceStatus.been`, SQL `status = 'been'`,
legacy Feed event values, and old decoder tests. Introduce new Check-in language
only at presentation and new UI-intent boundaries.

Production failure avoided: a big-bang raw-value rename would strand offline
SwiftData snapshots, break old clients against new constraints, and require
every RLS/RPC/feed contract to change in one release.

#### 4. Check-in time is missing from the save submission contract

`[P1] (confidence: 10/10) Wander/Features/Map/MapScreen.swift:3228-3240 and
Wander/Services/WanderLocalStore.swift:5471 — the form cannot submit a visit
time, so a first compatibility visit silently uses the parent’s save time.`

Motivating code:

```swift
struct MapPlaceSaveSubmission {
    ...
    var plannedDate: Date? = nil
}
```

```swift
existing.visitedAt = userPlace.visitedAt ?? userPlace.savedAt
```

Selected recommendation: add `visitedAt` to the Check-in submission, default it
to now, allow past values, reject future values, and pass it through both first
and repeat paths. Add the same control to Edit check-in. Do not require
proximity or describe the record as live presence.

Production failure avoided: someone imports last month’s restaurant photo
today and receives a ticket/calendar/Feed timestamp claiming the visit
happened today, with no way to correct it.

#### 5. New first check-ins cannot use the backfilled visit path

`[P0] (confidence: 10/10) Wander/Services/WanderLocalStore.swift:3620,
3978-3980, and 5790-5805 plus
supabase/migrations/20260709220000_place_visits_visit_photos.sql:459-480 —
the local first-save path creates a backfilled visit, then remote hydration
adopts the server’s backfilled row; RLS explicitly forbids an owner update from
remaining backfilled.`

Selected recommendation: new first check-ins call an atomic
`public.save_own_check_in` contract that upserts the parent and one explicit
visit by client UUID. Keep `backfilled_from_user_place` only for legacy
parents with no visits.

Security contract: the caller never supplies a user id; ownership comes from
`app.current_user_id()`. The public entry point is authenticated-only,
`security invoker`; any `security definer` implementation is narrow, pins
`search_path`, revokes public/anon/authenticated direct execution, and is
covered by `prosecdef`, `proconfig`, grants, RLS, and hosted smoke assertions.

Production failure avoided: a user checks in for the first time, sees a ticket,
then cannot edit its date/note/rating after sync because the server record is a
protected compatibility row.

#### 6. Visit deletion needs a durable remote outbox

`[P0] (confidence: 10/10) Wander/Services/WanderLocalStore.swift:3912-3932 and
4060-4082 — `syncPendingVisits` filters out deleted rows, while a failed
`deleteVisit` marks the locally deleted visit failed. No relaunch path retries
that remote deletion.`

Selected recommendation: persist owner deletion operations with stable
operation/visit ids. A maintenance pass retries pending deletes after relaunch
and network restoration, deletes dependent remote state atomically, and
tombstones the outbox only after acknowledgement. Creates/updates and deletes
have separate retry scans.

Production failure avoided: a check-in deleted offline stays visible on
another device forever and can rehydrate back onto the deleting device.

#### 7. Historical Wanna restoration must be cross-device atomic

`[P0] (confidence: 10/10) Wander/Services/WanderLocalStore.swift:5585-5610
and supabase/migrations/20260709220000_place_visits_visit_photos.sql:326-352 —
the client can restore a local historical Wanna after the last visit, while the
database delete trigger only soft-deletes the Been parent. The historical
fields are not in the current remote save payload.`

Selected recommendation: persist the minimum owner-only historical Wanna
snapshot remotely and replace last-visit deletion with one idempotent,
authenticated transaction that either restores the parent to `wanna_go` or
unsaves it. The operation returns the resulting parent state for local
reconciliation.

Production failure avoided: one device shows a restored Wanna while the server
and every other device show the place as deleted.

#### 8. Check-in publication time and visit time are different facts

`[P1] (confidence: 10/10)
supabase/migrations/20260712130000_followed_place_visit_notifications.sql:111-198
and supabase/migrations/20260720234500_feed_activity.sql:60-123 — every visit
insert can queue a follower push, and the Feed currently owns only a parent
transition timestamp. A backfill or old imported memory can masquerade as
live activity.`

Selected recommendation: define current/historical/import/backfill publication
rules in the data contract. Current-day explicit writes may Feed/push;
historical/import writes may Feed with distinct `visited_at` and “added a
check-in from [date]” copy but never push; backfills do neither.

Production failure avoided: followers receive “checked in” alerts that imply
live presence for a memory from months ago.

#### 9. Feed facts must follow the visit lifecycle

`[P1] (confidence: 10/10)
supabase/migrations/20260720234500_feed_activity.sql:7-45 and 247-280 — Feed
events have no visit foreign key and eligibility validates only the parent, so
deleting one repeat check-in cannot remove only that activity fact.`

Selected recommendation: add nullable `visit_id references
place_visits(id) on delete cascade`, require it for new `place_been` facts,
retain null for legacy rows, and make projection eligibility reject missing or
soft-deleted visits.

Production failure avoided: deleting one ticket leaves a stale follower event
whose rating/note now comes from a different latest visit.

Architecture result: nine issues found, all folded into the plan.

### 2. Code quality review

#### 4. Check-in grammar cannot be another set of duplicated literals

`[P1] (confidence: 10/10) Wander/Models/WanderEnums.swift:209-215,
Wander/Features/Map/MapScreen.swift:2851-2893, and
Wander/Features/Profile/ProfileOwnerHome.swift:691-694 — status, action,
singular/plural, and past-tense copy are independently assembled.`

Motivating code:

```swift
case .been: "been"
```

```swift
case .addVisit:
    "add visit"
```

```swift
let been = "\(insights.monthVisitCount) been"
```

Selected recommendation: add one small `CheckInCopy` namespace for action,
repeat action, singular/plural, past tense, and count grammar. Keep
surface-specific sentences local. Do not introduce a service or localization
framework.

Production failure avoided: the app ships “check-in” as a verb on one screen,
“check ins” on another, and old “Been” accessibility labels that sighted QA
misses.

#### 5. Search needs additive vocabulary, not a destructive replacement

`[P1] (confidence: 10/10) Wander/Services/DiscoverModels.swift:642-647 —
deterministic search recognizes “been” but not check-in variants.`

Motivating code:

```swift
if normalized.contains("been") || normalized.contains("went")
```

Selected recommendation: recognize `check in`, `check-in`, `checkin`,
`checked in`, and `check-ins` while preserving `been`, `went`, `tried`, and
the existing intent synonyms. Audit string hits semantically so ordinary
English such as “It may have been removed” is not corrupted.

Production failure avoided: new marketing copy teaches “check in,” but Discover
returns no status filter for the phrase, while an automated global replace
damages unrelated English.

Code quality result: two issues found, both folded into the plan.

### 3. Test review

Framework: XCTest/XCUITest-style contract tests through `xcodebuild test`, with
pgTAP/hosted smoke coverage for Supabase behavior when backend contracts change.

#### Coverage diagram

```text
CODE PATHS                                             USER FLOWS
[+] CheckInCopy                                        [+] First Check-in
  ├── [GAP] verb / noun / past tense                     ├── [★★ TESTED] parent + one compatibility visit
  ├── [GAP] zero / one / plural counts                   ├── [GAP] exact new copy + accessibility
  └── [GAP] no product-status "Been" residue             ├── [GAP] rapid double-submit stays one visit
                                                         └── [GAP] explicit remote visit remains editable

[+] Map save/check-in                                  [+] Check in again
  ├── [★★★ TESTED] first visit + default rating          ├── [★★★ TESTED] appends and averages rating
  ├── [★★★ TESTED] Wanna -> visit + history              ├── [★★★ TESTED] visit-scoped defaults
  ├── [★★★ TESTED] edit/delete/last visit                └── [GAP] [→E2E] ticket appears and old remains
  ├── [★★★ TESTED] parent sync failure
  ├── [GAP] now/past/future visit-time semantics
  ├── [GAP] delete outbox survives relaunch
  └── [GAP] remote Wanna restore vs unsave transaction

[+] Persistence compatibility                         [+] Discover
  ├── [★★★ TESTED] old snapshot backfill                ├── [★★ TESTED] "been" synonym
  ├── [★★★ TESTED] remote visit upsert                   └── [GAP] check-in spelling variants
  └── [GAP] old "been" + new UI vocabulary contract

[+] Feed / notifications                              [+] Social repeat Check-in
  ├── [★★ TESTED] legacy place_been rating               ├── [GAP] [→E2E] first emits once
  ├── [GAP] visit-keyed first/repeat trigger             ├── [GAP] [→E2E] repeat emits new memory
  ├── [GAP] no duplicate first event                     └── [GAP] block/privacy hides old event
  ├── [GAP] legacy null visit projection
  ├── [GAP] current vs historical/import/backfill rules
  ├── [GAP] visit delete cascades event
  └── [GAP] visit note/rating; no Feed media

[+] Ticket rendering                                  [+] Accessibility/visual
  ├── [GAP] zero/one/many photos                         ├── [GAP] [→E2E] Dynamic Type + long name
  ├── [GAP] self/social/shared variants                  ├── [GAP] VoiceOver labels/actions
  └── [GAP] lazy grouped projection                      └── [GAP] current + smaller iPhone screenshots

COVERAGE: 9/36 branches/flows already covered (25%)
QUALITY: ★★★:7  ★★:2  ★:0
GAPS: 27 assertions grouped into 8 implementation test tasks
E2E: 6 flow/visual checks  |  EVAL: none
```

#### Test gaps selected for the implementation plan

1. **Vocabulary contract:** unit-test verb/noun/plural/past-tense grammar and
   scan supported user-facing source for product-status “Been”.
2. **Map flow:** navigation/interaction test for first copy, “Check in again,”
   save feedback, accessibility, submission locking, and visit-time rules.
3. **Persistence compatibility:** old `"been"` snapshots/payloads render new
   copy without rewriting stored values.
4. **Discover:** preserve old synonyms and accept every new spelling.
5. **Atomic persistence:** first check-in is an explicit editable remote visit;
   delete outbox survives relaunch; last-delete atomically restores the remote
   historical Wanna or unsaves.
6. **Feed/notification SQL:** one first event, one event per repeat visit,
   visit-scoped projection, legacy null-visit projection, current versus
   historical/import/backfill rules, idempotency, delete cascade, and
   visibility. Assert Feed media is absent in v1.
7. **Ticket behavior:** render/edit/delete the selected check-in with
   zero/one/many media, shared friends, and queued failures.
8. **Visual/accessibility:** current real iPhone and one smaller phone, Dynamic
   Type, VoiceOver, long content, and a history long enough to exercise the
   lazy grouped projection.

The atomic write/delete RPCs and Feed migration change iOS-called backend
contracts. Implementation must extend SQL regression coverage and
`scripts/supabase-smoke-test.mjs`, then run:

```bash
npm --prefix scripts ci --ignore-scripts
node scripts/supabase-smoke-test.mjs
```

The smoke test must exercise the exact first-check-in and delete-last payloads,
owner/stranger/anonymous access, retry idempotency, and historical Wanna
restoration inside rollback-safe transactions. Metadata assertions must check
`prosecdef`, pinned `proconfig`/`search_path`, and grants for every new or
replaced RPC. A local-only save or XCTest is not sufficient.

Test review result: diagram produced, eight grouped gaps identified, all added
to the tasks below.

### 4. Performance review

#### 6. Activity entry construction repeatedly scans the full visit array

`[P2] (confidence: 9/10) Wander/Services/WanderLocalStore.swift:2394-2403 and
Wander/Features/Map/MapScreen.swift:6819-6858 — every save calls a full
filter/sort over `placeVisits`, and several computed properties rebuild the
entry list.`

Motivating code:

```swift
return placeVisits
    .filter { userPlaceIDs.contains($0.userPlaceID) && $0.deletedAt == nil }
    .sorted { ... }
```

```swift
saves.flatMap { summary in
    let visits = store.visits(for: summary.visiblePlace.userPlace.id)
```

Selected recommendation: build one grouped, sorted activity projection per
store revision and reuse it for cards, photo viewer context, and companion ids.
Use `LazyVStack` for ticket cards.

Production failure avoided: a user with many friends/check-ins opens a place
sheet and sees scrolling hitch while the same arrays are repeatedly filtered,
sorted, and expanded.

#### 7. Remote Profile hydration is a sequential N-request loop

`[P1] (confidence: 10/10) Wander/Services/WanderLocalStore.swift:4773-4793 —
Profile requests visits once per user-place in series.`

Motivating code:

```swift
for userPlaceID in remoteUserPlaceIDs.sorted() {
    let results = try await backend.visits(for: userPlaceID)
```

Selected recommendation: do not hide this separate repository contract inside
a vocabulary/ticket release. File a measured follow-up for a bounded batch
query, account-staleness protection, and atomic cache replacement. REC-143
preserves current semantics and instruments request count/latency so the
follow-up has a baseline.

Production failure avoided: a profile with 80 places takes 80 network
round-trips before check-in tickets become complete, and partial failures leave
a misleading mixed-age history.

#### 8. Ticket history must not render an unbounded eager list

`[P2] (confidence: 9/10) Wander/Features/Map/MapScreen.swift:6777-6792 — the
expanded place sheet constructs every activity card in a regular VStack.`

Motivating code:

```swift
VStack(spacing: WanderTheme.spacing2) {
    ForEach(filteredEntries) { entry in
```

Selected recommendation: switch the existing card container to `LazyVStack`
and reuse the grouped projection in REC-143. Defer server paging and bounded
companion hydration to the measured Profile/history follow-up; they introduce
new repository/cursor contracts and are not required to rebrand repeat visits.

Production failure avoided: a favorite weekly venue accumulates years of
photos and check-ins, making every place-sheet open allocate the entire history
and attempt incomplete companion hydration past the current 50-id cap.

Performance result: three issues found. Grouped projection and lazy rendering
are in REC-143; batch hydration and server paging are explicitly split into a
measured follow-up.

### Retrospective learning

The same hot modules previously needed REC-101 app-wide interaction-stall work
(`65e839e8c`) and REC-104 cold-start visit indexing (`828a10552`). This plan
therefore protects the cheap projection/cache boundary now, but does not
smuggle new batch and pagination APIs into a cross-surface language release.
Those changes should be driven by measured request count and latency.

### Outside-voice review

The preferred external reviewer could not run because the environment blocked
source egress. Per the review skill, a read-only independent reviewer inspected
the plan and code locally. Ryan preselected every recommended resolution.

| Independent concern | Selected resolution |
|---|---|
| first check-in becomes an uneditable backfilled visit | explicit atomic first-check-in RPC; legacy backfill only |
| offline delete has no relaunch retry path | durable delete outbox/tombstone |
| last-delete Wanna restoration disagrees across devices | persist historical snapshot and restore/unsave atomically |
| first/edit flow cannot supply `visitedAt` | add now/past input and reject future |
| old/import/backfill memories look live in Feed/push | explicit publication versus visit-time semantics |
| deleting a visit does not delete its Feed fact | visit FK with cascade plus eligibility check |
| per-check-in sharing expands the product contract | keep v1 sharing at the place level |
| Feed photo projection cannot safely sign private media in SQL | omit Feed media in v1 |
| batch Profile hydration and paging expand infrastructure scope | split into a measured follow-up; keep lazy/cached projection here |

Outside-voice result: nine concerns found, nine recommended resolutions
selected, five of them promoted to architecture findings 5–9.

## Failure modes

| New/changed path | Production failure | Test | Handling/user result |
|---|---|---|---|
| Check-in submit | rapid taps create two visits | submission-lock integration test | button disables; one ticket appears |
| First remote save | new visit is protected backfill and cannot be edited | RPC/RLS edit-after-create test | one explicit editable visit is returned |
| Offline create | parent/visit cannot sync | parent-failure + relaunch test | ticket remains queued with retry copy |
| Offline delete | remote visit survives forever | delete-outbox relaunch test | ticket stays hidden; same delete retries |
| Visit time | future or missing time corrupts calendar/Feed | now/past/future validation test | defaults now; future value is blocked inline |
| Feed trigger | first save emits parent + visit events | SQL exact-count test | unique visit key prevents duplicate |
| Feed projection | legacy event has no visit id | SQL legacy projection test | parent-summary fallback renders |
| Repeat Feed | retry inserts same visit event | SQL idempotency test | no duplicate activity |
| Historical/import activity | follower interprets old memory as live | SQL trigger/push matrix | dated Feed copy; no push |
| Legacy backfill activity | migration creates follower noise | SQL backfill suppression test | no Feed event or push |
| Visit deletion | stale Feed card survives | FK/soft-delete eligibility test | only that activity fact disappears |
| Feed photo | private bucket path leaks or URL expires | projection shape test | v1 Feed has no media field |
| Search | parser misses punctuation variant | parameterized parser test | all check-in spellings map to status |
| Copy migration | ordinary English is replaced | semantic source audit | ordinary sentence remains unchanged |
| Ticket photos | metadata succeeds, upload fails | visit-photo retry test | ticket remains; photo offers retry |
| Shared friends | invite RPC fails | outbox regression test | ticket remains; invite queued message |
| Long history | eager/repeated projection blocks sheet | 100/1,000-visit performance fixture | lazy cards reuse one grouped projection |
| Last delete | device/server disagree on Wanna or unsave | atomic RPC + cross-device state test | server result reconciles every device |

Critical silent gaps after planned coverage: zero.

## Worktree parallelization

| Step | Modules touched | Depends on |
|---|---|---|
| Foundation vocabulary | Models, shared presentation tests | — |
| Map check-in and ticket UI | Map, DesignSystem | foundation |
| Secondary-surface rebrand | Profile, Discover, Settings, Streak, imports | foundation |
| Atomic persistence + Feed contract | Supabase, store, remote DTO/repository, Feed | foundation |
| Integration and visual QA | tests, scripts, docs | all implementation lanes |

Execution:

```text
Foundation (small sequential merge)
              |
              +--> Lane A: Map/check-in/ticket UI --------+
              +--> Lane B: secondary surfaces ------------+--> integration + QA
              +--> Lane C: persistence + Feed backend -----+
```

Lanes A, B, and C can run in parallel isolated worktrees after the vocabulary
foundation lands. Lane C must own its migration and smoke-test edits. Lane A
must own `MapScreen.swift`. Avoid splitting either high-conflict file across
agents. Integration/QA runs only after all three lanes merge.

## Implementation Tasks

Synthesized from this review’s findings. Each task derives from a specific
finding above.

- [ ] **T1 (P1, human: ~3h / CC: ~25min)** — Vocabulary — Add the Check-in
  grammar boundary and compatibility tests.
  - Surfaced by: code quality finding 4 and architecture finding 3.
  - Files: `Wander/Models/WanderEnums.swift`, focused test files.
  - Verify: focused grammar, old snapshot, and raw-value XCTest cases.
- [ ] **T2 (P0, human: ~2d / CC: ~3h)** — Atomic persistence — Replace
  new-save backfill with `save_own_check_in`, persist the historical Wanna
  snapshot, and implement idempotent restore-or-unsave deletion.
  - Surfaced by: architecture findings 5 and 7.
  - Files: one reviewed Supabase migration, backend protocol/DTO/repository,
    store save/delete contracts, SQL/XCTest/smoke coverage.
  - Verify: owner/stranger/anonymous RLS, edit-after-first-create, retry
    idempotency, `prosecdef`/`proconfig`/grants, hosted smoke payload.
- [ ] **T3 (P0, human: ~1.5d / CC: ~2h)** — Delete durability — Add a
  persisted visit-delete outbox and retry it across relaunch/network recovery.
  - Surfaced by: architecture finding 6.
  - Files: local persistence snapshot/model, store maintenance/retry,
    repository delete result, focused relaunch tests.
  - Verify: offline delete, kill/relaunch, retry, dependent photo/shared state,
    remote acknowledgement, and no resurrection.
- [ ] **T4 (P1, human: ~1.5d / CC: ~2h)** — Map — Reframe first/repeat
  actions, visit-time input, forms, feedback, edit/delete, accessibility, and
  ticket cards.
  - Surfaced by: architecture findings 1 and 4 and test gaps 1, 2, 7.
  - Files: `Wander/Features/Map/MapScreen.swift`, existing design components,
    Map/store/navigation tests.
  - Verify: focused XTests plus current/smaller-phone screenshots; newest
    ticket visible in the compact first viewport; labeled “Check in again”
    outranks Directions; form has early “When?” and labeled submit.
- [ ] **T5 (P1, human: ~1.5d / CC: ~2h)** — Feed/notifications — Emit one
  visit-keyed event for every explicit check-in, cascade it on delete, keep
  legacy events readable, and enforce current/historical/import/backfill
  publication rules without Feed media.
  - Surfaced by: architecture findings 2, 8, and 9.
  - Files: new Supabase migration, SQL tests, Feed DTO/projection tests,
    `scripts/supabase-smoke-test.mjs`.
  - Verify: pgTAP/hosted metadata and smoke tests; first/repeat exact counts,
    push matrix, delete cascade, legacy projection, no media field.
- [ ] **T6 (P2, human: ~1d / CC: ~75min)** — Product surfaces — Replace
  product-status Been copy across Profile, calendar, imports, Settings, Streak,
  Discover, mockups, and accessibility.
  - Surfaced by: scope audit and code quality findings 4-5.
  - Files: the 17 audited app files and matching contract tests.
  - Verify: semantic residual scan and focused navigation/parser tests;
    primary Profile count uses visit rows with unique places secondary;
    populated calendar days open tickets; import confirms the check-in date.
- [ ] **T7 (P2, human: ~4h / CC: ~40min)** — Ticket performance — Group
  activity projections and lazy-render existing cards.
  - Surfaced by: performance findings 6 and 8.
  - Files: Map activity presentation, store projection helper, performance
    fixtures/tests.
  - Verify: 100/1,000-visit local fixture and smooth manual QA; log baseline
    Profile request count/latency for the follow-up.
- [ ] **T8 (P1, human: ~1d / CC: ~2h)** — Validation — Close the eight test
  gaps and run the complete suite, hosted smoke where required, and visual
  accessibility matrix.
  - Surfaced by: test review.
  - Files: `WanderTests/`, Supabase tests, smoke script, QA artifact.
  - Verify: full `xcodebuild test`, SQL/smoke result, two-size screenshots,
    VoiceOver/Dynamic Type/Reduce Motion checklist, and loading/empty/error/
    queued-state coverage.

## NOT in scope

- Persisted `been` → `check_in` rename: high compatibility cost with no user
  value in this release.
- New Ticket model/table/repository: duplicates `place_visits`.
- Live presence/geofencing: changes rec.me into a location product.
- Gamification/redemption/venue-issued tickets: conflicts with trusted place
  memory positioning.
- Per-check-in privacy: existing parent visibility remains the contract.
- Per-check-in sharing: existing place sharing and shared-visit context remain
  the contract.
- Feed photos: private media requires a separate authorized hydration design.
- Batch Profile hydration and server paging: tracked as a measured performance
  follow-up in
  [REC-145](https://linear.app/recme/issue/REC-145/measure-and-optimize-profile-check-in-hydration-and-long-history),
  not bundled into this rebrand.
- New tab or dedicated ticket wallet: the map, place activity, Feed, and
  Profile already own discovery.
- Historical Feed burst: old repeat visits are not backfilled into current
  follower feeds.
- TestFlight/release work: requires a separate explicit release request.

## TODO decisions

Two follow-ups were considered independently:

1. Rename persisted `been` values after old-client sunset. Recommended choice
   selected: **skip**. Stable internal values are harmless and a vague cleanup
   TODO would create migration pressure without product value.
2. Add per-check-in privacy. Recommended choice selected: **skip**. It is a new
   privacy product contract, not a required part of repeat check-ins.

`TODOS.md` receives no new item.

## iOS design review

The requested `/ios-design-review` inspected the existing experience using a
signed instrumented build on a connected iPhone 15 Pro, followed by the
workflow’s simulator/source fallback after the phone became locked and then
unavailable. The fallback captured the Add visit form, place activity,
Profile, Profile calendar, and import candidate on an iPhone 17 Pro Max and
compact iPhone 17e.

All recommended design choices were selected:

1. Count check-in records, not unique places, in Profile’s primary green
   number. Show unique places as secondary context.
2. Make a labeled “Check in again” the primary place-page action. Do not make
   Directions or an unlabeled plus more prominent.
3. Title the form “Check in at [place]”, move “When?” early, remove the
   redundant Visit/Been/Wanna selector in check-in mode, and label submit.
4. Reduce oversized map/header chrome so the newest ticket appears in the
   compact first viewport.
5. Use only subtle ticket cues such as notches and a date stamp. Do not add
   fake transport, admission, QR, barcode, price, or redemption language.
6. Make calendar summaries and drill-downs check-in based. Selecting a
   populated day opens its tickets and announces the count accessibly.
7. Rename import actions to “Check in” and “Wanna go”; imported check-ins open
   the standard form and confirm the date instead of silently recording now.
8. Specify loading, empty, error, queued/offline, Dynamic Type, VoiceOver,
   Reduce Motion, and color-independent states before ship validation.

The complete local report and screenshot set are:

- `/Users/ryanlieblein/.gstack/projects/joelipshutz-wander/ios-design-review-2026-07-24.md`
- `/Users/ryanlieblein/.gstack/projects/joelipshutz-wander/ios-design-review-2026-07-24-screenshots/`

Review status is **DONE_WITH_CONCERNS**: the simulator/source design review is
complete, but real-device screenshot, accessibility tree, Dynamic Type,
VoiceOver, Reduce Motion, and color-filter checks remain required before
shipping implementation.

## Engineering review completion summary

- Step 0: complete cross-surface scope accepted after rejecting a parallel
  Ticket model and unrelated infrastructure scope.
- Architecture Review: 9 issues found, 9 recommended options selected.
- Code Quality Review: 2 issues found, 2 recommended options selected.
- Test Review: diagram produced, 8 grouped gaps identified.
- Performance Review: 3 issues found; 1 bounded fix selected here and 2
  infrastructure changes split into one measured follow-up.
- NOT in scope: written.
- What already exists: written.
- TODOS.md updates: 0 items added; 2 candidates skipped.
- Failure modes: 0 critical silent gaps after planned coverage.
- Outside voice: 9 concerns found, 9 recommended resolutions selected.
- Parallelization: 3 parallel lanes after 1 sequential foundation.
- Lake Score: 18/18 recommendations chose the complete option.
- Unresolved decisions: 0.
- iOS Design Review: 5 existing screens inspected at 2 simulator sizes, 8
  recommended design decisions selected, real-device accessibility validation
  retained as a pre-ship requirement.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | NOT RUN | Optional for this product reframe |
| Codex Review | `/codex review` | Independent 2nd opinion | 1 | CLEAR (local fallback) | 9 concerns, 9/9 resolved |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR (PLAN) | 22 findings/test groups, 0 critical gaps |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | NOT RUN | Separate `/ios-design-review` completed via simulator/source fallback; real-device validation remains |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | NOT RUN | Not required for this native product reframe |

**VERDICT:** ENG CLEARED — implementation-ready architecture and task graph;
iOS simulator/source review completed with all recommendations selected.
Real-device accessibility validation remains a pre-ship requirement.

NO UNRESOLVED DECISIONS
