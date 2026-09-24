# Privacy ratings and stealth-list test guide

Use the REC-590 branch with two test accounts: A owns the activity and B follows A.
Start A with a public profile and the legacy Everyone default. Enable the setting
that automatically saves places added to lists to Wanna. Use places neither
account has saved unless a case explicitly asks for an existing save.

The complete privacy rollout is not ready for acceptance. Ratings, automatic
private companions, cached activity/photo access checks, and source-aware server
rules are implemented on the branch. Hosted migration/worker verification and
two-account device acceptance are required before calling the gaps closed.
Follow requests and account/activity exclusion controls remain separate unfinished
parts of REC-590; use the existing audience/private/block controls for these tests.

Deployment order: publish the generic-preview website reader, apply the reviewed
`activity_source_privacy_and_ratings` and `generic_share_previews` migrations,
deploy `push-notification-worker`, run the standard hosted smoke gate, then test
the matching iOS branch. The source/privacy SQL regression runs inside a rollback.
Do not describe an unapplied migration or an unexecuted smoke test as a pass.

The storage cutover also requires a CDN purge through the Storage API and checks
against previously issued public and signed URLs. A SQL bucket update alone does
not prove edge-cache invalidation. Purge `share-card-previews` after making it
private; invalidate legacy visit-photo URLs and verify old URLs cannot fetch bytes
before accepting photo revocation. An unexpired signed token can repopulate a cache,
so a purge alone is insufficient for those tokens. Keep this rollout gate open
until legacy URLs have been retired or their expiry plus cache invalidation is
verified. See [Supabase's CDN behavior](https://supabase.com/docs/guides/storage/cdn/smart-cdn)
and [purge API](https://supabase.com/docs/guides/storage/cdn/purge-cdn-cache).

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

Small-sample inference from Astir's anonymous score/count is deferred to
[REC-608](https://linear.app/recme/issue/REC-608/review-small-sample-inference-in-global-astir-ratings).
