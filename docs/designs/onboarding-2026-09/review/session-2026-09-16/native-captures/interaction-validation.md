# Native interaction validation

Status: complete. Final native auth, profile/crop, follow/search, and actual permission request/denial journeys all have passing regression evidence and verified captures.

All journeys execute production SwiftUI/UIKit views in the app on the dedicated iPhone 17 Pro test simulator (D0D0B63E-85CE-401E-A701-0D57069908E0). Authentication, member, and profile repositories use the native review host’s local providers; no account, follow, message, or avatar network write occurs. Screens and videos are simulator captures, not HTML approximations.

The profile photo journey selects the app’s existing bundled sample avatar artwork through the real system Photos picker and production crop view. Sample names and artwork are review data.

## Regressions under test

- Welcome advances to the real Create account form; Log in switches methods; password and email code forms work; a partially entered code survives background/foreground.
- Profile name/handle preview updates, taken-handle validation appears, and Continue remains disabled until a real chosen photo is cropped.
- Following one suggested member does not follow the other rows; search and clearing search preserve each row’s state.
- Actual native location and Contacts alerts appear; denial preserves the corresponding recovery path. Notifications records the real first prompt when eligible and validates Open Settings after denial.

## Unit fixture correction

`OnboardingStateTests.testCompletionStoreIsIsolatedPerUserAndPersistsProgress` now explicitly expects `hasSavedRequiredIdentity: false`. The stored state begins fresh and optional-step progress/completion does not certify that a required identity was saved. The previous omitted argument expected nil and was stale. No production identity condition was weakened.

## Recording evidence

- Auth: passed, 41.611 s. Evidence `native-test-results/auth-20260917T102024/result.xcresult`. Exported and visually verified N04, N06, N07, N05, N08-after-auth. `native-auth.mp4` replaces the earlier two-benefit recording with the current three-screen welcome → signup → Log in → password/back → email code → required-profile journey. The actual raw recording has 12.0 s of startup removed; retained duration 38.412 s. No internal edits. The first welcome screen is paused for deterministic manual navigation; separate opening recordings demonstrate automatic flicker and timing. The combined app includes the final flicker implementation. The final video frame and N08-after-auth prove successful local verification and entry into required-profile onboarding.
- Follow/search: passed, 34.135 s. Evidence `native-test-results/follow-20260917T093137/result.xcresult`. Exported N11-following. `native-follow.mp4` = raw after removing 46.0 s of test startup; retained duration 22.982 s. No internal edits.
- Location/Contacts: passed, `native-test-results/permissions-20260917T093708/result.xcresult`. Exported and visually verified N30, N31, N36. Actual OS alerts were denied and recovery assertions passed.
- Notification first request, denial, and recovery: passed, 21.546 s, `native-test-results/notification-permission-20260917T094838/result.xcresult`. Exported N12-system-permission and N32 from this successful run. The app was reset only on the dedicated local test simulator before this test; its Photos library was preserved.
- Profile/crop: passed, 79.583 s, `native-test-results/profile-20260917T095538/result.xcresult`. Exported and visually verified N08-filled, N35, N08-photo-picker, N67, N08-photo-chosen. The chosen real crop changes the preview and enables Continue. `native-profile.mp4` retains 68.438 s after removing 47.0 s of test startup; no internal edits.

Auth’s Log in action missed its transition in some native diagnostic runs while another simulator was being driven. The initial AX target was only 20.7 points tall because its minimum height was outside the Button label. The production improvement moves the 44-point minimum height and rectangular content shape into the label and applies the plain button style; provider and auth-state logic are unchanged. The next concurrent test still missed a correctly centered tap on the fully visible 370×44-point target. Three subsequent quiet runs successfully changed auth mode, including the final fully passing journey. Input contention is a plausible contributor, not a proven sole cause; no unsupported auth callback workaround was introduced.

Two test-only input defects surfaced in the quiet runs and were corrected using actual screenshots and accessibility frames. The ScrollView AX frame extends behind the number pad, so a drag starting at 85% of that frame pressed 0 instead of dismissing the keyboard. The helper now starts 30 points above the observed keyboard frame and requires dismissal to complete. Refocusing the center of the centered code field could place the caret before existing digits; the test now appends from the field’s trailing edge and asserts the preserved code before and after. Profile’s initial diagnostic had the analogous cursor issue and uses the same observed trailing-edge approach. Failed diagnostic recordings remain only under native-test-results and are not published as completed journeys.

## Observed system text

N30 location: **Allow “Astir” to use your location?** Purpose: “Astir uses your location to suggest nearby places when you ask and to keep an optional nearby widget useful. It never broadcasts live location.” Buttons: **Allow Once**, **Allow While Using App**, **Don’t Allow**.

N36 Contacts: **“Astir” would like to access your Contacts.** Purpose: “Astir uses your contacts to help you connect with people you know.” Buttons: **Don’t Allow**, **Continue**.

The above is observed from the actual D0D0 iOS 26.3 system captures. The app’s loading CTA behind the Contacts alert currently says “Opening settings…” during its first request; this is a minor source-copy follow-up, not a false claim about the system dialog.

## Profile regression discovered during recording

The final native keyboard-dismissal gesture reproduced a production issue: `taken` showed its unavailable result, then resigning focus wrote the same text through `handleBinding`, resetting availability to idle. Because the normalized handle did not change, the asynchronous availability task did not run again. Evidence: `native-test-results/profile-20260917T094021/result.xcresult`, AX shows `@taken` and the default “2–39 letters, numbers, or underscores” after dismissal. The recording regression intentionally requires the taken result to remain visible. Root added the same-value equality guard. The subsequent native run verifies `That username is taken` remains visible after keyboard dismissal; N35.png is its clean screenshot. The remaining crop step uses the actual PhotoKit image frame because the system reports no synthesized hit point for that remote image tile.

N12 native notification request: **“Astir” Would Like to Send You Notifications**. Body: “Notifications may include alerts, sounds, and icon badges. These can be configured in Settings.” Buttons: **Don’t Allow**, **Allow**. The successful regression uses the actual system permission action to disambiguate the OS alert from the product overlay’s accessibility alert trait.

## Crop regression discovered during recording

The first true N67 capture exposed the custom crop header at the top of the full-screen cover, overlapping the status bar/Dynamic Island. XCTest reported an invalid hit point for Choose and could not finish the crop. Evidence: `native-test-results/profile-20260917T094935/result.xcresult`. Root replaced that header with a native NavigationStack title and toolbar Cancel/Choose placements. Final native crop acceptance passed on the combined build. N67.png is refreshed with the proper native navigation bar; N08-photo-chosen.png proves Choose completed and Continue is enabled. The earlier defective frame remains only in its diagnostic run’s attachments.


## Final local state

The dedicated D0D0 test app and runner were stopped after the final capture. No test or recording process remains. Final auth source/test compilation is recorded in `native-onboarding-build/auth-caret-test-build.log` (`TEST BUILD SUCCEEDED`), including the current LoggedOutCarouselView, OnboardingWelcomeContent, OnboardingWelcomeTests, and NativeOnboardingFlowUITests. Root owns the separate final full-unit and broader onboarding UI validation.
