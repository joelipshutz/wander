# Native onboarding implementation audit

Read-only audit against `wander-release-174`; implementation must recheck the new isolated main checkout. No app source was changed by this audit.

## Latest September 17 correction — mechanical letter flips

Joe clarified that the intended effect is a **mechanical split-flap display / flip board for individual letters**, followed by the slide. The new native source is now implemented and settled: top/bottom glyph halves use 3D hinged flap faces with five staggered cycles per changed letter. A manual source audit confirmed unchanged visible copy and refreshed refs/hashes in native-copy.json, including the shifted N69 launch reference. Current timing is 1.6s hold + 1.0s flip = 2.6s per word; delayed text starts its slide at 3.9s; final phrase settles at 10.4s, holds 2.4s and the page advances at 12.8s, followed by 7s benefit pages. Reduce Motion/VoiceOver switched on mid-flip resolves to a readable complete-word boundary. The actual current build/test passed exit 0: 1,989 unit tests, zero failures in 41.869s (43.117s wall), and three welcome UI tests, zero failures in 59.523s (`native-split-flap-tests.log` / `.xcresult`, completed 11:10:06). Source hashes are unchanged. Final A/B/C mechanical split-flap media is visually verified and published. Native frames show hinged halves/staggered cycles, initial lead-in/community, all words, final headline and loaded Map → People → signup. Trims are A 2.0s / B 2.0s / C 1.8s; W00/V01 use A, state frames use raw A at 2.5/7.5/13.5/18s, and the new native W00-compact screenshot is readable. `split-flap-review-ready.json` records hashes and the media manifest is refreshed; brief, gallery and full board are published. The first-pass cadence and supporting-copy timing/fate remain for creative review. Final browser QA passed video play/seek through signup, Focus/Compare, brief images and main V01 controls, with no JavaScript errors or missing assets (`final-split-flap-report.json`); root's implementation PR remains open. The pulse takes and **1,984-unit / three-welcome-UI pass** below are historical, superseded by the current 1,989-unit/three-UI result. Prior auth/profile executions remain evidence for unchanged flows.

## Previous September 17 opacity-pulse source and evidence

Joe supplied **“Connect with your”**, rotating **community / people / places / loved ones**, then the standalone final phrase **“a local experiment”**. His latest clarification retains both motions: repeated flicks change words; a slide moves to the next composition. Current `OnboardingTickerFrame` implements on/off opacity pulses; `OnboardingTickerView` keeps the lead-in stable during individual changes, then applies the treatment to the whole headline. The supporting description slides in, and page transitions still slide. Current source also hides the description during the final-headline change; its fate, cadence and timing remain review choices, not recovered requirements.

The default still includes opening → Places → People, with delayed baseline **“Keep track of everywhere you’ve been. Keep up with the people you love.”** Explicit empty configurations can omit the opening; Debug overrides support review alternatives. No copy strings changed in the repeated-flicker update. Source refs/hashes in native-copy.json were refreshed after checking the new frame/view behavior. The first native flicker pass is now published: final A/B/C movies/posters replace the smooth-fade versions, with exact native-frame review confirming alternating flicks on each side of community → people and the final headline/actual signup in every take. The brief, gallery and board were regenerated; final browser QA is running separately.

The newest flicker source compiled. The quiet full native auth journey passed on that build in **41.611 seconds** (`auth-20260917T102024`), including verification through backgrounding. Signup Log in's measured approximately 20.7pt text hit area was expanded to a full-width 44pt minimum; callback wiring was already correct. Reliable UI helpers and quiet execution addressed the flaky test path, so this must not be reported as a callback bug fix. Profile/crop passed separately in **79.583 seconds** with native toolbar and actual Choose. Final post-flicker validation now passed: **1,984 unit tests, zero failures in 34.418 seconds**, and **three affected native welcome UI tests, zero failures in 58.312 seconds**. Final A/B/C flicker recordings were reviewed, trimmed and published, recorded by native-captures/flicker-review-ready.json. Their cadence remains a first pass for review; word flicker in place and whole-scene slide are distinct motions. See native-verification.md for exact evidence, broader UI limitations, and the separate final browser QA/PR work.

## September 17 native implementation update — Contacts copy

The current REC-529 native branch implements the user-requested concise N10/N36 copy: **“Connect with your people”**, **“Use your contacts to connect with people you know.”**, and system purpose **“Astir uses your contacts to help you connect with people you know.”** The no-upload and Messages sentences are removed from these two surfaces. This is high-level connection wording, not a claim that the address book automatically finds existing members. Actual Contacts behavior remains local invitation selection; real name/username member search and per-row Follow are separate. Historical Apple evidence supports the reason the old disclosure was added but does not mandate its exact words. Native permission sequence, settings and data flow are unchanged. The rebuilt Info.plist and actual N36.png system dialog now show this exact new purpose. The native Location/Contacts denial-and-recovery test passed; N30/N36 and notification-system wording are recorded in native-copy.json from real iOS captures.

The sections below retain the initial source audit and should not be read as current implementation status; use `native-verification.md` and `native-copy.json` for the implemented branch.

## Identity and live profile preview

- Production component: `Wander/Features/Onboarding/OnboardingFlowView.swift`, private `OnboardingIdentityView` beginning around line 142.
- Mutable inputs already owned there: `@State name`, `handle`, `selectedPhoto`, `photoCropSelection`, `previewImage`, `jpegData`, `availability`, `errorMessage`, `isSaving`; `draft` normalizes the name/handle. Inline a production preview or extract it with input values. No external state mutation is needed.
- `canSubmit` currently allows no photo. Require a selected, successfully cropped photo (or verified existing avatar for resumed identity) and valid identity. Replace optional-photo labels/accessibility copy.
- `save()` currently updates identity, then swallows avatar upload errors with `try?`, then advances. Required-photo behavior must stop on failed upload, expose retry, and advance only after the required save succeeds. Track success honestly. Repeated identity save on upload retry should be safe, or retain the saved result in state.
- `ProfileOwnerHome.swift` has private `identitySection` (~404), `profileIdentityBlock` (~480) and avatar controls (~560). The entire profile home requires statistics, graph/navigation actions, motion environment and many unrelated inputs. Reuse the same typography/avatar/surface styles in an onboarding production preview, or deliberately extract a small shared identity component; do not embed the entire profile page merely for capture.
- `AuthSession` has name/handle but no avatar property. Existing photo detection must come from the current profile, not an invented session field.

## Follow people and member search

- `OnboardingFriendSuggestionsModel.swift` currently loads 12 recommendations, preselects the first three, and batch-follows selected rows at Continue. `OnboardingFlowView.swift` ~595 owns that model and renders selectable rows with a reason label.
- Replace selection with explicit per-row Follow/Following, pending IDs, errors keyed to ID, and successful follow count. Remove preselected users. Continue should not silently initiate follow requests. Handle retry and avoid duplicate requests.
- Real existing-member search is available as `WanderBackend.searchProfiles(handleQuery:)` (~738), implemented by `SupabaseProfileRepository.searchProfiles` (~135) using `search_profiles_by_handle`.
- Actual SQL in `supabase/migrations/20260717180000_discover_profile_recommendations.sql:3` matches public profile **name or handle prefix**, minimum two characters, excludes self/deleted/private profiles, max 20. A placeholder such as “Search name or username” is supported. Debounce, cancel stale responses, and keep zero-result/error states distinct.
- Recommendation DTO contains `ProfileShell`; unify rows around profile identity, not an invented contact-match object. Verify relationship data on search: the search RPC returns no relationship column, so use known following IDs/current relationship state to avoid showing Follow on an already-followed search result.
- Real Contacts provider does not match device contacts to accounts. Do not promise existing-contact discovery merely because member search was added; see `contacts-evidence.md`.

## Permission wording and notifications

- Contacts explainer is the `.contacts` branch in `OnboardingFlowView.swift` (~57). System-purpose strings are in `project.yml:99–100`. Current Contacts functionality supports selecting people to invite; removing implementation disclaimers is possible, but changing the purpose to contact matching requires that feature first.
- Preserve native permission sequencing and the existing request/denied/allowed policies. User-facing prose changes do not justify bypassing the native prompt or recording a grant in fixtures.
- `ProductUpsellScreen.swift` renders the real onboarding and contextual notification surface and retains request/open Settings/enable actions, response analytics, and progression.
- `ProductUpsellContentView` (~148) is currently just a circle/bell, headline, and working indicator. It is the small isolated place to implement native notification example cards and entrance animation. Use `accessibilityReduceMotion`, a cancellable task, and predictable static states for captures.
- Copy is in `ProductUpsellCoordinator.swift` catalogue (~58–73). Preserve existing eligibility/campaign caps; see `permission-and-map-evidence.md`.
- Actual notification routes include followed activity/check-ins, `capture_ready`, and `import_finished` in `PushNotificationManager.swift:924–950` and worker validation. Check payload producers before making more specific promises in examples.

## Existing native capture support

- `SimulatorTestSessionPolicy` in `Wander/App/WanderApp.swift` supports `-WanderAuthenticatedUITest -WanderOnboardingUITestStep identity|location|contacts|friends|notifications` on Simulator. This directly renders the production flow using a local fixture session.
- `-WanderOnboardingUITestSignedOut` opens the production signed-out carousel. Carousel also supports `WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS` and `WANDER_ONBOARDING_FORCE_AUTO_ADVANCE`.
- `-WanderOnboardingCommentsCapture` renders the real `ActivityCommentsScreen` via `OnboardingCommentsCaptureView`; it uses public-safe local fixtures and optionally `WANDER_COMMENTS_CAPTURE_RECT` to save a crop after layout.
- Existing hooks are preferable to a separate recreation. Add debug-only input fixtures narrowly if populated identity/friend/animation captures require them, but keep the rendered UI and interactions production components.

## Suggested ownership

1. Identity + permission + friend view edits: one owner of `OnboardingFlowView.swift` to avoid overlap.
2. Follow/search state and meaningful model tests: owner of `OnboardingFriendSuggestionsModel.swift` plus its test file, coordinating the view API.
3. Notification art/animation and catalogue copy: owner of `ProductUpsellScreen.swift` / catalogue; coordinate any root changes.
4. Root integrates isolated app build, fixture repository support, native screenshots/recordings, and review-board image replacement.
