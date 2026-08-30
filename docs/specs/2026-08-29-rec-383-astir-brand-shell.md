# REC-383 Astir brand shell

Status: exploratory prototype

## Purpose

Make the Astir name tangible across the product that exists today before the
production rec.me product or design system is renamed. The shell is entered only
through the debug launch argument `-AstirBrandShell [page]` and has no backend,
authentication, or analytics dependency.

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
| Paper | `#F2E9DB` | Daylight canvas and memory surfaces |
| Raised paper | `#FFF9EF` | Cards and notes |
| Ink | `#141714` | Primary text, controls, and contrast |
| Deep ocean | `#0E3033` | Place and list accents |
| Clay | `#C65A3C` | Warm action and editorial emphasis |
| Signal | `#F05A3C` | High-energy emphasis |
| Pool | `#3D6A78` | Places, people, and coastal context |
| Gold | `#C99B3E` | Rituals and secondary highlights |

### Typography

- Display and wordmark: native editorial serif for emotional statements.
- Body and controls: Avenir Next for warm, production-realistic clarity.
- Time and metadata: Avenir Next Condensed for compact logistics.

### Motion

- Fast native navigation and native sheet presentation.
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

## Prototype pages

1. Map — search, filters, trusted-person signals, selected-place actions, and
   the entry point to Add.
2. Feed — recent place activity from people the user trusts.
3. Lists — the user's saved and shared place collections.
4. Profile — Been, Wanna Go, friends, monthly pattern, and recent activity.
5. Add sheet — current location, link, manual search, photo, and unresolved
   drafts.

The bottom tabs are exactly `Map`, `Feed`, `Lists`, and `Profile`. Add is a sheet,
not a fifth tab. Event discovery, event details, arrival, at-event presence, and
post-event memory are intentionally excluded from this pass. They remain future
product directions rather than current navigation.

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
