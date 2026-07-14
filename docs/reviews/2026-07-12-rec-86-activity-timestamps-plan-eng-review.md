# REC-86 Saved Activity Timestamps Engineering Review

Date: 2026-07-12
Branch: `codex/rec-86-activity-time`
Linear: `REC-86`
Status: clean to implement

## Scope Challenge

The three reported symptoms share one root cause and should ship as one contract fix:

- Remote visible-place rows omit persisted timestamps.
- `RemoteVisiblePlaceDTO` therefore constructs `LocalUserPlace` with `.now` defaults.
- Been activity renders that synthetic current time.
- Discover sorts those synthetic times, effectively reversing decode order.
- Latest Activity never renders the save time.

This does not require a new activity service, a second request, local inference, or a data backfill. PostgreSQL already has the correct timestamps.

Expected implementation size: one RPC migration, one DTO mapping change, one small Discover projection/formatter, two focused XCTest files, one pgTAP contract test, and coordination docs. This is below the complexity threshold for scope reduction.

## Architecture

```text
public.user_places
  visited_at / saved_at / created_at / updated_at
                  |
                  v
app.visible_places_in_view + app.profile_visible_places
  preserve RLS, grants, avatar field, category/rating fields
                  |
                  v
public RPC wrappers -> RemoteVisiblePlaceDTO
                  |
                  v
LocalUserPlace
  Been activity: visitedAt ?? savedAt
  Discover: savedAt DESC, stable id tie-break
                  |
                  v
Latest Activity row: place metadata + compact saved-time label
```

### Contract Decisions

1. The database remains the only timestamp source. Client receipt time is never a fallback for remote data.
2. The migration lands before the app change. Adding JSON fields is backward-compatible with build 68, while the new DTO intentionally requires the persisted non-null timestamps.
3. `visited_at` stays optional because wanna-go rows legitimately have no visit date. `saved_at`, `created_at`, and `updated_at` are required by the schema.
4. Discover owns its newest-first presentation order and uses `saved_at`, not `updated_at`; editing a note must not make an old save look newly saved.
5. Existing profile RPC ordering remains unchanged to avoid changing unrelated profile behavior.
6. The migration restores `owner_avatar_url`, which a later RPC recreation accidentally dropped even though the iOS DTO still expects it.
7. Both app functions remain `stable security invoker`, pin `search_path`, and keep execution limited to `authenticated`.

## Failure Modes

| Failure | User impact | Prevention |
|---|---|---|
| App ships before migration | Visible-place decode fails and social places disappear | Deploy and verify migration first |
| Missing timestamp silently becomes `.now` | Original bug returns | Required DTO fields; no `.now` fallback |
| Discover sorts by `updated_at` | Edited old saves jump to the top | Sort only by `saved_at` |
| Equal timestamps reorder between renders | Activity rows jump around | Stable `user_place_id` tie-break |
| RPC recreation loses security posture | Unauthorized execution or RLS surprises | pgTAP metadata/grant assertions |
| RPC recreation loses existing fields | Avatars/category/rating UI regressions | Preserve full latest return shape and test avatar plus timestamp mapping |
| Small future offset from clock skew | Misleading negative relative time | Treat offsets up to five minutes as `just now` |
| Implausible future-dated row | Activity remains pinned above real saves | Demote it in ordering and render an absolute date |
| Explicit visit date changes without a matching parent write | Been activity keeps showing the old date | Trigger recomputes the latest active explicit visit into `user_places.visited_at` |
| Long place metadata truncates the timestamp | User still cannot tell when a place was saved | Keep the timestamp fixed-width and truncate metadata first |

## Test Plan

```text
SQL contract
  explicit persisted timestamps + avatar
        -> both RPCs return exact values
        -> security invoker/search_path/grants remain correct

DTO contract
  RFC3339 JSON row
        -> LocalUserPlace receives visited/saved/created/updated dates

Presentation contract
  unsorted rows with distinct/equal savedAt values
        -> newest first + deterministic tie-break
  savedAt at now/minutes/hours/days/old date
        -> readable saved-time label
  legacy Been without explicit visit object
        -> visitedAt, otherwise savedAt, never updatedAt/now
```

Required validation:

- Focused XCTest for remote mapping, Discover ordering/labels, and Been fallback.
- Full `xcodebuild test` suite.
- `git diff --check`.
- Local pgTAP when available; otherwise rollback-wrapped hosted pgTAP before applying.
- Apply linked migration, verify migration list and function metadata, then smoke-test payload values.

## Pre-Landing Hardening

The final review against latest `main` identified three gaps beyond the original
RPC fix. They are included in the same release because each can otherwise
recreate one of the reported symptoms:

1. Explicit `place_visits.visited_at` edits now recompute the latest active
   visit into the denormalized `user_places.visited_at` summary. The trigger is
   narrow, `SECURITY DEFINER`, pins `search_path`, skips derived backfill rows to
   avoid recursion, and has no direct authenticated execute grant.
2. Saved timestamps more than five minutes in the future no longer sort ahead
   of valid activity or render as `just now`; they sort last and display an
   absolute calendar date. Small clock-skew offsets retain the forgiving
   `just now` treatment.
3. Latest Activity keeps the saved-time label visible on narrow layouts by
   allowing locality/category metadata to truncate first.

The additive trigger migration was applied to the linked hosted project.
Rollback-wrapped hosted pgTAP passes 27/27 assertions, including trigger
metadata, explicit visit edit propagation, exact RPC timestamps, avatar fields,
RLS-facing behavior, and grants. The integrated iOS suite passes 291/291 tests
on iPhone 16 Plus / iOS 18.6.

## Not In Scope

- A general event/activity table.
- Fetching every social user's `place_visits` and photos.
- Changing profile list ordering or map pin ordering.
- Rewording other place-profile activity copy.
- TestFlight release; this request is implementation and validation only unless separately requested.

## Parallelization

Implementation stays serial because the SQL return shape and Swift DTO are one shared contract. Tests can run in parallel only after that contract compiles. Splitting the migration and DTO across agents would add coordination risk without reducing meaningful elapsed time.
