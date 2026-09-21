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
  -only-testing:WanderTests/NavigationContractTests \
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
