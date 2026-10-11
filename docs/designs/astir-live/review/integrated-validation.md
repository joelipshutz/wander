# REC-636 integrated validation

October 10, 2026 · Integrated `Wander` app · **Draft implementation; activation blocked**

This record supersedes the standalone prototype as implementation evidence. The historical [prototype validation](validation.md) and [prototype captures](captures.md) remain design references only. Selected integrated screenshots are in the [current gallery](integrated-captures.md).

## Candidate and reproduction

- Branch: `codex/live-experience-review`, based on `origin/main` commit `d9f827353648bab91a17187721b5ea41e65e1a42`. The implementation commit containing this report identifies the candidate; later documentation-only edits do not change the app.
- Isolated worktree: `/private/tmp/wander-live-review`.
- Review scheme: **Live Experience Review** in the normal `Wander.xcodeproj`, generated from `project.yml` with XcodeGen. It uses explicit authenticated Simulator fixtures, disables walkthrough overlays and supplies a dated received invitation. It does not activate a hosted flag.
- Toolchain: Xcode 26.6, iOS Simulator SDK/runtime 26.5. Dedicated review devices: iPhone 17 Pro and iPhone SE (3rd generation).
- Raw results, recordings and original captures: `/private/tmp/rec636-evidence/`, outside the worktree. Only selected compressed final screenshots are in Git.

Open the project, select the review scheme, and Run on either phone. For the focused gate, run the `WanderTests` target and `WanderUITests/LiveExperienceUITests`. To repeat the full native gate, run both targets without an `-only-testing` restriction. Use a new result bundle and record the actual candidate/destination.

The review scheme exercises the production Live shell, drawing, existing Feed/Profile routes and new messaging UI. Demo messages use an isolated memory repository, are labelled **nothing is delivered**, and acknowledge **Simulated**. The demo plan uses the existing invitation editor and recipient rehearsal; its detached Wanna does not write to the shared store or send an invitation. Production repository and HTTP behavior are tested separately with synthetic responses. Neither establishes hosted delivery.

## Results

| Check | Observed result |
|---|---|
| V3 large, `live-final-v3-large.xcresult` | **2,781 passed: 2,770 unit + all 11 Live UI tests. Zero failures or skips.** Includes D2/D3 local filters, latest D9 semantic migration and D10 invitation routes. |
| V3 compact, `live-final-v3-compact.xcresult` | **10 of 11 Live UI tests passed.** Feed-card scrolling failed after five full swipes; the compact check now uses shorter edge drags to avoid skipping cards and starting inside horizontal recommendations. The final V4 rerun passes on both sizes; the original failure is preserved as diagnosis history. |
| **Final V4 compact**, `live-final-v4-compact.xcresult` | **2,781 passed: 2,770 unit + all 11 Live UI tests. Zero failures or skips.** Includes final Map top inset, accessible drawing labels and short Feed scroll gestures. |
| **Final V4 large**, `live-final-v4-large.xcresult` | **All 11 Live UI tests passed, zero failures or skips**, using the same compiled build as final compact. Pins are clear of controls on both sizes. All 383 Swift source hashes matched the validated candidate at packaging. |
| Full native suite, earlier integrated candidate, `app-native-full.xcresult` | **2,955 passed, 16 failed, zero skipped.** This is not a passing full-suite gate. Two older Live failures are superseded by later focused results. The other failures remain unresolved except the dark Events tab recheck below. |
| Legacy root recheck, `legacy-root-recheck.xcresult` | **1 passed, 2 failed.** Events dark-tab navigation passed after correcting empty root inset spacing. More Filters navigation and REC-386 member-photo checks still failed. |
| Legacy Feed audience recheck, `live-final-v2-large.xcresult` | Unit tests passed before the legacy menu-filter test failed and cascaded through later assertions. The run was stopped; **interrupted, not a pass**. Standalone Feed audience navigation remains an unresolved regression check. |
| Real messaging transport tests | All eight passed within the V3 unit suite: account changes during authentication/response, cancellation, one 401 refresh, repeated-401 failure and no URL cache/cookies. Synthetic responses only. |
| Messaging state tests | All 24 passed within the V3 unit suite: ambiguous-send retry identity, authoritative refresh/access failure, draft preservation, context revocation and stale-response fencing. |
| Analytics/dashboard contract | `analytics:check` and all 12 dashboard tooling tests passed. Private-message success properties are aggregate-only; fixture messages suppress analytics. |
| SQL draft preparation | JavaScript syntax, rollback-preview generation and static contract inspection passed. **No database execution.** |
| New Live query | Native geometry/time/type/repository tests passed. Five proposed store-integration tests remain an unapplied patch and have not run. |

No baseline run establishes that the outstanding native failures predate this branch. Keep them as review/activation gates rather than calling them unrelated or pre-existing.

## Remaining full-suite failures

The earlier full run failed founders welcome playback (two), normal live authentication (one), Events appearance (two), map filter/place behavior (two), dense-map performance (one), import/history/share-extension flows (three), onboarding (three) and the two superseded Live checks. The dark Events tab test subsequently passed; the other Events appearance check has no passing rerun. The separate standalone Feed audience menu recheck also remains unresolved.

Founders playback has a confirmed prerequisite: `Wander/Resources/FoundersWelcome/founders-welcome.mp4` remains a Git LFS pointer in both available checkouts, and Git LFS is unavailable on the validation host. Fetch the required payload before rerunning playback. Normal authentication requires live Clerk configuration/connectivity and signed-out state; share-extension testing requires the embedded extension to be registered. Import fixtures enter their own harness, bypassing Live. These observations narrow diagnosis; they do not convert failures into passes.

## Native review scope

The 11 Live cases cover three tabs/Profile continuity; visible-area Apply/Clear/tab retention; drawer drag and original Feed modules/cards; staged filter reset/cancel; committed audience retention; Settings guide replay; private demo reply/keyboard/foreground draft; Wanna → contextual reply → existing invitation editor → preview → recipient; Nearby 5/25 km staging and tab retention; Upcoming → recipient/inbox; and drawing at the largest accessibility text size.

Still screenshots establish visible layout only. They do not prove freehand gesture geometry on hardware, spoken VoiceOver order, production-volume performance, readable-replay exclusion, app-switcher snapshot timing or real two-account messaging. The inactive-scene cover is implemented, but actual snapshot and replay inspection remain separate requirements. D9 policy/unit coverage does not replace retained-checkpoint, fresh-account, force-quit and rollback UI validation.

## Activation gates and restart

1. **Shared query integration:** recheck and apply the prepared [Feed-only store patch](../implementation-drafts/store.patch), run its five tests, and bind committed Live queries with fixed pagination bounds. Current pins/cards filter authorized loaded Feed rows. Extend the initial time/type/polygon RPC draft for the accepted radius/category/person controls; current-location centering and eligible discovery remain pending.
2. **Hosted contracts:** package the two SQL drafts as ordered CLI-created migrations, review the confirmed target/history, install them and verify RLS/grants, mutual/block/source checks, idempotency, pagination and quotas using the rollback-only hosted smoke suites. No schema has been deployed.
3. **Migration:** verify retained onboarding/save/import/contact work, explicit-route priority, account changes, force-quit and rollback. Opening a destination is not completion.
4. **Native gates:** resolve or isolate the outstanding full-suite and standalone Feed audience failures. Open this worktree's project in Xcode and verify the branch chooser and review scheme; that final GUI handoff has not been verified.
5. **Product/privacy rollout:** D11 cache lease remains unanswered. Existing Profile/shared-cache policy is unchanged. Message reporting and soft-delete retention require a rollout decision. Readable replay, app-switcher and actual mutual-friend delivery still need operational evidence.

Keep `unified_live_v1` default off and this PR in draft. `ship` classification is required because the branch contains app behavior; it is not an activation or release approval. No merge, hosted deployment, real message/invitation send or TestFlight release is part of this handoff.
