# Archived onboarding film exploration C

Joe preferred C, requested continuous film shakiness during scene transitions, and asked to keep the exploration for later review. This archive does not replace the approved production opening.

Native source: `1e27cb4`, tag `archive/rec-529-film-c-2026-09-18`, branch `codex/rec-529-onboarding-film-exploration` in `wander-native-onboarding-review`. Base is remote main `916a6b765021527f41da3f83b39b913886ac7640` as fetched on September 18. No merge or release.

The continuous decorative film state is independent of the reading timer: full-screen slides no longer freeze grain, ink flutter, tracking damage or registration motion. C retains italic Connect with your and condensed Signal headlines. Native Next, Log in and account controls remain live. Film stops at account entry as before; pause, backgrounding and accessibility behavior remain intact.

Review: [archived full-screen comparison](../../opening-film-archive.html). Its manifest is pinned to `native-film-archive.json`, separate from the working comparison. A retains approved captures from `6432401`; B/C use the continuous-film source above. The original Events reference and the two previous film passes remain available through the comparison.

To resume native review: use the existing worktree/shared cache and existing iPhone 16e. Build only through `.tools/ios-work.py`; launch the local fixture with `WANDER_ONBOARDING_TREATMENT=film-type`, `WANDER_ONBOARDING_REVIEW_PICKER=1`, and `WANDER_ONBOARDING_PAUSED=1`. A source tag is retained even if the working branch advances. Do not merge the broad historical NUX branch.

N08-N12 account setup follows the visual checkpoint. Ryan owns post-onboarding NUX.

Validation: 24 focused tests passed, including both full automatic film modes and live Next/Log in/signup/email/verification interaction. Both final native recordings reach account creation. Browser Focus and transition playback passed. The fixed header film region no longer freezes across the scene handoff (1.1 seconds before, none after at 100 ms sampling). See `../../native-board-qa/film-continuity-pixels.json` and `../../native-film-continuous-tests.xcresult`.
