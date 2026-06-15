# Build 25 QA And M6 Checklist

Date: 2026-06-15
Current public TestFlight build: `0.1 (25)`
Public link: https://testflight.apple.com/join/knEhRa6t

Use this for the next friend test session. Mark each item pass/fail and capture screenshots or screen recordings for failures.

## Setup

- [ ] Install TestFlight build `0.1 (25)`.
- [ ] Test signed out first.
- [ ] Sign in with a real Clerk account.
- [ ] Force quit and relaunch after saving at least one place.

## Expected Current Behavior

- [ ] First-time signed-out user does not see seeded demo places/people as if they are theirs.
- [ ] Sign-in works and the signed-in profile shows the correct account.
- [ ] Sign out is available from Settings and returns to a logged-out state.
- [ ] Saved places persist after force quit/relaunch.

## Map

- [ ] Current-location dot is Apple-style blue.
- [ ] Current-location recenter button sits bottom-right, recenters, and zooms to a useful nearby radius.
- [ ] Tapping a saved/network pin opens the place card.
- [ ] Tapping empty map space unselects the active place.
- [ ] Saved own places show an edit affordance, not a plus button.
- [ ] Unsaved search/typeahead results show a plus/add affordance and do not claim "you saved it."
- [ ] Search/typeahead drops the keyboard after selecting a result.
- [ ] Map search distinguishes saved/network results from global MapKit results.
- [ ] Map filter chips show inactive bone fill and active terracotta ring/icon; no checkmark.

## Add

- [ ] Add tab title is `add a place`.
- [ ] Add flow has only the upper-left back path; no redundant `try a different link` or `back to add` buttons.
- [ ] Manual add resolves a real MapKit candidate before confirmation.
- [ ] `I'm here now` asks for/uses location and returns nearby relevant candidates.
- [ ] Step 1 confirmation has search or manual rescue if the extracted/resolved candidate is wrong.
- [ ] Step 2 details preserve multi-select tags and multi-select "best for" answers.
- [ ] Rating/excitement question uses emoji-style answer affordances.
- [ ] Successful save shows a brief celebratory saved moment/toast, then returns to the normal Add tab.
- [ ] Sync failure does not falsely imply the save succeeded remotely.

## Discover And Profiles

- [ ] Discover people are above places.
- [ ] Discover places use a single `mine` / `friends` / `everyone` segmented control.
- [ ] Tapping a place in Discover opens a place profile/card, not the owner's profile.
- [ ] Profile people section uses one segmented control for `following` / `followers` / `friends`.
- [ ] Follow/unfollow/block flows behave consistently across relaunch.
- [ ] A place saved to `Everyone` by someone you follow is visible from the follower account after refresh/relaunch.

## Place Profile

- [ ] Expanded place profile uses only data Wander actually has: name, category, address/locality, coordinates, save state, visibility, notes, answers, social proof, friend saves, share, and directions.
- [ ] No empty website/phone/hours/price/cuisine/order/ratings/photos fields appear unless populated by a real source.
- [ ] Address is not shown as a weird chip.
- [ ] User notes remain visible in the expanded card and do not look private-only when shared.
- [ ] Other people's shared notes/answers appear when visibility allows.
- [ ] Directions opens a useful map URL.

## M6 Extraction Regression

- [ ] Signed-in Google Maps link with place name and coordinates can return to confirmation instead of draft.
- [ ] Signed-in Apple Maps link with `q` and `ll`/`sll`/`center` can return to confirmation.
- [ ] Unsupported/social links stay as drafts/manual rescue and do not create fake pins.
- [ ] Photo import stays as draft/manual rescue until OCR is actually wired.
- [ ] Park-like names/categories remain `park`, not `hike`.

## Known Deferred

- Photo OCR is not wired yet.
- TikTok/Instagram extraction is not wired beyond manual fallback.
- Native Contacts permission is planned later.
- Share extension is planned later.
- Public web fallback for shared place/profile links is planned later.
