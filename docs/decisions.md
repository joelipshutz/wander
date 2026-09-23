# Decisions

Last updated: 2026-09-21

Durable product and engineering decisions for rec.me, formerly Wander. See the product spec and engineering plan for fuller rationale.

## Lists within Wanna and check-in saves (REC-567)

Wanna places **Add to lists** below the note and above the date, outside More
options. Check-in places it directly below Friends, before Photos and More options.
List selection remains optional and is available for first saves, repeat saves,
and edits. Lists already containing the canonical place are disabled and labeled
**Already in list**; repeat visits never create duplicate entries for that place
in a list.

Picker choices are staged until the parent save succeeds. Canceling the picker
preserves the form; closing an unsaved form adds no list memberships. List delivery
reuses the committed save and reports partial sync separately. Retrying list
delivery never creates another check-in or Wanna. Each list retains its visibility
and ownership, and selecting lists never changes the save's audience.

## Initial map preparation and retained returns (REC-484)

The approved launch artwork covers the mounted initial map for a two-second
minimum while local rendering and source refresh begin underneath it. The
cover blocks both touch and accessibility interaction, including bottom tabs.
Reveal does not wait for remote refresh completion, so offline or stalled
requests cannot hold the user behind an unbounded loading screen. A retained,
prepared map remains immediately available on ordinary foreground or tab
returns; those returns do not add another fixed splash delay.

Same-account refresh callers share work. Unchanged responses should not rebuild
presentations or rewrite persistence. Reuse must remain bounded and invalidate
for local edits, remote changes, and access revocation. Account replacement or
root teardown cancels owned reads before their results can apply. The cover
provides preparation time; it does not establish that post-reveal responsiveness
has passed device validation.

## Native onboarding review (REC-529)

Onboarding review uses the production Swift views and simulator recordings. The
review host supplies local sample data through the existing repository interfaces;
it does not recreate phone screens in HTML or create real accounts/follows.

The welcome sequence retains the September 18 Signal treatment from main:
“Connect with your” introduces community, people, places, and loved ones with
whole-word slides before the final “a local experiment” phrase. Supporting
copy slides in separately; the entire composition slides into the next screen.
The flow advances once through
the places and people benefits into account creation, with Next, pause, and
direct Log in. Profile setup requires a
name, available username, and saved photo; its header previews the profile live.
Following is an explicit action on each person, with search and retry states.

The first-visit tour explains Map controls in order: Featured, Friends, More,
Search, Plus, then pin meanings. It continues directly into the user's current
Feed and ends at the Feed top without forcing a save. Independent first-use
annotations remain for Plus and place profiles; Lists and scheduled follow-on
NUX are retired. Established accounts are not newly enrolled by this change.

The delayed supporting line “Keep track of everywhere you’ve been. Keep up with
the people you love.” is the current review baseline; supporting-copy alternatives
and timing remain open. The lead-in, four words and final phrase are confirmed.
Explicit empty preview/test configurations can omit the opening; the production
default includes it. Broader explorations remain in the REC-529 open questions.
Native capture routes are DEBUG-only. Validation and native media evidence are
recorded in the implementation PR and `docs/reviews/rec-529-native-onboarding.md`.

### September 18 post-onboarding NUX selections

Slide/fade remains selected. The quote/Enjoy ending is removed. After Map rings,
the app slides into the user's actual current Feed. A people tile stays sharp
with “Connect with your circle,” then the blur clears and the Feed scrolls to
center the latest actual activity tile. Its entire bounds—including the footer—
remain unblurred with “Keep up with their moments.” Both beats have Next and
finite automatic playback, with 2.7-second reading holds and 6.6 seconds total
once targets are ready. The page clears and returns to the top to finish.
Completion is account-scoped and does not repeat on later visits. Missing data
is not replaced with example content. The old multi-card scroll is not restored.

On the first voluntary + opening, guide nearby search and the import entry with
“Search nearby places” and “Import your saved places from Instagram, TikTok and
Google Maps.” Wait for nearby loading and sheet layout to settle. Keep the page
unblurred and outline the entire Nearby section, including its header, results
and See more. Without location/results, outline only the search bar. The two
reading windows total eight seconds. Normal source actions remain usable; the
lesson itself never requests location access. On first place-profile entry,
keep the 3.5-second moderate blur, static annotations and real floating buttons,
then one 1.4-second diagonal glimmer. Wanna copy is “Places you wanna go.” No
Next/Skip on the profile; Reduce Motion omits its sweep. Later visits are normal.
The More highlight continues to hug only its dropdown. Starter lists are deferred.

## Astir Events engineering direction (REC-467)

The September 15 [conditional handoff](designs/astir-events/engineering-handoff.md)
plans the complete Events journey with two changing work lanes: parallel backend/history
and native/Clip/web foundations, then before-event/admission and after-event/history.
Keep the existing Supabase identity, canonical place and visit history. App Clip/browser
RSVP and management precede the required app QR at the door. Admission, explicit
check-in and historical completion remain distinct. Issued waitlist offers hold seats;
manual pending review and phone verification do not. Use one full-access Team admin
console role and a prepared offline roster with durable reconciliation.

The [engineering plan](designs/astir-events/engineering-plan.md) records exact D1–D19
approvals, including code allowance, rescheduling and registration deadlines. This
entry approves no additional operating default and claims no implemented Events code.
[Open decisions](designs/astir-events/engineering-open-decisions.md) remain explicit.

## Feed activity grouping (REC-494)

The Feed combines already-visible check-in, Wanna, and list-addition events from
the same actor and canonical place within 30 minutes of the first event. The
window does not slide. A second check-in starts a new group; list creation,
missing-place events, and ambiguous legacy social saves remain separate.
Check-in leads over Wanna, then list addition. Group identity and Feed ordering
stay anchored to the first event, so later organization does not bump the card.

One card shows the place artwork and headline, with visible list context and an
inline **View activity / Hide activity** disclosure. Expanded rows show the
chronological action and timestamp and open the original post or visible list.
Original event IDs, likes, comments, shares, and authorization remain intact;
the main action row belongs to the headline event. No conversations or stored
events are merged. Grouping covers the events loaded in the current Feed page,
and a refresh recomputes it solely from currently visible events.

## Product Decisions

| Decision | Status | Notes |
|---|---|---|
| Map-first app | Locked | The map is the primary memory and discovery surface. |
| Lists icon identity | Locked for REC-444 | Bottom Lists navigation uses a slim paper outline with three evenly spaced bullet rows. All other Lists actions, metadata, empty states, and settings use the plain three-bullet `list.bullet` symbol. Wanna and saved lenses retain bookmarks. Icons inherit their surface's colors and preserve existing hit targets. |
| Map source and refinement contract | Locked for REC-249, REC-253, REC-261, and REC-418; revised 2026-09-03 | Featured is the default source; Featured, Friends, and You are mutually exclusive. Friends contains the viewer plus everyone the viewer follows, includes both Been/check-in and Wanna places, and treats one-way follows as eligible. Featured contains Been/check-ins only and considers the broader rec.me community: existing RLS-visible own/followed rows retain their detail, while a non-followed save may contribute only when its owner is active and non-private and the save uses the persisted `followers` value presented as Everyone. That broader signal is an anonymous canonical-place aggregate only—support count, rating, and recency—with blocks enforced and no stranger identity, user-place id, note, tag, answer, or photo returned. The server caps each expanded viewport at 120 candidate place groups; the client builds one taste profile per pass from the viewer's positively rated or Wanna saves, then weighs self/follow relationships, category/cuisine/tag fit where known, community support, rating, and recency before deduplicating and rendering at most 24 groups. Source switching and panning inside the prefetched buffer rerank locally with no request. Leaving the buffer preserves current pins, waits for the 250 ms camera-idle debounce, cancels stale work, fetches one bounded expanded viewport, and swaps only after success. More exposes Categories and People on Featured, Friends, and You; Status is available on Friends and You. Every section has All, and People lists followed accounts. Selecting a person from Featured or You automatically switches to Friends while preserving all More selections and keeping the panel open. Clearing People leaves Friends selected. Tapping a source directly dismisses More and resets its selections. Specific values OR within a section; source and non-All sections AND together, and zero-result combinations stay empty. |
| Search corpus, geography, ranking, and camera contract | Locked for REC-352 on 2026-09-01; typeahead preview clarified by REC-402 on 2026-09-02; Discover fallback revised by REC-424 on 2026-09-03 | Map search always includes every saved memory the viewer is authorized to see, independent of the current viewport and source/presentation caps; active More refinements remain intentional filters. Provider rows are eligible only when the provider can prove every selected refinement: Category must match the normalized provider category, while People or non-All Status excludes provider-only rows. Generic category provider search is regional around the map center captured when the request begins, not the viewer's GPS or only the visible rectangle: start at the larger of the viewport radius or 2 km, expand through at most four bounded passes up to 100 km, deduplicate, and stop when saved plus eligible provider results fill four visible rows. Named-place ranking compares query fit across corpora: an exact outside place may outrank a weak saved match, while trust wins an equal-relevance tie. While the user types, typeahead is suggestion-only: it does not select a place, show a place preview or active search pin, or move the camera. A preview appears only after an explicit suggestion tap or Return submission. Submitting a category search fits the first four combined results and the original submitted center without zooming in past the submitted viewport; changing More reruns against that original center. A specific named place may recover an exact lexical result beyond the regional cap, with proximity breaking equal-source ties, and submitting or explicitly tapping one place centers that place. Discover/Feed search combines authorized trusted saves, wider eligible rec.me saves, and Apple Maps fallback results, then deduplicates physical places and applies the same relevance-first, trust-on-ties rule. Outside results must be actual MapKit points of interest; a Category match requires provider evidence rather than a client-applied fallback category. Outside results are labeled, distinguish proved name/category evidence from unverified rec.me-only facets, and can enter the normal save flow, but they are excluded from owner, relationship, or explicit visit-status queries that MapKit cannot truthfully satisfy. |
| No manual lists | Locked | Lists were explicitly removed from product direction. |
| Trusted people, not stranger content | Locked; revised for REC-253 | Named social proof, notes, tags, answers, photos, and save identities come only from the viewer or people visible through the existing trust/privacy graph. Featured may use anonymous aggregate place-level evidence from non-private community Everyone check-ins, but never exposes the stranger or their save content. |
| Cross-category places | Locked | Not restaurant-only; coffee, hikes, bars, parks, restaurants, etc. |
| No live location | Locked | Current location is for nearby place resolution, not broadcasting. |
| No gamified check-ins | Locked | Avoid mayorships, streaks, leaderboards, and public check-in framing. |
| Four bottom tabs | Locked | Map, Add, Discover, Profile. |
| Settings from Profile gear | Locked | Do not add Settings as a fifth tab. |
| Profile scroll header | Locked for REC-482 | Use the approved inline option for owner/member profiles: no initial header blur; reveal a light native blur from the screen top as the name reaches the toolbar, aligning the original-size name beside the 86pt photo. Keep navigation pinned and preserve its actions. On upward scrolling to the bio boundary, restore the original identity and remove the blur. Retain the original reading layout at accessibility text sizes. |
| Profile merges self memory and social profile | Locked | Owner and other-user profile states share the same conceptual surface. |
| Follow graph, not friend requests | Locked | One-way follows; mutual follows are friends. |
| Public/private copy | Locked | UI says Everyone/Friends/Self; data stores `followers`/`mutuals`/`self`. |
| Dropped-pin custom names | Locked for REC-295 | A dropped-pin rename is a label on one user's save, not a mutation of the shared canonical place. The owner sees their label throughout their map and save flow. Another user may see it only as part of that owner's memory when the existing visibility and block rules authorize the memory; it never renames another person's save or the canonical coordinate place. |
| Private place taxonomy and stable saved defaults | Locked for REC-362 | Category, subcategory, and food-type edits belong only to the person who selected them and never appear in another person's view of that save. People without a prior relationship to the place receive the latest provider taxonomy until at least 10 distinct people explicitly select a value for that dimension; at that point the plurality becomes the anonymous global default, with provider-first then lexical tie-breaking. A person's first active Wanna, Check-in, or list add freezes the then-current effective default for that person, so later provider or consensus changes affect only people without an existing relationship. |
| Block behavior | Locked | Hard block; remove follow edges and hide profiles/content both ways. |
| People finding | Locked for REC-224 | Username search remains available. Native Contacts is now a contextual invite path from Check-in Friends, Discover People, and list collaborators; the app reads phone-bearing contacts only after an explicit primer and never uploads the address book. |
| Contact invite relationship | Locked for REC-224 | Sending a contact invite opens a pre-addressed native Messages composer with the public TestFlight link and sender profile. It does not auto-follow either account. A generic TestFlight install cannot be attributed to the sender, so joined notifications and deferred check-in/list acceptance require a future attributed invite backend; until then the recipient may follow the sender and the sender can follow back from the resulting profile notification. |
| Discover network-building null state | Locked for REC-90 first slice | Places keeps its tabs and shows **Find people to follow** only after Activity loads successfully with zero rendered followed-user rows. That action switches to People, whose no-search state leads with a horizontal real-profile recommendation shelf and inline Follow actions. |
| Discover recommendation privacy | Locked for REC-90 first slice | Active public profiles are recommendation-eligible by default. Private Profile, deleted, blocked, current-user, and already-followed accounts are excluded server-side; Private Profile is also enforced by member search, follower/following graph RPCs, and direct follow. Recommendations use profile/follow data only, never place rows. |
| Discover People section naming | Locked for REC-90 populated state | **People worth following** contains eligible accounts not yet followed. **People** contains the viewer's existing follows; the prior **Following** heading is retired. |
| Hosted Discover alpha fixtures | Approved exception for REC-90 | Six fictional public profiles with four existing-place reviews each may live in the linked alpha project. They are managed by an exact-id, idempotent operational script, create no fake follow edges, and must not become a general migration or implicit environment seed. |
| Discover plain-language search mode | Locked for REC-150 | Tapping the place-search field enters a temporary top-pinned search mode with an explicit Back control. Clear returns to the rich example-query state without exiting; Back cancels active work and restores the prior Discover state. Typing is local and the LLM runs only on keyboard Search or example selection. |
| Discover result truth | Locked for REC-150 | Results show how the query was understood and compact `Matched:` metadata derived from the exact visible owner-place record. `Favorite` means Been plus the queried person's rating of 4.0+ or explicit favorite personal label; Wanna Go and silent broadening are forbidden. The LLM does not generate per-place explanation copy. |
| Following not-yet-on-app users | Deferred | Track later; not in v0.1. |

## Technical Decisions

| Decision | Status | Notes |
|---|---|---|
| Dark-mode rating colors | Locked for REC-499 | Use the approved neon palette for the liquid rating slider in dark appearance: electric blue at 1, orange at 3, and neon red at 5, interpolating across the existing half-point rating scale. Light appearance retains its original palette; rating values and interaction are unchanged. |
| Native iOS | Locked | SwiftUI, iOS 17+, iPhone-first. |
| Import review details and source identity | Locked for REC-409 | Import row details expand inline using the same save-editor components, mode switching, validation, and local persistence as ordinary Wanna and Check-in saves. A source mention may select up to five concrete candidates with one shared save mode. Place imagery comes from the place-photo pipeline; history uses preserved source artwork when available and monochrome source-brand assets shared by the app and Share extension. History labels remain Matching while either the batch or an item is processing. |
| Import attention and progress | Locked for REC-409, revised for REC-540 | The History badge counts each matching import and each import with unresolved returned places once. Opening a report acknowledges its completion notice but keeps its badge until all returned places are saved, already exist, or are explicitly dismissed. Failed scans and empty results count until opened; cancelled imports never count. History shows Partially imported when more than half of known source places matched and returned places remain unresolved, then Done once those returned places are resolved. Source-level retry markers and unmatched hints do not keep an otherwise resolved import open. The review timestamp remains an independent, owner-scoped completion-notice acknowledgement. Matching progress is transient and based on actual source/hint/row completion; unknown totals remain indeterminate until extraction returns. Each import-sheet presentation selects the content-fit detent afresh while retaining manual expansion. |
| XcodeGen | Locked | `project.yml` is source of truth. |
| Instagram Feed direct handoff | Provisional for REC-271 | Ryan explicitly accepted the risk of trying the undocumented `instagram://library?LocalIdentifier=` route first so the rendered ticket can open already selected in Instagram. The app must save the ticket to Photos, keep `.igo` plus `com.instagram.exclusivegram` as the automatic fallback when the deep link cannot open, and retain the system share fallback behind that. Remove or revise this experiment if physical-device testing fails or Instagram/App Review rejects it. |
| Clerk + Supabase | Locked | Clerk for identity/account, Supabase for data/RLS/PostGIS/storage/functions. |
| Apple-first Clerk auth | Locked for REC-259 | The existing auth sheet opens on a rec.me-owned native Sign in with Apple CTA. Clerk remains the identity/session owner and handles Apple sign-in/sign-up transfer. Email, Google, verification, recovery, and any incomplete Apple continuation stay in Clerk's prebuilt `AuthView` behind **Use email or Google**; do not build a second independent account system or duplicate those flows. |
| Clerk user id mapping | Locked, revised for production cutover | Existing rec.me profile IDs remain canonical; do not rewrite the 30 dependent foreign-key relationships when moving Clerk environments. Imported production users carry their development Clerk ID in `external_id` and public metadata `canonical_user_id`. The signed Clerk session claim `canonical_user_id` feeds `app.current_user_id()`, which falls back to `sub` for legacy development tokens and post-cutover new users. A private service-role mapping table resolves sparse delete webhooks and fails closed when no mapping exists. The iOS session uses the same public metadata value for local-cache continuity. |
| SwiftData local-first | Locked | Local cache, guest-local records, sync queue. |
| Offline identity and own-map cache | Locked for REC-196 | After a transient Clerk refresh failure, the last confirmed identity may open only that user’s protected, locally cached own-map slice on the same device. The state is locally identified but not remotely validated: Supabase tokens, maintenance, push work, and deep links remain blocked until Clerk validates again. Confirmed sign-out, account deletion, or account switch clears the session-scoped cache. Social-map rows are not persisted by this contract; save retry and follow intent remain in REC-197 and REC-198. |
| MapKit-only v0.1 | Locked | Keep provider-extensible place IDs. |
| First-visit park selection | Locked for REC-236; revised 2026-08-16 | The automated saving demo uses an already-authorized device location only to derive a normalized ZIP, then asks MapKit for `popular parks` within a strict 10-mile radius and preserves the provider's result order as the available popularity proxy. If that query has no eligible result, it tries an ordinary `park` search before using Hotchkiss Park. ZIP 90403/90405, denied/unavailable location, lookup failure, or no eligible result uses Hotchkiss Park. Do not select or rank this Apple-map demo with Google Places ratings: Google-derived place content cannot safely drive a non-Google map under the current provider terms. The walkthrough never prompts for location and never sends coordinates to rec.me. |
| Place default photo priority | Locked for REC-82, revised 2026-07-12 | The full place-profile header and collapsed place card use one priority: a Google Places photo when the provider can make a trustworthy place match; otherwise the earliest uploaded visit photo the viewer can see. A newly captured local photo renders immediately for its owner. Shared user photos stay in the private `visit-photos` bucket and are read through authenticated storage plus visit/user-place RLS, so a follower can inherit a dropped pin's first photo without making the object public. |
| Google Places photo enrichment | Locked for REC-82, revised for REC-340 on 2026-08-25 | Maps/search stay MapKit-first; Ryan explicitly approved representative Google Places photos on the existing MapKit surfaces on 2026-07-13. Photos load on demand through the authenticated Supabase `place-photo` Edge Function. After paid Google Cloud billing and a $50 monthly budget alert were activated, Ryan explicitly removed the former 900/month global and 120/day per-user application caps; Google Cloud billing reports and advisory budget alerts now monitor spend without an automatic app-side cutoff. A cache miss downloads the selected image into the private, service-role-only `google-place-photo-cache` bucket and records a SHA-256 lookup key plus attribution metadata; later users receive a 24-hour signed Supabase URL instead of repeating Google Search and Photo calls. At Ryan's direction, cached photo bytes and metadata have no automatic expiration and remain until deliberately removed or replaced, with the associated Google Places caching-policy risk explicitly accepted; Google photo resource names and provider URLs are not persisted. The Google key and Storage service credential stay server-side. Coordinate/dropped pins never call Google. REC-340 keeps Google photos as the preferred shared-preview source but removes the visible on-image Google Maps/Google badges, logos, strips, and provider-only gallery attribution card across Featured/For You, Activity, Place Profile, collapsed place previews, Lists, and import review. Ryan explicitly accepts the resulting attribution/provider-policy risk. Author/source metadata remains stored for operational traceability. Yelp is not the fallback because its free tier is evaluation-only and commercial access is paid. When Google has no safe match, is unavailable, or its media fails to load, use the RLS-backed first visible visit-photo fallback above. |
| Supabase RLS authoritative | Locked | Client policy is for UI behavior only. |
| Taxonomy projection boundary | Locked for REC-362 | Canonical provider taxonomy stays on `places`; anonymous 10-selector plurality values are cached separately per dimension. Private first-relation snapshots live in a server-managed, RLS-enabled table with no direct client grants. Social, Featured, feed, profile, list, and search RPCs strip another owner's category overrides and `restaurant_cuisine`, then attach only the authenticated viewer's effective taxonomy through an internal projection envelope. |
| Repository/protocol boundaries | Locked | Views should not call Clerk/Supabase directly. |
| Typed feature-flag platform | Locked for REC-355 | Every Boolean or integer feature flag is registered once in `FeatureFlagKey`, is fetchable remotely, and appears automatically in Profile → Settings → Feature flags. Account-scoped device overrides win over remote account/global values, are snapshotted at process launch, and therefore apply or reset only after fully quitting and reopening the app. Debug and Simulator builds honor explicit Off values; one-off UserDefaults flags, build-mode force-enables, and remote-only flag rows are prohibited. `debug_settings` remains visible but read-only because its remote entitlement gates the tester panel itself. |
| Profile avatar identity contract | Locked | Any new UI surface that shows a profile photo must be wired from a stable user/profile id through the store's freshest profile/avatar state. Do not copy ad hoc avatar strings from lower-fidelity place, list, search, or graph payloads without preserving richer cached profile metadata. |
| Shared Visits ownership and privacy | Locked for REC-88 | A Shared Visit invite is available only between mutual, non-blocked, non-private profiles and only from a non-stealth persisted Been visit. The sender sees pending invitees in visit attribution immediately and can reconcile the exact friend set from Edit This Visit. Removing a friend clears pending or accepted attribution, snapshots, and unsent delivery, but never deletes that person's independently owned visit; re-adding them creates a new invitation generation. Each pending invitation generation holds an immutable private snapshot. Acceptance atomically creates or updates the recipient's independently owned save and creates one recipient visit with deterministic retry identities; recipient edits never mutate the sender's visit. Selected photos are copied into recipient-owned storage paths. Stealth, source deletion/status changes, blocks, and account privacy cancel affected sharing/attribution and erase pending snapshots while preserving already-created independent visit records. Client access is RPC-only and every acceptance is protected by a server operation ledger. |
| Notification enrollment and account isolation | Locked for REC-88; presentation revised for REC-425 | New backend preference rows default every category off. One centrally configured notification campaign is reused once per trigger in onboarding and after new saves/follows while notifications are off, with a maximum of three lifetime impressions per account across those triggers. It queues behind active product presentations instead of stacking. Before a native permission alert it uses one neutral Continue action and cannot be dismissed; after denial it offers Settings plus dismissal. Successful enrollment explicitly enables all categories and registers the current device; Disable Notifications turns all categories off and deactivates the token. APNs tokens are exclusive to the current account, and asynchronous inbox, outbox, deep-link, and photo work must discard completions after an account switch. |
| Private save-streak reminders | Locked for REC-195; delivery revised for REC-200 | An opted-in account gets one 8 PM reminder only when its active private save streak is uncovered that day. The device computes the account-scoped schedule, then reconciles it into the central remote notification governor; saving a Check-in or Wanna cancels that day's intent. The preference defaults on only after the global notification program is enabled, never crosses accounts, and tapping the reminder opens I'm Here Now. No public rank or social pressure is introduced. |
| Save-streak reminder copy and measurement | Locked for REC-195 | Copy rotates deterministically by the device calendar weekday: Monday/Thursday use the original count-aware title and body; Tuesday/Sunday use `Anything worth remembering today?`; Wednesday/Saturday use `One place keeps the streak alive`; Friday uses `Your map has room for today`. Reconciliation preserves an already-matching same-day request. Analytics records non-PII `scheduled`, `cancelled_by_save`, `opened`, and first `completed_save_after_open` events with copy variant, weekday, streak count, and save status where relevant. Post-open completion uses an account-scoped four-hour attribution window and is consumed once; events never include account ids, place data, notes, coordinates, or notification event ids. |
| Apple Calendar reservation prompts | Locked for REC-200; settings placement revised 2026-08-31; frequency hardened for REC-403 | Apple Calendar access and manual sync live in Profile → Settings → Privacy and trust under Permissions; the reservation-reminder delivery preference remains in Notifications. Connecting Calendar does not silently enable that notification preference. NUX integration is deferred until onboarding reaches the social experience where the value can be explained in context. EventKit detection happens locally and MapKit resolves the restaurant; rec.me services receive only a hashed occurrence key, derived place identity, service times, and time zone—never raw calendar identifiers, titles, notes, attendees, URLs, or addresses. Reservations for the same account, provider place, and reservation-local calendar date share one two-stage waterfall: one prompt is eligible one hour after the earliest reservation and a second at 8 AM the next morning. Each stage is lifetime-idempotent after it first enters the queue, so foreground and calendar-change syncs cannot recreate a terminal event. A completed matching check-in suppresses all remaining prompts. Tapping either prompt opens the normal Add editor with Check-in, place, and visit time prefilled. |
| Notification intent governance | Locked for REC-200 | Calendar, Wanna, save-streak, import-complete, and server-generated notifications share one Supabase queue and claim-time governor. Every intent carries a producer source, priority, optional conflict group, earliest delivery time, and deadline. Current consent, mute state, expiry, and reservation completion are rechecked when the worker claims work. Future cross-source spacing and quiet-hour rules belong at that single claim boundary, not in individual producers. |
| Backend extraction jobs | Locked | Link/photo extraction should run on backend, not fake client-only extraction. |
| Social import understanding | Trial behind `social_import_apify_gemini_v1` for REC-120; acquisition revised for REC-411 on 2026-09-04 | Signed-in Instagram and TikTok imports may use a bounded Supabase Edge Function for acquisition plus Gemini multimodal place-hint extraction. Instagram reels use Bright Data first and fall back to Apify. Instagram `/p/` posts acquire both in parallel, merge Bright caption, slide-scoped tag, and accessibility metadata with Apify's higher-resolution image media, and continue with either provider when the other fails. TikTok remains Apify-only. Grounded hints are enriched server-side with bounded Google Places Text Search candidates containing a stable provider id, structured address, and required coordinates; the app deterministically ranks those candidates, retains alternatives, and uses MapKit only when Google returns no usable candidate. Provider credentials and raw provider payloads stay server-side; paid work requires database-backed idempotency and per-account admission. Gemini files are temporary. The trial remains account-gated while Google Places attribution, non-Google-map display, and coordinate-retention requirements receive an explicit production-policy decision; do not infer production rollout approval from the technical canary. Unsupported, disabled, incomplete, rejected, quota-limited, or failed extraction remains honest rather than inventing a canonical place. |
| Social import identity evidence | Trial for REC-411 | Preserve bounded provider-attested neighborhood and full administrative names through the server response, iOS candidate, and matcher instead of dropping geographic qualifiers. The optional field remains compatible with previously persisted candidates. Server filtering must retain full-name spacing variants accepted by the app. Social-only name descriptor equivalence and normalized area agreement must be used consistently for ranking and selection; distinct businesses, branches, and conflicting geography remain reviewable. Evaluate the actual Swift matcher separately from extraction recall and provider candidate presence. A model-generated confidence or suggested provider choice is not independently verified POI accuracy and does not by itself authorize automatic selection. |
| M2 extraction shells | Locked | Link/photo create unresolved drafts until backend jobs exist. |
| Discover parser interface | Locked, revised for REC-150 | Reuse the existing authenticated `parse-discover-query` Edge Function and swappable structured-JSON provider. One submitted cache miss produces at most one model parse; deterministic fallback uses the same typed query plan and semantic invariants. |
| Discover Search retrieval platform | Trial behind `semantic_place_search_v1` for REC-280; revised for REC-355 and REC-424 | Discover Search keeps the existing local and Postgres lexical providers, may add one Search-only semantic rec.me provider, and independently queries Apple Maps for eligible outside-place fallback. Lexical and semantic rec.me retrieval share the same server-side privacy, block, source, scope, category, area, and favorite eligibility contract; the client deduplicates canonical/physical place ids before cross-corpus ranking. Apple Maps rows carry no contributor content, are visibly sourced, and are omitted when a query requires an owner, relationship, or explicit visit status. Either remote corpus may fail without taking down the others. OpenAI receives only the submitted search phrase and minimized canonical place documents containing name, category, subcategory, coarse locality, and region. User/profile identity, notes, labels, answers, ratings, photos, coordinates, memories, and people embeddings are prohibited. Debug, Simulator, and Release builds all honor the typed registry's resolved value so an explicit device Off works everywhere; the remote global remains off until backfill and aggregate latency/result/failure checks pass. This trial does not change Map Featured: Featured continues to use its explicit network/taste/community ranker and does not invoke embeddings while the map moves. |
| LLM data minimization | Locked, revised for REC-150 | Send raw query phrase + allowed schema only, not graph/place/contact/user data. The model may normalize query intent but cannot receive result records or generate per-place match explanations; deterministic code proves and formats result evidence. |
| Home screen widgets | Locked for REC-142, revised 2026-07-25 | One WidgetKit extension hosts Quick Capture, Search, and Activity Calendar widgets. Quick Capture deep-links to the in-app I'm Here Now flow. WidgetKit does not provide an inline keyboard, so Search deep-links to Map with its in-app search focused instead of accepting text on the Home Screen. The Activity Calendar and the in-app Profile calendar are Been-only; Wanna remains elsewhere in the product but does not contribute calendar markers, counts, legends, day details, or widget data. Tapping the calendar widget persistently targets the Profile calendar's top anchor so the whole section snaps into view even during a cold TabView launch. The calendar reads a redacted, aggregate-only JSON snapshot from App Group `group.com.grayline.wander.shared`; its backward-compatible schema still carries zero-valued Wanna fields, but the publisher emits only daily Been counts and the widget ignores any historical cached Wanna state. The snapshot never contains place names, notes, precise locations, or user identities. It is an identity-scoped cache in practice: clear it on sign-out/account change, keep it out of backups, and treat it as unusable when the current time zone or first-weekday setting differs from the stored calendar context. |
| Nearby Rich Visit widget | Locked for REC-154 | A separate location-enabled WidgetKit extension hosts one system-large widget with up to five nearby MapKit points of interest. Separate packaging keeps `NSWidgetWantsLocation` off the three widgets that do not need it. The app requests only When In Use location; adding the widget may trigger WidgetKit's own location-authorization prompt. Each place opens the existing manual Rich Visit form with the selected candidate prefilled, while `See all` and the widget background enter the existing I'm Here Now nearby list. The widget asks for a 15-minute timeline, retries transient failures after five minutes, receives WidgetKit's significant-location-change reloads, and reloads from an app-active refresh, but never claims guaranteed live cadence. A bottom-left App Intent refresh requests a new widget-authorized location and MapKit search in place, briefly shows `Refreshing…`, and advances the minute timestamp even when the place set is unchanged. Exact distance becomes generic `near you` after 30 minutes and the entire result set becomes unusable after 24 hours. Nearby place metadata, coordinates, and short-lived refresh state are bounded App Group caches, excluded from backup, marked privacy-sensitive in the widget UI, and never uploaded or treated as live location sharing. |
| Share extension | Trial for REC-227; composer revised for REC-409 on 2026-09-03 | The URL/text/file Share Extension writes bounded idempotent envelopes to the App Group. The composer now prefills the link and asks only for Start import; it no longer chooses a save mode, rating, or countdown. New envelopes omit automatic-save intent and enter the same review flow as in-app captures. It dismisses only after durable capture. Matching still begins when the host app receives runtime; true closed-app processing needs the server-job/privacy decision in open questions. |
| Multi-source place imports | Trial for REC-227; review revised for REC-409 on 2026-09-03 | Google Maps, Instagram, TikTok, Snapchat, and Text/Notes feed one owner-private durable Import Inbox. New captures are reviewed before saving, with up to five selectable matches per source mention and inline shared Wanna/Check-in details. Legacy envelopes with explicit save intent retain their compatibility path: Wanna may auto-save confident matches; multi-place Check In requires verification. Existing saves/visits remain idempotent, and reports edit the particular saved record. The current device-side processing boundary remains until a server extraction job is approved and implemented. |
| Native Contacts | Locked for REC-224, superseding REC-132 Phase A | Contacts permission is requested only after an explicit contextual primer from an invite entry point. The provider reads name and phone fields only, filters out contacts without phone numbers, and does not upload or analytics-log address-book data. Denied access remains recoverable through Settings. |
| Product analytics dashboard | Locked for REC-170 | The acquisition-to-referral dashboard lives in PostHog and is provisioned from `scripts/posthog-product-dashboard.mjs`. Explicit, privacy-safe events are the source of truth; PostHog autocapture remains disabled. Engagement is normalized to Connect, Expression, and Status. Referral measurement stops at invite handoff until attributed links exist, and Monetization remains visibly blank until a product decision defines it. |
| Analytics provider | Locked for alpha | Use PostHog through the vendor-neutral analytics interface. Keep sync/auth diagnostics non-PII: counts, enum metadata, and internal auth user id only; no place names, notes, coordinates, emails, or handles. |
| Sync conflict behavior | Locked v0.1 | Simple `updated_at`/server-wins plus local retry queue. |
| Full onboarding | Locked for REC-132 Phase A; permissions revised for REC-396 and REC-425; opening revised for REC-529 on 2026-09-18 | Logged-out users see the Signal word sequence, then native Places and People previews. Next and Log in remain available throughout; the final scene advances into native Clerk-backed account entry with a horizontal slide, and sign-up has no close button. Closing Log in restarts the welcome flow. Required display name/username and a saved profile photo (including an existing provider avatar), followed by location, Contacts, trusted-friend, and notification steps, complete account setup. A permission primer that immediately precedes a system alert has one neutral Continue action and no skip path; denied state recovery may open Settings or continue without the optional capability. Apple Calendar setup stays in Profile → Settings → Privacy and trust until the NUX reaches the relevant social experience. Existing users remain complete. Contextual notification enrollment reuses the central campaign after new saves/follows. |
| M3 backend schema/RLS/profile foundation | Project created, migrations applied, webhook verified | New Supabase project `rugmtlgufrhlxwfkumhw` and new Clerk app `app_3Eb3JbpbMDjOA2qKUCqfsZwfct9` are created. Migrations `20260602131500`, `20260602140304`, `20260602143000`, `20260602210000`, and `20260604185000` are applied remotely. Hosted pgTAP tests passed with 29 assertions. Clerk profile mirroring is deployed through Svix -> Supabase Edge Function -> PostgREST RPC, and real create/delete webhook flow was verified. Schema includes custom `question_definitions` plus JSON-backed `place_attributes` so future user-created questions/inputs can be added without answer-column churn. |

## Check-in details (REC-485, revised 2026-09-17)

- Each selectable place subcategory has three deliberately curated, optional default questions. Cuisine alone does not change dining logistics: ordinary restaurants share parking, outdoor seating and dietary options; vegan/vegetarian, gluten-free, tabletop cooking, takeaway and fine dining get practical exceptions. Coffee, tea and sweets always include dogs. Synonymous gym, cafe, lodging and station types can share defaults, while genuine differences such as Pilates, CrossFit, beach courts and hostels remain distinct. Shared questions are reused when the practical need is the same; functional subtypes receive their own selection. The complete inventory is in [the question catalog](product/check-in-question-catalog.md).
- A fresh Check-in starts with no answers. Explicit negative and qualified answers are retained as observations; unanswered means unknown. Later unanswered visits do not erase earlier explicit observations. Editing or deleting an observation updates the owner's latest available details.
- Wanna leads with one introduction/context note, with its optional date above categories. Check-in orders rating, note, date, categories, Useful details, then friends/photos. Optional tags stay at the bottom. Adding a visit retains the original Wanna note.
- Customize belongs beside Useful details and in Settings → Check-in questions. A person can search subtypes, reorder, remove, restore, add catalog questions, or create recurring yes/no questions. Configuration is account-scoped on the current device. Removing a question retains its previous answers. Not useful persists a hidden ID for that account and subtype, including when editing an older save; the current row grays out with Undo. Explicit re-add or confirmed Restore brings a prompt back. Restoring suggestions requires a native confirmation; existing customizations do not silently adopt changed defaults.
- Each recurring question has an inline eye button (signal open eye for shared, gray slashed eye for private), with no separate Stealth page. Each question has a Stealth setting: on keeps its answer owner-private on this device; off shares it only with that Check-in's audience. New custom questions default to Stealth on; catalog questions default off. Add/create screens omit privacy controls; the recurring-list eye is the single place to change them. The Check-in shows its gray Stealth badge beside the question. Changing a default in Settings never republishes historical answers. Only an explicit audience change in the visit editor moves its draft answer between channels.
- Most built-in observations use Yes/No with the existing `single_choice` type. Older qualified values remain readable and selectable when already answered. Dietary options use the existing `multi_tag` array contract (Vegan, Vegetarian, Gluten free), preserving every selection across shared/private transitions. Explicitly shared custom answers use a versioned prompt/yes-no JSON envelope with the existing `text` value type and a distinct `place_detail_custom_` key. Legacy private custom keys never imply publication consent. Search uses explicit answer semantics: a negative answer does not become a positive amenity match. Existing labels and unknown attributes remain intact when edited.
- Shared Visit invitations preserve their established note, rating, tags, and photos, but omit the source owner's question answers. Recipients answer firsthand details themselves. New snapshot construction and reads of older pending snapshots use the same filter; stored history is not rewritten.
- Tag suggestions describe uses and occasions rather than repeating question facts. Each category offers a small curated set; exact duplicates and an explicit list of near-synonyms render as one chip. Existing personal labels remain stored unchanged unless the person explicitly removes their chip.
- Synced owner visits hydrate complete answer JSON through `own_place_visit_details`, an authenticated owner-only read. Raw table-column grants remain restricted. Unknown remote answers cannot be edited or synchronized as an empty answer set. This endpoint exposes no other person's answer history.
- Voice capture and semantic personal recall remain separate follow-up work (REC-490, REC-491, REC-492). This change preserves useful narrative context without introducing those features.

## Release Decisions

| Decision | Status | Notes |
|---|---|---|
| Manual batched TestFlight releases | Locked | TestFlight remains frequent and manual, with no weekly or automatic cadence. Joe or Ryan explicitly triggers a release when enough finished features are grouped. The release packages an exact releasable `main` candidate and increments the build number once; merging alone never archives, uploads, attaches, or announces a build. |
| Rolling `Next TestFlight` manifest | Locked | One open GitHub issue titled `[machine] Next TestFlight manifest` is the machine release queue. Every PR declares `ship`, `exclude`, or `release-operation` in a validated hidden JSON payload; every push to `main` sweeps the complete pending Git range and records the exact commit, while a direct push or invalid payload becomes an `unclassified` blocker. The rolling Linear issue is a human status/relation mirror, not the uploader's data source. |
| Releasable `main` and exact release candidates | Locked | Work merged to `main` is eligible for the next build unless disabled behind a feature flag. At an explicit release, `scripts/testflight-manifest.mjs snapshot` refreshes the same machine issue and proves that every first-parent commit since the prior immutable tag is classified exactly once. It runs before the build-number bump and again against the exact candidate, generating TestFlight, Slack, and Linear copy from the same snapshot. The uploader requires version-2 evidence and rechecks the live issue hash; successful release finalization advances its immutable tag baseline while preserving later merges. |
| Linear completion after merge | Locked | Product issues move to `Done` once their implementation is merged to `main` and required validation passes. Waiting for a manual TestFlight batch does not keep them in `In Review`; TestFlight-specific integration QA lives on the release issue, and any discovered regression reopens or creates a focused bug. |
| Dedicated Slack release channel | Locked | Post one top-level announcement for each TestFlight build in `#release-notes` (`C0BM5CY0GQY`). Keep `#testflight-feedback` (`C0BAA7DG2AC`) for bug reports, screenshots, repro steps, and discussion. Do not duplicate routine release notes there or in `#all-recme` unless Joe explicitly asks. |
| Agent work log retirement | Locked | `docs/agent-log.md` is frozen historical context. Linear and PRs own current coordination and handoff; git and immutable TestFlight tags identify shipped code; App Store Connect and Slack own release/tester state. Do not create docs-only PRs that merely restate a merge or release already represented in those systems. |

## Design Decisions

| Decision | Status | Notes |
|---|---|---|
| In Common naming | Accepted for REC-486, 2026-09-16 | **In Common** is the user-facing name for the member-profile feature and its curated place page, replacing Common Ground and In good company. Keep internal type, file, and accessibility identifiers unchanged. |
| In Common Wanna evidence | Accepted for REC-486, 2026-09-16 | Match Wannas and check-ins independently for each person and canonical place. Inspect every visible Wanna event, including repeat events attached to a Been summary; deduplicate event IDs. A previous check-in remains compatible with a Wanna recommendation. Copy must allow returning to a place. The live adapter groups all authorized rows and consumes REC-497 repeat-Wanna events from every matching user-place record without changing the checked-in summary. |
| In Common invitation inbox | Accepted for REC-486, 2026-09-18 | Creating a shared plan adds it to the recipient's Profile → Notifications → Plans. The authenticated recipient can reopen the same read-only invitation without its external link. Opening marks it read without removing it; expired invitations, deleted accounts, and blocks make it unavailable. External sharing remains optional after creation. The inbox returns up to 100 newest active plans and never returns bearer tokens. Read state persists on the server; the client cache is account-scoped and does not persist invitation contents on disk. |
| Notifications bell badge | Accepted for REC-486, 2026-09-18 | The numeric bell badge counts unseen received plans and pending check-in invitation deliveries. Entering Notifications clears the badge without opening plans or accepting/declining check-ins, including items that finish loading while the inbox is visible. Seen opaque IDs persist per account on the device; new plan IDs and new check-in invitation generations count again. Individual plan read state remains server-owned and separate from this local badge acknowledgment. |
| Handoff package is source of truth | Revised provisionally for REC-383 / REC-397 | Keep `preview/follow-profile-settings-mocks/` as the interaction, layout, and functionality reference. Joe's explicit Astir exploration direction supersedes its visual palette and typography across production surfaces. The Astir public name is now approved in REC-475. |
| `tokens.css` is canonical | Revised provisionally for REC-397 | Its spacing, radius, and functional component guidance remain useful. Production color and type now resolve through the adaptive Astir semantic tokens while this exploration is evaluated in-app. |
| Adaptive Astir editorial style | Provisional for REC-383 / REC-397 | Light Mode is warm paper with ink; Dark Mode is ink-black with paper. Astir signal coral `#F05A3C` is the brand-action/selection accent. Semantic status colors remain distinct. These adaptive editorial variants are the only live Astir modes; launch arguments do not select a separate palette. |
| Floating Astir header grammar | Provisional for REC-383 / REC-397 | Logo, search, tabs, and actions float as independent Liquid Glass components over a slight frameless blur. Feed hides the header on sustained downward scrolling and restores it on upward scrolling, respecting Reduce Motion. Do not wrap the whole component group in one glass block. |
| No competing visual direction | Superseded by explicit Joe request | The Astir light/dark exploration is intentionally implemented in the real app so the brand could be judged in context; the Astir public name is now approved in REC-475. Do not introduce additional directions without another explicit request. |
| Native font stack | Revised provisionally for REC-397 | Use Dynamic-Type-aware native editorial serif for screen/place/list/major section titles, Avenir Next for body and controls, and Avenir Next Condensed only for short metadata. Avoid black-weight utility text and fixed point sizes in production surfaces. |
| Public app name | Locked for REC-475 | Astir replaces rec.me in the installed display name and public app copy. Internal Wander targets, modules, bundle identifiers, domains, service identities, and build numbers remain unchanged. |
| Production app icon | Locked for REC-475 | Joe selected direction 55 with the Signal base: a warm family statue on matte ink-black over a full-width detached coral foundation with ONENESS at the right. Preserve the approved full-frame pixels through the canonical Icon Composer source and asset-catalog master. This supersedes REC-343; the separately approved splash screen is handled in its own change. |
| Editorial typography phase two | Locked for REC-165 direction C | Use Apple's Dynamic-Type-aware system serif for named content, major content-section headings, and eligible custom content-screen mastheads. Keep navigation and header controls, persistent search, tabs, filters, buttons, body copy, metadata, counts, and timestamps in native system sans. This typography pass must not alter check-in ticket geometry/colors/media, the streak screen, check-in rating typography, or the approved serif treatment for overall place-profile rating values. |
| SF Symbols/native controls | Locked | Use native symbols instead of mock emoji chrome for structural UI. |
| iPhone-first visual QA | Locked | Verify real simulator screenshots before calling UI accepted. |
| Map filter selected state | Locked | Inactive chips keep the bone/sand fill; active chips add a terracotta ring and terracotta icon, with no checkmark. |
| Map More presentation | Locked for REC-249 | More opens as a compact popover anchored to its pill, not a bottom sheet. The pin renderer and pin iconography remain unchanged by this filter release. |
| Map place labels | M2 selected/simple labels | Show place labels on Wander pins in the local prototype, with selected/tapped state made visually explicit. Revisit clutter rules later with real density. |
| Social proof copy | Locked | Place sheets should show who saved a place with avatars/facepile, not "`Name`'s tip" copy. |
| Rich place profile data | Locked v0.1, revised 2026-07-12 | Expanded map place profiles use only data Wander actually has: place name/category/address/locality/coordinates, save status/visibility, notes, flexible answer attributes, social proof, friend saves, share, keyless map directions, MapKit/directly captured website or phone data, and on-demand Google Places representative photos under the REC-82 attribution/no-cache contract. Do not show empty hours/price/cuisine fields. Price can appear only as a user answer attribute. "Order" and "Reserve" are allowed only when backed by a direct provider/place URL; non-authoritative provider searches must be labeled as search/find actions. No other paid place metadata is part of this v0.1 surface. |
| Screen titles | Locked | Main surfaces use plain titles like Discover and Settings; avoid oversized informal slogans as page titles. |
| Discover hierarchy | Locked | People stay near the top under search; Places are the primary Discover content with a segmented `mine` / `friends` / `everyone` scope switch at the top of the Places section. |
| Add question answers | Locked | M2 persists starter contextual answers into flexible `LocalPlaceAttribute` rows using `question_key`, `value_type`, and JSON values. Starter templates are category-aware: coffee = work setup/tags, hike = strenuousness/tags, restaurant = price/occasion/tags, plus a rating/excitement signal. Expanded place sheets read persisted attributes rather than inferred placeholder chips. Future user-created/custom questions should add question-definition metadata, not hardcode new answer columns. |
| Unified save-place tags | Locked for REC-155 implementation | The save flow merges place tags and legacy `My Labels` into one user-facing field named **Tags**. It uses Option D's selected-tag shelf plus one uncategorized, symmetrical suggestion grid inside the existing More Options disclosure. Suggestions are normalized, deduplicated case-insensitively, and recomputed with every optional question when status or taxonomy changes: category + cuisine for Restaurants & Food, or category + subcategory otherwise. Incompatible generated values are removed while custom tags and answers survive; edited legacy labels are folded into the active tag attribute instead of writing a second user-facing field. The rest of the Check-in page remains unchanged. |
| Save More Options controls | Locked for REC-173 | Every option-based contextual question inside Check-in and Wanna More Options uses the Tag Shelf's structured card language instead of free-wrapping chips. Three-value single-choice scales use equal-width icon-over-label tiles; multi-select questions use a two-column add/check grid plus the same full-width dashed custom-entry affordance as Tags. Accessibility Dynamic Type collapses grids to one column. This is a rendering contract only: question templates, taxonomy refresh, single/multi selection semantics, stored values, and content outside More Options remain unchanged. |
| Place attribute value-type contract | Locked | iOS `PlaceAttributeDraft.valueType`, `question_definitions.value_type`, and `place_attributes.value_type` are one cross-layer contract. Semantic `personal_label` and `restaurant_cuisine` types are first-class alongside generic input types. Every new type must update both constraints and pass the authenticated hosted `public.save_own_place` smoke transaction before merge/release. |
| Import report confirmation | Locked for REC-442, revised for REC-540 | Wanna, Check In, lists, and inline details stay staged until Save. Ready to add appears before Saved and disappears when empty. Both sections use the same card layout and controls; saved cards have a visible soft green border, removed while edits are pending. Successful Save persists the choices and closes the import flow. Toggling off a saved selection requires a metadata-loss confirmation and remains staged until Save. Each tile has one Wanna OR Check In plus optional lists. Switching confirms removal of the old action and its metadata, then creates a new action; independent visits remain. Check-in removal targets the captured visit; Wanna removal targets its event or original Wanna; list removal targets the confirmed lists. Explicitly cleared selections remain cleared when reopening. Receipt snapshots retain Wanna, visit, candidate, and list identities and any unfinished confirmed replacement removal; legacy receipts infer the currently displayed selections, and check-in confirmation identifies the visit date. List membership is independent of Wanna or Check In. Source artwork fits the entire image; the post title appears in History, with the author below the report cover. |
| Import completion frequency | Locked for REC-442, 2026-09-07 | Each import completion is surfaced once through a toast or notification, with the consumed state retained across launches. Historical completed imports remain available in History without a fresh alert; dismissal does not clear the unresolved-import badge. Explicit retries reset completion eligibility. A grouped completion opens History so each post retains its own report. |

## Reset Decisions

| Decision | Date | Notes |
|---|---|---|
| Revert low-pass implementation | 2026-06-01 | Joe moved reasoning to very high and requested an audit/reset. |
| Add M1.5 contract lock before M2 | 2026-06-01 | Prevent fixture UI from becoming accidental architecture. |
| Run refreshed design review | 2026-06-01 | Completed clean; score 8/10 to 9/10. |
| M2 local product loop pushed | 2026-06-01 | Commit `962efce`, 18 tests passing, visual QA still pending. |
| Add agent work log protocol | 2026-06-01 | All agents must update `docs/agent-log.md` before, during, and after non-trivial work. |
| Retire agent work log protocol | 2026-07-28 | REC-177 supersedes the active diary requirement. The file is frozen as history; Linear and PRs are the current coordination surface. |

## 2026-09-14 — Repeat Wanna saves preserve check-in state (REC-497)

The place-profile right floating action always starts a fresh Wanna. The left
Check in action keeps its existing behavior and always displays “Check in”,
including after earlier visits. Repeated Wannas are independent history and Feed
events; they do not rewrite the parent save. Each completed form creates a new
record with its own date and details, retained until explicitly deleted. New Wanna
events sort by their own save time in ALL; only the original pre-check-in Wanna
summary is grouped as historical.
Completing a Wanna form flushes the local save before dismissing the editor.
Remote delivery and reminder reconciliation continue afterward; failed delivery
retains the same record identity for retry instead of holding the form open.
Any existing check-in therefore remains authoritative for the map pin, place
state, rating, and unique-place profile counters. Wanna → Check-in → Wanna
stays Been and does not increase the profile Wanna count. Repeat Wanna-only
saves still count as one place. This supersedes REC-357's proposed active-Wanna
after-check-in relationship rule, without adopting its planning/invitation work.

Repeat Wanna creation uses the same save celebration as an initial save. Every
owned activity tile exposes its edit pencil. Wanna edits update only that event's
details and preserve its identity and original activity timestamp, including the
original Wanna archived by a later check-in. Pending revisions remain durable and
are protected from stale reads and acknowledgements; edits never trigger a new
save celebration or change check-in state or unique-place counters. If the last
check-in is deleted, an edited original Wanna is restored with its own content
and visibility; later edits keep that Wanna summary consistent.

## 2026-09-17 — Compact people cards and first Feed load (REC-531)

People worth following occupies the former Featured for you position above
Recent. Its shared cards are 184 points wide and at least 188 points tall at
standard text sizes: a 48-point circular portrait, name, short accurate follow
context, and a full-width 44-point Follow control. Handles and bios stay on the
profile. Cards retain the adaptive Astir palette, Avenir identity text, and
existing horizontal rail margins. Accessibility sizes widen cards to 240 points
and allow content to grow vertically. Following and retry feedback stays inside
the button so standard cards do not jump in height.

Tapping Follow gives one medium-impact haptic and immediately shows Following while
the request syncs in the background. A pending card uses the same appearance as
a confirmed follow, prevents duplicate taps, and keeps its profile accessible.
Failed requests restore the in-button retry action; server completion does not
generate another haptic.

September 17 device feedback increased that single tap to medium impact at full
intensity. Feed postcard photos use the existing background image decoder with
a separate 48 MiB / 24-entry cache. Decode dimensions follow the card's display
size in 64-pixel buckets, capped at 2,048 pixels. Local visit photos retain
priority over authorized remote URLs; missing local files fall back remotely.
A changed source or layout request cannot display an earlier request's image.
Original upload data and full-screen photo behavior are unchanged.

Featured's views, models, and original database projection remain available.
`FeedPresentation.showsFeaturedPlaces` controls both presentation and the remote
request contract; restoring it uses the original RPC. The additive
`followed_feed(input_include_featured, input_before, input_limit)` overload skips
Featured's candidate projection when false, while retaining the same authorized
activity and cursor semantics. Future activity-projection changes must keep both
overloads aligned and pass `supabase/tests/feed_activity_only.sql`.

People and posts load independently. Existing in-memory feed content remains
visible during refresh; authorized text can render before media. No new disk
cache of social content is introduced. Clients fall back to the original RPC
only when the new overload is absent from the API schema, allowing either
deployment order without retrying ordinary network or authorization failures.

## 2026-09-17 — Bundled Events coming-soon motion (REC-528)

The temporary Events preview is the middle of five native tabs: Map, Feed,
Events, Lists, Profile. Add remains a modal action. Events presents the approved
03C VHS composition on a dark background in both appearance modes: COMING /
SOON, a worn vertical bar, and AN / OCEAN PARK / EXPERIMENT on three lines.
The faded signal-orange hue stays fixed; sparse speckles and intermittent
tracking failures replace most continuous sideways jitter. This supersedes the
older static Astir lockup and waitlist exploration.

Ship a small, silent recording and its still in the app bundle. A native video
layer uses the still immediately, reuses the local player between visits, and
pauses off the tab or outside the active scene. Reduce Motion shows the still.
Do not add a live shader, network dependency, playback UI, or per-frame SwiftUI
state to this decorative surface. No event data, waitlist, booking, or RSVP
behavior is implied by the teaser. The source and asset handoff are documented
in `docs/designs/events-coming-soon/README.md`.

## 2026-09-17 — Map opening location precedence (REC-539)

On ordinary app opening, center Map on a fresh authorized device location. While
acquiring it, or when permission is unavailable or acquisition fails, use the
most recently shared location. With no recorded location, center on Ocean Park,
Santa Monica, California. Saved places and Featured results never choose the
launch camera. Explicit place navigation and gestures take precedence over a
late location response.

Retain one timestamped valid location locally on the device, including locations
obtained through Allow Once. Keep it after temporary permission expires or
permission is disabled; only a newer authorized fix replaces it. This is a map
fallback, not a live location indicator or a location history. Do not sync this
record or put coordinates in analytics. Older installations without a recorded fix
cannot reconstruct a past one-time share.

Map location acquisition does not prompt for permission on launch. Approximate
permission is sufficient for centering the map; nearby POI resolution retains
its stricter accuracy requirement. Cancel obsolete launch requests and retry
when the app returns from the background or authorization changes. Preserve the
existing deterministic Los Angeles viewport only for explicit debug fixtures.


## 2026-09-19 — Share cards use topic-specific content (REC-546)

One native SwiftUI renderer powers previews and exported Link, Story and Post
artwork. Profiles use “Discover <first name>’s world” without a footer subtitle.
Named map snapshots use the saved list name. Lists use a place collage for two
or more places, one cover for one place, and an empty state for zero. Missing
photos keep their slots. View remains visible in the link card footer.

Check-ins use their visit date. Wanna cards use the exact event’s planned date
when present, otherwise “On <first name>’s radar”; their action is “Let’s Go”.
List invitations omit a repeated list-name subtitle and use “Join”. Messages and system sharing use one published card link. Instagram and TikTok
photo handoffs copy that link for captions or stickers.

## Linked share-card snapshots — initial rollout (REC-546)

Sharing publishes the approved Link card as a static public image behind an
unguessable preview token on a website-only `/cards/<entity>/<id>` URL.
Messages and the system share sheet send only this URL. The card itself is the website's tappable
preview; no separate caption or PNG is attached. Copy Link and social handoffs
use the same published URL. Merely opening the preview or saving an image to
Photos does not publish it.

Publication is authenticated, target-authorized, and scoped to the creator's
storage folder. Anonymous resolution requires both token and matching route;
it reads only the published title and image path, never underlying saves, notes,
visits, or list contents. The tappable card opens the original query-free app
route, including on older installed clients that reject query parameters. Card wrapper paths deliberately
stay outside AASA associations. Existing app visibility rules remain authoritative.
Snapshots are deliberate shared copies: later edits do not change them, and
public image copies/third-party link caches cannot be recalled. List-invitation
resolution also respects invitation expiry, acceptance, and revocation.


## 2026-09-21 — Username-scoped notification diagnostics (REC-581)

Joe requested a permissions enablement dashboard and lookup by username of daily
notification delivery. Permit the server's separate diagnostic snapshot to export
public usernames and opaque account identity with preference booleans and daily
counts to the existing authenticated Astir PostHog project. Continue excluding
Joe/Ryan and keep notification content, device tokens, event IDs and actor identity
out of this path. This is a specific exception to the former aggregate-only server
analytics rule. Existing aggregate events and client sanitizer rules remain intact.
Label successful sends as APNs acceptance, never confirmed device delivery.

## Your Map includes Check-in and Wanna places (REC-573 / REC-574)

Your Map's preview, total and Places/Cities/Countries breakdowns include both
eligible Check-in and Wanna saves. A canonical place counts once; a place with
both statuses uses the main Map's mixed solid/dashed marker. Status/time filters
must still match a newer Wanna independently of an older check-in. The activity
calendar and check-in totals retain their check-in-only meaning.

Your Map Explore reuses the main Map's native renderer, pin hit testing and
selection policies. Pan and empty-map tap dismiss the compact selection; zoom
retains it. Selection, dismissal and returning from a place profile preserve the
viewport and active lens.

Every matching Check-in/Wanna place remains rendered in Your Map at every zoom
level. There is no pin-count cap or collision-based hiding; dense markers may
overlap at their real coordinates. Active filters and canonical-place
deduplication still apply. The main Map retains its existing collision policy.

At wider zooms, Your Map shows tiny neutral gray dots alongside spatially
scattered category pins. Check-in dots are filled; Wanna-only dots are hollow.
Selecting any dot promotes it to its full category pin without moving the
camera. At neighborhood detail (3 meters per screen point or closer), every
marker becomes a category pin, including coincident places. It returns to
adaptive detail beyond 4 meters per point so small pinch changes do not flicker
between modes. Existing category representatives get modest spacing tolerance
during movement, and detail changes crossfade unless Reduce Motion is enabled.

## 2026-09-21 — Shared cards open the installed app directly (REC-577)

Published `/cards/<entity>/<id>?card=<token>` links should open the exact entity
in a compatible installed Astir app when tapped from Messages. This supersedes
the browser-first routing of REC-546; the published snapshot, one-URL message,
and website fallback remain unchanged.

The native parser accepts only the five published card roots and one valid
preview token, discards the token, and reuses the canonical route through the
existing session and authorization checks. The token grants no native access
and is never an analytics property. The website associates only those five
card paths with the app; it retains its preview and View action for browsers.

Roll out the compatible iOS build before deploying the website association,
then verify a tap from Messages on a device with that build. Older clients
cannot parse card paths and association rules cannot select an app version.
Keep the website PR unmerged until the tester-update gate is satisfied; account
for Apple's association cache when verifying. Coordinate domain changes with
REC-586 without removing existing getrec.me link support.

## 2026-09-22 — Canonical Astir public links (REC-599)

New profile, place, activity, list, invitation, and published-card links use
`https://astirmovement.com` with their existing paths, encoded identifiers, and
preview tokens. The app also accepts `www.astirmovement.com` and previously
shared `getrec.me` links. Associated Domains includes both Astir hosts and the
legacy apex; the internal `recme://` scheme and Clerk identity stay stable.

The website serves card-capable Apple association rules only on the Astir
hosts. Older released apps have no Astir association, so they retain the web
fallback. The legacy host's card association remains gated by REC-577's tester
update requirement. Previously sent messages and published artwork are immutable
copies; they are not rewritten by changing the generator.

Client-generated links require an app update. Apply the notification-link
migration after its rollback-only regression passes; it preserves the existing
activity-id payload used by older notification clients and does not rewrite
queued notifications. Share Kit supplies `https://astirmovement.com/share/tiktok`
as the request redirectURI; its portal has no separate callback-list field
for this product. Verify the Astir URL prefix for the existing sandbox and
production configurations, serve the return path in the association file,
and retain the verified legacy domain for installed clients. Provider
production approval is separate from domain ownership verification.
