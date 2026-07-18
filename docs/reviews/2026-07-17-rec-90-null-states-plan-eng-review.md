# REC-90 Discover Null States — Engineering Review

Date: 2026-07-17
Branch: `codex/rec-90-discover-plan`
Linear: `REC-90`
Status: APPROVED TO BUILD

## Outcome

Build the first REC-90 slice as one network-acquisition loop:

1. Places keeps newest-first Activity. After a successful load with zero privacy-visible followed-user rows, it shows a purposeful empty state with a **Find people to follow** action.
2. People shows a horizontally scrolling **People worth following** shelf whenever no member search is active.
3. Both surfaces read the same cached recommendation response and use the same profile-card component.
4. A successful inline Follow keeps the card visible as **Following** for the current response, refreshes the existing social graph and visible-place cache, and allows Activity to populate without silently claiming success on failure.

This is narrower than the earlier full Discover direction. Search-answer work, place recovery, city shelves, contacts, recommendation dismissals, and place-derived ranking remain deferred.

## Scope Challenge

The original plan combined a Discover redesign, people recommendations, search semantics, recovery candidates, city discovery, and new privacy/consent fields. That was too large for one trustworthy release.

The approved slice contains only the null/default states and the minimum real-profile data path needed to make them useful. It does not create fictional production profiles or social proof. All active non-private profiles are eligible by default; Private Profile accounts are excluded server-side.

## What Already Exists

- `DiscoverScreen` already owns the permanent Places/Members tabs, newest-first Activity presentation, member search, profile navigation, and the app's four-tab shell.
- `WanderStore.follow(userID:source:backend:)` already persists a follow, waits for server acknowledgement, and refreshes the remote graph and visible places.
- `ProfileRepository`, `SupabaseProfileRepository`, and `WanderBackend` are the correct existing remote boundary.
- `ProfileShell` already contains the allowed public card fields and viewer-relative relationship.
- `profiles.is_private_profile`, owner privacy updates, local hydration, and content-private behavior already exist on current `main`.
- Profile and follow RLS already hide blocked relationships. The final profile search/graph functions still need explicit Private Profile filtering.
- The approved horizontal-card visual direction exists under `preview/discover-redesign/`.

No new service class, coordinator, persistence subsystem, or navigation route is required.

## Architecture

```text
authenticated Discover appearance
              |
              v
 WanderStore.refreshDiscoverPeopleRecommendations
              |
              v
      ProfileRepository (existing)
              |
              v
 public.discover_profile_recommendations(limit)
              |
       security invoker + RLS
              |
       +------+-------------------+
       | profiles                 | follows
       | public, active, unblocked| graph signals only
       +------+-------------------+
              |
              v
 one [DiscoverPeopleRecommendation] response
       +------+-------------------+
       |                          |
 Places Activity empty     People default shelf
       |                          |
       +------ shared card -------+
                    |
                 Follow
                    |
        existing FollowRepository RPC
                    |
         server ack / failure truth
                    |
       graph + visible places refresh
```

### Recommendation RPC

Add one authenticated, `security invoker` RPC. It may inspect only RLS-readable `profiles` and `follows`; it must not inspect or return place data.

Eligibility:

- exclude the viewer;
- exclude deleted or Private Profile accounts;
- exclude profiles already followed by the viewer;
- exclude blocks in either direction through RLS and explicit predicates;
- include all remaining active public profiles by default.

Ranking and reason precedence:

1. Candidate follows the viewer: `follows_you`.
2. People the viewer follows also follow the candidate: `shared_follows`, descending aggregate count.
3. Remaining public profiles: `suggested`, newest profile first, then normalized handle for a stable tie-break.

The response returns only the public profile shell, `reason_kind`, optional `shared_follow_count`, and final rank. The client receives no graph identities, place names, place counts, private activity, location inference, or contact data.

The RPC clamps its limit to 1–50, pins `search_path`, revokes `anon`/`public`, and grants only `authenticated`.

### Privacy hardening

The same migration makes the chosen Private Profile contract authoritative for the final RPC definitions:

- profile search omits Private Profile accounts;
- follower/following results omit Private Profile accounts and do not expose another private account's graph;
- direct follow rejects a private/deleted target;
- recommendations omit Private Profile accounts.

The owner can still view their own following/follower graph while private; other callers cannot enumerate it.

### Client state

`WanderStore` owns a small shared load state: idle, loading, loaded, or failed. It deduplicates simultaneous refreshes and clears the state when the signed-in identity changes or signs out. No recommendation request is made while signed out.

The UI trigger contract is:

- Places empty state: show only after the Activity data request has completed and rendered Activity count is zero. Loading and failure are separate states.
- People shelf: show whenever no member search query is active, regardless of follow count.
- Empty recommendation response: explain that nobody is suggested yet and keep member search available.
- RPC failure: show retry affordance and never substitute a false success or fictional people.
- Follow tap: disable only that card while in flight. On acknowledgement, keep it in the cached response as Following until the next explicit/full recommendation refresh. On failure, restore Follow and expose retryable failure copy.

## Code Quality Review

- Reuse `ProfileRepository`; add one protocol method and DTO rather than a new recommendation service.
- Keep recommendation state and remote orchestration in `WanderStore`; views do not call Supabase.
- Extract one reusable recommendation shelf/card so Places and People cannot drift.
- Preserve the existing search and friends list behavior. Active member search replaces proactive recommendations.
- Make the async store follow method return acknowledged success so UI state is truthful without reading global error text.
- Keep new types explicit and `Equatable`; no `any`, force casts, or new dependency.
- Do not persist the recommendation cache across app launches in this slice; stale social suggestions are worse than a small refresh.

## Test Review

### Coverage map

```text
                         RPC contract tests
              +--------------------------------+
              | auth/grants/search_path/RLS    |
              | private/block/follow exclusion |
              | reason order + stable rank     |
              +---------------+----------------+
                              |
                     repository decode tests
                              |
              +---------------+----------------+
              | WanderStore state tests        |
              | load/success/empty/error/dedupe|
              | signed-out reset/follow ack    |
              +---------------+----------------+
                              |
                   presentation contract tests
              +---------------+----------------+
              | Activity load vs empty vs error|
              | People search vs default shelf |
              | Follow/Following/retry states  |
              +---------------+----------------+
                              |
                    simulator visual QA
                  iPhone 17 Pro + 17e
```

Required automated coverage:

- pgTAP metadata and behavior tests for recommendation, search, graph, private target follow rejection, blocks, current user, already-followed profiles, reason precedence, limit, and stable rank.
- repository test for RPC name, parameter encoding, DTO mapping, and reason decoding.
- store tests for success, empty, error, request deduplication, sign-out clearing, profile hydration, and acknowledged follow success/failure.
- source/presentation contract tests for both trigger paths, persistent tabs, CTA mode switch, horizontal shelf, and accessible Follow states.
- full existing XCTest suite plus generic simulator build.
- screenshots of the main Places empty and People default states on the current large and smaller iPhone targets.

## Performance Review

- One bounded SQL query replaces per-card requests; no N+1 profile or graph fetches.
- The client shares and caches one response per signed-in appearance rather than fetching separately for Places and People.
- Only the follow mutation refreshes graph/place data. Recommendation cards do not prefetch protected place content.
- RPC work is bounded by the active public-profile candidate set and a maximum response of 50. Existing follow indexes support the `exists` and shared-follow joins; no place-table scan is introduced.
- Search remains capped at 20. No image binary is returned by the recommendation RPC; existing avatar URL loading/caching remains unchanged.

## Failure Modes

| Failure | User-visible behavior | Recovery |
|---|---|---|
| Signed out | No people RPC; current auth gate remains authoritative | Sign in, then refresh |
| Recommendation loading | Skeleton/progress treatment, not an empty claim | Wait |
| Recommendation RPC fails | Honest retry panel; Activity rows remain usable | Retry |
| Zero eligible profiles | Honest no-suggestions copy plus search | Search or retry later |
| Follow RPC fails | Card returns to Follow with failure text | Retry |
| Follow succeeds but Activity stays empty | Following is truthful; no claim that a place exists | Future eligible saves populate Activity |
| Profile becomes private between load and follow | Server rejects follow; card remains retryable/refreshable | Refresh recommendations |
| Block/private change leaves cached card | Follow is rejected or card disappears on next refresh; server remains authoritative | Refresh |

## Sequential Build Plan

These steps should remain sequential because each establishes a contract consumed by the next:

1. Add the migration and pgTAP contract.
2. Add recommendation models, repository method, DTO, and repository tests.
3. Add the shared store state/refresh/follow acknowledgement and store tests.
4. Add the shared shelf/card and wire Places/People triggers.
5. Add presentation contracts and run focused tests.
6. Run the full suite, generic build, migration verification, and dual-size visual QA.

## Explicitly Not in Scope

- Natural-language answer-engine redesign or search truth fixes.
- Place recovery / Places You May Have Been.
- City shelves, device location, Contacts, invitations, or fake production accounts.
- Recommendation consent flags, place/activity-derived eligibility, popularity, ratings, or taste ranking.
- Dismissals, pagination, push notifications, analytics experiments, or admin curation.
- TestFlight build, release, or Slack announcement.

## GSTACK Review Report

| Section | Verdict |
|---|---|
| Scope | Reduced to one shippable network-building loop |
| Architecture | Reuses current boundaries; one invoker RPC; no place-data access |
| Code quality | Shared store state and shared component; no new service layer |
| Tests | Complete RPC → repository → state → UI → visual coverage specified |
| Performance | One bounded response, no N+1, no protected-content prefetch |
| Outside voice | Not used; no delegated or external review was requested |

No unresolved implementation decision remains. No new TODO comments are proposed; deferred product slices stay in Linear/product docs rather than source.
