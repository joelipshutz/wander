# REC-90 Discover Competitive Research and Direction Brief

Date: 2026-07-14  
Status: Research complete; no implementation approved  
Linear: [REC-90](https://linear.app/recme/issue/REC-90/redesign-discover-around-activity-nearby-place-memories-and-people)

## The point

Discover should become a **social answer engine for places**, not a taller activity feed and not a member directory.

The page's primary job is:

> Help me find a place that fits this moment, using evidence from people I trust.

Following people, recovering unfinished saves, and showing new activity all support that job. They are not the job themselves.

This brief responds to two observed problems:

1. The idle Discover page is visually repetitive and functionally thin. It presents a list of saves but does not help the user decide where to go.
2. Natural-language search is not semantically truthful. `Joe's restaurants` and `Joe's favorite restaurants` can behave the same, and a favorite query can show Wanna Go records.

No SwiftUI, backend, schema, or parser implementation is part of this research branch.

## Current-screen critique

The supplied build screenshot has a clear mode switch and a prominent search field, but nearly all remaining space is spent on repeated `saved` events.

- Activity states a fact but rarely answers a place question. `Joe saved X` is weaker than `Joe rated X 4.5 for date night`.
- Place names and metadata truncate before the user can judge relevance.
- Been/Wanna Go is visible, which is good, but judgment and query-match evidence are absent.
- There is no nearby/trusted answer, category pivot, suggested intent, map handoff, or compact people-acquisition loop.
- A thin network produces a visibly empty page instead of a more helpful alternate state.
- The rotating example query advertises intelligence that the result contract does not yet support.

The existing REC-90 mock improves hierarchy and states, but it still makes Activity visually primary and treats network growth as the page objective. It also lacks a first-class place-search-results journey.

## Competitive research

Research was performed against current first-party product pages and official product documentation on 2026-07-14.

| Product | Pattern worth understanding | Take for rec.me | Do not copy |
|---|---|---|---|
| [Beli](https://apps.apple.com/us/app/beli/id1478375386) | Separates places tried from places to try, combines friend activity with filters, rankings, and personalized recommendations. | Preserve strict visit-state truth and make a friend's judgment more important than the save event. | Restaurant-only framing, global ranking obsession, streaks, or a feed as the whole product. |
| [Mapstr](https://en.mapstr.com/faq) | Its Inspiration area mixes updates from followed maps, timely selections, geolocated search, natural-language mood queries, and a multi-map overlay. | Let trusted people's places become a map layer and make search hand off directly to the map. | Influencer/editorial maps, paywall-led discovery, or generic trend content. |
| [Corner](https://apps.apple.com/us/app/corner-curate-share-places/id1668282277) | Leads with vibe-oriented queries and community-added places; place pages foreground who saved a place and summarize the vibe, what to get, and the practical move. | Use expressive moment language and show provenance directly on every result. | A global tastemaker feed, public trend chasing, or aesthetics that outrun utility/privacy. |
| [Google Maps](https://blog.google/products-and-platforms/products/maps/ask-maps-immersive-navigation/) | Ask Maps handles compound real-world questions, visualizes answers on a customized map, and turns them into save/share/directions actions. Explore also adapts suggestions to place and time context. | Treat natural language as an answer request, keep the map close, and make the next action obvious. | Opaque personalization, web-scale popularity, background-history assumptions, or anonymous abundance. |
| [Yelp](https://blog.yelp.com/news/fall-product-release-2025/) | Natural-language results annotate which aspects matched and surface intent-specific evidence from reviews. | Show exactly why each result satisfies the query. | Anonymous-review volume, star-ranking dominance, sponsored clutter, or business-conversion chrome. |

### Category baseline

Strong discovery products converge on:

- a search field that accepts intent, not just names;
- fast category/moment pivots;
- location or map context;
- visible reasons for recommendations;
- a direct action after deciding;
- home content that changes when the user's context or network is thin.

### rec.me's opportunity

Every large competitor optimizes for abundance. rec.me should optimize for **provenance and truth**.

The differentiated answer is not “here are 50 popular restaurants.” It is:

> “Here are four places that fit. Joe has actually been to all four, rated these two highly, and Maya also saved one for date night.”

That is a more useful and defensible product than a generic AI place recommender.

## Why current search fails

### 1. `favorite` is not a modeled meaning

`DiscoverFilters` can represent category, area, visit status, relationship, owner, and a small tag set. It cannot represent opinion, rating, recency, distance, exclusions, or ranking intent.

The deterministic parser maps `favorite`, `best`, `liked`, and `recommended` to only `status = been`. Search therefore understands:

```text
Joe's favorite restaurants = restaurants Joe has been to
```

It does not understand:

```text
Joe's favorite restaurants = restaurants Joe has been to and rated highly
```

The existing regression test locks this incomplete behavior by asserting only owner, category, and Been status.

### 2. Keystroke searches can finish out of order

`DiscoverScreen` starts a new asynchronous request on every `placesQuery` change. There is no debounce, cancellation, request identity, or final-query guard before assigning `placeResults`.

Typing the longer query can produce this sequence:

```text
request A: Joe's restaurants
request B: Joe's favorite restaurants
request B finishes
request A finishes later and overwrites B
```

That is a strong fit for the reported identical results and Wanna Go leakage, especially because the remote AI parse has variable latency.

### 3. Schema validation is not semantic validation

The Edge Function asks the model for allowed enum values and includes the favorite query as an example. The validator only removes values outside the schema. A schema-valid response with `statuses: []` for a favorite query is accepted rather than repaired or rejected.

The deterministic parser runs only when the remote call throws. It does not audit a successful but meaningfully wrong response.

### 4. The fallback grammar is brittle

- `Joe's` can resolve an owner, but apostrophe-less `Joes` cannot reliably do so.
- Owner matching uses substring containment, so `Joe` can also match `Joelle`.
- Category/status aliases use substring checks rather than token or phrase boundaries.
- The literal area `LA` is currently treated as a no-op filter.
- Unrecognized intent words disappear rather than being shown as unsupported or unresolved.

### 5. Result cards do not prove the answer

The result card can show a score, status, note, and owner, but it does not carry a structured per-result explanation such as:

```text
Matched: Joe · Been · 4.5 rating · Restaurant
```

Without that evidence, the UI cannot catch a contradiction between the parsed query and the record being presented.

## Three page directions

### Direction A — Social Answer Engine (recommended)

Make the search/answer loop the hero. Idle Discover provides a useful launchpad; active search becomes a transparent answer surface.

Idle order:

1. Plain `Discover` title.
2. One universal search field for people, places, vibes, and moments.
3. Suggested intent chips based only on available data: `near me`, `date night`, `coffee + work`, `outdoors`, `friends' favorites`.
4. `Nearby from your people`: three strong trusted results with distance and provenance, plus `Show on map`.
5. `New from your people`: at most three activity rows, then `See all activity`.
6. `People worth following`: compact, reasoned suggestions; no peer People homepage required.
7. Conditional `Pick up where you left off` / `Places you may have been` from REC-90's honest evidence contract.

Active-search order:

1. Search field.
2. `Understood as` chips, for example `Joe` · `Restaurants` · `Favorites` · `Los Angeles`.
3. Answer summary: `4 places Joe has been and rated 4+`.
4. `Show 4 on map` handoff.
5. Place cards with matched evidence and the queried person's record as the primary provenance.
6. Refinements based on valid data: `closer`, `date night`, `group-friendly`, `quiet`, `wanna go instead`.

Why this wins: it serves the north star on the first screen and makes intelligence inspectable.

Risk: it requires a real query contract and careful empty-state behavior; visual polish cannot hide semantic shortcuts.

### Direction B — Contextual Briefing

Open with dynamic modules such as `For tonight`, `Near you`, `New this week`, and `Worth a detour`, followed by Activity and people suggestions.

Why it is appealing: the page always feels full and can surface value before a query.

Why it is second choice: rec.me currently lacks authoritative hours and broad real-time context. Overpromising “right now” intelligence would recreate the same truth problem in a prettier form.

### Direction C — Network Builder

Continue the existing REC-90 direction: peer Places/People modes, Activity, proactive follow suggestions, and place recovery.

Why it is appealing: it directly improves cold-start graph density and the existing follow loop.

Why it is third choice: it optimizes the means (more follows) over the user outcome (a useful place answer), and the People mode can remain undiscovered. Keep its recommendation-card and recovery ideas inside Direction A instead.

## Recommended query contract

The LLM should translate language into a bounded query plan. Deterministic code should resolve identities, enforce truth constraints, execute filters, and rank records.

Proposed intent fields:

```text
owner/profile IDs
relationship scope
place categories
visit states: been | wanna_go
opinion: favorite | liked | neutral
minimum/relative rating
area or near-me radius
attributes/tags
time/recency when authoritative
sort intent
excluded concepts
parser confidence and unresolved terms
```

Hard invariants:

- `favorite`, `best`, `loved`, and `highly rated` can return only Been records.
- For v1, favorite should mean Been plus either an explicit favorite label or the queried person's rating of 4.0+, ordered by that person's rating. The answer copy must name the rule.
- If no exact favorites exist, show zero exact matches and offer `Show Joe's visited restaurants`. Never silently broaden.
- `wanna go`, `want to try`, and equivalent terms return only Wanna Go records.
- `Joe's restaurants` may include both Joe's Been and Wanna Go records, with status visible.
- The queried person's save is the primary record. If the current user also saved the place, render that as secondary context such as `You want to go`, not as Joe's state.
- Every returned card must be able to explain all hard facets it matched.
- Ambiguous identities produce a disambiguation choice before results are claimed.
- A stale request can never replace a newer query's result.
- Remote and deterministic parsing must converge on the same semantic post-validation rules.

### Example truth table

| Query | Required interpretation | Forbidden result |
|---|---|---|
| `Joe's restaurants` | Joe + Restaurants + Been/Wanna Go | Another owner presented as Joe. |
| `Joe's favorite restaurants` | Joe + Restaurants + Been + favorite/rating rule | Any Wanna Go place or unrated broad fallback. |
| `Joes favorite restaurants` | Resolve `Joes` against known profiles, then same as above | Dropping the owner silently because punctuation is absent. |
| `Joe's wanna-go restaurants` | Joe + Restaurants + Wanna Go | Been-only places. |
| `friends' favorite date-night restaurants near me` | Mutuals + Restaurants + Been + favorite + date-night + radius | Popular strangers, Wanna Go places, or unsupported hours claims. |

## What to keep from the existing REC-90 proposal

- Plain `Discover` screen title and warmer open-list Activity treatment.
- Honest strong/weak recovery titles and provenance.
- Suggested-person cards that answer why the person is shown.
- Follow success that stays in place long enough to explain what changed.
- Full loading, partial, offline, error, Dynamic Type, and block-state coverage.

## What to change before approval

- Reframe the objective from `Discover that builds the network` to `Discover that answers through the network`.
- Make place search results a first-class mocked journey with query interpretation, exact-result evidence, no-results, ambiguity, and stale-response behavior.
- Reduce Activity to a supporting module rather than the primary home payload.
- Move bounded people suggestions into the Places-first home instead of hiding them behind a peer mode.
- Add `Show on map` as the natural completion of a trusted place answer.
- Define favorite semantics before drawing more search UI.

## Decision requested

Choose whether to revise REC-90 around Direction A.

If approved, the next artifact should be a small set of visual alternatives for only these two screens:

1. Direction A idle Discover home.
2. `Joe's favorite restaurants` results with transparent query chips and provenance.

Do not start engineering review or implementation until those two screens and the favorite contract are approved.
