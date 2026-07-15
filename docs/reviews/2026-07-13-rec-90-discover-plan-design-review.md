# REC-90 Discover Redesign: Full-State Design Review

Status: IN PROGRESS — mock v1.2 compares Direction A and Direction B; Joe’s direction choice is the blocking gate before engineering review.

Linear: [REC-90](https://linear.app/recme/issue/REC-90/redesign-discover-around-activity-nearby-place-memories-and-people)

Canonical product contract: `docs/specs/2026-07-13-rec-90-discover-redesign-product-spec.md`

Canonical clickable mock: `preview/discover-redesign/index.html`

## Outcome

REC-90 gives Discover one stable structure with two peer modes:

- Places is the default and stays useful before the social graph is dense: search, newest-first Activity, then a conditional place-recovery shelf.
- People is the graph-building loop: search, bounded proactive recommendations, explicit reasons, public profile context, and direct Follow actions.

The design borrows Beli's scannable Places / People pattern without importing its leaderboard language, restaurant-only framing, five-tab navigation, blue brand system, or popularity model.

Initial design completeness was 7/10. Mock v1.2 brings specified visual and state coverage to 9/10 across two directions. The missing point is Joe’s direction choice, taste/approval pass, and any resulting product-contract revision.

## Not in scope

- Implementing SwiftUI, recommendation RPCs, migrations, local evidence storage, analytics, feature flags, or production fixtures.
- Contacts permission or contact matching.
- Device-location ranking for people.
- Popularity ranks, “Top Members,” public leaderboards, or global member browsing.
- Protected pre-follow place names, counts, categories, recency, ratings, or private graph identities.
- Production fictional accounts or fabricated social proof.
- A fifth bottom tab, a Discover-only navigation shell, or an iPad redesign.
- Dark-mode production UI in v0.1.

## What already exists

- `DiscoverScreen` already owns Places / Members mode, independent search strings, newest-first privacy-filtered Activity, member search, profile presentation, and follow/unfollow behavior.
- `DiscoverLatestActivityPresentation` already owns REC-86 timestamp ordering and stable display copy.
- `VisiblePlaceGrouping` already defines duplicate-place grouping precedence used by place results.
- `ProfileShell` already provides the public identity fields needed by search and recommendation cards.
- `WanderTheme`, `DESIGN.md`, and `preview/follow-profile-settings-mocks/tokens.css` already provide the warm canvas, bone surfaces, ink, terracotta, social sky, typography direction, 8pt spacing, radii, and semantic colors.
- The app already has four bottom tabs: Map, Add, Discover, Profile. REC-90 preserves that contract.
- Existing profile detail, follow confirmation, block, auth-gate, and place-save flows remain the downstream destinations.

## Pass 1 — Information Architecture

### Permanent hierarchy

1. Existing four-tab root navigation, with Discover selected.
2. Screen title and current-user profile affordance.
3. Places / People peer tabs with an underline and selected label.
4. One mode-specific search field.
5. Mode content.

Places content order:

1. Activity.
2. Empty/thin Find People intervention when applicable.
3. Strong `Places You May Have Been` shelf, or weak `Pick Up Where You Left Off` shelf, or no shelf.

People content order:

1. Low-network value note explaining what a follow changes.
2. `Suggested for You` graph shelf.
3. `More in {Profile City}` or `More People to Follow` curated shelf.

Search is not a third mode. An active place query replaces the Places home content with place results. An active people query replaces all proactive people shelves with search results. Clearing restores the last settled home state and scroll position for that mode.

### Density and geometry

| Element | Mock contract |
|---|---|
| Screen gutter | 16pt at 320–430pt widths |
| Title | 28pt display, 44pt profile target |
| Mode tab | At least 46pt high, label + icon + 3pt selected underline |
| Search | 48pt minimum height, 12pt radius |
| Section gap | 24–25pt |
| Activity row | Minimum 70pt at standard type; grows with content |
| Activity treatment | Open list with hairline dividers; no enclosing card |
| People shelf | Horizontal, 180pt standard card width, 10pt gap, next-card peek |
| People card | Bone surface, 15–16pt radius, hairline border, no decorative shadow |
| Follow | Full card width, 44pt minimum, terracotta; Following uses label + outline |
| Candidate card | Bone surface, 68pt place thumb, explicit provenance, two 44pt actions |
| Root tab | Existing four-tab bar, at least 50pt per tab target |

### IA judgment

The primary risk was turning Discover into a generic social directory. The bounded shelf architecture avoids that. People are presented as inputs to better place discovery, and every recommendation must explain its relevance.

## Pass 2 — State Coverage

### Places home

| ID | State | Visual contract |
|---|---|---|
| PL-01 | Initial loading | Search and tabs render immediately; bounded Activity skeletons; recovery omitted until classified. |
| PL-02 | Activity empty | Full Discover chrome persists: title, Places / People tabs, search, and four-tab navigation. The body shows one centered explanation and one primary `Find people to follow` action. No fake rows. |
| PL-03 | Activity thin | Render one or two real rows, then compact Find People callout before recovery. |
| PL-04 | Activity populated | Open newest-first row list; author, action, place, area, age; row opens authorized place detail. |
| PL-05 | Cached offline | Quiet offline banner says `Saved earlier`; cached rows remain usable if details exist. |
| PL-06 | Failure without cache | Inline error plus Retry; tabs/search remain available; no graph coaching because state is unknown. |
| PL-07 | No recovery evidence | Recovery section is absent, including its heading. |
| PL-08 | Strong evidence | `Places You May Have Been`, foreground provenance, Been, Wanna Go, open, dismiss. |
| PL-09 | Weak evidence | `Pick Up Where You Left Off`, neutral provenance, Continue save, open, dismiss; no presence claim. |

### People home and search

| ID | State | Visual contract |
|---|---|---|
| PE-01 | Initial loading | Search works; two bounded shelf skeleton regions; no empty flash. |
| PE-02 | Populated | Unique cards, stable order, one reason, two-line bio, Follow/Following, dismiss. |
| PE-03 | No suggestions | `No suggestions yet`; exact name/@handle guidance; search stays available. |
| PE-04 | Partial shelf failure | Successful shelf remains; failed shelf alone receives error + retry. |
| PE-05 | Cached offline | `Saved earlier`; eligible public shells only; Follow disabled with `Connect to follow`. |
| PE-06 | Offline without cache | Search/shelves explain offline and offer Retry; no stale graph reason. |
| PE-07 | Search loading | Progress inside search; prior settled results remain until replacement settles. |
| PE-08 | Search populated | Row results replace proactive shelves; followed results may render Following. |
| PE-09 | Search empty | `No members found`; exact-handle guidance; no shelves mixed underneath. |
| PE-10 | Search error | Preserve query and clear control; retry same normalized query. |
| PE-11 | Signed out | Disabled search-shaped control, direct sign-in CTA, no query or personalized request. |

### Social mutations and navigation

| ID | State | Visual contract |
|---|---|---|
| MU-01 | Follow ready | 44pt terracotta Follow action named for the person. |
| MU-02 | Follow in flight | Optimistic Following + spinner; disabled repeat tap; card does not move. |
| MU-03 | Follow success | Following remains for current appearance; success announcement explains shared-place eligibility. |
| MU-04 | Follow failure | Roll back to Follow in place; inline retry copy; no phantom edge. |
| MU-05 | Profile open/return | Card body opens existing profile; Follow target does not navigate; return restores mode/query/shelf/scroll and reconciles. |
| MU-06 | Suggestion dismiss | Optimistic removal + short Undo; explicit search unaffected. |
| MU-07 | Unfollow | Existing confirmation before mutation; success removes newly unauthorized data after refresh. |
| MU-08 | Unfollow failure | Restore Following; inline feedback; reconcile any open data whose access changed. |
| MU-09 | Hard block | Immediately evict profile, recommendation, search result, Activity, map result, and stale detail. |

### Place recovery mutations

| ID | State | Visual contract |
|---|---|---|
| RC-01 | Duplicate candidate | Merge before rendering; one physical place appears once. |
| RC-02 | Already saved | Omit candidate; normal saved place remains elsewhere. |
| RC-03 | Save in flight | Candidate actions disable while normal save flow owns the mutation. |
| RC-04 | Save failure | Candidate returns; draft data remains; inline retry feedback. |
| RC-05 | Save success | Remove all aliases; short saved confirmation; map/store refresh. |
| RC-06 | Dismiss | Remove optimistically; short Undo; device-local 90-day exclusion. |

## Pass 3 — Emotional Journey

| Moment | Desired feeling | Design mechanism | Failure to avoid |
|---|---|---|---|
| Open Places | “There is useful context here now.” | Search first, real Activity next, no onboarding lecture. | Empty feed that feels broken. |
| See a person | “I understand why this person could be relevant.” | One plain-language reason plus public bio. | Popularity or stranger endorsement. |
| Decide to follow | “I know what changes and what stays private.” | Compact value note and protected profile explanation. | Implying all their places unlock. |
| Follow succeeds | “That did something.” | Stable Following state, status announcement, refreshed Activity. | Card vanishes before acknowledgement. |
| See place recovery | “rec.me remembered something I started.” | Specific foreground provenance and confidence-matched title. | Background-tracking or false-visit feeling. |
| Error/offline | “My context is safe and I can recover.” | Preserve content/query/position; name stale state; local retry. | Blank screens or silent rollback. |

The copy stays direct and non-celebratory. It does not gamify follows, call people “top,” use scarcity, or congratulate the user for routine taps.

## Pass 4 — AI-Slop and Trust Audit

- No gradient hero, decorative blobs, travel photography, generic three-column grid, or dashboard chrome.
- No popularity badges, follower counts, place counts, taste scores, “top member,” or influencer language.
- No nested cards around Activity. Section hierarchy comes from typography, spacing, and dividers.
- No fake private preview. The public profile explains the access contract with a lock, not obscured sample content.
- No permission prompt on Discover open.
- No emoji as structural icons; the artifact uses simple line icons corresponding to SF Symbols in production.
- No generic `Get Started` CTA. Actions name the task: Follow, Find people to follow, Continue save, Been, Wanna Go, Try again.
- The Beli reference influences scan and shelf structure, not visual identity or ranking claims.

## Pass 5 — Design-System Fit

The mock promotes no new global palette. It uses existing values 1:1:

- Canvas `#F3DFCA`, bone `#FFF7EA`, raised `#FFFFFF`, sand `#EFE3D0`.
- Ink `#2C2118`, muted `#7B6555`, faint `#A8957F`.
- Terracotta `#D46F4D` for primary action and selected Discover accent.
- Social sky `#DBEAF1` / `#69B8D7` family for network explanation and avatars.
- Existing success, warning, and error colors with text/icon redundancy.
- Existing Funnel direction for mock hierarchy; production continues the app's current native rounded typography until the approved system-level font decision is implemented.

New feature-level components should reuse existing primitives where possible:

- `DiscoverModeTabs`
- `DiscoverSearchField`
- `DiscoverActivitySection` and existing timestamp presentation
- `DiscoverPeopleShelf`
- `DiscoverRecommendationCard`
- `DiscoverPeopleSearchRow`
- `DiscoverValueNote`
- `DiscoverRecoverySection`
- `DiscoverPlaceCandidateCard`
- existing `EmptyPanel`, status/banner, profile, auth-gate, follow, block, and save-flow patterns

The recommendation card is not a general-purpose profile card. Its reason, dismiss action, and follow-state contract are specific to proactive discovery.

## Pass 6 — Responsive and Accessibility Contract

- Supported design widths: 320–430pt iPhone. At 320pt, outer gutters stay 16pt and the people shelf scrolls horizontally rather than shrinking actions or text below readable sizes.
- Standard people cards remain 180pt; at accessibility type sizes, SwiftUI may switch the shelf presentation to vertically growing recommendation rows if the fixed-width card cannot keep the reason, bio, and 44pt action visible without clipping.
- Dynamic Type rows grow vertically. Names wrap before CTA width is compressed. Bios may cap visually at two lines only at standard categories; accessibility categories receive full text or a row presentation.
- Long names are used whole in reason copy. The client never extracts a presumed first name.
- VoiceOver recommendation order: name + handle, reason, bio, Follow/Following, then separately named Dismiss action. Decorative avatars/icons are hidden where redundant.
- VoiceOver Activity order: person, action, place, area, timestamp, then `button`.
- Loading, Following, offline, stale, success, and error never rely on color alone.
- All production interaction targets are at least 44×44pt. The mock was corrected after automated audit found 32–40pt dismiss/follow targets.
- Focus returns to the logical origin after auth/profile/save sheets. Returning from profile preserves People mode, query, shelves, and scroll before reconciliation.
- Reduce Motion disables shelf travel/reorder animation and shimmer. State changes use opacity/no motion plus accessibility announcements.
- Search results and shelves remain usable with the keyboard visible; scroll content must clear the keyboard and home indicator.
- Cached/offline labels are accessible status text, not decorative metadata.

## Pass 7 — Decisions and Gates

### Founder-requested Direction B exploration

Joe requested a second visual direction after reviewing Direction A. Direction B reframes Discover as a social answer engine whose primary job is: `Find a place that fits this moment, using evidence from people I trust.` It is represented by three additional full-screen journeys and does not replace the approved product contract unless Joe selects it.

Direction B zero-query order:

1. Existing Places / People peer tabs for persistent wayfinding.
2. One universal search for places, people, vibes, and moments.
3. Horizontally scrolling useful prompts.
4. `People Worth Following` using the same approved horizontal recommendation cards, placed before place and activity modules.
5. `Nearby From Your People` with distance and human provenance.
6. `New From Your People`, limited to useful recent evidence rather than a dominant event feed.
7. Confidence-appropriate place recovery when eligible.

Direction B active-answer order:

1. Preserved query with clear control.
2. Editable `Understood as` chips for person, category, intent, and area.
3. A visible source-person anchor and plain-language answer summary.
4. `Show on map` plus meaningful refinements.
5. Results ordered by the requested truth rule, each with a `Why it matched` explanation.

The visual mock makes the proposed truth contract explicit:

- `Joe’s restaurants` may contain Joe’s Been and Wanna Go restaurants only when each status is clearly labeled.
- `Joe’s favorite restaurants` means Been plus Joe’s explicit Favorite label or rating of 4+, sorted by Joe’s rating. Wanna Go is excluded.
- Apostrophe-less `Joes` must resolve against eligible known people rather than silently dropping the owner.
- A zero-favorite result remains zero and offers `Show Joe’s visited restaurants`; the query never broadens silently.

The reported parser/race defects are engineering inputs, not claims that the mock fixes production behavior. If Joe selects Direction B, the office-hours product spec must be revised and `plan-eng-review` must cover cancellation/stale-result protection, semantic-empty filters, owner resolution, substring false matches, real LA filtering, and strict server/client truth enforcement before implementation.

### Resolved in the approved product contract

- Places is the default peer mode; People is not a modal or onboarding-only screen.
- Activity is newest first.
- Strong and weak place evidence get different titles and actions.
- Recommendations use follows-you, one-hop graph, then curated real opted-in profiles; Contacts and device location are out.
- Recommendation reasons never expose graph identities or protected places.
- Follow success stays in place for the current appearance.
- Production fictional people and social proof are forbidden.
- Four bottom tabs remain unchanged.

### Awaiting Joe visual approval

1. Choose Direction A, Direction B, or request a named hybrid. Direction B currently preserves the Places / People tabs and moves the horizontal People shelf directly below search prompts.
2. Approve the strict friend/favorite/Wanna Go truth contract before it becomes a product or engineering requirement.
3. Approve the confidence-matched place recovery copy and provenance treatment shared by both directions.
4. Approve using grouped body-state boards as the compact full-state handoff, with 10 Direction A journeys and 3 Direction B journeys represented as full phone screens. Journey A2 explicitly shows the complete Activity-empty screen because the compact board crop hid persistent navigation chrome.

Any requested visual changes are applied to the mock and this document before the design gate closes.

## Prototype Test Script

Use five authenticated users who follow 0–4 non-blocked people.

1. Open Discover. Ask what they expect Places and People to contain.
2. Ask them to find one person worth following without coaching.
3. Before tapping Follow, ask why rec.me showed that person and what they expect following to change.
4. Complete the follow and switch to Places. Ask what changed and whether the new Activity content feels expected.
5. Show one strong and one weak recovery candidate. Ask why each appeared, what rec.me knows, and whether either feels invasive.
6. Exercise one Follow failure and offline cache state. Ask whether the current truth is clear and what action is available.
7. Compare Direction A home with Direction B home. Ask which screen helps them choose a place sooner and whether People still feels sufficiently prominent.
8. Give `Joe’s favorite restaurants` a zero-result and a populated result. Ask what each result claims, whether they expect Wanna Go places, and whether the suggested fallback feels honest.

Gate metrics remain those in the canonical product contract. This review does not weaken them.

## Implementation Tasks After Mock Approval

```jsonl
{"id":"REC90-D1","title":"Reconcile DESIGN.md Discover guidance with approved bounded recommendations","blocked_by":["Joe mock approval"],"deliverable":"Updated canonical design rules with no-directory/no-leaderboard boundary"}
{"id":"REC90-D2","title":"Create SwiftUI component and presentation-state inventory","blocked_by":["Joe mock approval"],"deliverable":"Plan-eng-reviewed view/repository/state boundaries"}
{"id":"REC90-D3","title":"Build People acquisition slice behind its own flag","blocked_by":["REC90-D2","plan-eng-review"],"deliverable":"Search, shelves, follow/dismiss states, analytics, tests"}
{"id":"REC90-D4","title":"Prototype and trust-test place recovery before backend work","blocked_by":["Joe mock approval"],"deliverable":"Five-user provenance/comprehension result against the locked trust gate"}
{"id":"REC90-D5","title":"Build place recovery slice behind a separate flag","blocked_by":["REC90-D4","plan-eng-review"],"deliverable":"Local evidence, dedupe, save/dismiss states, analytics, tests"}
{"id":"REC90-D6","title":"Run simulator visual QA","blocked_by":["REC90-D3 or REC90-D5"],"deliverable":"390pt/current target, 320pt/small target, Dynamic Type, offline/error screenshots"}
```

## Approved Mockups

| Surface | Artifact | Status | Approval note |
|---|---|---|---|
| Main journeys | `preview/discover-redesign/index.html` → Main journeys | Pending Joe | Ten Direction A flows plus three Direction B flows. |
| Full-state boards | `preview/discover-redesign/index.html` → State boards | Pending Joe | Five boards covering data, mutation, recovery, and accessibility states. |
| Places overview | `preview/discover-redesign/discover-journeys.png` | Pending Joe | 390pt default Places. |
| Activity-empty screen | `preview/discover-redesign/discover-activity-empty.png` | Pending Joe | Full 390pt screen with persistent Places / People tabs, search, and four-tab navigation. |
| People overview | `preview/discover-redesign/discover-people.png` | Pending Joe | 390pt populated People. |
| Direction B home | `preview/discover-redesign/discover-direction-b-home.png` | Pending Joe | Universal search, prompts, and horizontal People shelf first. |
| Direction B answer | `preview/discover-redesign/discover-direction-b-answer.png` | Pending Joe | Joe-anchored favorite answer with interpretation, map, refinements, and match reasons. |
| Direction B zero result | `preview/discover-redesign/discover-direction-b-zero.png` | Pending Joe | `Joes` resolves to Joe; strict Favorite returns zero and offers an explicit visited fallback. |
| State overview | `preview/discover-redesign/discover-states.png` | Pending Joe | Places state board; other boards are interactive in HTML. |

## Review Log

| Pass | Result | Evidence |
|---|---|---|
| IA | Pass pending direction choice | Direction A and B both preserve Places/People wayfinding; Direction B changes zero-query priority and answer structure. |
| States | Pass | Product-state table plus 5 rendered state boards. |
| Emotional journey | Pass | Value comprehension and trust mechanisms mapped per moment. |
| AI-slop/trust | Pass | No leaderboard, fake preview, generic travel treatment, or structural emoji. |
| Design system | Pass pending final DESIGN.md reconciliation | Existing tokens/components are reused; conflict is explicit. |
| Responsive/accessibility | Pass for artifact | No horizontal overflow across all 13 screens at 390pt and 320pt/1.32×; 44pt product targets; zero console errors. |
| Unresolved decisions | Blocked on one gate | Joe must choose or revise Direction A/B before engineering review. |

## GSTACK REVIEW REPORT

Status: DONE_WITH_CONCERNS

Design completeness: 9/10

What is ready:

- Stable information architecture.
- Full product-state and visual-state contract.
- Ten Direction A journeys plus three Direction B journeys.
- Five grouped state boards.
- Responsive/accessibility behavior and verification evidence.
- Explicit design-to-engineering tasks.

Concern:

- The canonical product spec still reflects Direction A. No engineering review or implementation should begin until Joe chooses A, B, or a named hybrid and the product contract is reconciled.

### UNRESOLVED DECISIONS

- Joe selection of Direction A, Direction B, or a named hybrid, followed by approval of density, people-card treatment, search truth contract, and strong/weak recovery presentation.
