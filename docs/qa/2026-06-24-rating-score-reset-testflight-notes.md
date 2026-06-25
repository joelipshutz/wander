# Rating Score Reset TestFlight Notes

Use this copy when the numeric rating/reset branch is packaged into the next TestFlight build.

## TestFlight What To Test

This build resets saved-place data so the alpha starts clean with the new 1-5 rating system.

What happens after you update:

- Your account, profile, follows, blocks, and default visibility stay in place.
- Existing saved places, drafts, and old dummy/stale place artifacts are intentionally cleared once on launch.
- You do not need to reinstall or sign out. Open the updated build normally.
- New `Been` saves use the 1-5 slider where `5` is best. `Wanna go` saves do not get a rating.
- Recommended scores now average visible `Been` ratings, so two people rating a place `4` and `5` should show `4.5`.

Please test:

- Open the updated build and confirm old saved/dummy places are gone.
- Confirm your profile/following graph still looks right.
- Save a real place as `Been`, move the slider between 1 and 5, force quit, and confirm it remains saved after relaunch.
- Save a real place as `Wanna go` and confirm it does not ask for a rating.
- Follow another tester and confirm their newly saved real places appear on social/discover map surfaces after refresh.

Known/reset behavior:

- Everyone will need to re-save places in this alpha build.
- The hosted Supabase reset migration must run before or with the TestFlight release so old server rows cannot rehydrate stale places.
- Normal TestFlight launches should not seed demo/fake places. Demo/fixture data should stay limited to explicit demo/test modes.

## Slack Draft

rec.me build `<build-number>` is `<live/approved or processing>` on TestFlight: https://testflight.apple.com/join/knEhRa6t

This build intentionally resets saved places so we can move cleanly to the new 1-5 rating system without old dummy/stale data showing up.

What will happen:

- Your account, profile, follows, blocks, and default visibility stay.
- Your saved places and old drafts are cleared once when you open the new build.
- You do not need to reinstall or sign out.
- New `Been` saves now use a 1-5 slider, where `5` is best.
- `Wanna go` places do not get rated.
- Recommended scores average visible `Been` ratings.

Why this should prevent fake/stale places:

- The app clears old on-device saved-place snapshots once for this release.
- The release migration clears saved-place rows on Supabase while preserving accounts and social graph data.
- Normal TestFlight builds should not seed demo places; after the reset, places should only appear when a tester saves a real place or follows someone with real saved places.

Please test:

- Open the build normally and confirm old saved/dummy places are gone.
- Save a real `Been` place, try the rating slider, force quit, and confirm it persists.
- Save a real `Wanna go` place and confirm there is no rating prompt.
- Follow another tester and confirm their newly saved real places show on map/discover surfaces after refresh.

Reply in-thread with device, account/email if relevant, screenshots, and exact repro steps for anything weird.
