# Permission prompts and map coach definitions

Read-only source verification, September 16, 2026. Baseline is review-board/build-174 checkout `wander-release-174`, commit `4a9f122c062d04db2f06e7b75226a9e85999169b`. No app changes or new runtime claim.

## N28 / N29 are contextual requests, not success confirmations

N28 is the notification campaign's `place_saved` trigger. N29 is `follow_created`. They invite someone to enable notifications after a relevant action. They do not say “permission granted,” and are not the confirmation screen shown after accepting N12.

Actual gates:

- The store emits `place_saved` when its save path creates a new save and `requestsProductUpsell` is true; imports can pass false. It is not a mandatory page after every save or edit. [WanderLocalStore.swift:6225](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/WanderLocalStore.swift:6225>), [WanderLocalStore.swift:6378](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/WanderLocalStore.swift:6378>)
- The follow path emits `follow_created` for a new follow. The async backend path emits after success; local/queued paths also support the trigger. Already-followed rows do not repeatedly emit it. [WanderLocalStore.swift:7422](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/WanderLocalStore.swift:7422>)
- Root requires a validated session, loaded notification preferences, and no conflicting flow/banner. It buffers requests for 220 ms and can defer presentation. Initial and deferred eligibility both use `!pushNotifications.notificationsAreEnabled`. [WanderRootView.swift:2046](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/App/WanderRootView.swift:2046>)
- “Enabled” means **Astir's `pushEnabled` preference is true AND iOS is authorized, provisional, or ephemeral**. Thus an earlier iOS grant alone does not make someone permanently ineligible: an account with Astir push off can still see an enable prompt. [PushNotificationManager.swift:389](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/PushNotificationManager.swift:389>)
- Campaign caps are one lifetime impression per trigger and three across the three triggers (N12 onboarding plus N28 save plus N29 follow), keyed by account in local preferences. Debug fixtures can bypass the cap; screenshots alone do not prove ordinary eligibility. [ProductUpsellCoordinator.swift:50](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/ProductUpsellCoordinator.swift:50>), [ProductUpsellCoordinator.swift:242](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/ProductUpsellCoordinator.swift:242>)
- The screen's primary action enables/requests notifications or opens Settings after denial. Completing the enable request dismisses the campaign; there is no separate post-grant success page here. [ProductUpsellScreen.swift:95](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Onboarding/ProductUpsellScreen.swift:95>)

**Board wording:** “Conditional notification request after a save” and “Conditional notification request after following someone.” Use **“Suppress while notifications are enabled”**, not “Never show after the user has ever granted iOS permission.” If the transcript decision is to retire both campaigns, record that as a requested product change rather than merely removing already-redundant success screens.

## Featured / Friends / You

| Source | Actual selection | Concise truthful coach |
|---|---|---|
| Featured | Check-ins in the map area, from eligible own/social/community candidates; ranked by taste fit, relationship, support, rating, then recency. Up to 24 place groups in the current client. It is broader than followed people. | **Recommendations for your taste.** Optional fuller line: **Discover places through your people and the Astir community.** |
| Friends | Visible saves whose owner is followed, excluding the current user; then active More refinements. Includes check-ins and Wanna saves by default. “Friends” does not mean mutual follows only. | **Places saved by people you follow.** |
| You | Current user's visible saves, with active refinements. | **Your check-ins and places you want to go.** |

These are source-backed definitions, not new ranking promises. “Featured is the best places from your people” is too narrow. “Friends is people nearby” is incorrect. Avoid teaching “all” as a promise that bypasses private/blocked content or active filters.

Evidence:

- [MapSource.subtitle](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Models/WanderEnums.swift:37>) currently says Featured recommendations are based on taste, Friends is everyone followed, and You is own check-ins/Wanna places.
- [baseVisiblePlaces](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Map/MapScreen.swift:1489>) dispatches to the actual source selectors.
- [MapFeaturedSelection](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Map/MapScreen.swift:8569>) filters to `.been`, respects the viewport/refinements, ranks groups, and caps results. Its taste profile uses the viewer's Wanna saves and check-ins rated at least four, with category/cuisine/tag affinities.
- [MapFilterSelection.friendsPlaces](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Map/MapScreen.swift:8778>) uses followed IDs minus the current user.
- [fetchRemoteFeaturedViewportPlaces](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/WanderLocalStore.swift:7667>) fetches a separate community candidate set; [featuredPlaces](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/Remote/SupabaseRepositories.swift:424>) calls `featured_places_in_view`.

## Solid / dotted map marks

The actual implementation teaches **outline style**, not “filled circle versus empty circle”:

- Solid outline = a check-in (`been`).
- Dotted outline = Wanna (`wannaGo`, dash pattern `[1.5, 3.5]`).
- Color currently identifies ownership: own saves use `pinYou` orange `#F05A3C`; social saves use `pinSocial` blue `#69B8D7`. A new universal “signal” color treatment would be a design change, not a description of this implementation.
- One place can have own and social outlines. Mixed social check-in + Wanna states split the social outline into solid and dotted arcs. For current-user states, check-in takes precedence in the builder.
- Active search results use a separate double-outline treatment with a dashed outer ring. Therefore do not teach that *every dotted circle anywhere on the map* means Wanna. Highlight a known saved-place example when introducing the legend.

**Recommended coach:** **Solid ring: checked in. Dotted ring: want to go.** When the example specifically depicts the user's own save, **“Places you've been” / “Places you want to go”** is appropriate. Do not use “you” while pointing at a friend's saved-place ring.

Evidence: [MapPinOutline.dashPattern](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Map/MapScreen.swift:10569>), [MapPinOutlineBuilder](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Map/MapScreen.swift:10614>), [ownership colors](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Map/MapScreen.swift:10087>), [theme tokens](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/DesignSystem/WanderTheme.swift:166>), [native pin drawing/search treatment](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Map/MapScreen.swift:7199>).

## Revision audit status

Follow-up audit of `revisions.json` and `review.template.html` completed after the files appeared. No other agent's file was edited by this audit.

- R21 initially said “ungranted” and “cooldown.” The content author corrected it to the actual OS-plus-app-preference eligibility and lifetime frequency caps; corrected JSON verified.
- R13 initially promised finding a person from Map Search. Actual search matches owner names/handles against saved places, but returns saved/MapKit place results, not member profiles. Corrected JSON now says “Find places by name, area, or person” / “Search for a place—or places from your people.” Evidence: [TrustedPlaceSearch.swift:982](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/TrustedPlaceSearch.swift:982>) and [MapSearchSuggestion.Source](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Map/MapScreen.swift:8852>).
- Contacts matching dependencies and broader Featured semantics are correctly marked in the JSON.
- Template observations sent to the coordinating agent: the sample nonmember Invite row showed an @username, which visually implied membership; notification examples and starter-list titles were hardcoded differently from the selected numbered copy. Use the selected copy in the preview and plain contact identification for nonmembers.
- R12/R13 use a cropped native baseline map screenshot, not a complete revised pin demonstration. Keep it labeled as baseline reference, and ensure the motion/legend study points to explicit own-save examples when using “you’ve been” / “you want to go.” Source/color/mixed-ring limitations remain as documented above.
