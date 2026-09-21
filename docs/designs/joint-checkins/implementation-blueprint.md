# Joint check-ins: implementation blueprint

REC-566 · Engineering pass requested September 21, 2026 · Current-main baseline `8890e5a`

This makes the [product and compatibility contract](engineering-plan.md) buildable. Joe requested the feature, then an engineering plan first, and explicitly requested the linked `plan-eng-review` skill. No feature code or database migration is included in this planning revision. The [88-case matrix](test-plan.md) is the acceptance contract; the exact-skill pass added three deletion/rejoin/composer cases.

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
| `feed_events` | Nullable `standalone_engagement_started_at timestamptz`, monotonic once set for a v2 personal event | Remember that the personal discussion has been used even after its last like/comment is deleted. Never infer this permanent identity from the current engagement count. |
| `shared_visit_participants` | Nullable `retained_visit_id` for detach/rejoin/private-save provenance; nullable `consent_version`; use existing generation/status/revision | Provenance never counts as accepted membership; active `visit_id` remains unique. No duplicate visit on reinvitation. |
| New `joint_check_in_operations` | `(actor_user_id, request_id)` primary key; group FK, operation kind, generation/expected revision, payload hash, committed result and timestamp; RLS with no direct client policies | All v2 operations use a caller-bound ledger. Keep `shared_visit_operations` unchanged: its existing unique `(participant, generation, type)` and accept-only constraint cannot represent repeated group edits safely. |
| `activity_comments` | Nullable client request UUID plus partial uniqueness on `(author_user_id, client_request_id)`; v2 creates also write a receipt to `joint_check_in_operations` | Live-row uniqueness alone does not survive deletion. Keep the operation receipt with comment ID and payload hash, never a duplicate body; a deleted comment returns terminal `comment_deleted` on replay. Existing comments unchanged. |
| Native/hosted feature registry | `joint_check_ins_v2`, bundled/global default off | Gate creation of new v2 groups; never gate reading or closing already-created v2 groups. |

The current `feed_events_subject_check` permits a Been event without `visit_id`; add a narrow constraint that a nonnull group binding requires that shape. Keep `feed_events_explicit_visit_unique_idx` unchanged for personal events. The group itself retains `source_visit_id`. Do not add a cyclic group→event→group foreign key: resolve the canonical event through the indexed unique group binding. No new standalone-post table is needed. The small v2 operation ledger is not a second invitation service: it records transactional retry outcomes for the same groups. Write the completed outcome in the same transaction as its effects; a failed transaction leaves neither partial effects nor a started ledger row.

Server helpers must distinguish (a) canonical group events, (b) member personal events and (c) ordinary legacy events before applying legacy source visibility. A closed canonical event can never fall through to a readable parent save. Group deletion cascades its canonical discussion according to existing account/data-retention rules; it must not delete other members’ independent saved visits.

For nonowner detach and starter closure, retain existing personal events at their original timestamps; their independent conversation starts empty unless it already had engagement from an earlier detached period. A child event that has received standalone engagement never changes its conversation target again. The shared tile explicitly carries its group conversation ID, so it can coexist with a separately reachable old standalone discussion without another feed card.

Set `standalone_engagement_started_at` in the same transaction as the first successful standalone like/comment on a v2 personal event, including a legacy engagement call while detached. Unlikes, comment deletion, member removal and rejoin never clear it. Rejoin and standalone engagement must serialize identity resolution with the same group/event lock order: either the personal write wins and permanently pins the personal discussion, or rejoin wins and a stale personal-target write fails. No historical backfill is needed because published v1 events cannot be converted to v2. Add an inline state diagram beside the SQL conversation resolver.

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
| `activity_comments_v2`, `set_activity_like_v2`, `add_activity_comment_v2` | Reads may resolve an active alias. Writes use the exact resolved conversation ID shown in the composer/action context; new comment adds stable request UUID and discussion-consent version | Never redirect a write to a different discussion. Return `activity_context_changed` if the supplied personal target has become an alias; preserve the draft, refresh and require resubmission after the actual discussion/audience is shown. Current authorization and author block filtering apply. |

Keep owned-comment deletion usable for its author even if the conversation became inaccessible; do not require access to the whole discussion to remove one’s own content. Return a minimal deletion result when the author can no longer read a summary. This prevents leaving/blocking from trapping an author’s prior comment.

For joint comments, use the existing proposed v2 request ledger with operation kind `comment_create`. After current authorization and payload validation, replay resolves its committed comment ID. If the comment was deleted, return `comment_deleted` without inserting anything or returning deleted text. The receipt survives individual comment deletion and is removed with the owning account/group under existing retention rules. Keep the request UUID bound to the originally displayed conversation; refreshing after `activity_context_changed` never silently rebinds and resends the old request. A fresh explicit submission gets a fresh request ID. Ordinary v1 comment creation keeps its existing behavior; do not claim deletion-safe replay for legacy calls.

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

## Exact-skill review, September 21

Review target: this blueprint plus the product contract and acceptance matrix, on `296a82a`, with current main `8890e5a` already merged. Invoked from Joe's exact link: `/Users/joelipshutz/gstack/.agents/skills/gstack-plan-eng-review/SKILL.md`. Its referenced section was resolved to `/Users/joelipshutz/gstack/plan-eng-review/sections/review-sections.md` because the generated `.agents` copy has no sibling section file. All four sections were read and evaluated.

Scope remains the full requested feature. Joe's earlier “go” and delegated edge-case/migration decisions authorize these implementation refinements; no migration policy, audience policy or user-facing scope was reversed. The 8+ file complexity trigger was evaluated: fewer services is desirable, but a face-pile-only patch cannot deliver one conversation and profile parity. Keep the existing five sequential tasks and no extra service. The existing “What already exists” and “NOT in scope” sections in [the product contract](engineering-plan.md) remain in force. No unrelated TODO was proposed.

### Findings resolved in the plan

Line references below identify the pre-review blueprint at `296a82a`, so the motivating quotes remain auditable after edits.

1. **[P1] (confidence: 9/10) blueprint:52, permanent personal discussion.** “A child event that has received standalone engagement never changes its conversation target again.” The schema at lines 41–45 lacked a durable historical marker. Existing `set_activity_like` physically deletes unlikes (`20260810155601_activity_engagement.sql:220`), and `delete_own_activity_comment` physically deletes comments (`20260812054719_delete_own_activity_comment.sql:23`). Current-row counts cannot prove that a discussion was ever used. Recommendation [Layer 1]: add one monotonic timestamp to the existing event and serialize first engagement with rejoin. Tradeoff: one field and write guard, instead of a new discussion table; no history rewrite. Covered by L18 and T1/T2.
2. **[P1] (confidence: 9/10) blueprint:45, deletion-safe comment retry.** “Nullable client request UUID plus partial uniqueness on `(author_user_id, client_request_id)`.” Deleting the comment also deletes that unique key, so a delayed retry could recreate it. Recommendation [Layer 1]: retain only its ID/hash in the already-planned v2 operation ledger and return a terminal deleted result. Tradeoff: receipt retention for the group lifetime; avoids another ledger and does not retain deleted body text. Covered by E11 and T2/T3.
3. **[P1] (confidence: 8/10) blueprint:67–68, stale composer target.** “Resolve active mappings” and “Existing args” did not state that writes must use the exact discussion the person saw. A compose → rejoin → submit race could otherwise route personal text to the group. Recommendation [Layer 1]: aliases may resolve reads; writes reject a changed conversation target, retain the draft and require an explicit refreshed submission. Tradeoff: a rare extra confirmation when the destination changed; protects the approved audience contract. Covered by E12 and T2/T3/T4.

These are prospective implementation risks found in a plan, not reproduced defects in a shipped v2 feature. Existing v1 behavior remains unchanged.

### Code quality and performance result

Reuse the existing repository boundaries, sync engine, feature flag platform and postcard. The comment receipt reuses the planned request ledger. No new retry service, global feed rewrite, dependencies or duplicated profile renderer. The current staged-media path was verified in `SupabaseRepositories.swift:688–757`; repository tests for first text preceding slow media and neutral artwork on failure already exist at `RemoteRepositoryTests.swift:1395` and `:1468`. Keep those as regressions and extend them to joint payloads. No additional performance issue was found beyond the already-specified batched reads, canonicalization before paging, bounded groups and viewer-scoped invalidation. Latency and frame-rate claims require the implementation measurements in F06–F08.

### Test diagram and implementation coverage

Frameworks: XCTest/native UI tests and the existing pgTAP/rollback SQL runner. No LLM prompt change or eval suite is involved. Existing tests below were inspected, not rerun. Every v2 branch is still **PLANNED**, not tested.

```text
CODE PATHS / REQUIRED BRANCHES                  USER FLOW / CASES / EVIDENCE
save_joint_check_in + syncVisit
  |- v1 queue / flag off / fresh joint draft    choose people before publishing [V01-V04,R04-R06]
  |- auth / invalid data / capacity / commit   publish once, clear errors [V06,V08,L04,R07]
  '- restart / lost response / account switch preserve pending draft [L16-L17; ->E2E]
accept / private-save / exact-set / leave
  |- new parent / existing / Wanna / Self     keep personal data [D01-D08; ->E2E]
  |- pending / stale / terminal / replay      accept only current generation [L01-L08]
  |- leave / reinvite / close / restore       preserve visit and old discussion [L09-L15]
  '- concurrent standalone write + rejoin     permanent identity even at zero count [L18; ->E2E]
context / feed / detail / media projections
  |- v1 / canonical / personal alias / closed correct conversation per surface [E01,E06,E09]
  |- follow / mutual / private / blocked      no hidden names, totals or photos [P01-P14]
  |- subject unreadable / accepted tenth      profile eligibility and order [P02,U02-U03]
  '- empty / duplicate / page edge / timeout  one tile; text before media [F01-F10]
comment / like / author deletion
  |- current auth / consent / valid target   same shared conversation [E01-E03,E05,E07]
  |- same key / changed payload / deleted    no duplicate or resurrection [E04,E11]
  '- stale personal composer / lost access   draft retained; own deletion possible [E08,E12]
postcard / profiles / invitation forms
  |- 1 / 2 / 10 readable / missing fields    truthful attribution [U01-U04,U09-U10]
  |- expand / keyboard / navigate / retry    recover without double submit [L16,U08]
  '- large type / RTL / dark / small / iPad   native accessible layout [U05-U07]
legacy endpoints + rollout
  |- old read / old write / missing RPC       fail closed only for v2 [R01-R03,R07]
  '- creation disabled after commit          keep existing group usable [R04-R08]
```

Existing legacy behavior has edge/error assertions for owner-scoped queue persistence, exact-set replacement, stale-account results and blank metadata (`WanderStoreTests:5792,5865,5961,6648`), plus RPC fallback and media failure tests. These are useful regression foundations, not v2 coverage. V2 execution: **0/88 cases executed**, 88 specified. New plan gaps: L18, E11, E12; all now assigned. Add SQL tests in `supabase/tests/joint_check_ins.sql`, request/context tests in `RemoteRepositoryTests.swift`, recovery tests in `WanderStoreTests.swift`, and stale-composer/old-link UI fixtures in `WanderUITests`. SQL race cases use independent connections and assert no unintended rows/notifications.

For each new failure: L18 resolves to one locked conversation or a visible context error; E11 resolves to a terminal deleted receipt without insert; E12 preserves the draft and refreshes the audience. Their SQL/store/UI tests are required alongside the implementation. No failure is left with neither planned handling nor a planned test. Add inline diagrams at the conversation resolver, pending-operation state machine and shared projection ordering helper.

### Evidence, exclusions and execution

Official PostgreSQL guidance confirms consistent lock ordering and whole-transaction retry for deadlocks, and partial unique indexes as a native subset-uniqueness mechanism ([locking](https://www.postgresql.org/docs/17/explicit-locking.html), [indexes](https://www.postgresql.org/docs/15/sql-createindex.html)). No custom distributed lock infrastructure is needed.

Prior learnings applied: `shared-visit-ledger-accept-only` and `linked-smoke-preview-pgtap-isolation`. A separate Events-history lock-order learning names an unmerged migration absent from this checkout; it is **suppressed as a current-code finding**, and only belongs in a future pre-merge drift check. Confidence 4/10 for applicability here. Do not copy that other branch's locking design without reviewing its actual merge.

The exact skill's outside-voice preflight detected `under_codex`; this invocation therefore skipped nested Codex per its explicit instruction. The earlier independent reviewer remains historical evidence, not a new independent review. Local structured brain context was unavailable; source, current issue, plan, PR and project-scoped learnings supplied context instead.

Build feasibility check: `ios-work.py status` reported 38.1 GiB free against a 50 GiB build floor, zero running builds, one existing booted iPhone 17 Pro. This does not block planning/light coding, but native builds must wait for sufficient headroom; never bypass the helper or delete another task's files. No native tests or production changes were attempted in this review.

### Implementation Tasks

The five original tasks remain the build sequence; these are narrow acceptance refinements, not extra parallel workstreams:

- [ ] **T1/T2 (P1, human: ~2–4h / agent: ~1–2h)**: persist the standalone discussion marker and serialize rejoin with the first standalone engagement. Verify L18 with real two-connection ordering and old-link UI checks.
- [ ] **T2/T3 (P1, human: ~2–4h / agent: ~1–2h)**: retain comment creation receipts after deletion and expose terminal replay without deleted text. Verify E11, changed-payload conflicts and no repeated notification.
- [ ] **T2/T3/T4 (P1, human: ~2–4h / agent: ~1–2h)**: bind writes to the displayed conversation, preserve stale drafts and require explicit refreshed submission. Verify E12 across two devices/accounts as appropriate.

Sequential implementation, no parallelization opportunity in the shared core. No new tasks from performance; no unrelated `TODOS.md` edits. Scope accepted as already authorized; Architecture: 1 new gap; Code quality: 1; Tests: 1 stale-composer gap, with three new cases across the findings; Performance: 0 additional gaps. Critical unassigned failures: 0. Lake score: 3/3 refinements take the complete in-scope behavior.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
| --- | --- | --- | --- | --- | --- |
| Eng Review | Exact linked `plan-eng-review` | Architecture, quality, tests, performance | This invocation: 1 full pass | Clear for implementation | 3 plan gaps resolved: permanent standalone identity, deleted-comment receipt, stale composer target. |
| Test review | Same invocation | Branch/error/user-flow mapping | 1 | Specified; not executed | Diagram above; 88 named cases, 0 executed for v2. |
| Outside voice | Skill preflight | Independent challenge | 0 this invocation | Skipped: under Codex | Earlier independent pass retained as historical evidence only. |
| Design | Earlier preview inspection | Shared card/profile parity | 1 preview pass | Native QA pending | No new design review claimed by this invocation. |
| CEO / DX | Not invoked | No new product strategy or developer product | 0 | Not required | Existing user-approved scope retained. |

**VERDICT:** Engineering review complete; plan clear to implement. This is not an implementation, native test or production rollout pass. Native build headroom remains an execution prerequisite.

NO UNRESOLVED DECISIONS
