# Joint check-ins: implementation blueprint

REC-566 · Engineering pass requested September 21, 2026 · Current-main baseline `8890e5a`

This makes the [product and compatibility contract](engineering-plan.md) buildable. Joe requested the feature, then an engineering plan first. No feature code or database migration is included in this planning revision. The existing [85-case matrix](test-plan.md) remains the acceptance contract.

## Scope and current-main check

Reuse Shared Visits, owned `place_visits`, `feed_events`, existing engagement tables, existing visibility predicates, the local sync queue and `ActivityPostcardView`. No new messaging service, background infrastructure, historical conversion or general feed redesign. This necessarily touches more than eight files because server identity, native sync, shared rendering and profile timelines must agree; reducing it to a face-pile-only patch would leave duplicate threads and stale profile activity. Implement one coherent feature in a sequential lane.

Current main has advanced from `fb1bad2` to `8890e5a`. The intervening changes cover Home Screen naming, Featured/rating display and one-sided place-plan invitations. They do not implement joint check-ins or change the Shared Visits contracts. Merge them before implementation and retain the newer rating fallback and smoke suite registration. `TODOS.md` contains no prerequisite specific to this feature; REC-566 remains its work record.

Three integration facts matter:

1. `WanderLocalStore.syncVisit` currently calls `saveCheckIn`; `retryPendingSharedVisitInvites` waits for the saved visit/photos and separately calls `setSharedVisitInvitees`. A joint draft must be durable before the first sync call, otherwise it publishes as a solo event before the shared-audience contract exists.
2. `ProfileActivityPresenter` builds personal activity from visits, and `ProfileActivityRow` is a compact row reused by profile history. Merely changing the feed renderer will not update those surfaces.
3. `SupabaseFeedRepository` returns authorized text first and hydrates `activity_media` separately. Preserve that latency behavior; do not wait for ten people’s signed image URLs before showing the card.

## 1. Identity and additive schema

**Engineering refinement:** give the shared conversation its own row in the existing `feed_events` table at creation. Do not reuse and later retire the starter’s personal visit event. This supersedes that one identity detail of the first plan; it preserves the product behavior while removing a risky close-and-replace operation.

```text
shared_visit_groups (version 2, lifecycle/revision, one occasion)
    |
    +-- feed_events.shared_visit_group_id ---- one canonical conversation
    |       type=place_been, visit_id=NULL      likes/comments use this ID
    |
    +-- participants: starter -> owned visit -> personal visit event
    +-- participants: Joe     -> owned visit -> personal visit event
    +-- ... up to ten occupied slots

active + authorized -> project one group card, suppress member events in Feed
detach/close        -> personal visits/events remain, no copied conversation
```

Use the following additive changes in one reviewed migration (choose its timestamp at implementation time):

| Table | Change | Invariant |
| --- | --- | --- |
| `shared_visit_groups` | `model_version smallint NOT NULL DEFAULT 1 CHECK (model_version IN (1,2))`; `revision bigint NOT NULL DEFAULT 1`; nullable `closed_reason` | Old rows are v1; v2 creation is explicit; closure is permanent. Existing `cancelled_at` is the terminal timestamp. |
| `feed_events` | Nullable `shared_visit_group_id uuid REFERENCES shared_visit_groups(id) ON DELETE CASCADE`; partial unique index on nonnull group ID | Exactly one canonical event per group. Canonical events have `event_type='place_been'` and `visit_id IS NULL`, retaining required place/parent subject fields. |
| `shared_visit_participants` | Nullable `retained_visit_id` for detach/rejoin/private-save provenance; nullable `consent_version`; use existing generation/status/revision | Provenance never counts as accepted membership; active `visit_id` remains unique. No duplicate visit on reinvitation. |
| New `joint_check_in_operations` | `(actor_user_id, request_id)` primary key; group FK, operation kind, generation/expected revision, payload hash, committed result and timestamp; RLS with no direct client policies | All v2 operations use a caller-bound ledger. Keep `shared_visit_operations` unchanged: its existing unique `(participant, generation, type)` and accept-only constraint cannot represent repeated group edits safely. |
| `activity_comments` | Nullable client request UUID plus partial uniqueness on `(author_user_id, client_request_id)` | A retried comment is one comment; reusing a key for a different activity/body is a conflict, not a second write. Existing comments unchanged. |
| Native/hosted feature registry | `joint_check_ins_v2`, bundled/global default off | Gate creation of new v2 groups; never gate reading or closing already-created v2 groups. |

The current `feed_events_subject_check` permits a Been event without `visit_id`; add a narrow constraint that a nonnull group binding requires that shape. Keep `feed_events_explicit_visit_unique_idx` unchanged for personal events. The group itself retains `source_visit_id`. Do not add a cyclic group→event→group foreign key: resolve the canonical event through the indexed unique group binding. No new standalone-post table is needed. The small v2 operation ledger is not a second invitation service: it records transactional retry outcomes for the same groups. Write the completed outcome in the same transaction as its effects; a failed transaction leaves neither partial effects nor a started ledger row.

Server helpers must distinguish (a) canonical group events, (b) member personal events and (c) ordinary legacy events before applying legacy source visibility. A closed canonical event can never fall through to a readable parent save. Group deletion cascades its canonical discussion according to existing account/data-retention rules; it must not delete other members’ independent saved visits.

For nonowner detach and starter closure, retain existing personal events at their original timestamps; their independent conversation starts empty unless it already had engagement from an earlier detached period. A child event that has received standalone engagement never changes its conversation target again. The shared tile explicitly carries its group conversation ID, so it can coexist with a separately reachable old standalone discussion without another feed card.

## 2. Transaction and RPC contracts

Use named v2 RPCs, not ambiguous overloads. Names below are the proposed public contract; pin `search_path`, explicitly choose SECURITY DEFINER, revoke public/anonymous execute and grant only the narrow authenticated operations. Read all earlier definitions before wrapping any legacy endpoint. Extend hosted smoke assertions for function metadata and grants.

| RPC | Request | Response / behavior |
| --- | --- | --- |
| `save_joint_check_in` | Existing place/parent/attributes/visit/historical-want payloads + stable operation UUID + up to nine invitee IDs + consent version | Atomically use the owned-check-in core, create v2 group + canonical event + starter membership + pending invites/outbox. Return personal save result plus group/event/revision. Reject conversion of an already-published unrelated visit. |
| `set_joint_check_in_invitees` | Group ID, expected group revision, exact invitee set, operation UUID | Owner-only reconciliation; never change another contribution. Count owner + pending + accepted under the group lock; removed acceptors detach. New generations require new consent. |
| `accept_joint_check_in` | Participant ID, generation, snapshot revision, operation UUID, consent version, optional own note/rating/answers and own save IDs | Validate current caller/lifecycle/privacy before replay. Append or relink one owned visit, preserve an existing parent save’s metadata, inherit its visibility and recompute chronological summary. Return authoritative owned save/visit + group revision. No source-photo copying in v2. |
| `save_joint_invitation_privately` | Same invitation identity and personal draft/operation ID | Atomically decline this generation and save/reuse a private visit, with retained provenance but no membership, alias or group attribution. Never broaden existing privacy. |
| `leave_joint_check_in` | Group ID, expected revision, operation UUID | Detach caller’s accepted contribution; owner action closes instead. Return lifecycle result and surviving visit/event IDs. |
| `joint_check_in_contexts` | Up to 50 visit IDs, or explicit canonical activity IDs in a distinct typed request | Authorized mapping + deduplicated group DTOs for profile/history/detail; absent or closed mapping is explicit, never interpreted as “safe to use cached group”. |
| `followed_feed_v2` | Existing keyset cursor, bounded limit, include-Featured value | Legacy and canonical v2 rows in one stable ordered page. Resolve candidate canonical IDs before LIMIT. No member duplicates. |
| `activity_detail_v2`, `activity_media_v2`, `activity_engagement_summaries_v2`, `place_activity_engagement_summaries_v2` | Existing identifiers/bounds | Resolve active mappings, apply v2 audience rules and return canonical identity with consistently filtered content/counts. Ordinary v1 events keep v1 semantics. |
| `activity_comments_v2`, `set_activity_like_v2`, `add_activity_comment_v2` | Existing args; new comment adds stable request UUID and discussion-consent version | One canonical thread; idempotent set-like/comment creation; current authorization and author block filtering. An unsupported consent version fails before writing. |

Keep owned-comment deletion usable for its author even if the conversation became inaccessible; do not require access to the whole discussion to remove one’s own content. Return a minimal deletion result when the author can no longer read a summary. This prevents leaving/blocking from trapping an author’s prior comment.

Legacy mutation RPCs reject a v2 group/member/canonical event with `joint_check_in_upgrade_required`, including invitation edits and engagement. Legacy social feed/detail/media readers exclude unsupported v2 projections; never return a half-populated owner-only shared thread. Owned ordinary note/photo edits and deletes continue to work with lifecycle reconciliation. Place/date edits after acceptance require the explicit detach/close path. New readers support v1 and v2; absence of the new RPC permits legacy fallback only for an exact missing-function response and only for operations with no v2 draft/identity. Auth, timeout and decoding errors are not capability detection.

The creation feature flag is checked remotely. A device override may expose UI for testing but is not authorization to bypass the server rollout flag. Already-committed create replay and all reads/accept/leave/close for existing v2 groups remain valid when new creation is disabled. An uncommitted v2 draft stays pending with an explicit unavailable message; never fall back to publishing it as legacy.

### Atomicity, locks and errors

At create, one transaction covers the personal save, group, canonical event, pending members and notification outbox. The intermediate personal feed event is never observable as a separately published social post. Preserve the existing `app.explicit_check_in` suppression of compatibility parent events.

At accept/manage/leave/close, lock affected groups in ID order, participant rows in ID order, then owned parents/visits. Audit legacy parent privacy, block and delete entry points that invoke triggers: they must prelock affected v2 groups before taking parent/visit locks, or use a documented bounded whole-transaction deadlock retry. A client must never retry only the second half of an operation. Existing row locks, unique constraints and transactions supply the mechanism; no distributed lock service.

Distinguish transport retry, stale generation/revision, capacity, removed/closed, privacy, ownership and upgrade-required errors in one native mapping. Persist typed drafts through retryable errors. An optimistic pending invitation is never inserted into an accepted-only group projection. A malformed v2 response fails closed rather than silently decoding as a solo legacy activity.

## 3. One typed projection and native integration

Add a small value model, `JointCheckInProjection`, with group ID, canonical event ID, revision, occasion date, readable contributions and viewer permissions. `JointCheckInContribution` contains participant/visit IDs, `ProfileShell`, own optional rating/note, authorized media references and edit permission. No entire private `LocalUserPlace` or invitation snapshot should be serialized as a contribution. Pending management rows are a different payload.

Carry optional joint data through `RemoteFeedActivityDTO` → `FeedActivity` → `ActivityEngagementContext`, with default nil for legacy fixtures and stored payloads. `FeedActivity.id` is the canonical event ID for v2. Keep `event_type=place_been`, so the existing ticket vocabulary remains stable; the explicit joint payload identifies the presentation. Prevent `FeedPresentation.groupedActivity` from absorbing a canonical joint card into its unrelated 30-minute actor/place bundle.

| File/area | Concrete work |
| --- | --- |
| `Wander/Services/RepositoryProtocols.swift` | Typed group/contribution DTO boundaries, versioned invitation/draft/result, stable operation/request IDs, repository methods with legacy-compatible defaults. |
| `Wander/Services/Remote/SupabaseRepositories.swift`, `SupabaseDTOs.swift` | Explicit v2 calls and decoding, canonical IDs, typed errors, bounded context hydration and preserved staged text/media response. |
| `Wander/App/WanderBackend.swift`, `FeatureFlags.swift` | Route capability-aware operations; register the creation flag in the existing platform. Do not use a one-off UserDefaults flag. |
| `Wander/Services/WanderLocalStore.swift` | Persist joint intent before `syncVisit`; route first publication atomically; retain account-scoped operation IDs; apply server-owned parent metadata/summary instead of legacy acceptance replacement; invalidate viewer projections. |
| `PendingSharedVisitInvite` and `Wander/Services/WanderStorePersistence.swift` | Add an operation-kind/version discriminator with old records decoding as legacy reconciliation. Freeze the first-create payload for an in-flight operation; queue later edits separately. Do not invent a second sync engine. |
| `Wander/Features/Map/MapScreen.swift` | New joint-draft selection before first save; v2 accept/private-save forms; fixed-occasion detach/close confirmation; use existing edit/upload flows for owned content. |
| `Wander/Features/SharedVisits/SharedVisitComponents.swift` | Nine invitee seats for a new group, reserved pending-seat display, existing v1 picker limit unchanged, consent and terminal/error states. |
| `Wander/Services/FeedModels.swift`, `ActivityEngagementModels.swift` | Stable joint identity and pure presentation ordering; same canonical context on every surface. Keep own visit stats independent. |
| `Wander/Features/Activity/ActivityEngagementViews.swift` | Extend `ActivityPostcardView` with accepted face pile, attributed rating/note rows, expansion and one action row; optional profile-subject ID selects the first contribution. Reuse comments, with shared-audience notice. |
| `Wander/Features/Feed/FeedScreen.swift` | Consume canonical DTO and reuse postcard; batch group media/engagement, retain normal feed loading/retry behavior. |
| `Wander/Features/Profile/ProfileOwnerHome.swift`, `ProfileScreen.swift` | Add optional resolved joint projection to activity items. Hydrate visible page visit IDs in one batch. Render joint items using the same postcard in owner, other-profile and See more activity; retain compact rows for legacy/solo items. Count each owned visit once. |
| Place history/detail, share and notification routing call sites | Resolve canonical context from visit ID; route through the same postcard/conversation. Externally publish venue-only default; never source hidden identity from a stale parent actor. |

Do not change every personal visit model into a group object. Keep persisted membership/context metadata minimal and viewer-scoped; readable contributions are server projections. Clear them on account switch and invalidate on group edits, acceptance, privacy, follows, blocks, deletion and visibility-related errors. A missing mapping after refresh must remove stale joint UI, not leave cached notes visible.

The feed orders starter then acceptance order. Profile activity passes its subject ID to a pure ordering function and shows that contribution first. Header attribution remains stable among readable contributors. User-facing actions edit only the authenticated user’s contribution, even while viewing another person’s profile. Tests must include the profile subject being the tenth accepted person, not only Joe at position two.

## 4. Read pipeline and performance constraints

```text
eligible legacy events + readable v2 memberships
  -> map active memberships to canonical event IDs
  -> filter unreadable/closed/blocked groups and hidden profile subjects
  -> DISTINCT canonical ID
  -> stable keyset page (occurred_at, event ID)
  -> one batched DTO projection + engagement summaries
  -> publish text card
  -> one authorized media batch/signing stage
  -> update artwork in place, retaining ID/order/scroll position
```

No per-person network request or query in the card render path. Bound initial page size to the existing 50 maximum, group size to ten and context lookup to 50 visit IDs. Derive every visible count from the same filtered rows as detail; pending/hidden people cannot contribute to overflow. Store canonical ID in the cursor and do not use acceptance time as the sort key. Keep the personal history occasion fixed; unrelated same-place groups remain separate.

Use indexes for the unique group event, active group/member and visit lookup. Explain the real query on a synthetic multi-page fixture, with followers overlapping across all ten participants. Record request count, response size, first-text latency and scroll performance against the existing feed. The existing staged media path is a regression gate; an image signing outage must not block all text cards or expose a fallback image from an unreadable contributor.

## 5. Implementation order and test gates

Implement T1 → T2 → T3 → T4 → T5 from the engineering plan, with these concrete checkpoints. Keep one worktree lane; the same migration, repositories and shared model files would conflict under parallel implementation.

| Checkpoint | Code and matching tests | Exit gate |
| --- | --- | --- |
| A. Identity/lifecycle | Additive schema and create/accept/manage/leave/private-save core; fixture helpers in new `supabase/tests/joint_check_ins.sql` | v1 unchanged; personal/group event IDs separate; operations atomic; no duplicate visit or capacity overflow; secure replay; privacy metadata preserved. |
| B. Reads/engagement | V2 feed/context/media/discussion + legacy gates; extend hosted smoke with new RPCs and metadata assertions | One canonical page identity; union discussion and per-contribution filtering; closed anchor never readable; no legacy endpoint bypass. |
| C. Sync/model | Native DTOs/backend, durable intent/outbox, canonical context and error mapping | `RemoteRepositoryTests` and `WanderStoreTests`: first sync never solo; lost responses/restart/account switch safe; v1 payloads and old queues decode unchanged. |
| D. Native surfaces | Shared postcard, profile integration, invite/editor/discussion/share states | `FeedModelsTests`, `ActivityEngagementTests`, profile presenter tests and UI fixtures demonstrate feed/profile/detail parity and subject-last ordering. |
| E. Release evidence | Full unit/UI run, exact matrix, migration smoke, multi-connection race harness, compact/standard/iPad screenshots and performance comparison | No unresolved privacy/identity/compatibility failures; flag-off preserves existing v2 reads; no production creation until server/client checks pass. |

```text
atomic publication      -> SQL V03/V08 + store C + UI pending recovery
parent-preserving join  -> SQL D01-D08 + store summary/privacy assertions
capacity/replay         -> two-connection L02-L07 (sequential pgTAP is insufficient)
projection/discussion  -> SQL P01-P14/E01-E10/F01-F10 + repository DTO tests
profile/card reuse     -> presenter U02/U03 + native U01-U10
rollout/old clients    -> real old RPC payloads R01-R08 + flag platform tests
```

For the hosted smoke, do not use a generic last-login Supabase session. Generate the existing rollback-only suite with the supported `--write-linked-sql`, `--migration-preview` and `--migration-test` options, then execute that file through the isolated Astir launcher after reading the account registries and verifying the target. Register the suite in `scripts/supabase-smoke-test.mjs`; preserve its savepoint isolation so a migration-preview pgTAP plan does not contaminate subsequent suites. Generation alone is not a test pass. Race checks require an isolated test database with two connections; do not simulate them by sequential calls or mutate production to demonstrate a race.

For native tests use `.tools/ios-work.py` with existing reserved standard/compact/iPad devices. Focused tests during development, then the repository-required full unit/UI run before implementation handoff. No Xcode build is needed for this docs-only revision. Save final meaningful screenshots/results and report any unexecuted matrix case rather than claiming all 85 passed.

## 6. Failure handling and rollout

| New path | Real failure | Required response and test |
| --- | --- | --- |
| Atomic create | Response lost after commit | Retry stable operation; one canonical event; preserve draft until authoritative success (V08, C). |
| Accept/private save | Parent became Self/deleted or invite revision changed | No widening/resurrection; typed privacy/stale result; preserve typed note (D02/D07/L08). |
| Member edit/close | Race with accept or lock conflict | Whole transaction commits one legal state or retries; no partial detach (L05). |
| Group context hydration | Mapping removed while profile is open | Remove cached joint projection, keep authorized personal entry; no hidden content fallback (P09). |
| Feed/media | Signing/network fails | Keep authorized text and neutral artwork; retry media without moving the post (F06/F08). |
| Comments | Server commits, connection drops | Same request key yields same owned comment; no duplicate notification (E04). |
| Old client | Accepts/edits a v2 target | Explicit upgrade error before any write; legacy targets still work (R01-R03). |
| Rollback | New creation flag off with accepted v2 data | Continue v2 reads and lifecycle; pending uncommitted v2 drafts never downgrade to v1 (R04-R06). |

Deploy the additive backend with creation off; verify grants and smoke; deliver the capable app through the existing TestFlight pipeline; enable an internal cohort only after the matrix and native evidence pass. Then expand through the same flag platform. No new distribution pipeline. A kill switch stops new creation, not support for existing group records. Preserve the migration/version data when rolling forward or back; never transform v2 groups into legacy conversations.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
| --- | --- | --- | --- | --- | --- |
| Engineering | Joe: “do an eng plan first” | Make the accepted direction executable | 1 refresh after initial review | Clear for implementation planning | Separate group/personal event identity; atomic first sync; profile row integration; explicit RPC and testing gates. |
| Code quality | Same pass | Reuse and error handling | 1 | Included | Typed optional projection, one postcard renderer, existing outbox; no extra service or broad cleanup. |
| Tests | Same pass | Cover each new path | 1 | Specified, not executed | Existing 85 cases retained; added exact layer/runner mapping and independent connection requirement. |
| Performance | Same pass | Preserve feed latency | 1 | Included | Canonicalize before paging, batch context, preserve staged text/media delivery. |
| Independent review | Previous completed pass | Privacy/lifecycle challenge | 1 with follow-up | Incorporated | Existing findings retained; the identity refinement removes the close-and-replace source event complexity. |

Scope: complete requested joint experience using the existing subsystem. No unrelated TODOs added. Failure paths have explicit errors and assigned tests; implementation is still required. Sequential implementation; no parallelization benefit in the shared core. No new product decision is needed under Joe’s delegated edge-case/migration authority.

**VERDICT:** Engineering plan ready to build in checkpoints A–E. This document does not claim implemented behavior or passing v2 tests.

NO UNRESOLVED DECISIONS
