# REC-383 Astir brand shell

Status: exploratory prototype

## Purpose

Make the Astir name and event expansion tangible in a real SwiftUI shell before
the production rec.me product or design system is renamed. The shell is entered
only through the debug launch argument `-AstirBrandShell [page]` and has no
backend, authentication, or analytics dependency.

## Brand thesis

Astir is a cinematic neighborhood signal: warm and useful by day, deeper and
more atmospheric around live events, then intimate and editorial the morning
after. It helps someone feel that something worth doing is close and that they
already have a place in it.

The system combines four useful ingredients from the supplied handoff without
adopting any board as a source of truth:

- Cult Classic's emotional pull and authored sequence.
- Living Almanac's information clarity and accumulated record.
- Local Frequency's time, distance, and live-state energy.
- Open House's generous welcome and social safety.

## Design system

### Aesthetic and layout

- Hybrid editorial/native layout: expressive full-bleed moments sit on a strict,
  scannable iPhone grid.
- Intentional decoration: frame corners, chapter numbers, and restrained
  metadata appear only where they organize the experience.
- Mystery lives in photography, pacing, and partial reveal. Logistics never hide.

### Color

| Role | Value | Use |
|---|---|---|
| Paper | `#F2E9DB` | Daylight canvas and memory surfaces |
| Raised paper | `#FFF9EF` | Cards and notes |
| Ink | `#141714` | Primary text and event-night canvas |
| Deep ocean | `#0E3033` | Arrival and wayfinding |
| Clay | `#C65A3C` | Warm action and editorial emphasis |
| Signal | `#F05A3C` | Live state and time-sensitive emphasis |
| Pool | `#3D6A78` | Places, people, and coastal context |
| Gold | `#C99B3E` | Rituals and secondary highlights |

### Typography

- Display and wordmark: native editorial serif for emotional statements.
- Body and controls: Avenir Next for warm, production-realistic clarity.
- Time and metadata: Avenir Next Condensed for compact logistics.

### Motion

- Fast native navigation and one short entry dissolve.
- No cinematic delays, decorative loading sequences, or disorienting map motion.

## Safe choices

- Native map behavior and four-item bottom navigation.
- Obvious primary actions and fully visible date, time, price, location, guest,
  and arrival details.
- At least 44-point interaction targets and non-color status cues.

## Deliberate risks

- Lifecycle palette shift: warm daylight utility becomes a dark event world,
  then returns to paper for memory. This creates emotional progression but must
  still feel like one product.
- Authored post-event memory: selected photographs, a host note, and contextual
  people replace a chronological photo dump. This gains meaning at the cost of
  requiring real editorial and consent operations.
- Sparse film vocabulary: `chapter` and frame marks make events memorable, but
  appear rarely enough to avoid film-distributor cosplay.

## Prototype pages

1. Intro and brand promise.
2. Today in Ocean Park.
3. Map with places and a live event.
4. Event detail and RSVP.
5. Arrival guidance.
6. Minimal at-event screen that returns attention to the room.
7. Morning-after photographs, host note, and connections.
8. Personal history.

## Asset note

`AstirWestsideBoard` is a cropped reference-board asset supplied for this
exploration. It is not a production photography asset or final creative.

## Running

Generate the Xcode project, then launch the Debug app with one of:

```text
-AstirBrandShell intro
-AstirBrandShell today
-AstirBrandShell map
-AstirBrandShell event
-AstirBrandShell arrival
-AstirBrandShell present
-AstirBrandShell memory
-AstirBrandShell profile
```
