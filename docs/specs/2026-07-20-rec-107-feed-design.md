# REC-107 Feed design spec (draft)

Status: Approved by Joe on 2026-07-20. Engineering plan locked before production implementation.

## Product job

Feed is the place to catch up on useful place memory from people a member
trusts. It is not a generic public social feed and it is not a second place
search result screen.

The first release answers: “What did people I follow recently save, visit,
want to try, or organize that I may want on my own map?”

## Information architecture

1. Keep the existing compact, ticker-style universal search at the top. The
   resting placeholder continues to cycle through the current useful prompts;
   when focused it enters the existing place/people search experience. A static
   mock captures its size and hierarchy, not the ticker motion.
2. Render a `Featured for you` horizontal place rail only when it has useful
   candidates. It is a subordinate personalized module, not the page's main
   job.
3. Render `Your feed` immediately below. It is reverse chronological in v1.
4. Rename the bottom-tab label from `Discover` to `Feed` and change its icon to
   a feed/newspaper-style symbol. Preserve the existing five-tab shell in this
   release: Map, Feed, Add, Lists, Profile. Moving Lists into a four-tab
   navigation model is explicitly deferred.

No top filter chips, calendar, notification, menu, likes, comments, shares, or
follower counts belong in the initial Feed screen.

## Visual direction

Borrow Beli's compact social-event hierarchy, not its branding or its
engagement mechanics. Follow rec.me's warm utility tokens:

- Cream/bone surfaces, espresso copy, terracotta save affordances, quiet sky
  only for social provenance.
- Thin dividers define activity modules. Avoid a stack of floating social cards.
- Search is 44pt high. It keeps the existing ticker placeholder behavior.
- Avatars are 48pt circles; all action controls remain at least 44pt.

Primary review artifact:

`~/.gstack/projects/joelipshutz-wander/designs/feed-20260720/feed-primary-contract.png`

## Feed module contract

Every activity module has a stable leading actor identity and a distinct
activity payload. Modules own their presentation, which allows future ranking
or personalization without changing the Feed container.

### Common anatomy

| Position | Content |
|---|---|
| Leading | Actor avatar, display name, and action verb |
| Main | Place or list title, category/type, locality, and relative time |
| Upper-right | Rating only when the actor has recorded one |
| Body | Actor note only when present |
| Media | Horizontally scrollable photos only when present |
| Bottom-right | `Save to my map` for a place; `View list` for a list event |

Place actions use `+ Save to my map` in the first release. On compact rows this
can collapse to the same clearly labelled or accessible save icon, but it
remains anchored bottom-right. It opens the canonical prefilled save flow
rather than creating a parallel Feed-specific save path. A saved state becomes
a clear checkmark; a failed save offers retry. List creation and list-add
events use `View list`; rec.me does not yet support saving or cloning another
person's list, so the Feed must not present a false `Save list` state.

### Supported activity types

| Type | Example copy | Required payload | Optional payload | Save action |
|---|---|---|---|---|
| Place saved | “Maya Chen saved Anna Jack Thai” | actor, place, category, locality, created time | rating, note, visit photos | Save place |
| Been | “Marcus Reed marked La Sorted’s Pizza Been” | actor, place, category, locality, created time | rating, note, visit photos | Save place |
| Want to go | “Marcus Reed added La Sorted’s Pizza to Want to go” | actor, place, category, locality, created time | note, saved-place photos | Save place |
| List created | “Priya Shah created Sunday in Silver Lake” | actor, list title, item count, created time | list cover/item photos, description | View list |
| List add | “Maya Chen added Wayfare Tavern to Sunday in Silver Lake” | actor, place, list title, created time | actor rating for the added place, place/list photo | View list |

Do not fabricate a rating for a Want to go activity. Omit missing notes and
media rather than adding empty slots. Place photos are visit photos first,
then usable place photos; list media uses list cover or contained-place photos.
All media rails scroll horizontally inside their originating module.

## Modular ordering contract

The view consumes modules, not a hard-coded flat event type list:

```text
FeedModule.featuredPlaces(candidates)
FeedModule.activity(items, ordering: reverseChronological)
FeedModule.networkRecovery(people) // only when feed has no useful activity
```

V1 orders visible followed-person activity by durable event timestamp,
newest-first. A future ranker can reorder modules or activity items using trust,
location, recency, relevance, and save likelihood without altering the card
contracts.

## Required states before implementation

| State | Expected behavior |
|---|---|
| Loading | Compact search stays interactive; featured and activity use quiet skeleton rows, not a full-screen spinner. |
| Populated | Show the featured rail when candidates exist, then chronological activity modules. |
| No featured candidates | Omit the rail entirely; `Your feed` moves directly under search. |
| No following/activity | Explain that Feed fills from people followed, then show a compact people-recovery module with direct Follow actions. Do not render an empty white feed; the four bottom tabs remain visible. |
| Partial activity | Omit only missing rating, note, photo rail, or locality. Preserve the event and save action. |
| Remote error | Preserve cached modules when available. Otherwise show a quiet inline retry row beneath `Your feed`; search remains available. |
| Offline/stale | Render cached activity with a quiet “Updated earlier” treatment. Do not imply live updates. |
| Place save default/saved/failure | `+ Save to my map` → checkmark confirmation → retry state on error. Do not change the source activity. |
| List action | `View list` opens the visible list detail. No list-bookmark or clone state is implied. |
| Search idle/focused/results/no results | Feed exists only at idle. Focus opens the current search mode; clearing the query restores the prior Feed scroll position. |
| Private/blocked actor | Exclude the module before it reaches the Feed. Private-mode opt-outs, blocked people, and any otherwise-ineligible actor must not expose profile, place, list, or photo remnants. |
| Small phone/Dynamic Type | Text wraps before it collides with rating or save controls; media remains horizontally scrollable; no control falls under bottom navigation. |

## Explicit non-goals for v1

- Likes, comments, shares, leaderboard/challenge activity, and public
  engagement counts.
- A live-location or real-time check-in interpretation.
- A fifth tab, a separate social-feed hierarchy, or a second save backend.
- Personalized ranking beyond reverse chronological order.

## Mock audit notes

The final primary mock is the approval candidate because it keeps the four-tab
rec.me shell, makes the Featured rail subordinate, places a rated place's
rating in the upper-right, keeps notes/photos in the activity block, and puts
expanded-module save/list actions at the bottom-right. The production version
must also retain a bottom-right save affordance for compact Been and Want to go
rows, preserve the existing ticker animation, and provide a short trust reason
on featured cards rather than an anonymous recommendation score. An automated
alternate that introduced generic rounded cards and `Home/Search/Lists`
navigation was discarded; it is not a candidate for implementation.

## Approval gate

Before engineering:

1. Joe approves or changes the primary Feed mock and the optional-featured-rail
   choice.
2. Design review confirms the primary and required state coverage above.
3. Engineering review is locked by
   `docs/plans/2026-07-20-rec-107-feed-engineering-plan.md`: immutable
   database-emitted events, an RLS-filtered feed RPC, deterministic featured
   places, canonical place-save handoff, visible-list navigation, and full
   hosted/native tests.
