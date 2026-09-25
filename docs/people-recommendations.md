# Shared people recommendations — REC-587

Onboarding and the People recommendation shelf call `WanderBackend.peopleRecommendations` and use one ordered result from `ranked_people_recommendations`. Search remains a separate, explicit lookup. The ranking is provided by migration `20260923183000_ranked_people_recommendations.sql`.

The score adds independent signals rather than throwing away location or social context when someone is a contact:

| Signal | Points |
| --- | ---: |
| Existing administrator-curated priority | priority × 10 |
| Verified, opted-in match from currently allowed contacts | 120 |
| Each distinct public, visible contact or person you follow who follows the candidate | 12 per person, with no score cap |
| Candidate already follows you | 35 |
| Same chosen home area | 30 |
| Nonempty bio | 5 |
| Profile photo | 5 |

Rachel Leung (@nenesinla) already has curated priority 100, giving her a 1,000-point boost when eligible. This remains a score contribution: someone followed by 100 of your matched contacts gets 1,200 social points and can rank above her. This branch preserves the existing configuration without adding a name-based special case. Contacts with local/social relevance outrank contacts with no other signals. Social proximity and a shared area combine; profile completeness is a small fallback. Ties resolve by the total distinct supporting-person count, account creation date, handle and canonical ID for stable results.

Contact graph support works before you follow the matched contact: one supporting contact adds 12 points, three add 36, five add 60, six add 72, and 100 add 1,200. Every additional supporting person adds 12 points. A person who is both a contact and someone you follow counts once in that shared social boost. Private, deleted, hidden, blocked and self intermediaries add no signal. The label says “Followed by N contacts” when contact support contributes; direct matches still say “In your contacts.” The count reflects distinct people following that candidate, not the total address-book size or duplicate entries. Overall follower popularity is not a signal. The existing contact-discovery payload limit remains 100 matched profile IDs per ranking request; this change removes the five-person score cap.

With no contact matches or no contact permission, the same ranking still returns eligible profiles using curated priority, existing follows, follows-you, home area and profile completeness. It is not restricted to the local area and does not use overall follower popularity.

Location uses the viewer's saved onboarding/Settings home-city name, falling back to their public profile home area when no city is saved, with whitespace/case normalized. Candidates are compared using only their public profile home area. Other accounts' private home-city records are not read or exposed. Empty areas never match. There is no background GPS lookup, fuzzy same-city assumption, inferred demographic signal or access to private saves. A reason label explains the strongest relevant personal signal; all applicable points still contribute.

The ranking RPC accepts only matched profile IDs, not phone numbers or emails. Those IDs influence only the current response and are not retained. They cannot widen profile visibility. Both surfaces exclude self, existing follows, private/deleted/hidden profiles and blocks in either direction, even for curated accounts and contacts. The RPC retains caller RLS and permits only authenticated callers. Revoking contact access removes direct-contact and contact-graph rows from both surfaces immediately. If access disappears during an in-flight ranking request, the client reranks without contact IDs so membership and order no longer depend on contacts. The client falls back to the existing contact/general suggestions if the new endpoint is unavailable during rollout; that older endpoint has no contact-graph signal.

`PeopleFollowButton` is shared by horizontal cards and onboarding. It shows Following immediately during a pending request, starts the same press haptic, prevents duplicate requests, preserves native drag cancellation and restores Try again after failure. A pending state is never counted as a completed follow.

Validation includes rollback-only hosted scoring/privacy tests, remote payload/order decoding, existing pending/retry/double-tap model tests, and a native UI test that pauses and fails an onboarding follow before retrying.
