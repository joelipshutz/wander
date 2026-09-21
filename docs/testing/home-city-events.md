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
  -only-testing:WanderTests/HomeCitySearchTests \
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
country picker, inline city search states, and each Events eligibility layout to the result.

## What to check

- The city field paints immediately with Los Angeles as the fallback. Existing
  saved home takes priority. Otherwise, already-authorized location supplies its
  locality without blocking editing; late hydration/geocoding cannot replace edits.
  It reuses a recent authorized fix and cancels the background lookup after three seconds.
- Clear the city and type `Par`: an inline dropdown distinguishes Paris, France
  from Paris, Texas. Select France and check +33. Try Kyoto, Nairobi, São Paulo,
  and non-Latin city names. The production provider uses worldwide MapKit locality
  search, not the old fixed metro catalog. iOS 18+ uses locality-filtered completion;
  iOS 17 uses one address search with city-only result filtering.
- Search waits 150 ms after the last edit, cancels superseded requests, ignores
  out-of-order responses, and keeps at most 20 recent queries in memory. Only the
  selected completion gets a detail lookup. Empty input sends no request. Search
  timeouts show retry copy; a partial query cannot be saved as a confirmed city.
- The simulator review scheme uses deterministic search fixtures. `Par` deliberately
  waits two seconds to capture the typing state; this delay is absent in production.
  `zzzzcity` shows no matches and `offline` shows retry. Add launch argument
  `-WanderHomeCityLiveSearch` to use real Apple city search with the same fictional
  account; it still performs no account/SMS writes.
- Confirm or correct the city in the same form as the phone. The country code
  follows city selection until the phone/country is edited. US numbers need ten
  national digits; use fictional `2025550123`. Blank phone is allowed. Continue
  and Not now both advance to Contacts, preserving the existing step order.
- Check the keyboard's Done button, scrolling, inline dropdown, VoiceOver labels
  and large text on both phone sizes. The native screenshots cover initial,
  cleared, typing, matching cities, selected Paris/Kyoto, no-match and offline states.
- Change Settings → City & phone from LA to Irvine, then Long Beach. Events
  disappears/reappears immediately; the selected Profile tab stays selected. LA
  County metadata includes Pasadena, Long Beach and Lancaster; Orange County,
  Ventura and Inland Empire cities do not qualify. No radius-based LA inference.
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

[Native run 35637604171](https://github.com/joelipshutz/wander/actions/runs/35637604171)
passed at app/test commit `57a4f7add4dc08dbc27feac243470d487091ea3a`:

- iPhone 17 Pro, iOS 26.5: 138 passed, zero failures or skips (129 selected
  feature/onboarding unit tests and all nine feature UI flows).
- iPhone 16e, iOS 26.2: all nine UI flows passed, zero failures or skips.
- Captures include prefill, clearing, loading, worldwide matches, selected
  Paris/Kyoto, no matches, retry, phone entry, country picker and Events states.
- Selection remains confirmed when the keyboard commits text on focus loss;
  Continue/Save stays enabled. The Settings LA → Irvine → Long Beach loop passed
  on both phones without restarting or changing the selected Profile tab.

The workflow artifacts contain original native screenshots, result summaries,
full result bundles and the simulator app. Local live Apple search also returned
Kyoto (resolved to Japan/+81) and São Paulo from an unaccented query. Review
fixtures are deterministic; their two-second `Par` delay is absent in production.
Swift 6 provider/model type checking also passed against the local iOS 26.3 SDK
with iOS 17 as the deployment target.

The earlier full-unit run had three failures in unchanged areas: the glass-cluster
source contract (`NavigationContractTests`), a search timing threshold (58.7 ms
against 50 ms on the hosted runner), and the calendar widget month-boundary
snapshot. Those remain broader release-review items. The passing run above covers
the relevant feature/onboarding suites and is not a full-app suite pass claim.

## Worldwide city persistence

The owner-private payload includes `home_city` (name, ISO country, region,
county), with no exact coordinates. The server validates those fields and derives
LA eligibility from the city even if a caller supplies a contradictory metro ID.
Legacy saved metro records remain readable. The two migrations are undeployed,
so the worldwide-city extension is included in the original draft migration.
The full hosted rollback-only smoke suite passed after this change; a separate
read verified that neither the new table nor RPC was left deployed. Production
cross-launch/cross-device acceptance requires deployment and a dedicated account.
