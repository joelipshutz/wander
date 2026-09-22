# Joint check-ins implementation validation

REC-566 · September 21–22, 2026 · branch `codex/rec-566-joint-checkin-plan`

The implementation follows the reviewed 88-case contract. Historical v1 groups are not migrated. New v2 creation remains disabled by default; no durable production migration, feature enablement or deployment has occurred. SQL previews used fictional records in transactions that rolled back.

## Implemented behavior

- A separate canonical group event supplies one conversation, while accepted people retain owned visits, ratings, notes, answers and photos. Pending invitations reserve seats without appearing as accepted people. The limit is ten including the starter.
- Feed, profiles and place history share the same card and canonical discussion. Profiles order their subject first. Collapsed cards show three contributions; expansion includes all readable contributions. Hidden people never increase the face-pile overflow.
- Create, accept, edit, invitation management and leave use durable account-bound request IDs. Edits compare the original displayed server timestamp. Acceptance preserves existing parent privacy, metadata and chronological summaries. Blank contribution fields stay blank. Reopened acceptance restores the account’s pending response; its own photo references remain durable and are attached with stable asset IDs after acceptance, including background retry.
- Detachment retains owned visits; starter closure permanently closes the shared discussion. A personal conversation remains permanently personal once standalone engagement begins, including after all that engagement is removed.
- Shared comment receipts survive comment deletion. A stale personal-target composer never redirects its write into a group. Authors can delete their own comments after losing thread access.
- Viewer projections expire on account/privacy changes. Failed refreshes preserve only canonical identity and show a refresh state instead of cached people or a misleading solo conversation. Cold restart restores this account-scoped identity without other people's contribution content; changing accounts clears it. In-flight responses cannot restore a prior audience.
- External sharing exports venue identity only. Active v2 note/rating/answer edits require the upgraded editor; v1 edits and owner-scoped photo/delete operations retain their existing contract.

## Executed database evidence

The six migrations were previewed in order over the linked Astir schema. The strict smoke runner executes pgTAP `finish()` under isolated savepoints and fails the command for any failing assertion; generating SQL alone is not considered validation.

| Check | Result | Evidence |
| --- | --- | --- |
| Strict full smoke after final query optimization | 9/9 rollback batches passed | Local `joint-checkin-implementation-evidence/final-smoke-summary.json` and `final-smoke-part-01` through `09` |
| Five new pgTAP suites | 142 passing assertions: identity 18, creation 13, lifecycle 45, projections 58, security 8 | `supabase/tests/joint_check_in_identity.sql`, `joint_check_ins.sql`, `joint_check_in_lifecycle.sql`, `joint_check_in_projections.sql`, `joint_check_in_security.sql` |
| Existing Shared Visits and private-question regressions | Passed in the full smoke, including 73 Shared Visits and 18 private-question assertions | Existing registered suites; all four invitation snapshot readers retain private-taxonomy filtering |
| Actual simultaneous PostgreSQL requests | 14/14 cases passed | `scripts/test-joint-check-in-races.py`; local `race-results.json` |
| Full-page synthetic database benchmark | p50 995.781 ms, p95 1017.2261 ms, maximum 1024.4 ms over 10 samples; 376,047-byte maximum payload | `supabase/tests/joint_check_in_performance.sql`; local `performance-result.json` |
| Keyset pagination | Five pages without repeated canonical IDs | Same performance fixture |

The race harness uses two independent libpq connections and a lock-holding third connection. It checks that requests actually wait on row/advisory locks before release. Cases cover same/different acceptance requests, removal in both orders, concurrent capacity updates, privacy in both orders, comment/like retries, closure versus engagement in both orders, and rejoin versus first personal engagement in both orders. It loads the production functions into a narrow local fixture with adapters for unrelated metadata/notifications; it does **not** prove full-schema RLS concurrency. Hosted rollback smoke supplies the full-schema authorization checks. Its disposable local database was stopped and removed after saving results.

The benchmark contains 25 ten-person groups, 250 owned contributions with long notes and 2,000 older fictional events. The first measured query had p95 2491.7461 ms. Reusing each group's authorized projection and adding the feed cursor index reduced it to the result above. These are database execution timings, not mobile/network latency or scroll frame measurements. Large production history and media hydration still need an internal-cohort performance check.

## Native evidence and remaining gates

The final compact iPhone 16e run on iOS 26.3.1 passed **2,427/2,427 tests**: all 2,418 unit tests and all nine feed/profile UI tests. This covers two/ten contributors, own and other profile ordering, posting from a profile and reading the same comment in Feed, enlarged text, the 44-point expansion target, existing feed grouping and notification navigation. Screenshots were inspected; the explicit device appearance produces the expected dark treatment on iPhone. The own-profile fixture was corrected to invalidate the normal profile/calendar caches after inserting fictional visits. A subsequent small presentation refinement uses the same venue icon/detail across Feed and profiles, and avoids truncating short notes that have no expansion control; follow-up device runs compile these refinements.

The earlier full regression run completed 2,633 tests: 2,604 passed and 29 failed (2,409 unit and 224 UI). Its two failures in the changed area—a source-contract expectation using the old context name and a small expansion accessibility frame—are fixed and pass in the focused run. The other 27 UI failures have not been reproduced on an unchanged baseline and remain unresolved; do not label them pre-existing or count the full run as passing. Local `native-full-failure-triage.md` lists every failure. Verbose simulator diagnostic collection repeatedly timed out after execution; the final focused run disables only that optional collection, retaining test assertions, logs, screenshots and result bundles.

The first iPad Air 11-inch (M3) run passed four of five joint UI cases. Its remaining assertion compared screen-coordinate bounds to window width, which is incorrect for the centered iPhone compatibility window; the assertion now compares both sides in screen coordinates. The corrected iPad and iOS 26.1 standard-iPhone runs are pending.

Do not equate 142 SQL assertions or 14 races with passing all 88 multi-layer cases. The matrix includes native visual, accessibility and operational conditions beyond these automated checks. Before enabling creation, retain evidence for:

- Final native unit/UI results, two- and ten-person feed/profile/detail parity, and shared conversation navigation.
- Standard/compact/iPad layouts, dark mode, large text, VoiceOver and Reduce Motion; blank acceptance and failed-response recovery.
- Suspended network/account/privacy transitions, photo upload recovery and open editor/composer conflicts on device.
- Old-client and capable-client testing against the deployed additive schema; feature disable/reenable with existing v2 records.
- Notification delivery after audience changes, live media authorization and production-sized performance.

The app flag stays off until the server and client gates pass. Disabling creation does not disable existing v2 reads or lifecycle actions; rollback never converts shared discussions into legacy posts.

## Local evidence and reproduction

Machine evidence is outside the checkout at `../joint-checkin-implementation-evidence/` to keep logs, generated SQL, screenshots and `.xcresult` bundles out of the PR. Durable test code and this report are tracked. Use the workspace's `ios-work.py` helper for every Xcode build/test, reusing its existing checkout cache and simulator reservation. Do not bypass its 50 GiB floor.

Generate linked rollback SQL using `node scripts/supabase-smoke-test.mjs --write-linked-sql PATH` and one `--migration-preview` per ordered migration. Execute through the isolated `supabase-astir` launcher only after verifying the intended project. The race harness accepts a local libpq path, socket and port; run `--help` for its exact arguments. The performance file is a separate rollback benchmark, not part of the routine smoke suite.
