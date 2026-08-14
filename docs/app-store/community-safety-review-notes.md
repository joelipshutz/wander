# App Review notes — community safety

Use `reviewer-notes.txt` as the source for the App Review Notes field. This file retains the operational safety detail and launch-owner placeholders that must be resolved before submission.

## Reviewer walkthrough

rec.me includes user-generated profiles, place memories, activity, comments, photos, and shared lists. The build provides filtering, reporting, blocking, and human review:

1. **Report a profile:** open another person's profile, tap the actions button, then **Report**.
2. **Report activity or a place memory:** open Activity or the check-in history on a place, tap the ellipsis, then **Report activity**. In check-in history, the report is tied directly to the shared place memory even when no activity event is available.
3. **Report a comment:** open an activity's comments, swipe another person's comment or use its accessibility actions, then tap **Report comment**.
4. **Report a photo:** open another person's full-screen place photo, tap the ellipsis, then **Report photo**.
5. **Report a shared list:** open a list owned by another person, tap the ellipsis, then **Report list**.
6. **Block a person:** report confirmation offers **Block this person**. A direct Block action is also available from that person's profile. Blocking removes the person and their content from the viewer's social and discovery surfaces.
7. **Guidelines and support:** Profile → Settings → Legal & Safety contains Community Guidelines, Support, Privacy, and Terms.
8. **Account terms:** the sign-in/sign-up screen links the Terms of Use, Community Guidelines, and Privacy Policy directly beside the continue actions.

Reports are private. The reported person is not told who submitted the report. Authenticated users cannot read the report queue or its evidence snapshots. A server-side visibility check prevents a caller from reporting content they cannot see or spoofing a different content owner.

## Filtering and response

The app performs a deterministic client check before shared text is saved. The database applies the same minimum policy to place metadata, profile text, place notes, visit answers, list text, and comments, so a modified client cannot bypass it. Private report details may quote the content being reported and are visible only to the safety workflow. Photo moderation is report-driven for launch.

Reports enter a private moderation queue with a captured content snapshot and append-only audit history. Dangerous or sexual-content reports are marked urgent. The launch response commitment is:

- urgent: acknowledge within 4 hours and act within 24 hours;
- normal: triage within 1 business day and resolve within 2 business days.

Primary reviewer: `[name and role]`

Backup reviewer: `[name and role]`

Support contact supplied in App Store Connect: `[verified monitored address]`

The public Support page currently publishes `support@getrec.me`; verify receipt and ownership before replacing the placeholder above.

Do not submit the build until those three fields are complete, the production moderation migration and live queue test have been verified, and the dedicated review account can enter a populated fictional graph without requiring an external inbox, phone, or one-time code.

## Suggested App Review Notes copy

> rec.me is a trusted-people social map with user-generated profiles, place memories, activity, comments, photos, and shared lists. Every shared-content surface includes an in-app report action. Reports are private, visibility-checked on the server, and enter a service-role-only human moderation queue with evidence snapshots and an audit trail. The report confirmation also offers immediate blocking; blocked users and their content are removed from the viewer's search, profiles, lists, activity, and map results. Shared text is checked in the client and enforced again by database triggers. Community Guidelines and Support are available from Profile → Settings → Legal & Safety. Our named safety reviewers cover urgent reports within 4 hours/24 hours and normal reports within 1/2 business days. Review account: [credentials in App Store Connect].
