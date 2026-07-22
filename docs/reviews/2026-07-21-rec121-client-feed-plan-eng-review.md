# REC-121 Client Feed Failure — Engineering Review

**Date:** 2026-07-21
**Scope:** Restore the signed-in iOS Feed request after TestFlight Build 86
still reaches the unavailable state.

## Evidence

- The hosted `followed_feed` RPC succeeds for Joe's authenticated database
  role and returns a valid empty envelope.
- A new short-lived token minted for Joe's active Clerk session succeeds
  against the exact production REST RPC with HTTP 200.
- The Build 86 client still falls into the Feed recovery state. Release
  analytics are not configured, so its error class is not currently emitted.

## Proposed minimal change

Keep the existing `WanderSupabaseClient` and repository boundary. When a
shared authenticated RPC receives 401 or 403, request one fresh Clerk token
with cache bypass and repeat that same request exactly once. If the second
request fails, preserve the existing typed error and Feed recovery behavior.

This targets stale/cached-session claims without weakening authorization,
adding client-side data fallbacks, changing RLS, or masking a persistent
server failure as an empty Feed.

## Data flow and failure handling

```text
FeedScreen.refresh
  -> WanderStore.refreshFollowedFeed
  -> SupabaseFeedRepository.followedFeed
  -> WanderSupabaseClient.call
  -> Clerk cached token -> Supabase RPC
       401/403 only -> Clerk forced fresh token -> same RPC once
  -> decoded Feed page -> loaded / valid empty state
       otherwise -> existing Feed recovery + Retry
```

The forced refresh is intentionally in the common client instead of Feed UI:
all authenticated RPCs receive the same correct recovery semantics, while the
retry is bounded to one request and never promotes a failed fetch to an empty
Feed.

## Validation

- Unit-test the forced-token retry after 401 and its bounded failure behavior.
- Run the focused Feed store and remote repository tests, then the full iOS
  test suite on the required iPhone 16 Plus simulator.
- Verify the exact hosted authenticated RPC remains HTTP 200 after the change.

## Decisions

No product, data-retention, or security-policy decision is required. The
change preserves the server as the authority and sends no new user data.
