# REC-589 engineering review and native review plan

Reviewed implementation: `d7515d3a8bcad57511c65009e5326ae41febe723` against
`1fccbede1190a64a1a17416a2eb58fc726904e35`. Full branch, product spec, and every
sender-control SwiftUI scenario. Accepted changes 1A and 2A are implemented.
The September 25 integration includes origin/main `ebd07f847`; final validation
and native evidence are recorded below.

## Scope challenge

The original 33-file diff crosses views, persisted intent, repository payloads,
database triggers, and notification delivery. That breadth is justified: leaving
one automatic producer or retry path outside the contract can announce a Silent
action. Keep the accepted scope. Reuse the production views for native mockups;
do not create a parallel set of save forms or a second notification queue.

## What already exists

| Problem | Existing implementation to reuse |
| --- | --- |
| Save/edit/share acceptance form | MapPlaceSaveFlowSheet and MapPlaceSaveEditor |
| One choice across list memberships | MapPlaceListPickerSheet and parent submission policy |
| Quick/direct actions | Discover and Lists native confirmation dialogs |
| Import first choice and later saves | PlaceImportCanonicalReviewScreen and its persisted import ledger |
| Offline/relaunch/retry | WanderStoreSnapshot, existing save outbox, frozen visit identities |
| Grouping and recipients | Existing queue governance, import renderer, row-locked finalization |
| Review fixtures | Existing DEBUG native hosts, ephemeral imports, fixture auth and resolver |
| Tests | XCTest/XCUITest plus rollback-only authenticated SQL smoke tests |

## Architecture review

**Finding 1: P1, confidence 9/10 — queued group snapshots outlive source access.**
The sender migration queues `input_body := content->>'body'` at line 478 and
stores the place destination/count at lines 479–481. Its cancellation path at
509–511 changes status without removing the payload. The original recipient RLS
predicate is `recipient_user_id = app.current_user_id()` (push migration line
133). Read-only hosted metadata verified that policy and authenticated SELECT.
Recipients can therefore retrieve old names after source access disappears.

**Accepted 1A:** preserve named grouped copy and close raw-read bypass. Add a
narrow, claim-bound private helper and restrictive SELECT policy that compare
the queued snapshot with the current visible group. Empty or changed groups are
withheld; the existing claim path can refresh a changed snapshot. Check body,
count, place identity, destination, and recipient ownership. This is an additive
restriction, preserving the existing queue grant and non-import policies.
No new user-facing privacy setting or audience default is introduced.

The independent adversarial pass agreed with this finding and found no further
verified defects in the owner/import key, row lock, transactional queue/seal,
lost-response replay, or frozen first-attempt manifest. Identical content
imported in two separate captures is two imports; dedupe is by durable import ID.

**1A implementation:** additive migration
`20260924035547_sender_import_notification_read_guard.sql` is deployed. Its
claim-bound definer compares the entire body/place/count/deep-link snapshot and
the authenticated recipient. The SELECT policy is restrictive. Tests exercise
raw reads after block, unfollow, deletion, partial and full revocation, including
sent snapshots, plus foreign/unknown event IDs and function/policy metadata.

REC-590 now recognizes grouped import identities in source authorization. Hosted
metadata verified that definition September 25. The sender regression passes
with both guards installed; empty groups can be skipped by either source
authorization (`source_not_visible`) or the import renderer
(`activity_unavailable`). Both must clear the claim and omit worker output.

## Code quality review

No separate blocking finding. The small policy value type, shared native toggle,
repository envelope, and persisted import identity avoid separate implementations
of silence. Error paths retain the original intent and do not fall back to
announcing RPCs. The direct-action dialogs have similar copy but only a few
lines each; extracting a new presentation framework would add more complexity
than it removes. Keep the DEBUG review harness separate from shipping behavior.

The import state comment and recovery contract remain accurate. Add the read
authorization diagram beside the new policy so future queue changes preserve
partial-revocation handling.

## Test review

**Finding 2: P2, confidence 9/10 — native UI wiring is under-covered.**
The UI test selects a Wanna and confirms Silent (CheckInQuestionUITests lines
623–639); the three-then-seven test invokes the store directly
(SenderNotificationPolicyTests lines 17–24). SQL independently verifies groups.
Those tests do not prove that the production import screen passes the selected
choice and first visit set through the coordinator.

**Accepted 2A:** add native integration tests with the real SwiftUI screens and
local fixture data. Assert the saved policies and frozen manifest, not just
whether a control exists. Keep signed-device APNs delivery as a manual check.

```text
CODE / BRANCHES                         USER FLOW / COVERAGE
Map save editor
  first/repeat/Wanna/historical ------> control state + draft
  normal/Silent/explicit override       [existing: toggle + draft unit]
  edit/no lists vs new memberships      [2A: native state + saved policy]
  friends selected ------------------> invitation exception copy
  source save/acceptance -------------> save boundary receives policy
                                       [2A: native forms and integration]
Discover / Lists direct action
  normal / Silent / Cancel ----------> saved source/membership policy
                                       [2A: all direct-action entry points]
List picker
  standalone vs parent-staged --------> one effective policy
  one/many/new lists; cancel            [existing: list lifecycle]
                                       [2A: silent memberships + parent]
Import screen
  first Save -> Cancel ---------------> no ledger / no save [existing UI]
             -> Silent/Notify --------> first 3 saved visits [2A -> native]
  same import -> remaining 7 ---------> unchanged first manifest [2A]
  details / Wanna / lists ------------> outer policy; per-item suppression
Store + persistence
  new/existing/legacy receipt --------> first choice [existing unit]
  partial/crash/relaunch -------------> frozen successes [existing unit]
  pending/deleted/synced visit -------> finalize readiness [existing + 2A]
  timeout/retry/account change ------> same intent; owner guard [unit]
Repository
  standard vs policy envelope --------> no unsafe fallback [unit + SQL]
SQL
  owner/stranger/anonymous -----------> grants/ownership [existing SQL]
  first/sealed/losing commit ---------> at most one event [existing SQL]
  one/many/distinct/hidden places ----> current group [existing SQL]
  revoked before/after claim --------> safe push [existing SQL]
  revoked before/after raw read ------> hide stale body/count [1A CRITICAL]
  block/unfollow/delete/partial ------> safe raw access [1A CRITICAL]
  metadata + restrictive composition -> no policy bypass [1A CRITICAL]
Delivery
  signed iPhone + real recipient -----> actual APNs behavior [manual gap]
```

The diagram maps behavior rather than claiming a line-coverage percentage.
Mockup screenshots are visual evidence; assertions on persisted intent provide
the separate behavioral evidence. The new suite covers the actual coordinator:
first-three saved visits, exact frozen manifest IDs after the later seven,
Cancel/no ledger, Silent and Notify choices, consumed/Wanna-only imports,
full-form policies, direct-action dialogs, and staged/standalone/new-list paths.
Shared acceptance asserts the native submission; SQL verifies its server write.

The final integration run passes all **2,576 unit tests**. Final UI results are
recorded in the validation section. The original pre-review run passed 2,475
unit tests and 207/233 UI tests; 21 UI failures reproduced on its base and five
passed focused reruns. Those historical results do not substitute for current
validation.

## Native SwiftUI scenario inventory

| Scenario | Production surface / state to capture |
| --- | --- |
| First check-in | Save form, Silent off/on, initial viewport and control viewport |
| Repeat check-in | Same form with prior place context; fresh action choice |
| Historical check-in | Same form with Silent on by default |
| First/repeat Wanna | Wanna layout and attached-list behavior |
| Another person's place | Full save form and Discover quick-save dialog |
| Standalone lists | Picker footer; one/multiple selections; new-list sheet |
| Direct list addition | List-detail suggestion, Add Places suggestion, search result |
| Staged lists | Picker without competing Silent toggle; parent retains choice |
| Existing edit | No toggle for content-only edit; toggle when adding lists |
| Shared-visit acceptance | Acceptance form and policy at save boundary |
| Explicit companions | Silent with invitation exception helper |
| Single-place import | First Save native prompt, Cancel and both choices |
| Multi-place import | First Save and first-three/later-seven behavior |
| Consumed import | Later-save explanation and absence of another prompt |
| Import inline details | Outer choice applies; no competing inline toggle |
| Accessibility/appearance | Large and small phone, dark, large Dynamic Type |

## Performance review

No additional blocker at the supported import scale. Finalization bounds visit
IDs at 10,000 and uses one owner/import row lock; visits have primary-key access
and import metadata indexes. Per-follower rendering repeats work proportional
to the frozen group, consistent with the existing per-follower queue pattern.
No new worker, cache, or asynchronous fanout infrastructure is justified here.
The restrictive read helper uses a primary-key event lookup and the existing
renderer. Evaluate its plan against fixture data and keep bulk list reads scoped
to the recipient. Large-fanout production load has not been benchmarked.

## Failure modes and validation requirements

| Failure | Handling / user effect | Validation |
| --- | --- | --- |
| UI drops Silent | Incorrect announcement; unacceptable | 2A saved-policy assertions |
| Cancel consumes import | Lost first opportunity | Native Cancel + empty ledger |
| Retry expands group | Unexpected later announcement | Existing recovery tests + native 3/7 |
| Network/finalizer error | Saved content retained; same intent retries | Existing unit + SQL replay |
| Account changes mid-sync | Owner guard prevents wrong acknowledgement | Existing unit + SQL ownership |
| Imported visit deleted | Omit from group | Unit/SQL regression |
| Source hidden before push | Recompute or skip | Existing SQL claim regression |
| Source hidden before read | Restrictive policy hides stale snapshot | 1A authenticated regression |
| Only one group place hidden | Entire stale snapshot is hidden until refreshed | 1A whole-snapshot comparison |
| Additional permissive RLS | Could bypass a normal extra policy | Restrictive policy metadata + role tests |
| Shared UI overflows | Control hard to find/use | Two-size captures + large text |
| Native UI passes, APNs fails | Real delivery still uncertain | Manual signed-device positive control |

## NOT in scope

- Receiver settings and new audience controls: REC-591 / REC-590 own these.
- Import audience defaults: pre-existing quick-save Self versus detail-editor
  account-default inconsistency belongs to the privacy work; record it without
  silently broadening visibility in this sender branch.
- New notification categories, content-based import dedupe, ranking, or analytics.
- Automatic merge or TestFlight distribution: review/build handoff comes first.
- Replacing every unrelated failing UI test: retain the established baseline.

Existing TODOS.md items do not block this scope. No new TODO is proposed; both
accepted findings are requirements in this branch and privacy work has an issue.

## Implementation and validation

- 1A: deployed the additive raw-read guard; preserved the original migration.
- 2A: added a DEBUG fixture host and native UI-to-store tests. The **Sender Silent
  Review** scheme opens all production SwiftUI scenarios without a live account.
- Fixed an observed visual defect: scrolling list rows showed through the new
  fixed Silent footer. The footer now has the screen's opaque background.
- [Native placement guide and gallery](../designs/rec589-sender-controls/README.md).
- [Action coverage and signed-device checklist](../plans/rec589-sender-notification-testing.md).

| Check | Latest result (September 25–26) |
| --- | --- |
| Full unit suite | 2,576 passed, zero failures on integrated main `ebd07f847` |
| Native sender UI | All 14 distinct cases pass on both phone sizes across the complete and focused runs; 56 captures covering 28 states |
| Broader UI attempt | Interrupted after 20 UI passes, three failures and one canceled case. Final three-case rerun: dietary selection passes; live-auth launch and customization still fail |
| Sender hosted regression | Passed with REC-589 + REC-590 deployed guards |
| Core hosted smoke | Branch fixture fails at the superseded share-card response; composition check passes using REC-590's corresponding share-card test |
| Hosted migration history | Both REC-589 migrations present |
| Rollback cleanup | Zero reserved sender/smoke profiles or sender ledgers remain |
| Analytics contract/dashboard | Passed, 11 tests |
| JavaScript / gallery exporter syntax | Passed |

The core hosted fixture mismatch is specific: this branch's inherited share-card
test expects artwork/title, while deployed REC-590 intentionally returns
`{ "preview_mode": "generic" }`. Replacing only that test body in the temporary
verification SQL with REC-590's checked-in regression lets the generated core rollback
smoke pass. No privacy migration, production data, or other worktree was changed.
A clean branch-only core smoke requires integrating that privacy test contract.

The broader run completed all 2,572 units and 23 UI cases before cancellation.
Failures were live-authentication launch, custom-question privacy toggle, and
inline dietary-answer deselection. Cancellation interrupted the next customization
case. No current-baseline classification or full-suite pass is claimed.
On the final integration rerun, all 2,576 unit tests pass and dietary-answer
selection passes. Live authentication instead crashes with an external-symbol
report, and customization fails in `openCustomize`. These are unresolved broader
UI failures, not classified as baseline defects. The complete UI suite is not
claimed green.

All 14 distinct sender UI cases pass on iPhone 16 Plus and iPhone SE (3rd
generation). The compact complete run passed ten of the original 13 cases;
three focused reruns pass after correcting test switch gestures. The large
complete run passes all original 13. Final focused runs on both sizes pass the
new gallery return test and the strengthened inline-editor visibility test.
Store-policy and frozen-manifest assertions remain intact. The screenshot gallery
contains 28 real native states per device, with the inline editor actually in view.

Raw Xcode result bundles and full-resolution captures remain in the local
`outputs/rec589-review` evidence directory, outside this branch's tracked files.
The final unit/broader rerun is `integrated-regression.xcresult`; sender evidence
is in `compact-native-retry`, `compact-focused-final`, `large-native-final`,
`compact-gallery-check`, and `large-gallery-check` result bundles. No further
source edits were made after these tests except documentation and gallery output.

Validation uses installed iOS 26.5; the repository's iOS 18.6 runtime is absent.
Real APNs delivery, actual network interruption on a signed device, and production
fanout load are not proven by these simulator/SQL checks. Follow the manual
positive-control and sender/receiver checklist before distribution.

## September 28–29 validation follow-up

The sender implementation and native gallery remain unchanged. Both test targets
now generate Info.plists, and the signed app/test bundles pass codesign verification.
On a fresh dedicated iPhone 16 Plus / iOS 26.5 simulator, normal live-authentication
launch passes, including the second launch and native login entry. The earlier
unsigned Clerk crash is not reproduced in this signed run; its precise original
cause is not claimed proven.

The full unit suite passes again: **2,576 passed, zero failures**. The initial
four-case UI regression run passes accessibility and fails three customization
interactions. Recorded 50 ms presses sometimes did not register on visible controls.
The affected flows now use the sender suite's existing single 200 ms press pattern,
without retries or relaxed assertions. The final focused run passes **3 of 4**:
accessibility, restore/cancel with reopening, and hide/undo/re-add with persistence.

One failure remains in
`testCustomizeReordersRemovesAddsAndPersistsWhenReopened`: the custom question's
Yes answer does not report selected after a 200 ms press. The recording and touch
trace put the press at (113.5, 529), directly on the visible Yes button. This is
not resolved by increasing press duration; no further timing workaround is justified.
The custom-answer display/binding and live hit testing need inspection. The current
main-baseline attribution is still unverified. Do not describe the UI suite or this
follow-up as green.

Evidence under the local `outputs/rec589-review` directory:

| Result bundle | Result |
| --- | --- |
| `fresh-simulator-current-signed.xcresult` | Authentication passes; customization fails at a later privacy tap |
| `final-signed-regressions.xcresult` | 2,576 units and accessibility pass; three UI cases fail |
| `final-native-press-regressions.xcresult` | Three affected UI cases pass; custom Yes selection still fails |

The fresh simulator is `F867F011-7235-44A9-927D-B996D0364C03`. A clean compilation
into `DerivedData-FreshFinal` was stopped after prolonged dependency rebuilding;
it supplies no validation pass. The fresh-device run used verified current signed
bundles, and subsequent runs rebuilt the changed test source using the existing
REC-589 DerivedData cache. No other task's build or simulator was interrupted.
No REC-589 test command remains running.

Next: inspect the custom Yes interaction and answer binding on the dedicated
simulator before another code change, then rerun the single failing test and any
coverage affected by a confirmed fix. The desktop review handoff also remains
pending: the Xcode Branch Chooser was last verified September 26 and has not been
rechecked in this follow-up. Keep the PR draft until the remaining validation is
resolved or explicitly classified.

### Notification-history decision correction

The September 28 product decision preserves original personalized notifications
and inbox receipts after later Stealth/audience changes. Opening their source
activity must still enforce current access. This supersedes post-issuance hiding
in the earlier 1A design. REC-590's separate correction must reconcile its source
policy, generic push envelope, and REC-589's restrictive grouped read guard.
Unsent pushes still require authorization, and Silent plus the frozen import
manifest stay unchanged. This branch records the revised contract but does not
claim the privacy correction implemented or deployed.

## GSTACK REVIEW REPORT

| Review | Scope | Runs | Status | Findings |
| --- | --- | --- | --- | --- |
| Engineering | Full branch + spec + native scenarios | 1 | Accepted fixes implemented | 1A raw-read guard; 2A native integration coverage |
| Independent adversarial | Notification/ledger architecture | 1 | Complete | No additional verified blocker |
| Native visual | All sender placements | 1 | Complete | 28 states on each phone; dark and accessibility text included |

VERDICT: Engineering review and sender implementation complete. Signed validation passes all 2,576 units, authentication, and three affected UI flows; the custom-answer UI failure remains unresolved, so the follow-up stays draft. The REC-590 notification-history correction and signed-device APNs are separate remaining rollout checks.

NO UNRESOLVED DECISIONS
