# REC-383 Astir brand shell

Status: first production visual tranche, with a retained debug comparison shell

## Purpose

Make the Astir name tangible across the product that exists today before the
public rec.me name is changed. The first tranche applies the editorial visual
language to production Feed, Map, Lists, place-profile, check-in, and shared
activity surfaces while preserving copy, navigation, feature order, backend
boundaries, authentication, and analytics. A debug-only shell remains available
through `-AstirBrandShell [page]` for deterministic visual comparison.

## Brand thesis

Astir is a warm neighborhood memory: personal enough to feel authored, useful
enough to reach for whenever someone needs a place, and social without becoming
an influencer feed. It should make trusted taste feel alive while keeping the
map and saved-place utility immediate.

The system combines four useful ingredients from the supplied handoff without
adopting any board as a source of truth:

- Cult Classic's emotional pull and authored character.
- Living Almanac's information clarity and accumulated record.
- Local Frequency's neighborhood energy and visual contrast.
- Open House's generous welcome and social safety.

## Design system

### Aesthetic and layout

- Hybrid editorial/native layout: expressive full-bleed moments sit on a strict,
  scannable iPhone grid.
- Intentional decoration: small section numbers and restrained metadata appear
  only where they organize the experience.
- Personality lives in photography, typography, color, and specific copy. Core
  place actions remain obvious.

### Color

| Role | Value | Use |
|---|---|---|
| Paper | `#F2E9DB` | Light Mode canvas and memory surfaces |
| Raised paper | `#FFF9EF` | Light Mode cards and notes |
| Ink | `#141714` | Dark Mode canvas and high-contrast controls |
| Deep ocean | `#0E3033` | Place and list accents |
| Signal | `#F05A3C` | Astir actions, selections, and editorial emphasis |
| Pool | `#3D6A78` | Places, people, and coastal context |
| Cinema brass | `#C7A45D` | Explicit exploration override only |

### Typography

- Display and wordmark: native editorial serif for emotional statements.
- Body and controls: Avenir Next for warm, production-realistic clarity.
- Time and metadata: Avenir Next Condensed for compact logistics.

### Motion

- Fast native navigation and native sheet presentation.
- Feed's floating header hides after sustained downward scrolling and returns
  quickly on reverse scrolling, with a Reduce Motion-safe transition.
- No cinematic delays, decorative loading sequences, or disorienting map motion.

## Safe choices

- Native map behavior and the product's real four-item bottom navigation.
- Obvious save, check-in, search, list, profile, and add actions.
- At least 44-point interaction targets and non-color status cues.

## Deliberate risks

- The editorial serif and wide-tracked wordmark introduce more personality than
  the current utility shell, while compact sans-serif controls preserve clarity.
- Warm paper, clay, ocean, and gold deliberately reject both generic travel blue
  and an all-beige lifestyle app.
- Feed and profile are treated as records of trusted place behavior rather than
  content-creator surfaces.

## Production surfaces in the first tranche

1. Map — Astir wordmark, search, floating controls, pins, and selected-place
   presentation.
2. Feed — independently floating header controls, adaptive blur field, Places /
   People tabs, real place photography, and scroll-aware hide/reveal behavior.
3. Lists — editorial hierarchy, adaptive surfaces, and existing list behavior.
4. Place profile — real place photography, editorial information hierarchy,
   floating controls, and existing save/check-in actions.
5. Shared check-in and activity surfaces — initial palette and component bridge.

The production palette follows system appearance automatically: warm paper in
Light Mode and ink-black in Dark Mode. Cinema/brass remains available only via
the explicit `-AstirBrandMode cinemaGold` exploration override.

## Remaining consistency pass

Add, Profile, Settings, and nested check-in/save editors still contain legacy
typography, terracotta references, or fixed warm-paper surfaces. The next tranche
will migrate those screens to shared semantic Astir typography, the signal coral,
and adaptive Light/Dark surfaces without changing copy, order, or functionality.

## Debug comparison pages

1. Map — search, filters, trusted-person signals, selected-place actions, and
   the entry point to Add.
2. Feed — recent place activity from people the user trusts.
3. Lists — the user's saved and shared place collections.
4. Profile — Been, Wanna Go, friends, monthly pattern, and recent activity.
5. Add sheet — current location, link, manual search, photo, and unresolved
   drafts.

The bottom tabs remain exactly `Map`, `Feed`, `Lists`, and `Profile`. Add remains
a sheet, not a fifth tab. Event discovery, event details, arrival, at-event
presence, and post-event memory remain future product directions rather than
current production navigation.

## Asset note

`PlaceCarouselPhotos` provides existing in-app photography for the shell. The
reference board remains directional inspiration, not production creative or a
source of truth.

## Running

Launch the Debug app with one of:

```text
-AstirBrandShell map
-AstirBrandShell feed
-AstirBrandShell lists
-AstirBrandShell add
-AstirBrandShell profile
```
