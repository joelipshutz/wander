# Sender notification coverage and manual tests

Companion to [the REC-589 specification](rec589-sender-notifications.md).
Coverage compares `codex/rec-589-silent-notifications` with its original base,
`1fccbede1190a64a1a17416a2eb58fc726904e35`. The save actions themselves already
existed; this branch adds sender notification intent and import grouping.

## Implementation coverage

| Sender action from the spec | Added on this branch | Behavior that already existed |
| --- | --- | --- |
| First or repeat check-in | Silent toggle, persisted action policy, server suppression | Check-in saving and eligible follower announcements |
| Historical check-in | Silent defaults on until changed; applies to any companion announcements | Standalone follower announcements exclude visits before the current database day (UTC), future visits, and backfilled visits |
| First or repeat Wanna | Silent in the form; passed through companion saves/list additions | Plain Wanna has no follower check-in announcement producer; repeat Wanna does not create one |
| Save from another person's map | Form control and Discover quick-save normal/silent choice; source-attribution suppression | Saving the place and notifying the source person when an eligible first social save is inserted |
| Standalone add to lists | Silent in the picker, including new-list saves; Add/Add silently/Cancel on direct suggestions and search | List membership writes and eligible list-member announcements |
| Staged list selection with a save | Inherits the parent form's captured policy for every attached addition | Choosing lists as part of the save |
| Accept shared visit | Acceptance form's Silent choice reaches the saved check-in | Accepting the invitation and saving the recipient's own visit |
| Import one or many places | Native first-Save confirmation; Silent default; one durable grouped announcement opportunity; per-item/source/list suppression; retry/recovery handling | Import extraction, review, saving, and owner completion notices |
| Edit an existing memory | Control appears for attached list additions | Editing existing content does not create a new visit announcement |
| Invite companions, invite list collaborators, Let's Go | No suppression added, as specified | Explicit invitation delivery remains independent of Silent |
| Like, comment, follow, self-reminder, owner import-completion notice | No suppression added, as specified | Existing independent notification behavior remains |

No general sender Silent control or once-per-import notification ledger existed
at the base commit. Receiver controls and audience/privacy work are separate.
Future question-post integration belongs to REC-395.

**Eligibility matters:** Silent off permits an otherwise eligible notification;
it does not force delivery or override receiver preferences, blocks, mutes,
delivery governance, or the standalone check-in date rule. In particular, a
standalone check-in dated a week ago still does not announce to followers with
Silent off. A historical import can announce its first selected check-ins as a
group when the sender explicitly chooses Notify. Plain Wanna alone does not
produce a follower announcement.

## Test setup

1. Install a signed build from this branch on the sender's iPhone. Applying the
   database migration alone does not add these controls to an older app build.
   The migration file is
   `supabase/migrations/20260923193108_sender_notification_controls.sql`.
2. Use test accounts: A sends; B follows A and belongs to the shared test list;
   C is outside the tested audience. For source-attribution tests, A saves a
   place from B's map. For acceptance tests, use a separate follower of the
   accepting account so invitation delivery cannot be mistaken for a check-in
   announcement.
3. On B, enable both iOS notifications and the relevant in-app categories, with
   no mute/block/Focus interference. Establish a positive control: a fresh,
   ordinary check-in with Silent off must produce the expected notification.
   A missing positive control means delivery is not configured well enough to
   validate silence by observation.
4. Keep the receiver app in the background for push checks. Check its in-app
   notification inbox and badge as well. Silent must suppress the automatic
   event itself, not just its sound. Record the starting unread count.
5. Wait through the existing delivery cycle: follower announcements have a
   30-second hold before the worker can deliver them; allow roughly 1–2 minutes
   for normal processing. Investigate a delay rather than treating it as proof
   of silence. Space normal-notification tests so delivery governance does not
   obscure their result.
6. Use fresh places/list memberships/imports where specified. Existing dedupe
   rules mean deleting and re-adding the same social save or list item is not a
   reliable normal-notification control.

## Sender controls

| Test | Steps | Expected result |
| --- | --- | --- |
| Ordinary check-in | Save a fresh place dated now with Silent off. Save another fresh place with Silent on. | The normal save can announce to eligible B. The silent save produces no automatic push, inbox item, or badge increment. Both remain visible to their existing audience in Feed/profile/map. |
| Repeat check-in | Check in again at an already-saved place, once with each Silent choice, using separate visit records. | The new visit honors its own choice. A previous silent visit does not permanently silence future visits, and an earlier normal visit does not override a later silent one. |
| Historical check-in | Set the date to a week ago before changing Silent. Repeat with Silent explicitly off, and optionally attach a new shared-list addition. | Silent starts on. Neither old standalone visit announces to followers under the existing date rule. The attached list announcement follows the chosen Silent setting. |
| First and repeat Wanna | Save a fresh Wanna, then add another Wanna entry. Test both Silent choices, including a fresh shared-list addition. | The setting is available and preserved. Plain Wanna does not invent a follower check-in alert. Eligible companion/source/list announcements obey the captured choice. |
| Save from someone else's map | Save fresh places from B's map through the full form and through Discover's quick-save action. Exercise normal, silent, and Cancel. | Normal eligible first social saves may notify B. Silent suppresses the source-attribution alert. Cancel saves nothing. The saved place retains its existing visibility rules. |
| Standalone list picker | Add fresh places to one shared list, then to multiple lists. Test Silent off/on; include creating a list in the picker. | One captured choice applies to every membership and any companion save. Silent produces no automatic list/source/save alerts. Explicit invitations remain separate. |
| Direct list additions | Add a suggestion from list detail; add a suggestion and a search result from Add Places. Exercise Add, Add silently, and Cancel on each path. | Normal/silent choices reach the save and membership together. Cancel changes nothing. |
| Combined check-in/Wanna and lists | Select several shared lists inside a save, enable Silent in the parent form, and save. Repeat normally with fresh items. | There is no competing Silent setting in the staged picker. The parent choice covers the place/visit and every attached list addition. |
| Shared-visit acceptance | Accept two fresh invitations, one normally and one silently. Observe a follower of the accepting account. | Acceptance succeeds in both cases. The accepting account's automatic eligible check-in announcement respects Silent. The original explicit invitation is unaffected. |
| Existing-memory edit | Edit only the note/rating of a saved memory. Then edit while adding a fresh shared-list membership. | The content-only edit does not announce a new visit. The list-add case offers Silent and controls the new list announcement. |
| Explicit communications | With Silent on, explicitly invite a companion while saving. Separately invite a list collaborator and send Let's Go. | Intentional invitations still deliver according to their existing recipient rules. Silent helper copy does not promise to suppress them. |
| Independent notifications | Like/comment on a silent save; exercise follow, a scheduled self-reminder, and an import completion notice. | Those later or owner-directed events continue under their existing notification settings. A silent save does not mute future interaction with it. |

For every silent save, also check that A still has the saved content, B can see
what B was already allowed to see, and C gains no new access. Do not equate
Silent with private or profile-only.

## Imports

| Test | Steps | Expected result |
| --- | --- | --- |
| Native prompt and Cancel | Select items in a fresh import and press final Save. Choose Cancel, then press Save again. | Native Yes, save silently / No, notify followers / Cancel prompt. Silent is the primary/default choice. Cancel retains the unsaved selection and does not consume the first announcement opportunity. |
| Default Silent | On a fresh import, save check-ins using Yes, save silently. Later save more items from that import. | No automatic check-in, source-attribution, or list-add alerts from either save. Content still appears to its existing audience. |
| Three, then seven | Import ten distinct places. Save three as check-ins with No, notify followers. After delivery, return and check into the other seven. | One grouped logical announcement per eligible recipient for the first three, such as “XYZ and 2 other places.” No three individual announcements and no later announcement for the remaining seven. |
| One, two, several | Use fresh imports containing one check-in, two distinct check-ins, and several check-ins. | Correct singular/plural copy: one place; one other place; N other places. Tapping opens an accessible place. |
| Distinct places and mixed visibility | Where the importer permits duplicate candidates, choose the same place more than once. Include places outside one receiver's audience. | Count distinct visible places only. Hidden places contribute neither names nor counts. Each recipient's result can differ; someone with zero accessible places gets no event. |
| Wanna-only or list-only first save | On a fresh import, save only Wanna/list actions first, choosing Notify if offered. Later check into remaining items. | No follower check-in group for the first save, and no new follower group later: the first opportunity was consumed. Per-item/source/list announcements remain suppressed. |
| Multiple source batches | Import several links or attachments through one capture, then save check-ins across its batches. | One capture shares the import identity and can produce only its first grouped announcement. |
| Automatic and legacy saves | Review an automatically saved import and an older import with actual saved items, then save remaining items. | They stay consumed/silent. A review-only import with no actual saved receipt can still offer its first choice. |
| Offline and relaunch | Go offline before saving a fresh Silent import. Close/reopen the app, reconnect, and wait for sync. Repeat with a fresh Notify import. | Choice survives. Silent stays silent. Notify syncs the original saved group at most once; restarting or retrying does not add another announcement. |
| Interrupted first save | Using a controlled interrupted-save setup, stop after some first-attempt successes. Recover and save more items. | The announcement can contain only durable successes from the original attempt. Later items cannot enlarge it or create a second group. Use a controlled failure for this case rather than assuming a timed force-quit interrupted a write. |
| Access changes before delivery | After a Notify import, remove visibility/block the receiver or delete a captured check-in before the worker claims the pending event. | Remaining visible distinct places determine the group, or the event is skipped when none remain. A notification already delivered cannot be recalled. |
| Account switching | Save offline as A, switch accounts before sync, then return to A. | Another account cannot send or acknowledge A's pending import. A's original policy and identity survive. |

## Highest-priority acceptance sequence

Run ordinary Silent versus normal check-ins, both source-save entry points,
standalone and combined shared-list additions, shared-visit acceptance, the
native import Cancel/default path, and the three-then-seven import first. Then
run offline/relaunch, audience filtering, and explicit-invitation exceptions.

The SQL regression suite additionally exercises forged ownership, RPC grants,
private-ledger access, source-content isolation, immutable first intent,
replayed finalization, and send-time visibility without sending a real push.
These automated checks complement the two-device manual tests; they do not
replace a signed-device APNs delivery check.
