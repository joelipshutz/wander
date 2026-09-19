# REC-529 · Native NUX review

Continue `codex/rec-529-nux-playthrough` in [PR #663](https://github.com/joelipshutz/wander/pull/663). The [T05](transcripts/T05.txt) and [T04](transcripts/T04.txt) transcripts remain historical source material; the latest direction below supersedes earlier quote and Feed treatments. Latest main is integrated for the requested squash merge; no TestFlight upload is included.

## Current native flow

- **M01–M06:** native Map controls explain Featured, Friends, More, Search, Plus and solid/dotted pin rings. More trim follows only its dropdown. Detached demonstration pins never enter the persistent store.
- **Map → Feed:** after rings, slide directly to the user's current Feed. The quote/Enjoy screen is removed entirely.
- **Feed people:** a real available people tile stays sharp while the page blurs. The handwritten annotation says “Connect with your circle.” Next advances immediately; normal playback also advances automatically.
- **Feed recent:** clear the blur, scroll just enough to center the latest actual activity card, then focus the complete card, including attribution and engagement actions. Copy: “Keep up with their moments.” Both beats now hold for 2.7 seconds (6.6 seconds total plus bounded readiness). Next or automatic completion clears the page, returns to the Feed top and ends the primary NUX. There is no multi-card scroll montage, substituted example activity, or later repeat.
- **First +:** on the first voluntary Add opening, annotate “Search nearby places,” then “Import your saved places from Instagram, TikTok and Google Maps.” The first annotation waits for nearby loading and sheet layout, then outlines the complete Nearby section from its header through See more. Without location/results it highlights just the search field. The page remains unblurred; both reading windows total eight seconds. The second annotation points at the import entry. Next, timeout or actual use leaves normal Add behavior; later opens do not repeat the lesson.
- **First place profile:** 3.5-second moderate focus with static annotations and live Check In/Wanna buttons, followed by one 1.4-second diagonal glimmer. Copy includes “Places you wanna go.” No Next/Skip, and no repeated profile lesson. Reduce Motion omits the glimmer.
- **Retired:** quote finale, Lists guidance, forced save flow, scheduled import and automatic later device-setup lessons. Explicit device setup/review remains separate. Starter lists remain deferred.

The primary lesson uses existing Feed data and account-scoped completion. Missing targets never cause fabricated content. The local recording/test fixture remains explicitly DEBUG-only and does not change ordinary accounts' Feed. Following, saving, importing and permission requests remain real user actions.

See [native-validation.md](native-validation.md) for verification and exact replay commands. Current recordings and stills live in the local `outputs/pr663-native-nux/revision-5/` package, outside Git. Prior media is historical.
