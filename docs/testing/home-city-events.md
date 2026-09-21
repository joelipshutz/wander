# Home city, phone and LA Events review

Open this branch's `Wander.xcodeproj`. These shared Debug schemes use fictional
simulator data; they do not sign in, send SMS or write a real account:

| Scheme | Starting screen |
| --- | --- |
| City and Phone Review | Existing Location step, city prefilled to Los Angeles and country code +1 |
| Events LA Review | Events, with all five tabs |
| Events Outside LA Review | Feed, with four tabs; home is Orange County |
| Events Unknown Home Review | Feed, with four tabs; home has not been confirmed |

The review schemes are simulator-only. Their saved form values last for the app
process and reset on the next fixture launch. Use a dedicated test account after
the migrations are deployed to verify cross-launch and cross-device persistence.

On Joe's Mac, run builds and tests through the workspace resource helper. It
requires 50 GiB free and reserves the selected existing simulator. From this
checkout, run:

```sh
python3 ../.tools/ios-work.py build -- test \
  -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,id=FD6770B4-AF24-4435-BD3F-301C706D51E2' \
  -only-testing:WanderTests/AccountContactDetailsTests \
  -only-testing:WanderTests/EventsAccessTests \
  -only-testing:WanderTests/OnboardingStateTests \
  -only-testing:WanderTests/OnboardingConnectionTests \
  -only-testing:WanderTests/OnboardingEntryRegressionTests \
  -only-testing:WanderTests/FirstVisitWalkthroughTests \
  -only-testing:WanderUITests/AccountContactDetailsUITests \
  -only-testing:WanderUITests/EventsAccessUITests \
  CODE_SIGNING_ALLOWED=NO
```

Repeat the two UI suites on existing iPhone 16e
`6CB5D49F-FA87-4D3E-9C2E-F9A1296F257C`. UI tests attach the form, keyboard,
country picker, metro picker, and each Events eligibility layout to the result.

## What to check

- Allow location: LA County cities such as Long Beach and Lancaster suggest
  Los Angeles. Orange County and the Inland Empire remain separate. Denied,
  missing or ambiguous location still permits manual selection.
- Confirm or correct the city in the same form as the phone. US dialing code is
  +1; enter fictional `2025550123`. Nine digits cannot save. A country change
  updates the prefix and uses that country's phone validation. Blank phone is
  allowed. Continue and Not now both advance to Contacts.
- Check the keyboard's Done button, scrolling, picker search, VoiceOver labels
  and large text on both phone sizes. No new permission request should appear
  when the form reads location already authorized in the preceding step.
- Change Settings → City & phone from LA to Orange County and back. Events
  disappears/reappears immediately; the selected Profile tab stays selected.
- A completed member cold-starts on Feed. First-visit onboarding and Map → Feed
  walkthrough ordering and landing remain unchanged. An explicit hidden Events
  destination resolves to Feed without a blank tab.
- With a test account, save LA, cold-start offline, and travel or simulate another
  location: the saved home still wins. Sign out and use another account: no LA
  eligibility or private phone should carry over. Refresh online after a home
  change on another device and verify the new saved choice takes effect.
- Unknown-home existing members have four tabs until they confirm a home city
  in Settings. A public profile's freeform home area does not control Events.

## Backend release dependency

Deploy `20260921061500_account_contact_details.sql`, then
`20260921070000_events_home_metro_gate.sql`, before releasing the app. Until
deployment, live account saves and gate hydration are unavailable. The migrations
have rollback-preview tests; previewing them does not deploy them.

The server independently denies Events registration for unknown and non-LA
homes. Phone is optional, private and unverified; this form does not register a
verified contact-match identity. Existing Events interest is retained when home
changes, and becomes readable again if the member changes back to LA.

## Native CI evidence

The `Home city and Events native validation` workflow runs the feature unit tests,
onboarding and first-visit regression suites, and both feature UI suites on an
existing iPhone 17 Pro. It repeats the UI suites on an existing iPhone 16e and
exports original screenshots, result bundles, and a simulator app for review.

The initial full-unit run [35620835724](https://github.com/joelipshutz/wander/actions/runs/35620835724)
finished with 2,380 passes and four failures on Pro; compact UI had seven passes
and one failure. All 20 new feature unit tests passed. The feature UI failure was
a parent accessibility identifier overriding the Settings Save button identifier;
the parent identifier has been removed. Screenshot review also found the keyboard
clipping the phone field, addressed by revealing the whole phone section when
editing. The typing UI test now checks that its privacy note stays visible.

Three full-suite failures were in unchanged areas: the glass-cluster source
contract (`NavigationContractTests`), a search timing threshold (58.7 ms against
50 ms on the hosted runner), and the calendar widget month-boundary snapshot.
These are not hidden by a full-suite pass claim. The dedicated workflow now runs
the relevant feature/onboarding suites; broader-suite failures remain release
review items.

The follow-up [native run 35624797787](https://github.com/joelipshutz/wander/actions/runs/35624797787)
passed all 116 selected unit tests and seven of eight UI tests on each phone. The
keyboard/Save fixes compiled and the phone section is fully visible in both
native captures. The remaining Settings loop failure occurred on its second
Settings-open tap: XCTest chose (346.4, 78.4), outside the circular 44-point
button centered at (364, 96). The first home save, Events removal and selected
Profile assertion had already passed. The test now targets the button center;
manual native LA → Orange County → LA passed without a restart. This test-only
correction still needs its automated rerun before claiming all UI tests pass.
