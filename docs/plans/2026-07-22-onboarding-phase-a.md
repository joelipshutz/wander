# REC-132 — Phase A Onboarding and Logged-Out Entry

## Outcome

Ship an auth-first first-run experience that sells rec.me quickly, captures the
minimum durable identity needed for the social graph, offers optional activation
permissions without blocking entry, and routes returning users directly into the
main app without an onboarding flash.

## Scope

1. Logged-out three-slide carousel with real seeded in-app map screenshots.
2. Seven-second auto-advance, manual paging, and accessibility/background pauses.
3. Clerk sign-up and log-in through the existing native Clerk UI.
4. Required display name and username with an optional profile photo.
5. Optional location, contacts, friend suggestions, and notifications.
6. Durable server completion state and safe returning-user routing.

## Entry State Machine

```text
launch
  |
  +-- auth loading ----------------------------> branded launch surface
  +-- signed out ------------------------------> value carousel
  |                                                +-- sign up / log in
  +-- signed in
       |
       +-- completion cached ------------------> main app + background refresh
       +-- completion unknown -----------------> fetch current profile
       |                                            +-- complete -> main app
       |                                            +-- incomplete -> identity
       |                                            +-- offline -> retry / continue offline
       +-- identity completed -----------------> permissions sequence
                                                    +-- location (optional)
                                                    +-- contacts (optional)
                                                    +-- friend suggestions (optional)
                                                    +-- notifications (optional)
                                                    +-- main app
```

## Server Contract

- Add nullable `profiles.onboarding_completed_at`.
- Backfill current active profiles so existing users bypass onboarding.
- Extend `current_profile` responses with completion state.
- Extend `update_own_profile` with a server-owned mark-complete boolean and make
  it an authenticated insert-or-update so Clerk webhook timing cannot strand a
  newly signed-up user.
- Add a narrow boolean handle-availability RPC. Final profile submission remains
  authoritative against concurrent claims.
- Preserve `security invoker`/`security definer`, pinned `search_path`, RLS, and
  grants explicitly in the migration and regression tests.

## Client Boundaries

- `AppEntryCoordinator`: resolves auth/profile/completion and owns pending links.
- `OnboardingFlow`: reusable step router; Phase B can mount permission steps as a
  contextual tutorial without redesigning the screens.
- `ProfileIdentityDraft`: shared normalization and validation for onboarding and
  Edit Profile.
- `OnboardingCompletionStore`: positive, per-user local cache only; server remains
  authoritative and account deletion clears the cache.
- Existing Clerk UI, avatar image processing/upload, profile repository, follow
  repository, location manager, contacts boundary, push manager, and analytics
  client are reused rather than rebuilt.

## Failure Handling

| Failure | User experience | Automated coverage |
|---|---|---|
| Returning-user auth refresh is slow | Branded launch surface; no carousel flash | Unit + UI |
| Clerk webhook profile is late | Atomic profile upsert creates the caller row | pgTAP + repository |
| Username is taken | Field-level error; form values remain | Unit + repository + pgTAP |
| Network/profile fetch fails | Retry and Continue offline | Unit + UI |
| Optional photo upload fails | Completion succeeds; photo can be retried later | Unit |
| Permission denied | Continue to the next step | Unit + UI |
| Contacts unavailable/empty | General trusted-account suggestions | Unit + UI |
| App backgrounds during carousel | Auto-advance task cancels | Unit |
| VoiceOver or Reduce Motion enabled | Auto-advance pauses; manual paging remains | Unit |
| Deep link arrives before completion | Pending route opens after main app mounts | Unit + UI |
| User signs out or switches accounts | Identity shell/cache is isolated per user | Unit + UI |

## Test Plan

- Pure unit tests for entry-state resolution, completion cache, carousel timing,
  identity validation, permission step routing, and typed error mapping.
- Repository tests for profile completion, availability, completion decoding, and
  server error mapping.
- pgTAP tests for existing-user backfill, new-profile completion, idempotency,
  invalid/taken handles, RLS ownership, function metadata, and grants.
- Focused UI tests with DEBUG-only deterministic launch states. The exact
  seven-second interval is a unit assertion; UI auto-advance runs against an
  accelerated injected clock to avoid an eight-second flaky test.
- Manual/screenshot QA for first launch, smaller-phone layout, keyboard, denied
  permissions, empty suggestions, and returning-user bypass.

## Not in Scope

- Custom authentication or account-recovery UI.
- City selection, category preferences, imports/reservation sync, or a paywall.
- Live MapKit onboarding heroes; use optimized seeded-app screenshots.
- Hosted migration deployment, build-number bump, TestFlight upload, or release.
- Phase B tutorial routing; Phase A only keeps permission screens reusable.

## Implementation Tasks

- [ ] T1 — Add server completion/upsert/availability contracts and pgTAP tests.
- [ ] T2 — Add shared identity validation, typed errors, and repository coverage.
- [ ] T3 — Add app-entry coordinator, completion cache, and logged-out carousel.
- [ ] T4 — Add identity, permission, friend-suggestion, and completion screens.
- [ ] T5 — Add UI-test target, deterministic launch states, and accessibility tests.
- [ ] T6 — Update durable product/design decisions and complete visual QA.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| Eng Review | `/plan-eng-review` | Architecture & tests | 1 | CLEAR | Auth-first entry, durable completion, optional activation steps, and full test paths locked |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | Existing user-approved mocks and image boards are the visual source |

**VERDICT:** ENG CLEARED — ready to implement

NO UNRESOLVED DECISIONS
