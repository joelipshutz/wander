# People discovery placement

Native production SwiftUI captures for [REC-682](https://linear.app/recme/issue/REC-682/move-people-worth-following-to-profile-and-invite-people), following the approved [mockup review](https://github.com/joelipshutz/wander/pull/784).

| Surface | iPhone 17 Pro, light | iPhone SE, dark |
| --- | --- | --- |
| Profile | [Expanded Profile](profile-large-light.png) | [Carousel, streak, Activity](profile-compact-dark.png) |
| Invite people | [Recommendations above contacts](invite-large-light.png) | [Separate carousel and contact index](invite-compact-dark.png) |

Captured on iOS 26.5 with deterministic local fixtures. `PeoplePlacementUITests` exercises the actual Profile and Invite surfaces, including expansion resets, horizontal scrolling, shared acknowledged follows, contact search and permission states, section ordering, and removal from Feed. `CompactPeopleCardsUITests` retains coverage for Follow touch areas, drag cancellation, pending requests, retry, and accessibility text sizes.

To inspect the production Profile with the same fixtures, launch the Debug app with:

```text
-WanderAuthenticatedUITest -WanderUseDemoFixtures -WanderDisableWalkthroughs -WanderInitialTab profile -WanderUnifiedLiveUITest -WanderCompactPeopleUITest
```

Collapse is temporary: launch, tab return, foreground return, Profile appearance, and account changes restore the expanded section. The existing streak follows the carousel, then Activity, Your map, and Your calendar. The Invite carousel leaves the full contact-index touch area clear.
