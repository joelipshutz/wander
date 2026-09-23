# Privacy ratings and stealth-list test guide

Use the REC-590 branch with two test accounts: A owns the activity and B follows A.
Start A with a public profile and the legacy Everyone default. Enable the setting
that automatically saves places added to lists to Wanna. Use places neither
account has saved unless a case explicitly asks for an existing save.

The complete privacy rollout is not ready for acceptance. The branch adds the
ratings display and stealth-list companion protection; follow requests, account
and activity exclusions, media/share revocation, and notification enforcement
still need implementation. Live rating assertions additionally require the
reviewed ratings RPC to be installed and its SQL regression suite to pass.

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
Older public Wannas linked to stealth lists are not automatically rewritten:
membership alone cannot identify whether the original audience was intentional.

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

## Remaining revocation acceptance

After source authorization and delivery enforcement are implemented, repeat the
same denial through activity detail, profile, Feed, map, search, list previews,
shared visits, comments, photo URLs, share previews, notification inbox, queued
pushes, and notification taps. A visible canonical place or an independently
authored save must never grant access to another person's denied activity.

Verify a cached photo and open activity after a privacy change, after foreground
refresh, after account switching, and after a late request completes. The offline
behavior for other people's activity remains a product choice; the owner's own
saves and offline capture stay available. Public previews of protected activity
must use generic artwork and text. Previously exported copies cannot be recalled.

Small-sample inference from Astir's anonymous score/count is deferred to
[REC-608](https://linear.app/recme/issue/REC-608/review-small-sample-inference-in-global-astir-ratings).
