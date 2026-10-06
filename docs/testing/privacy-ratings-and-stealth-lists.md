# Privacy ratings and stealth-list test guide

Use the REC-590 branch with two test accounts: A owns the activity and B follows A.
Start A with a public profile and the legacy Everyone default. Enable the setting
that automatically saves places added to lists to Wanna. Use places neither
account has saved unless a case explicitly asks for an existing save.

The current test slice covers the three rating displays, automatic private-list
Wannas, cached activity/photo reauthorization, and source-aware shared content.
Follow requests and account/activity exclusion controls remain unfinished parts
of the larger REC-590 transcript and are tracked in REC-634; use the existing
audience/private/block controls for the checks below.

Both privacy migrations and the source-aware notification worker are deployed.
The generic-preview website reader is deployed to astirmovement.com. The full
hosted rollback smoke and source-authorization regression pass against the live
schema without preview migrations. Both photo buckets are private. No ambiguous
historical Wanna was changed: the hosted audit found no authoritative companion
origins eligible for repair; future origins are recorded.

Legacy signed-photo CDN retirement is tracked separately in
[REC-633](https://linear.app/recme/issue/REC-633/verify-retirement-of-legacy-signed-photo-and-preview-links).
Merging the tested app protections does not establish retirement of every old link;
that verification is still required before the full historical cutover is called closed. The project is on the Free plan; manual CDN purge requires Pro or provider assistance.
The scoped Supabase support request has been submitted and the dashboard
confirmed receipt. Provider completion is pending. No billing changes or visit-photo rewrites have been made.
All 12 recorded historical public artwork URLs now reject access. Their original
images were moved to a private archive, preserving bytes, object identity,
ownership, and custom metadata. The former paths contain only generic Astir
artwork. A final public-link check rejected all 130 stored-object URLs: 106
unchanged visit photos, 12 archived previews, and 12 generic replacements. A
synthetic signed-photo URL was warmed to a CDN hit and rejected after expiry. That representative test
and the elapsed maximum client token lifetime do not establish a global purge
of every previously issued signed URL.
See [Supabase's CDN behavior](https://supabase.com/docs/guides/storage/cdn/smart-cdn).

New protected-image uploads request `no-store` for HTTP caches; the app retains
its authorized, viewer-scoped offline cache. Public uploads use valid
`max-age=3600` syntax.

For local testing, open the privacy worktree's `Wander.xcodeproj`, confirm branch
`codex/rec-590-privacy`, choose **Wander → iPhone 17 (iOS 26.5)**, and Run. Use
normal sign-in for the two-account checks; demo fixture tests exercise layout
only. The checked-in public Clerk/Supabase configuration targets the live alpha
backend. Xcode's Branch Chooser was verified on this worktree on September 28.
This branch has not been uploaded to TestFlight.

## Validation and acceptance

[PR #716](https://github.com/joelipshutz/wander/pull/716) and
[REC-590](https://linear.app/recme/issue/REC-590/define-astir-activity-audiences-and-privacy-settings)
record the latest verified commit, native results, provider cleanup status, and
remaining gates. Check those records before treating this as a release-ready build.

The `Privacy native validation` workflow runs all unit tests, the two rating
layout tests, and the comment-draft foreground regression on iPhone 17, then
repeats the layouts on compact iPhone 16e. Its
artifacts include result bundles and screenshots for the three rating rows and
the start/end of the largest-text explanation. The explanation uses a scrollable
native sheet with a Done button at accessibility sizes and a popover at normal
sizes. A passing layout fixture does not replace the live two-account checks below.

The search benchmark retains its 50 ms budget. Track its measured native result
in [REC-627](https://linear.app/recme/issue/REC-627/investigate-trusted-memory-search-exceeding-the-50-ms-performance);
a phrase microbenchmark does not prove end-to-end search performance.

Run the following checks with fictional test-account content. Manual acceptance
and provider cleanup are distinct: testing this branch does not prove historical
CDN entries or old analytics records have been removed.

## Automatic Wannas

1. As A, create a stealth list and add a new place from search. Confirm that the
   place appears in both the list and A's Wanna collection, with a self-only
   audience. Refresh B's Feed, A's profile, and the map. B must not see A's Wanna.
2. Repeat using a place discovered through another person's activity. Only the
   public place metadata should be copied. A's new Wanna must be self-only;
   the source person's notes and answers must not be copied into it.
3. Select a public list and a stealth list together for a new place. The new
   Wanna must remain self-only regardless of list order. In failure-injection
   coverage, a failed private-list addition must not make a successful
   public-list addition publish the new Wanna.
4. Add a previously public Wanna to a stealth list. Its existing chosen audience
   stays public. Add a previously self-only Wanna to a public list: the Wanna
   stays self-only. The list's place membership and the owner's activity are
   separate visibility decisions.
5. Add a new place to a stealth list without a connection, then reconnect and
   retry sync. The Wanna must remain self-only before and after retry, with no
   public Feed event in between.
6. Open a collaborative list containing a place B has independently saved, then
   revoke B's access or block the list owner and refresh. The list membership
   must disappear even though B can still see their own saved place.

A failed save must not be presented as successfully synced. Verify activity
links as B in addition to checking whether a row happens to be absent from Feed.
Automatically hide historical Wannas only when the server has authoritative
companion provenance and no later explicit audience override. Ambiguous historical
saves stay unchanged. In a rollback fixture, verify one proven companion is
repaired, an ambiguous public save is untouched, and a later deliberate audience
choice is preserved.

## Ratings

1. Open a place profile with no ratings. Confirm three slots: **Your rating**,
   **Friends rating**, and **Astir rating**, each showing `—/5`. There must be no
   Fit score or substitute Featured 5 in this section.
2. Give A two check-ins rated 2 and 4 at the same place. A's Your rating should be
   3 with two check-ins. Followed people's readable ratings are averaged per
   person before forming Friends; Astir averages all active rated check-ins.
3. Hide a followed person's last readable rating. For the viewer, both the
   Friends contribution and person count disappear, while Astir retains the
   rating. Repeat with only some of that person's ratings hidden.
4. Open the same place from search on a fresh client with no cached visible
   save. The Astir result must match the place opened from a saved-place entry.
5. Delete a rated check-in, then refresh. Both its score and count contribution
   disappear. Deleted accounts must also be excluded from Astir.
6. Interrupt the ratings request. The rail should say **Unavailable** and offer
   **Retry ratings**, rather than claiming there are no ratings. Switch accounts
   or places while a request is in flight; an old response must not appear.
7. Check iPhone 17 and a smaller phone, including an accessibility text size.
   All three labels, values, empty states, and the explanation must remain
   readable without clipping or overlapping controls.

Per-activity Hide this time and Always hide from cases wait for those controls
and their server enforcement. The empty-ratings simulator regression uses the
explicit demo fixture and does not prove the live aggregate RPC works.

## Cached activity and photos

1. As B, open A's check-in, comments, and photos while connected. Reopen the same
   activity and the place-profile history while offline. Previously cached content
   should remain available; an uncached photo should not be fabricated.
2. Reconnect B. As A, make that source self-only, delete it, or block B. On B,
   reopen the activity and place profile and return from the background. The
   denied header, note, rating, comments, and photos must disappear.
3. After B has observed that denial, go offline again, reopen, and restart the
   app. The old photo/activity must not return. Check a second account on the same
   device cannot inherit B's cache.
4. Simulate an expired session or server error. Show unavailable/retry rather than
   using the offline exception. Repeat with a slow request completing after an
   account change or denial.
5. Create an owner photo offline, then reconnect. Interrupt the final metadata
   write after the bytes upload and retry. It must finish without uploading the
   bytes again or relying on a signed URL.

## Shared visits, notifications, and links

1. Invite B to A's shared visit, then hide/delete the source before B accepts.
   Its inbox snapshot, notification, and deep link must no longer reveal it.
2. Accept a shared visit with a copied source photo. Add B's own note, rating, and
   separate photo. Revoke B's source access. The copied photo disappears while
   B's independent content remains. Retrying the old acceptance operation must
   not return the revoked photo path.
3. Queue a social notification, revoke source access, then claim it. Repeat by
   revoking after claim but before delivery. Neither should send. A stale claim
   token must not send or settle another claim. Authorized social push copy is
   generic; tapping still checks access in Astir.
4. Share a protected activity or stealth list in Messages and open its web link
   signed out. Show generic Astir artwork/text and the exact Open in Astir action.
   Inspect Open Graph metadata too: no source note, title, photo, or contributor.
   An old public artwork URL must stop downloading after the bucket cutover and
   CDN invalidation; test the existing URL, not only a newly generated one.
5. Recheck list membership after collaborator removal/blocking even when B still
   owns an independent save of the same canonical place. Canonical-place access
   does not grant access to A's denied activity.

Previously downloaded exports and browser-cached copies cannot be recalled by
the client. Token expiry alone does not prove old signed URLs are inaccessible:
CDN copies can outlive it. Legacy URL retirement is part of the rollout gate above.
New visit-photo signing must be denied while authenticated downloads and owner
upload/retry/delete continue to work.

The worker reporting route must remain read-only and export aggregate counts only.
Verify `analytics_snapshot` never claims notifications or requests recipient/audit
rows containing identities or notification copy. Prior private PostHog audit
exports require a retention cleanup before claiming that secondary copy is removed.
An aggregate-only September 28 audit found 7,954 historical rows: 7,354 recipient
snapshots, 215 snapshot-completed events, and 385 delivery-audit events, spanning
September 21–24 UTC. Scoped removal was approved and submitted as
[PostHog support ticket #75809](https://us.posthog.com/project/557259/my-tickets?ticket=01a0ea42-9675-0000-44b2-49b7c1d197ef).
The request covers only those event names from September 21 at 23:01:56 UTC
through September 24 before 04:16:00 UTC. No deletion is confirmed yet; deleting
whole PostHog people could erase unrelated analytics.
Historical analytics cleanup is optional follow-up in
[REC-620](https://linear.app/recme/issue/REC-620/resolve-retention-of-historical-notification-diagnostics-after-privacy)
and does not block acceptance testing or rollout. The submitted support request
has not been withdrawn, and deletion remains unconfirmed. Provider confirmation
and a zero-count recheck would be needed only before claiming those copies were
removed. Future reporting remains aggregate-only.

No historical user-facing activity needs editing or deletion for this testing
slice based on the completed audit. Existing check-ins, ratings, lists, original
photos, and Wannas are preserved. Report the affected scope before any future
historical-record cleanup. Legacy link invalidation preserves stored photos and
remains separate from deleting app data.

Small-sample inference from Astir's anonymous score/count is deferred to
[REC-608](https://linear.app/recme/issue/REC-608/review-small-sample-inference-in-global-astir-ratings).
