# Sender Silent controls and import announcements

REC-589 · Product specification and engineering plan · September 22, 2026

## Product promise

Silent suppresses automatic notifications caused by a save. It preserves the
existing audience and activity in Feed, profiles, and maps. It suppresses the
notification event itself, including its notification inbox/badge, rather than
merely removing the push sound. Receiver settings and audience controls are
separate work (REC-590 and REC-591).

The [implementation coverage and manual test checklist](rec589-sender-notification-testing.md)
separates newly added controls from existing notification behavior for every
action below.

| Sender action | Control | Default and behavior |
| --- | --- | --- |
| First or repeat check-in | Silent toggle in final form | Off; one choice also covers attached list additions |
| Historical check-in | Same toggle | On until explicitly changed |
| First or repeat Wanna | Same toggle | Off; preserve intent for any companion save/list announcements; repeat Wanna has no current follower producer |
| Save from another person's map | Silent form control or native quick-save choice | Off; also suppress source-attribution notification |
| Standalone add to lists | Silent toggle in picker; native normal/silent choice for direct suggestions and search additions | Off; apply one captured choice across all selected lists |
| Staged list selection | Inherits parent | No competing control inside the picker |
| Accept shared visit | Silent toggle in acceptance form | Off; controls new save announcement |
| Import, one or many places | Native final-Save confirmation | Silent is primary/default; one lifetime grouped announcement opportunity |
| Existing memory edit | No new announcement | Show control only if adding new list memberships |
| Invite companions, list collaborators, Let's Go | No Silent suppression | These are explicit communications |
| Like, comment, follow, self-reminder, owner import-completion notice | Unchanged | Independent actions/categories |

The control belongs to a draft/action, not an account-wide setting. A later
unrelated save starts from its appropriate default. Inline import detail forms
inherit the outer import choice. The helper explains that visibility stays the
same and explicitly selected invitees still receive invitations.

Silent off permits existing eligible announcements. It does not override the
standalone follower producer's existing date rule: visits before the current
database day (UTC), future visits, and backfills do not announce. The grouped
import path can announce historical check-ins when Notify is explicitly chosen.
Plain Wanna saves do not have a follower check-in announcement producer.

## Import interaction and examples

The first final Save opens a native iOS alert:

- **Silence notifications for this import?**
- **Yes, save silently** is the primary/default action.
- **No, notify followers** explicitly opts into the grouped announcement.
- **Cancel** preserves the draft and consumes no announcement opportunity.

The message explains that visibility stays the same, only the check-ins saved now
can announce, later saves will not announce again, and direct invitations still
send. Notify never broadens visibility; if nobody can see those check-ins,
nobody receives an announcement.

For ten imported places, checking into three with Notify produces at most one
logical notification for each eligible follower: **Ryan checked in** / **XYZ and
2 other places**. Adding the other seven later produces no new announcement.
Silent on the first save also consumes the opportunity. A Wanna-only or list-only
first save does not invent a follower announcement or reserve one for later.

The group counts distinct visible places. Singular/plural copy is correct for
one, two, and several places. Hidden places contribute neither names nor counts.
Different recipients can receive different counts. The destination points to a
currently visible place. Existing blocks, mutes, notification preferences,
expiration, and device delivery rules still apply.

Background autosaves are silent. Existing imports with actual saved receipt
entries are treated as already consumed. Review-only or empty automatic receipts
do not consume the first real save choice. Mixed-source paste and multiple
attachments from one capture share one durable import identity.

## Failure and recovery contract

The first save attempt captures durable successful visits into one manifest.
Completion, a partial error, or recovery after process termination closes it.
Retrying those saved visits reuses their IDs. Newly chosen actions after an
interruption cannot expand the original announcement, even when the same import
item changes from Wanna to Check In or chooses a different candidate.

Offline content is saved locally with its policy before sync. Finalization waits
for the captured live visits to sync. A deleted local visit is omitted. A failed
finalization keeps the same intent for retry; there is no fallback to announcing
RPCs. A lost response, repeated finalization, or returning after delivery cannot
produce another event. Account changes prevent another account from sending or
acknowledging the pending intent. Account deletion clears local and server ledgers.

The promise is one logical event per eligible recipient/import. APNs transport
retries and delivery to multiple registered devices retain their existing
semantics. Already delivered notifications cannot be recalled.

## Implementation

`SenderNotificationPolicy` separates silence from the audience. Persist it on
user-place, explicit visit, and list-item outbox records. Keep it in the form
draft across recovery. Legacy unsynced records without policy restore silently;
malformed policy also fails closed. Ordinary synced legacy content retains its
existing behavior.

The canonical import coordinator creates one owner-scoped local commit before
saving items. It stores captured visit IDs, preserves the original choice, and
closes the manifest before scheduling finalization. All imported individual
visits and list additions suppress their normal per-item producers. The store
syncs the frozen set through `ImportNotificationRepository`.

The migration adds persisted suppression columns and a private
`app.import_notification_commits` ledger keyed by `(owner_user_id, import_id)`.
A validated transaction-local policy is installed before existing save operations
fire triggers; BEFORE triggers persist the policy. UPDATE retains the original
action policy. Wrappers restore transaction context after successful operations;
failed transactions roll it back.

Narrow wrappers cover own saves, atomic check-ins, social saves, list items, and
shared-visit acceptance. Existing business RPCs retain their original contracts.
The new social-save wrapper explicitly checks the source audience and active
profiles because the legacy invoker path relies on revoked raw-table SELECT.
It creates only the authenticated caller's blank Wanna, preserves existing Been
content and the caller's existing note, honors Self defaults, and never copies
source notes, ratings, private answers, or taxonomy snapshots. No raw table grant
is widened. All new public save RPCs are authenticated-only with pinned paths.

Only followed-check-in, source-attribution, and list-add producers check Silent.
Feed generation and intentional invitations are unchanged. Finalization locks
the import ledger, validates the caller's visit ownership and import membership,
queues recipient-filtered groups, and seals the ledger in the same transaction,
including silent and zero-recipient outcomes. The worker wrapper recomputes group
copy and destination from current visibility on each claim/retry, or cancels a
group with no accessible content.

Queued names and counts are also protected on raw recipient reads. The additive
`20260924035547_sender_import_notification_read_guard.sql` migration installs a
claim-bound helper and a restrictive authenticated SELECT policy. The helper
requires the stored body, place ID, count, and deep link to match the entire
currently visible group. Partial revocation hides the stale snapshot immediately;
the worker can refresh the remaining group at its next claim. A foreign event ID
cannot be used to read another recipient's content.

```text
first Save -> captured intent + frozen successful visits -> sync -> finalizer
                                                          | owner/import lock
                                                          v
                                      one recipient-filtered queue event
                                                          |
recipient SELECT -> recipient ownership -> current group == entire snapshot?
                                           yes: readable / no: hidden
worker claim ----> source eligibility -> recompute group -> refresh or skip
```

The restrictive policy composes with REC-590 source authorization. Its grouped
import branch recognizes `sender_import_id`; it does not require a single
`visit_id`. Neither guard broadens source access. Already delivered OS
notifications cannot be recalled.

No private notification payloads, import IDs, visit IDs, places, or recipients are
added to analytics. Existing successful save events and aggregate server delivery
metrics remain unchanged.

## Validation and rollout

Regression coverage includes draft/policy persistence, offline recovery,
3-then-7 imports, interrupted attempts, legacy empty/saved receipts, account
switch/deletion, mixed-source identity, immutable request intent, no unsafe RPC
fallback, and native Silent/Save confirmation behavior.

`supabase/tests/sender_notification_controls.sql` raises on a failed contract and
rolls back its fixtures. The checked-in smoke runner includes it. Preview the
migration and test in one rolled-back transaction before deployment. The suite
exercises all five authenticated wrappers, regular/silent saves, grouped counts,
Feed preservation, source and list suppression, direct invitation preservation,
private/default audience checks, forged ownership, metadata/grants, and worker
visibility revalidation, raw reads after partial/full revocation, block/unfollow/deletion,
stranger event IDs, and restrictive-policy metadata. No push is delivered by this suite.
The native review host and `SenderNotificationFlowUITests` exercise production
SwiftUI controls through saved policies and the unchanged three-then-seven manifest.
See [native review instructions](../designs/rec589-sender-controls/README.md).

Deploy the reviewed database migration before distributing the iOS build. New
silent operations fail closed if the server contract is missing. Do not change
receiver preferences or privacy settings as part of rollout. Migration deployment,
merge, and TestFlight distribution remain separate release steps. The PR records
actual validation evidence and any unavailable OS/device coverage.
