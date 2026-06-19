# M7/M8 Alpha Trust And Social QA Checklist

Date: 2026-06-18
Build target: next TestFlight after M7/M8 merge
Status: Draft until the implementation PRs land

Use this checklist to verify the M7 trust surface and the M8 social reliability gate. Do not mark REC-7, REC-9, or REC-10 done until the two-account cases pass on TestFlight or a real-device debug build pointed at the same Supabase project.

## M7 Trust And Privacy

Device coverage:

- Current primary iPhone simulator or device.
- One smaller iPhone viewport.
- Larger Dynamic Type pass if practical.

Checks:

- Open Profile -> Settings.
- Confirm there is one row labeled `Privacy and trust`.
- Tap `Privacy and trust`.
- Confirm the sheet opens and has the title `privacy and trust`.
- Confirm the sheet says `Everyone` means people who follow you, not public internet.
- Confirm the sheet says `Friends` means mutual follows.
- Confirm the sheet says location is used to find nearby candidates and does not broadcast live location.
- Confirm the sheet says low-confidence extraction never auto-saves to the map.
- Confirm the sheet says blocks hide profiles, places, search results, and map content.
- Confirm the sheet says native Contacts are planned later and username search works now.
- Confirm the `done` button dismisses the sheet back to Settings.
- Confirm no trust-copy text clips in the smaller viewport.

## M8 Two-Account Social Gate

Accounts:

- Account A: current tester.
- Account B: second tester or seeded profile.

Cases:

- A signs in fresh, searches for B by username, and follows B.
- B has at least one place saved to `Everyone`.
- A can see B's `Everyone` place in Discover `everyone`.
- A can see B's `Everyone` place on Map when social/following places are enabled.
- A kills and relaunches the app; B's relationship and visible place remain correct after refresh.
- B follows A back.
- A can see B's `Friends`/mutual-only place after refresh.
- A unfollows B.
- B's follower-visible places disappear from A after refresh or relaunch.
- A follows B again, then blocks B.
- B disappears from A's search, people lists, profile navigation, map pins, and visible-place cache after refresh.
- A unblocks B.
- B does not reappear as followed unless A follows again.

Failure capture:

- Screenshot or screen recording.
- Build number.
- Device and iOS version.
- Both account emails/handles.
- Exact steps and whether app was killed/relaunched.

## Known Non-Blocking Deferrals

- Native Contacts permission is planned later.
- Notification permission is planned later.
- Full multi-screen onboarding is not part of this pass.
- M9 capture expansion for photo/TikTok/Instagram is separate.
