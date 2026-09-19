# Onboarding device review — REC-547

Local review branch: `codex/rec-547-film-welcome-device`, in `wander-native-onboarding-review`. Joe lifted the release hold on September 19: land the selected film C opening and the full founders VHS C video, preserving the cleaned audio and outtake. Main/TestFlight validation is underway.

## Run in Xcode

Open this worktree’s `Wander.xcodeproj` and select **Onboarding Review**. Choose Joe’s connected iPhone as the run destination. The scheme runs real Swift views with local review accounts/data and selects film C. The same selected film C is now the release default. The review scheme does not create a live account.

The opening animates normally. Tap Next through the benefits into Create your account; there is no close X. To continue locally, enter `review@example.test`, choose Continue with email and enter `123456`. Then fill name and an available username (`jordan_review` works; `taken` deliberately exercises the error). **A profile photo is optional.**

N09 says **Find places nearby**. Its existing explanatory body, privacy line and real Hotchkiss Park image stay. N11 says **Keep up with the people you love**, without a subtitle. Notification examples use **Your Instagram import is ready**, with vertically centered app icons.

After setup, the founders’ video offers Play and Skip. The 1:31 cut keeps the outtake through the final Cut. Native pause, scrub and mute controls remain; backgrounding pauses playback. Ending or skipping fades into Ryan’s existing first-use walkthrough. The walkthrough is not constructed underneath the video. Playback progress and handled status are account-scoped; a new fictional review launch resets only the review account’s movie progress.

Captions are not included in this review candidate. Joe selected the full Events 03C VHS treatment for the welcome video. The complete cleaned audio and outtake remain unchanged. All three original eight-second options are archived. Automatic tests and device-build outcomes are recorded in the dedicated process archive when complete.

## Repeatable build

Regenerate after source membership or scheme edits:

```sh
xcodegen generate
python3 ../.tools/ios-work.py build -- build -project Wander.xcodeproj -scheme 'Onboarding Review' -destination 'generic/platform=iOS'
```

Use the workspace build helper and its existing cache. Do not bypass its disk floor or simulator reservations. For direct simulator capture, pass `-WanderNativeOnboardingReview location` (or `identity`, `contacts`, `friends`, `notifications`, `founders`, `welcome`) and `-WanderAuthenticatedUITest -WanderUseDemoFixtures`. The scheme’s `WANDER_NATIVE_ONBOARDING_REVIEW=welcome` provides an order-independent Xcode launch equivalent.

The full review and source-history archive is under `docs/designs/onboarding-2026-09/`. Its README distinguishes local preservation from the repository publication.
