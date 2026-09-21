# Shared people recommendations — REC-587 review branch

Onboarding and the People recommendation shelf call `WanderBackend.peopleRecommendations` and use one ordered result from `ranked_people_recommendations`. Search remains a separate, explicit lookup. This change is for review; its migration has not been deployed.

The score adds independent signals rather than throwing away location or social context when someone is a contact:

| Signal | Points |
| --- | ---: |
| Existing administrator-curated priority | priority × 10 |
| Verified, opted-in match from currently allowed contacts | 120 |
| Each public, unblocked person you follow who follows the candidate | 12, capped at 60 |
| Candidate already follows you | 35 |
| Same chosen home area | 30 |
| Nonempty bio | 5 |
| Profile photo | 5 |

Rachel Leung (@nenesinla) already has curated priority 100, so her 1,000-point boost keeps her first when eligible. This branch preserves that existing configuration rather than adding a name-based special case. Contacts with local/social relevance outrank contacts with no other signals. Social proximity and a shared area combine; profile completeness is a small fallback, not a substitute for those connections. Ties resolve by mutual count, account creation date, handle and canonical ID for stable results.

Location means the home area chosen in onboarding/profile settings, with whitespace/case normalized. Empty areas never match. There is no background GPS lookup, fuzzy same-city assumption, inferred demographic signal or access to private saves. A reason label explains the strongest relevant personal signal; all applicable points still contribute.

The ranking RPC accepts only matched profile IDs, not phone numbers or emails. Those IDs influence only the current response and are not retained. They cannot widen profile visibility. Both surfaces exclude self, existing follows, private/deleted/hidden profiles and blocks in either direction, even for curated accounts and contacts. The RPC retains caller RLS and permits only authenticated callers. The client falls back to the existing contact/general suggestions if the new endpoint is unavailable during rollout.

`PeopleFollowButton` is shared by horizontal cards and onboarding. It shows Following immediately during a pending request, starts the same press haptic, prevents duplicate requests, preserves native drag cancellation and restores Try again after failure. A pending state is never counted as a completed follow.

Validation includes rollback-only hosted scoring/privacy tests, remote payload/order decoding, existing pending/retry/double-tap model tests, and a native UI test that pauses and fails an onboarding follow before retrying. The migration must be reviewed and deployed only after this branch is approved.
