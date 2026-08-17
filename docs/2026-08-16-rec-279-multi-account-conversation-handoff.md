# REC-279 multi-account conversation and engineering handoff

Last updated: 2026-08-16 21:00 PDT

Status: incomplete implementation checkpoint; not compiled, tested, merged, or released

Canonical tracker: [REC-279](https://linear.app/recme/issue/REC-279/build-multi-account-switching-and-account-isolation)

Draft PR: [#453](https://github.com/joelipshutz/wander/pull/453)

Implementation branch: `codex/rec-279-multi-account-design`

Checkpoint commit: `2f48cd92045ab3d66f2d3ffa4c54545d3368232d`

Architecture/design commit: `5d274a5327c0025cbd04e74efe36d19cd266d1d4`

## Read this first

This document is the durable continuation context for another coding agent. It captures all user-visible requests available in the Codex conversation, the implementation work performed, the branch topology, relevant artifacts, known gaps, and exact restart instructions. It is not a transcript of system/developer prompts, hidden reasoning, credentials, or raw tool output.

The implementation is a checkpoint, not a finished feature. Do not infer that it compiles merely because the branch was committed. The last build was interrupted before app compilation produced a result, and no focused or full tests were added or passed for REC-279.

## Conversation history

### 1. Original product and architecture request

User:

> We're going to build support like Instagram for multiple accounts on one device. We need to make sure that everything on the device that's like a device fingerprint isn't only relying on that. We need to make sure that user can like easily switch between accounts, just like Instagram, both in the UI, be logged into multiple accounts and switch between them, like one at a time, but they can easily switch between them from profile. Think through this, and build it on a work tree. Actually, don't build it, just think through it and tee up the UI for me so I can take a look at what it would look like.

Assistant outcome:

- Audited the existing Clerk, Supabase, persistence, analytics, notification, widget, extension, and Profile boundaries.
- Produced the architecture plan at `docs/plans/2026-08-16-rec-279-multi-account-switching-plan.md`.
- Produced an interactive HTML prototype outside the repository at `/Users/joelipshutz/.gstack/projects/joelipshutz-wander/designs/multi-account-switcher-20260816/finalized.html`.
- Produced local preview images alongside that prototype: `preview-switcher.png` and `preview-switched.png`.
- Opened draft PR #453 and created/updated Linear REC-279.
- Confirmed the intended interaction: tap the active Profile handle/chevron, choose among saved sessions, keep one account active, add an account without destroying the current session, and rebuild the full authenticated app context when switching.

### 2. Approval to implement

User:

> Go ahead and build this, um, in a branch and test.

Assistant actions:

- Rebased the isolated worktree branch onto then-current `origin/main` at `40811705`.
- Updated REC-279 from a design spike to an implementation issue and kept it `In Progress`.
- Verified the pinned Clerk iOS 1.1.4 source already exposes `Clerk.shared.auth.sessions`, `setActive(sessionId:organizationId:)`, and targeted `signOut(sessionId:)`; no SDK upgrade was required for the checkpoint.
- Implemented an initial multi-session auth boundary, Profile switcher UI, account-keyed app-root recreation, and account-scoped local storage paths.
- Regenerated `Wander.xcodeproj` with XcodeGen.
- Started validation, but did not finish it. See “Validation truth” below.

### 3. Status check

User:

> is it done

The accurate state was no: the implementation and tests were still incomplete.

### 4. Lightweight remote checkpoint

User:

> commit the branch to remote so we can pick i tup later. do it lightly

Assistant actions:

- Committed the WIP implementation as `2f48cd92 feat: checkpoint multi-account switching`.
- Force-pushed the rebased branch to `origin/codex/rec-279-multi-account-design`.
- Renamed draft PR #453 to `[REC-279] WIP multi-account switching and isolation`.
- Explicitly reported that implementation and tests were not finished.

### 5. Current handoff request

User:

> find the branch in here which covers what we were working on if it exists. and commit the entire convo history as md so my friends coding agent can continue with context. includ all other docs/context that is relevant for him

User supplied these integration pointers:

```text
codex/feature-454-first-save-checkin → 81064d87
codex/feature-456-map-layout → 0ecf9d73
codex/feature-458-feed-glass-controls → f0fc851c
codex/feature-457-semantic-discover → ccfd07c4
codex/feature-459-map-search-polish → 0c9abb78
codex/feature-461-save-confirmation-ctas → e5325b19
```

User then asked to find the branch covering the multi-account work and commit the conversation plus all relevant continuation context.

Branch audit result: none of those six feature branches contains `2f48cd92`. The only local and remote branch containing the multi-account checkpoint is `codex/rec-279-multi-account-design`.

## Branch topology and integration state

The checkpoint’s merge base with current `origin/main` is `4081170559f79fc362beed54a6890df8a71b3bc1`, the integrated first-save change.

Current `origin/main` at the time of this handoff is `7b649a9b` and already contains the merged equivalents of the six supplied feature pointers:

- `40811705` — first-save Check in and Wanna flows (#454)
- `39aa45e1` — Option B Map layout (#456)
- `0464822b` — Feed floating/glass controls (#458)
- `dc538d00` — semantic Discover retrieval (#457)
- `266303d7` — Map search polish (#459)
- `7b649a9b` — attached place saves and confirmation CTA polish (#461)

The supplied `codex/feature-*` commits are feature/integration pointers, but the canonical landing history is already on `origin/main`. Rebase REC-279 onto current `origin/main`; do not cherry-pick all six feature pointers.

Expect real conflicts in high-churn files, especially:

- `Wander/App/WanderRootView.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Profile/ProfileScreen.swift`
- `Wander.xcodeproj/project.pbxproj`

Preserve current `main` behavior first, then reapply the account boundary deliberately. Regenerate the project through `xcodegen generate` rather than resolving `project.pbxproj` semantically by hand.

## Product and security invariants

These are non-negotiable:

1. A validated Clerk session and canonical signed user claim are the only account identity.
2. APNs tokens, installation IDs, PostHog anonymous IDs, IP, locale, device model, permissions, and other device/fingerprint signals may describe or route an installation. They cannot select an owner, authorize data, merge accounts, or choose the active account.
3. Multiple valid provider sessions may coexist, but exactly one account is active in the main app at a time.
4. Switching must replace the complete authenticated runtime, not only Profile chrome.
5. Private local state must be account-scoped or proven public.
6. Late async work from account A must never commit after account B becomes active.
7. Server authorization remains signed Clerk claims plus Supabase RLS. Client-side expected-user checks are defense in depth, not authorization.
8. Failure must fail closed without blending two accounts.
9. “Remove from this device,” “sign out current,” “sign out all,” and “delete account” are distinct operations and must use precise copy and behavior.

The full architecture, migration, notification, widget, extension, failure, rollout, and validation design is in `docs/plans/2026-08-16-rec-279-multi-account-switching-plan.md`.

## What checkpoint `2f48cd92` implements

### Auth and session catalog

- `AuthSession` gained an optional provider session ID.
- `AuthSessionProviding` gained an available-session catalog plus activate-one, remove-one, and sign-out-all operations with compatibility defaults.
- `AuthSessionStore` gained session catalog state, switching/removal state, recoverable errors, `switchAccount`, `removeAccount`, and `signOutAll`.
- `PreviewAuthSessionProvider` gained multi-session behavior for future tests/previews.
- `ClerkAuthService` maps Clerk’s on-device sessions, activates a targeted session, removes a targeted session, distinguishes current sign-out from all-session sign-out, and tries to activate a remaining session after removing the active one.
- The app passes its contextual analytics client into `AuthSessionStore`.
- A successful switch emits `account_switched` with only coarse `account_count` and `source` properties.
- `AppEntryCoordinator` resets analytics identity when changing directly between two non-nil user IDs.
- `AppEntryView` keys `WanderRootView` with `.id(session.userID)` so an account change constructs a new root graph.

### Local account vault

- `AccountStorageScope` derives a SHA-256 opaque local directory key from the validated canonical user ID.
- New vault root: `Application Support/rec-me/accounts/v1/<opaque-key>/`.
- Account-specific paths were added for the main store, save draft, imports, profile avatar, and new visit photos.
- Legacy main-store, draft, and import files are copied only when their embedded owner matches the validated account. A migration marker prevents repeated adoption.
- `WanderRootView` constructs live store/draft/import persistence for `initialSession.userID` and flushes store/draft persistence when disappearing.
- Profile avatar writes/deletes now use the current account’s scoped directory.
- New visit photos use `local_file_v2:<opaque-key>/<filename>` references; legacy `local_file:` reads remain for backward compatibility.

### Profile UI

- Tapping the owner Profile handle and chevron opens `AccountSwitcherSheet`.
- The sheet lists saved sessions, marks the active account, switches to another session, launches Add account through existing auth, offers Manage/removal, and offers Sign out of all accounts.
- The sheet explains that each account keeps separate local maps, drafts, photos, and settings.
- VoiceOver labels identify current and target accounts.

## Files changed by the checkpoint

```text
Wander.xcodeproj/project.pbxproj
Wander/App/AppEntryView.swift
Wander/App/WanderApp.swift
Wander/App/WanderRootView.swift
Wander/Features/Add/AddScreen.swift
Wander/Features/Map/MapScreen.swift
Wander/Features/Onboarding/OnboardingState.swift
Wander/Features/Profile/AccountSwitcherSheet.swift
Wander/Features/Profile/ProfileEditScreen.swift
Wander/Features/Profile/ProfileOwnerHome.swift
Wander/Features/Profile/ProfileScreen.swift
Wander/Services/AccountStorageScope.swift
Wander/Services/AnalyticsEvent.swift
Wander/Services/Auth/AuthSessionProviding.swift
Wander/Services/Auth/ClerkAuthService.swift
Wander/Services/PlaceImportStore.swift
Wander/Services/PlaceSaveDraftStore.swift
Wander/Services/ProfileAvatarStorage.swift
Wander/Services/VisitPhotoLocalFileStore.swift
Wander/Services/WanderStorePersistence.swift
```

## Validation truth

Completed:

- `xcodegen generate` completed successfully after adding the new source files.
- `git diff --check` passed before the checkpoint commit.
- The exact Clerk 1.1.4 source APIs were inspected locally.

Not completed:

- The first clean generic Simulator build failed before app compilation because the machine ran out of disk space while emitting an Apple framework PCM. It was an infrastructure failure, not a passing or failing REC-279 compile result.
- Only regenerable DerivedData directories were cleared to recover space; no source, simulator data, archive, or user data was removed.
- A second quiet active-architecture build began, but the Codex turn was interrupted before a final exit status or app compile diagnostics were captured.
- No REC-279 focused tests were added.
- No focused tests passed.
- The full `WanderTests` suite was not run for this branch.
- No two-device Simulator screenshots were captured from the native implementation.
- No hosted Supabase migration, smoke test, push test, TestFlight build, or release occurred.

Therefore, start by treating the source as unvalidated WIP.

## Known implementation gaps and review risks

### Must finish before merge

- Rebase onto current `origin/main` and resolve all conflicts against the six landed features.
- Compile the application and fix Swift/type/concurrency issues.
- Add focused auth tests for session catalog, targeted activation/removal, current vs. all-session sign-out, switch failure rollback, and analytics identity order.
- Add account-vault tests for stable/different keys, path containment, matching-owner legacy migration, mismatched-owner rejection, and target-only cleanup.
- Add integration tests proving accounts A and B preserve separate maps, drafts, imports, avatars, photos, and preferences across relaunch.
- Add UI/navigation contract tests for the Profile handle entry, active checkmark, switch, Add account, removal, sign-out-all, accessibility labels, Dynamic Type, and small-phone layout.
- Update `docs/analytics.md` for `account_switched` and run `npm --prefix scripts run analytics:check`.
- Capture visual QA on the current iPhone target and a smaller iPhone.
- Run the complete required iOS test suite before marking ready.

### Device integrations not implemented

- APNs registration still needs a many-account installation membership model. The existing active-device uniqueness semantics were identified as incompatible with notifications for multiple signed-in accounts.
- Push payloads and taps are not yet recipient-account routed. Do not open private inactive-account destinations without a validated switch.
- Widget snapshots are not yet tagged and guarded by account ID/switch generation.
- Share-extension captures are not yet stamped with the account active when capture began.
- The device-wide Wanna reminder preference is not yet account-keyed.
- Background operations do not yet use an explicit account switch generation throughout.

### Semantics requiring product-safe completion

- The design says account removal with unsynced work must be blocked or require explicit sync/export/discard. The checkpoint UI removes the provider session but intentionally retains the local vault; this is not the final removal policy.
- Sign out all and delete-vault behavior need a deliberate pending-work policy.
- Offline switching and expired-target-session recovery are not complete.
- The five-account cap from the plan is not yet enforced.
- Switch rollback is not a fully journaled transaction; the current store catches provider failure but does not preserve a formal previous runtime container.
- The switcher’s Manage-row gesture and presentation sequencing need native interaction review after rebasing/compiling.

## Recommended restart sequence

```bash
git fetch origin
git checkout codex/rec-279-multi-account-design
git rebase origin/main
xcodegen generate
xcodebuild build -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' \
  -derivedDataPath DerivedData-rec279 CODE_SIGNING_ALLOWED=NO -jobs 1
```

Then:

1. Fix compile issues before expanding scope.
2. Review the rebased diff against `origin/main` for lost current behavior or generated junk.
3. Add the focused tests listed above.
4. Finish account scoping for preferences, widgets, extensions, push routing, and background work.
5. Run analytics validation, focused tests, full tests, and two-device visual QA.
6. Update draft PR #453 with implementation reality and exactly one valid hidden `recme-testflight-payload` block required by current repo policy.
7. Keep REC-279 `In Progress` until compilation and implementation are complete; move to `In Review` only when the PR is genuinely ready.

The original REC-279 worktree may contain untracked `DerivedData-rec279/`. It is local build output, not source, and was never pushed. Do not add it to Git.

## Relevant documents and external references

- Repo rules: `AGENTS.md`
- Architecture and rollout plan: `docs/plans/2026-08-16-rec-279-multi-account-switching-plan.md`
- Product spec: `docs/specs/wander-ios-product-spec.md`
- Design system: `DESIGN.md`
- Analytics contract: `docs/analytics.md`
- General agent handoff: `docs/codex-handoff.md`
- Decisions: `docs/decisions.md`
- Open questions: `docs/open-questions.md`
- Setup and build commands: `docs/setup.md`
- Required coordination log: `docs/agent-log.md`
- Clerk official multi-session guide: <https://clerk.com/docs/guides/development/custom-flows/authentication/multi-session-applications>
- Clerk iOS auth reference: <https://clerk.com/docs/ios/reference/native-mobile/auth>
- Instagram account switching help reference: <https://www.facebook.com/help/instagram/1696686240613595?locale=en_GB>

The HTML prototype path is machine-local and is not portable to another developer by Git. The repo plan remains the portable source of truth if that artifact is unavailable.

## Definition of done

REC-279 is not done until all of the following are true:

- Multiple Clerk sessions coexist and one activates without destroying the others.
- Account A cannot observe or mutate account B’s private local or remote state.
- All private device state and late async callbacks are account-scoped or guarded.
- Device/fingerprint signals cannot satisfy identity or ownership APIs.
- Switching is serialized, rollback-safe, and visually atomic.
- Remove-one, sign-out-current, sign-out-all, and delete-account semantics are distinct and safe with unsynced work.
- Push, widget, extension, deep-link, background, analytics, and preference routing are explicitly account-safe.
- Focused, full-suite, accessibility, Dynamic Type, offline/failure, migration, security, and two-device visual validation pass.
- Draft PR #453 accurately documents the implementation and validation and is ready for review.
