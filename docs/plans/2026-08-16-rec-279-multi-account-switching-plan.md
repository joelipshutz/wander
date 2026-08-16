# REC-279: Multi-account switching and account isolation

Status: design spike; no production implementation in this branch

Linear: [REC-279](https://linear.app/recme/issue/REC-279/design-multi-account-switching-and-account-isolation-architecture)

Interactive prototype: `/Users/joelipshutz/.gstack/projects/joelipshutz-wander/designs/multi-account-switcher-20260816/finalized.html`

## Decision

rec.me should support up to five signed-in accounts on one device, with exactly one account active at a time. The active account is selected from Profile by tapping the handle and chevron. Switching must be a transactional change of the entire account context, not a visual profile swap.

The only authoritative account identity is a validated Clerk session and the canonical user ID in its signed token. Device- or installation-level signals may route notifications, measure analytics, or expose OS capabilities. They must never select an owner, authorize a read or write, or substitute for account identity.

The first implementation should not start with the switcher UI. It should first establish an account-scoped runtime and migrate every local singleton into an account vault. The UI can then activate that safe boundary.

## Product shape

### Primary interaction

1. Profile shows the active `@handle` plus a small chevron in the top-left.
2. Tapping it opens a bottom sheet listing accounts saved on this device.
3. The current account has a checkmark. Other rows can show account-specific attention, such as an expired session or pending activity, but only when the server can attribute that state safely.
4. Tapping another account briefly shows “switching to @handle,” then replaces the entire signed-in app root.
5. The new handle, profile avatar, Profile tab avatar, profile data, map, drafts, and preferences change together before interaction resumes.
6. “Add account” authenticates a new account without signing out the current one.
7. “Manage accounts on this device” supports removing one session and signing out all sessions.

An optional press-and-hold shortcut on the Profile tab is worth testing later, but it should not be the only entry point.

### UX rules

- Keep the active identity visible at the point of action. The handle and profile avatar should update atomically.
- Never blend content from two accounts in the main app. rec.me remains a single-account experience after each switch.
- Switching accounts is allowed while an account has pending work; removing that account is blocked until the user syncs, exports, or explicitly discards unsynced work.
- A failed or expired target session leaves the current account active and offers reauthentication for the target account.
- Offline switching is allowed only to an account with a valid cached session and a complete local vault. Network-required actions remain visibly offline.
- Destructive language must be precise: “Remove from this device” is not “Delete account.”

## Non-goals

- A combined feed, map, inbox, or search across accounts.
- Meta-style linked identities or an Accounts Center.
- Automatically linking accounts because they share a device, APNs token, contact permission, IP address, analytics identifier, or other fingerprint.
- Organization/member role switching within one account.
- Recommending which account to use based on device behavior.

## Current system audit

The remote data boundary is in substantially better shape than local storage:

- `ClerkAuthService` and `AuthSessionStore` currently expose one active session. `signOut()` has all-session semantics because it does not target a session ID.
- `WanderAppEntryView` already keys the signed-in root by `session.userID`. Recreating that root on a successful account change is a useful hard isolation seam.
- Authenticated Supabase requests validate the expected user before and after requesting a token. The database derives `app.current_user_id()` from signed claims, and RLS remains authoritative.
- Several async store paths already reject results when `currentUser.id` changes. Multi-account support should generalize this into a switch generation carried by every account-scoped task.
- No use of IDFA, `identifierForVendor`, or a hardware fingerprint was found in the app.

The unsafe part is that several on-device resources are still global singletons:

| Resource today | Current scope | Required scope |
| --- | --- | --- |
| `Application Support/Wander/wander-store-v1.json` | App install | Account vault |
| `Application Support/Wander/place-save-draft-v1.json` | App install, with an owner check inside the payload | Account vault |
| `Application Support/Wander/last-auth-session-v1.json` | One cached session | Session catalog or provider-managed sessions |
| `Application Support/Wander/ProfileAvatars/current-user-avatar.jpg` | App install | Account vault |
| `Application Support/VisitPhotos/` | Shared directory | Account vault or account-tagged references with enforced ownership |
| `Application Support/rec-me/place-imports-v1.json` | App install | Account vault |
| Widget snapshot | One app-group snapshot | Active-account snapshot tagged with account ID and switch generation |
| Share-extension inbox | App group | Each item stamped with the account active when capture began |
| Onboarding and first-visit flags | Mostly account-keyed already | Keep account-keyed |
| Save-streak reminder state | Account-keyed already | Keep account-keyed |
| “Wanna go” reminder preference | Device-wide | Decide explicitly; recommended account-keyed |
| APNs token | Device/app endpoint | Device signal with account memberships |
| PostHog anonymous/install ID | Device/install analytics signal | Keep as signal; reset and identify the active account transactionally |

## Identity boundary

### Account truth vs. device signal

| Input | Valid use | Forbidden use |
| --- | --- | --- |
| Signed Clerk session and canonical user claim | Select the account vault; authorize API calls; scope server data | None when validation succeeds |
| APNs device token | Deliver a push to an installation | Prove who owns data or decide which account is active |
| Random installation ID | De-duplicate an installation; attach account notification preferences | Authenticate a user or merge accounts |
| PostHog anonymous/install ID | Understand install-level funnels | Join private user histories or authorize anything |
| Contacts, Photos, Location, and notification permission | Describe an OS capability available to the app | Infer the signed-in account or share consent/preferences across accounts |
| App Group container | Exchange explicitly tagged extension/widget payloads | Treat untagged content as belonging to the currently active account |
| IP, locale, device model, or OS version | Security/risk or operational signals with appropriate privacy controls | Canonical account identity |

### Invariants

1. Every private local record, cache entry, pending task, upload, background callback, widget snapshot, and extension payload is either account-scoped or proven public.
2. Every server request carries the target account ID as an expectation, but authorization comes only from the signed token and RLS.
3. A device identifier can address an installation. It cannot address a user.
4. Late work from account A cannot commit after account B becomes active.
5. The UI does not become interactive until the active identity, storage container, repositories, analytics identity, routing context, and visible account chrome agree.
6. A switch failure fails closed and restores the prior account context.

## Proposed runtime

### Core concepts

- `AccountSessionSummary`: session ID, canonical user ID, display identity, authentication status, and last active date. It contains no app data.
- `AccountVault`: account-specific filesystem roots and preferences. The path is derived from a non-reversible local key mapped to the validated canonical user ID, not a display handle.
- `AccountContainer`: repositories, stores, caches, import queues, draft managers, and account-scoped services constructed for one validated account.
- `ActiveAccountCoordinator`: owns the one active session and executes a switch as a serialized transaction.
- `AccountSwitchGeneration`: monotonically increasing generation captured by async work. Results from an older generation are discarded.
- `InstallationContext`: device/app-level state such as APNs token, random installation ID, and OS permissions. It never owns user content.

### Switch transaction

```text
tap target account
  -> block new account-scoped actions
  -> flush current vault and persist pending-work metadata
  -> cancel or quarantine current account tasks
  -> activate the target Clerk session
  -> fetch/validate its canonical user claim
  -> open or create only that account's vault
  -> build a fresh AccountContainer
  -> reset then identify analytics for the target
  -> bind notification, deep-link, widget, and extension routing
  -> replace the keyed signed-in app root
  -> unblock interaction
```

The coordinator should retain the previous session/container until the target passes validation and its vault opens. On any failure it restores the prior context, increments the generation again, and reports a recoverable error.

All switch operations are serialized. Repeated taps either select the newest target or remain disabled until the current transaction finishes.

## Local storage and migration

Recommended layout:

```text
Application Support/rec-me/
  installation.json
  accounts/
    <local-account-key>/
      store.json
      drafts/
      imports.json
      avatars/
      visit-photos/
      preferences.json
      migration.json
```

`installation.json` contains only device-level metadata and a mapping from a local opaque key to a validated account ID. Private payloads remain inside the account directory.

### Existing-data migration

1. Require one currently validated session before touching legacy data.
2. Stop writes and snapshot the legacy files.
3. Validate embedded owner IDs where available against the active canonical user ID.
4. Atomically move the legacy singleton data into only that account's vault.
5. Mark the account migration complete, then reopen through the new container.
6. Quarantine a mismatch instead of copying or guessing ownership.
7. Do not enable account switching until the legacy migration has completed or been explicitly recovered.

Never copy legacy data into every newly added account. A device match is not evidence of shared ownership.

## Notifications

The current database can store a user ID with a device token, but its active-device uniqueness rule permits one active owner for an APNs token. That fits a single-account app and conflicts with Instagram-like notification behavior for multiple signed-in accounts.

Recommended model:

```text
notification_installations
  installation_id, token_hash, encrypted_token, environment, bundle_id, last_seen_at

notification_installation_accounts
  installation_id, user_id, notifications_enabled, last_active_at, removed_at
```

- `installation_id` is a random app-generated routing key, not user identity.
- One installation can have notification memberships for multiple validated sessions.
- Registration and removal require the corresponding signed account session.
- A push payload identifies its recipient account with an opaque server-issued account routing value. It contains no private place content.
- If the recipient account is inactive, tapping the notification offers or performs a validated switch before opening the destination.
- If the session is expired or removed, the destination remains closed and the user is asked to reauthenticate.
- Per-account notification preferences remain account-scoped even though OS notification authorization is device-wide.

Inactive-account notifications should ship only after this membership model and routing tests exist. Until then, the honest v1 behavior is notifications for the active account only.

## Widgets, extensions, deep links, and background work

- Widget: publish one active-account snapshot containing `accountID`, `switchGeneration`, generated time, and public display metadata. Clear it before a switch and republish after commit. The widget opens through validated account routing.
- Share extension: stamp each captured item with `capturedForAccountID` and a capture transaction ID when the extension starts. If there is no valid active account, ask the user to choose rather than guessing. A later switch must not reassign the item.
- Deep links and pushes: resolve an expected recipient account before navigating. If a different account is active, switch first or keep the destination queued.
- Background uploads/imports: persist them inside the source account vault. A completion callback must verify both account ID and switch generation before mutating UI state.
- In-memory caches: tag private cache keys with account ID or destroy the entire container on switch.

## Session management

The implementation must use a Clerk iOS version that exposes the list of on-device sessions, activation of a specific session, and sign-out of one session. The project currently pins Clerk iOS 1.1.4, so the first engineering task is to verify those APIs in that exact revision or upgrade deliberately before writing the coordinator.

Semantics:

- Add account: create another provider session while preserving existing sessions.
- Switch account: activate one existing session; do not reauthenticate when still valid.
- Remove account: revoke that session on this device and delete that account's local vault after pending-work resolution.
- Sign out current account: remove only the active session, then activate another saved session or show signed-out state.
- Sign out all: revoke all sessions and remove all private account vaults after confirmation.
- Delete account: a separate server-side destructive flow; never share wording or behavior with “Remove from this device.”

## Failure and edge-case behavior

| Case | Required behavior |
| --- | --- |
| Target session expired | Keep current account active; offer reauthentication for target |
| Switch while a save/upload is running | Persist or cancel safely in source vault; discard late UI callback |
| Switch offline | Open only complete cached target vault with valid cached session; show offline limitations |
| Remove account with unsynced work | Block removal; offer sync, export, or explicit discard |
| Push for inactive account | Switch through coordinator before navigation, or queue it |
| Share capture races with switch | Keep captured account stamp; never adopt current account after the fact |
| Widget refresh races with switch | Reject stale generation; show no private stale snapshot |
| Account deleted remotely | Revoke local session and vault access; offer recovery/export policy if applicable |
| Analytics event during switch | Buffer or drop until new identity commit; never attribute to either account ambiguously |
| App killed mid-switch | Recover from a journaled transaction to previous or target account, never a blended container |
| Same person owns two accounts | Keep independent data, preferences, graph, drafts, analytics identity, and notification membership |

## Rollout plan

### Phase 0 — design spike

- Review this interaction prototype and architecture.
- Resolve notification scope, account limit, and pending-work removal policy.

### Phase 1 — identity and account container foundation

- Verify or upgrade Clerk iOS multi-session support.
- Add `ActiveAccountCoordinator`, session catalog, switch generation, and keyed app-root recreation behind a feature flag.
- Add tests proving device/install signals cannot select account ownership.

### Phase 2 — storage isolation and migration

- Introduce account vaults and migrate store, drafts, imports, avatars, visit photos, and account preferences.
- Add journaled migration, mismatch quarantine, and rollback tests.
- Keep switcher UI disabled until vault migration is complete.

### Phase 3 — Profile UI and session lifecycle

- Build the approved handle/chevron entry and account sheet in SwiftUI.
- Add account, switch, remove one, sign out current, and sign out all.
- Cap saved accounts at five initially.

### Phase 4 — device integrations

- Redesign notification registration for installation-to-many-account membership.
- Account-tag widgets, share-extension inputs, deep links, and background queues.
- Add inactive-account notification routing only after the new model is verified.

### Phase 5 — hardening and rollout

- Race, offline, session-expiry, migration, privacy, and accessibility QA.
- Roll out to internal accounts, then a small TestFlight cohort, then all users.
- Monitor switch failures, vault migration failures, cross-account guard rejections, and push misroutes. Do not log private place data.

## Validation matrix

### Unit

- Vault locator never returns another account's directory.
- Switch coordinator serializes requests, increments generations, and rolls back failures.
- Old-generation async results cannot mutate the current container.
- Remove-current and remove-inactive semantics target exactly one session.
- Device signals cannot satisfy an account identity API.

### Integration

- Account A and B maintain independent maps, drafts, imports, photos, preferences, graph, and cached profiles across relaunch.
- Switching recreates the signed-in root and repository graph.
- Analytics resets before identifying the target account and events resume only after commit.
- Offline and expired-session recovery do not blend containers.

### UI and accessibility

- Handle and Profile-tab avatar always agree with visible account data.
- VoiceOver announces the current account and each switch target.
- Dynamic Type, reduced motion, keyboard, safe areas, and 44-point targets work on small and current iPhones.
- Switching, failure, reauthentication, max-account, remove, and sign-out-all states are covered.

### Backend and security

- RLS and RPC smoke tests prove account A cannot read or write account B data before, during, or after a switch.
- Token/session mismatch fails closed.
- Notification membership requires the signed user and cannot enroll another user ID.
- Push/deep-link routing cannot open an inactive account's private destination without a valid switch.

### Migration and recovery

- Legacy global data moves once to only the validated active account.
- Embedded owner mismatch is quarantined.
- Crash at every journal step recovers without duplication or cross-account assignment.
- Removing an account clears its private vault without damaging other accounts.

## Decisions to confirm

1. **Saved-account cap:** recommend five for the first release.
2. **Inactive-account notifications:** recommend active-account-only until Phase 4, then support all enrolled accounts.
3. **Unsynced work on removal:** recommend blocking removal until sync, export, or explicit discard; switching itself remains allowed.

## UI artifact notes

The prototype uses the existing warm rec.me visual language and is intentionally limited to Profile/account-management surfaces. It includes:

- Profile entry state.
- Account switcher sheet.
- Add-account state that preserves the current session.
- Transactional switching feedback and a fully changed active profile.
- Manage-on-device-accounts state.

It is an HTML review artifact, not production code and not a competing app redesign.
