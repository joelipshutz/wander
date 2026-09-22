# REC-597: Consolidate the Feed

Issue: [REC-597](https://linear.app/recme/issue/REC-597/consolidate-feed-with-unified-search-invites-activity-and-shared)

Branch: `codex/rec-597-feed-consolidation`

Plan baseline: `6dd9b4fb89d40966e8a9644e728902fec166a310`

Date: September 21, 2026

## Requested outcome

Joe requested a plan on September 21, 2026 to simplify Astir's Feed into one surface based on the current Places tab. Remove the Places/People switch and retire the separate People feed. Keep people discovery through combined search, recommendations, and invitations. This document is the implementation plan; app implementation has not started.

## Layout, top to bottom

1. Existing Astir masthead on the left; Notifications bell on the upper right, occupying today's Search position.
2. Search field/launcher in the row currently occupied by Places/People, with the existing + Add action immediately to its right. Suggested placeholder: “Search places and people.”
3. Existing “Invite people to Astir” entry, moved out of the People feed.
4. Existing people recommendation shelf (“People you should follow,” retaining its current approved copy/design).
5. “Activity,” replacing every user-visible “Recent” heading for the feed, including loading, empty, and recovery states. Preserve existing activity data, order, grouping, interactions, and refresh behavior.

Keep the existing floating-header behavior, search entry/exit transition, and Add flow. This changes the Feed's internal layout, not the app's bottom navigation.

## Combined search

- Use one input and one results screen. People and Places are result sections, not another pair of navigation tabs.
- Reuse the existing name/@handle lookup (local results plus remote discoverMembers); searching Dana or Ryan must show eligible matching accounts, including accounts not followed and not already cached.
- Show a People section above place results when people match, using existing account rows, profile opening, and Follow/Following behavior. Preserve the current place result ranking, natural-language queries, owner filtering, and save actions.
- Keep the current 225 ms people-search debounce and minimum two normalized characters. People results can update as the user types; retain the existing place submission/refinement behavior.
- Give each result source independent loading/failure handling. Cancel and discard stale queries so a slow earlier response cannot overwrite a newer search. Reset both result types when the field is cleared.
- Preserve server-authoritative visibility: blocked/deleted/ineligible private profiles must not be exposed, and include case-insensitive name/handle matching tests.
- Scope deprecation to the separate People feed. Do not remove shared people-search/recommendation/profile components still used elsewhere.

## Shared Notifications

Both Feed and Profile must open the same Notifications screen with the same data and badge state. Keep Profile's existing entry. Back from the inbox should return to the entry surface with its state preserved.

The current Profile screen owns PlacePlanInvitationInbox and NotificationBadgeStore; lift/share this state at the app/session layer so the Feed badge loads without requiring a Profile visit. Preserve plans and check-in invitations, their review actions, and established notification deep links.

Add persisted follower notifications to this inbox. A new follower (including a follow that makes the relationship mutual) produces one notification, shows the actor's account, and contributes to the badge. Opening either inbox acknowledges the shared badge using the existing semantics; it does not accept invitations. Keep state isolated by signed-in account and refresh on relevant foreground/follow-notification events.

Important backend detail: followed_you/mutual_follow push events already exist, but the current queue suppresses event creation when push preferences are disabled. Therefore merely displaying notification_events will miss follows for some users. Implement a recipient-scoped, durable in-app follow receipt independently of APNs/push opt-in, reusing existing follow triggers/identity where practical and preserving existing push-delivery preferences. Do not derive notifications from follower-count changes. Test duplicate/retry behavior, refollow identity, blocked/deleted actors, and recipient-only access. Do not manufacture unread history for all pre-existing followers on rollout.

Follow requests remain outside this change because they do not exist yet. When introduced, they should use this same inbox; no request UI or approval workflow is added now.

## Implementation sequence

1. Continue in the isolated `codex/rec-597-feed-consolidation` worktree. Refresh against latest `origin/main` and confirm overlapping feed/search/people-ranking work before app edits.
2. Consolidate FeedScreen around the current Places surface; move Search down, keep + beside it, add bell, move the invite entry, and rename Recent to Activity.
3. Wire name/handle lookup into the existing Discover place-search presentation; preserve profile/follow behavior and search cancellation.
4. Share inbox/badge ownership; add the follower receipt repository/read contract and follower rows; connect Feed and Profile to the shared screen.
5. Update first-visit walkthrough targets and instructions, removed People-tab routes/launch arguments, accessibility IDs, and analytics surface attribution. Preserve contacts/invite permissions and presentation behavior. Latest main also added a “Find friends from contacts” route on People: verify it remains reachable through the existing contacts/settings flow when removing that surface, without adding an unrequested module to the new Feed.
6. Validate and open the implementation PR with issue linkage and required TestFlight payload. This plan does not itself change the app or release behavior.

## Acceptance and validation

- No Places/People switch remains in Feed. Bell, Search, +, invite, recommendation shelf, and Activity appear in the requested order.
- Search Dana, Ryan, a partial name, and @handle; verify remote-only users, account opening, following, no matches, place-only results, mixed results, network failure, rapid query changes, and query clearing.
- Search close restores Feed scroll/state. + opens the existing Add flow. Invite opens the existing invite flow; cancel/denied permission remains recoverable.
- A synthetic new follow appears and badges both bells, including when OS push is denied or push preferences are off. Opening either inbox clears both displayed badges; account switching cannot leak counts or contents.
- Existing plan/check-in notifications and post/comment push routing retain their behavior. Follow requests are absent.
- Cover small-screen layout, Dynamic Type, VoiceOver labels/counts, Reduce Motion, loading/empty/error states, and first-visit walkthrough completion.
- Extend meaningful search/badge/inbox and walkthrough tests. Validate any new RPC/RLS with policy tests and the required rolled-back hosted smoke coverage. Use the workspace `ios-work.py` helper for Xcode tests; inspect standard iPhone 17 Pro and compact iPhone 16e. No tests/builds were run during planning.
