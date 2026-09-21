# Joint check-ins: one memory, individual contributions

REC-566 · September 21, 2026 · Source baseline `fb1bad2`

Joe approved the direction and delegated the edge-case and migration decisions. This is the implementation contract and an updated interactive preview, not a deployed feature. No production records were changed. Implementation and release validation remain to be done.

## Product contract

A new joint check-in has one identity, one feed card and one conversation. Ryan and Joe appear together only after Joe accepts. Each person owns their rating, note, photos and actual visit. On Joe’s activity the same card places Joe’s contribution first; on Ryan’s activity it places Ryan’s first. The attribution and conversation stay the same. A person’s stats count their own visit once, never the number of people in the group.

New groups support **10 people total**, including the starter and pending invitations. Pending invitations reserve seats but do not appear in the public-facing attribution, face pile or count. A group with only its starter renders as a normal single-person check-in while keeping its shared conversation identity and audience notice. Ratings and notes are optional; ratings use the existing 1–5 half-star contract, with no group average.

For two people show both contributions. For larger groups show three, with the profile subject first on activity, and expand to all visible participants in the card. The feed uses starter then acceptance order, breaking ties by participant ID. The profile only changes contribution order, never canonical ID, date or engagement. Face piles show up to three readable people and a readable overflow count. Hidden people never contribute to names, counts, avatar placeholders, photo totals or accessibility labels. Empty ratings are absent, not zero. Missing notes do not stop acceptance. Long notes expand in place rather than making ten full-length notes mandatory in the feed.

## Existing records: preserve them

**Keep every existing check-in, group, invitation, like, comment and deep link on the legacy behavior. Do not merge historical conversations.** Add a group version defaulting to legacy; only a joint check-in explicitly composed as a new joint check-in by a capable client uses version 2. This is an additive schema migration, with no historical content rewrite or date-based inference.

An older pending invitation remains a legacy invitation even when accepted after rollout. Existing groups keep their existing 20-person contract. Adding people to an already-published solo check-in follows legacy behavior in this phase; it does not silently convert comments to a different audience. The joint mode is chosen before first publication. Existing place/time lookalikes, separately logged visits and unrelated feed bundles never merge automatically.

Read-only live aggregate audit on September 21 found 25 groups, 19 uncancelled groups, 16 accepted participant rows, two pending invitations, and a largest occupied group of three. There were 21 linked activity events, five comments and six likes. These are database totals, including possible historical/test records, not counts of active customers. They prove there is existing engagement to protect; they are not a substitute for migration tests. See [audit queries](read-only-audit.sql).

Reasons: existing engagement belongs to a specific event and audience; old acceptance did not consent to shared comments; companion projections omit canonical identity; and timestamps cannot establish joint intent. Automatic conversion risks changing history for little immediate benefit. An explicit conversion tool is outside this release.

## What already exists and what to reuse

| Existing mechanism | Reuse / necessary extension |
| --- | --- |
| `shared_visit_groups`, participant generations, status transitions, operation ledger | Extend with an explicit version and a canonical event association; retain v1 semantics. Do not introduce a second invitation service. |
| Independent `place_visits` and their owned photos | Remain the source of personal history, edit permissions and statistics. Add only the association/projection needed for a shared card. |
| `activity_likes`, `activity_comments`, narrow engagement RPCs | Continue using one `feed_events.id` as the conversation key. Add v2 authorization and idempotent comment creation. Do not copy engagement between events. |
| `ActivityPostcardView`, `FeedModels`, engagement navigation | Extend with a typed joint payload and reuse the same component across feed, profiles, place history and detail. Avoid separate profile-only rendering logic. |
| Existing trust graph, block checks, private-profile rules | Evaluate for every contribution and media item at read time; never treat a group membership as permission to read someone’s private history. |
| Local invitation outbox, deterministic acceptance IDs and stale-account response checks | Extend for the versioned contract and server result; retain retry and account isolation. |
| Existing blank invitee metadata UI | Preserve it. The current app already starts the invitee’s note/rating blank; this is not a newly discovered UI bug. |

Source anchors: `20260714013000_shared_visits.sql`, `20260714022000_fix_shared_visit_acceptance_source.sql`, `20260714043000_manage_shared_visit_invitees.sql`, `20260714214500_shared_visit_copy_and_viewer_companions.sql`, `20260802044500_fix_shared_visit_check_in_deletion.sql`, `20260810155601_activity_engagement.sql`, `20260811044537_private_activity_visibility.sql`, `20260916171502_repeat_wanna_saves.sql`; `Wander/Services/RepositoryProtocols.swift`, `Remote/SupabaseRepositories.swift`, `WanderLocalStore.swift`, `FeedModels.swift`, and `Wander/Features/Profile/ProfileOwnerHome.swift`.

The existing `FeedActivityGroup` is a presentation bundle of individual events, not a joint check-in identity. The existing companions RPC can show pending people to the source owner and does not return other people’s notes/ratings; it must not be used as the v2 coauthor payload. The reusable invite-selection maximum of 20 must not be globally reduced, because unrelated invitation flows use it.

## Architecture and data flow

```text
New joint draft (client understands shared audience)
  -> v2 create transaction: source visit + group v2 + canonical feed event
  -> pending invitations (private to starter/invitee)
  -> v2 accept: authenticate + validate generation/revision + lock + commit
       -> independently owned visit (or relink surviving former visit)
       -> accepted membership + event association
       -> operation result + notification outbox

Owned visits ----> existing personal history / stats / chronological summary
       \--------> server projection of readable accepted contributions
                         -> canonical groups deduplicated BEFORE pagination
                         -> feed / subject activity / place history / detail
                         -> one canonical likes/comments conversation

Legacy groups ---> unchanged legacy paths, event IDs and conversations
```

Use the original source `feed_events.id` as the v2 canonical conversation anchor; store it once with a uniqueness constraint. Reuse the existing group ID, not a new unrelated post service. Event creation and group creation must be transactional: a v2 draft must not first publish a legacy event and change its comment audience afterward. The canonical event can project contributions from visible invitees even when the source contribution is not readable; v2 readers must therefore authorize the group projection explicitly instead of calling the legacy source-event predicate as the sole rule.

Represent `(group, user)` membership once, link each active visit to at most one active joint group, and retain the former participant-to-visit association privately when a person leaves. Unengaged child event IDs can resolve to the canonical conversation only while the viewer can read the active group and that association is active. On detach, the alias ends immediately: the child becomes an independent visit with its own engagement identity and does not acquire old shared comments. Once a standalone event has received likes/comments, its ID stays permanently bound to that standalone conversation, including after rejoining. Rejoin makes the feed tile explicitly target the canonical group event; visit detail/history offers the preserved standalone discussion separately. Never merge engagement or display a duplicate feed tile. Canonical links to closed groups return unavailable; never redirect them to another person’s visit.

When closure preserves the starter’s own visit (for example Self/private or detach-and-edit), its old canonical event cannot become the new solo conversation. In the closure transaction, retire the anchor from all read/engagement paths using its durable group association, clear its `visit_id` while retaining valid subject fields, and create a distinct standalone event for the surviving visit at its original date with empty engagement and no new notification. This respects `feed_events_explicit_visit_unique_idx` without reopening the canonical URL. A closed anchor with null `visit_id` must never fall back to legacy parent-place visibility. If the source visit was deleted, create no replacement. Preserve the group’s source-visit association and closed anchor for authorized lifecycle bookkeeping.

Group changes use server-generated revisions. Acceptance validates caller ownership, group version, lifecycle, generation, snapshot revision, eligibility and current privacy **before returning a cached operation result**. An authorized replay may return the original accepted result only while its membership/visit is still valid. A stale retry after removal or closure returns a terminal result without resurrection. Scope operation keys to caller, participant, generation and operation kind; validate payload consistency for retries.

Serialize capacity/lifecycle changes on the group row, then participants in consistent order, then personal-place/visit mutations in consistent order. Follow that ordering in accept, remove, cancel, block and delete paths. Use database uniqueness as the final guard. PostgreSQL row locks provide the native serialization mechanism; deterministic acquisition order and retrying a transaction aborted for deadlock/serialization are required ([PostgreSQL explicit locking](https://www.postgresql.org/docs/17/explicit-locking.html)). A capacity failure preserves the draft and explains that the group is full. Do not implement capacity with a client-only count.

The new payload includes canonical event ID, group ID/version/revision, readable contribution IDs, user summaries, note/rating/media, stable visit date and viewer permissions. Pending membership is a separate authorized management/inbox projection. Do not embed private snapshots, email/contact identifiers, private question answers, labels or arbitrary personal-place fields in the feed object.

## Saved places, privacy and discussion

**Preserve a saved place the invitee already has.** Today visibility is on `user_places`, and legacy acceptance overwrites that parent’s visibility, note/rating, attribution and attributes. The v2 path must not copy this behavior. Inherit an existing active saved place’s visibility; preserve its classification, attributes, source attribution and unrelated history. Append/relink the owned visit and recompute the existing chronological summary. An older joint visit must not replace a newer visit’s summary. Preserve Wanna history when moving to Been. Handle a tombstoned parent through the existing explicit restore/new-save policy; do not undelete it merely because an old request is replayed.

This release does not add per-visit visibility. An existing Self save cannot be widened by accepting. The invitation explains that the place is private and offers **Save privately** as a separate personal check-in (decline the invitation and save atomically, with no group membership or alias). Before choosing that terminal action, the person can separately change their place visibility in its established settings and review the still-pending invitation. After Save privately, that generation is terminal; later joining requires a new invitation and explicit consent. Keep private invitation-to-visit provenance so a retry or later reacceptance can reuse the surviving personal visit without duplicated stats; never expose that provenance as membership. New saved places can select Everyone/Friends; Self uses Save privately. Private profiles cannot join; they retain access to review/decline or save privately. This keeps the existing meaning of privacy without exposing all past visits or pretending a private entry is public coauthorship.

Everyone/Friends/Self are Astir’s labels, not anonymous public access. Current Everyone checks a follower relationship; Friends checks mutuals. For each viewer, render only accepted contributions whose parent place, user, visit and media remain readable under those rules. On a profile, the subject’s own contribution must be readable for the shared card to appear there. If only one is readable, show a single-person card without hidden membership hints. Changes of follow relationship or visibility invalidate projections and signed-media access.

**The shared conversation has a shared, changing audience:** an authenticated viewer who can see any accepted contribution can read/react/comment, subject to blocking and group closure. Individual contribution visibility remains separate. The invitation and first publication acknowledge that contract. Every comment composer, including when only the starter has accepted, says: “Comments are shared with everyone who can view this check-in. People who join later may bring more readers.” Keep an accessible audience detail explaining Everyone/Friends and that earlier comments can be read by later eligible viewers. Never label this entire discussion “Friends” based on just one participant.

Comments and likes filter blocked/deleted authors, including their counts, actor lists, previews and notification snippets. A block between two nonowner participants hides each from the other without removing unrelated memberships; it must not rely only on the old owner/participant cancellation trigger. A viewer blocked with the starter cannot access the shared group through a different participant; an owned surviving visit can still appear independently without the thread. Generated text and counts cannot reveal hidden identities. User-authored prose can mention other people; this contract does not promise automatic redaction of names inside arbitrary prose.

Sharing inside Astir resolves this same authenticated, viewer-filtered post. External share previews default to venue-only content. Publishing a user’s own contribution requires the existing explicit share-preview consent; never export other people’s notes/photos/face piles by default. Revocation removes app access and future resolution, but cannot recall an already explicitly exported external image. Pushes and in-app notifications reauthorize before sending/opening, avoid private note excerpts, deduplicate recipients and honor current blocks.

## Lifecycle and failure modes

```text
pending --accept--> accepted --leave/remove--> detached
   |                                             |
   +--decline/expire/cancel--> terminal           +--new generation--> pending

starter deletes / goes Self / goes private / source becomes unavailable
   -> group permanently closed; pending invitations cancelled
   -> shared thread inaccessible; surviving other visits independent
   -> restoring visibility never resurrects the old group
```

| Trigger | Required behavior |
| --- | --- |
| Decline / cancel / expiry | No activity or stats for an unaccepted invite; free the reserved slot; preserve stale-link status and no repeated pushes. |
| Invitation revised before acceptance | Re-review changed place/date/selected photos; keep the invitee’s typed draft locally; reject stale revision. Never copy the inviter’s note/rating as the invitee’s. |
| Blank acceptance / partially uploaded photo | Accept without required rating, note or photo; pending own uploads never block other contributions or masquerade as published media. Retry uploads by asset ID. |
| Concurrent accept on two devices / response lost | Same operation resolves to one membership and one owned visit, with one stats change and one deduplicated notification. |
| Leave / removal of accepted nonowner | Remove attribution, note/rating/media and alias from the joint projection; keep their independent visit at its original date, with no new feed bump. Prior authored comments remain on the original thread unless individually deleted; explain this in confirmation. No copying the thread to the solo entry. |
| Reinvite after leave/removal | New invitation generation requires new consent. Relink the surviving former visit instead of creating another visit or counting another check-in. If that visit was deleted, require an explicit fresh save. |
| Delete nonowner’s visit | Detach participation and remove its content; do not delete other people’s visits or the canonical thread. |
| Starter deletes / Self / private / source removed | Permanently close the shared post and thread, cancel pending invites, suppress queued notifications; retain the others’ independent visits. Explain before owner action; ordinary deletion remains possible from older clients. No automatic coowner transfer. |
| Nonowner goes Self / private | Detach their membership, preserve their private visit and invalidate projections. Their own comments follow existing author/delete/block rules; do not promise a place visibility setting deletes authored discussion. |
| Everyone ↔ Friends / follow or block change | Recompute readable identities/content and discussion access; no widening an existing parent save as a side effect of acceptance. |
| Edit own note/rating/photo | Update only owned contribution everywhere. Use revisions to detect conflicting edits, preserve drafts on conflict, and do not replace the whole group from a stale client. |
| Change place/date after others accept | Keep group occasion fixed. Offer an explicit detach-and-edit of the person’s own visit; if the starter moves it, close the group. Reject silent ordinary field updates that would split the occasion. |
| Venue merge / removed venue | Resolve established canonical place IDs; do not merge distinct groups. If source is truly unavailable, close; preserve historical personal data according to existing retention policy. |
| Offline accept / revoked access while composing | Keep the draft and show pending/failed state; do not show accepted coauthorship until committed. Explain expired/removed/upgrade/privacy errors without leaking hidden participants. Reauthorize comment submission, media, sharing and deep links. |
| Account switch / app restart | Persist operation IDs and draft ownership per account; discard late responses from a previous account; clear cached projections after auth/visibility changes. |
| Report / abuse / deleted account | Allow reporting the whole post and a specific contribution/comment. Attribution-based moderation affects the offending content, except source/account removal closes the group. Server rules apply to cached/detail routes too. |

Photos remain owned by their uploader; do not copy Ryan’s upload under Joe’s authorship. Deduplicate references by asset identity, not image appearance. A visible fallback hero may use another readable participant’s photo or the normal place placeholder. No stale source-owned image can survive a privacy filter merely because it was the chosen cover.

## Mixed clients, rollout and performance

Use separate v2 RPCs or an explicit validated capability/consent contract. A version column alone is insufficient. Legacy create/set/accept and engagement mutation RPCs must reject a v2 target with an upgrade-required result; they must not remove members or bypass the 10-person limit. Keep v1 calls unchanged. Ordinary owned note/photo edits and deletion remain valid with server-side v2 reconciliation; unsupported place/date changes return an actionable error.

Legacy feed/engagement readers must not emit a misleading v2 owner-only thread or let child aliases reveal the shared conversation. Exclude v2 group events from unsupported legacy social projections; personal owned history can remain visible with its original fields, but legacy engagement writes to grouped IDs fail closed. Old invitation/deep-link clients get a safe unavailable/update-required result and never auto-accept v2. Add regression fixtures for each old RPC, not just a mocked client-version flag.

Server deduplication happens before sorting/cursor pagination. Project canonical IDs from readable participants, then order by original `(occurred_at, canonical_event_id)`; late acceptance, editing and privacy changes do not bump the event. The profile timeline uses that person’s original visit occasion, not acceptance time. A visit under an active group appears once per surface, including when the viewer follows all ten people. Standalone detach does not publish a new burst of events or notifications.

Batch visible groups/contributions, media and engagement per page; never issue a query per person or per card. Index canonical association lookup, active participant lookup, legacy/version filtering and reverse aliases. Use bounded keyset paging and page hydration; omit long notes/media payloads beyond their summary bounds until expansion. Counts must use the same filtered set as detail. Cache by viewer plus group revision/privacy state and reauthorize server reads; no globally cached assembled face pile. Limit to 10 accepted/pending new participants without loading an unbounded invitation history.

Roll out additively: (1) migration and old-client gates with new writes off, (2) server tests using synthetic v1/v2 fixtures, (3) capable client and projection QA, (4) internal flag cohort, (5) broader enablement after monitored acceptance. Turning creation off stops new v2 writes but preserves v2 reads and lifecycle support. Rollback must never split an existing shared conversation into ten threads or rewrite version 2 rows to version 1. Keep v1 support until legacy invitations expire through their existing behavior. No automatic database writes are authorized by this document.

Telemetry measures duplicate canonical cards, duplicate visit creation, denied writes by reason, stale operations, capacity conflicts, hydration request count/latency and projection failures. Use aggregate/allowlisted events, not note text or named social graphs. Compare measured feed performance against the same baseline page on the same fixture/device; no invented latency promise. Correctness and privacy are release gates even if aggregate performance looks good.

## Review findings and validation

Architecture findings: (1) historical event ownership prevents safe automatic consolidation; (2) parent-save visibility prevents naive acceptance; (3) union discussion requires consent and block filtering; (4) lifecycle/reinvite needs durable association and permanent closure; (5) mixed clients need server gates; (6) a canonical group needs server pagination/alias rules. All six are addressed above.

Code quality findings: (7) reuse typed core models/rendering instead of inferring from companions or duplicating profile cards; (8) authenticate before replay, persist operation IDs, and detect edit conflicts. Both are included. Performance finding: (9) batch/filter before pagination rather than app-side collapse or per-person queries. Included.

Test review identifies six coverage areas beyond existing legacy tests: versioned rollout, permissions/discussion, lifecycle/races, personal-place preservation, surface parity and bounded reads. [The test plan](test-plan.md) provides named cases and the execution gate. Existing tests were read, not rerun, and none yet establishes the new v2 contract. An independent Codex reviewer found five concrete gaps (parent metadata, commenter consent, versioned gates, rejoin aliases, replay authorization) plus a nonowner-block case; all were incorporated. This is a plan review, not proof of implementation security.

The interactive preview was refined to pin the subject’s own contribution on activity, use the current rating/visibility vocabulary, disclose the discussion audience, and distinguish authenticated post sharing from external venue-only sharing. It is a fictional local demonstration, not connected to production. Additional lifecycle states are specified and tested by the implementation matrix rather than presented as fake working backend behavior.

## NOT in scope

Historical conversation conversion; inferred same-place/time groups; a new chat service; coowner succession; per-visit privacy redesign; a new global invitation cap; publishing other people’s content externally; changing recommendation/rating aggregation; shipping or migrating production from this planning PR. No unrelated TODO is needed.

## Implementation Tasks

All tasks are P1 release gates for REC-566. Estimates are planning ranges, not time promises. JSONL mirrors this list in [implementation-tasks.jsonl](implementation-tasks.jsonl).

- [ ] **T1 — versioned data and ownership** (human 1–2 days / agent implementation 4–8 hours): additive group version/canonical association, transactional creation, secure replay and capacity, preserved parent saves, detach/rejoin/closure. Files: new Supabase migration, `supabase/tests/shared_visits.sql` and focused v2 tests. Verify data/lifecycle/security cases in the test plan, including concurrent real transactions.
- [ ] **T2 — projections, engagement and compatibility** (human 1–2 days / agent 4–8 hours): canonical pagination, privacy-filtered payload, gated legacy endpoints, aliases, idempotent comments, filtered counters and notification authorization. Files: new migration, engagement/read RPC tests, notification worker contracts. Verify mixed audiences, old RPCs and duplicate-free page boundaries.
- [ ] **T3 — native models and mutations** (human 1–2 days / agent 4–8 hours): typed joint projection, durable operation IDs, invitation consent, inherited save privacy, private-save alternative, revision conflicts and owned-edit lifecycle. Files: `RepositoryProtocols.swift`, `Remote/SupabaseRepositories.swift`, `WanderLocalStore.swift`, local store models, invitation/add/detail flows. Verify store/repository acceptance and restart/account-switch tests.
- [ ] **T4 — shared card across surfaces** (human 1–2 days / agent 3–6 hours): one postcard renderer and engagement route, profile-subject prominence, ten-person expansion, missing content, accessibility, audience and sharing UI. Files: `FeedModels.swift`, `Wander/Features/Activity/ActivityEngagementViews.swift` (the `ActivityPostcardView` definition), profile and place-activity presenters, comment/share views. Verify the fixture scenarios on standard/compact iPhone and iPad.
- [ ] **T5 — compatibility rollout and acceptance evidence** (human 1 day / agent 3–5 hours): execute the complete matrix, measure queries/frame performance, prove rollback/new-write flag behavior and preserve final evidence. Files: v2 SQL tests, `WanderTests`, `WanderUITests`, rollout config and this test plan. Required before production flag enablement.

Execute T1 → T2 → T3 → T4 → T5. UI fixture exploration can accompany T1/T2, but the durable protocol and server/client contracts must agree before merging behavior. One sequential implementation lane avoids concurrent edits to shared repositories/models and migrations. This review used one independent read-only reviewer; no parallel implementation is implied.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
| --- | --- | --- | --- | --- | --- |
| CEO | Not invoked | Existing user-approved direction | 0 | Not run | User delegated routine edge-case/migration decisions. |
| Independent Codex | Engineering outside review | Challenge compatibility/security | 1 | Incorporated | Five concrete findings plus nonowner block case incorporated. |
| Engineering | `plan-eng-review` | Architecture, quality, tests, performance | 1 | Clear for planning | 6 architecture + 2 quality + 1 performance findings; 6 test coverage areas specified. |
| Design | Direct preview review | Feed/profile parity | 1 | Preview checked | Subject-first activity, accepted-only pile, 1–5 rating, audience disclosure. Native UI still requires implementation QA. |
| DX | Not invoked | No developer-facing product | 0 | Not applicable | No new external API or SDK product. |

Scope stays on the requested joint experience; reuse reduces the implementation from a new subsystem to extensions of Shared Visits and engagement. What exists, exclusions, failure modes and tasks are documented. No unresolved product decisions or unassigned critical plan gaps remain; all new behavior still requires implementation and the release gates in the test plan. No claim is made that the currently shipped app passes those gates.

**VERDICT:** Engineering plan ready for implementation. Production implementation, migration execution, native tests and rollout remain outstanding.

NO UNRESOLVED DECISIONS
