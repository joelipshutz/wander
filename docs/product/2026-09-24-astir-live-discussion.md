# Astir Live — product discussion notes

Date: September 24, 2026

Status: Saved discussion for a future spec. This is not an implementation specification or approval to build. Develop the spec only when Joe asks.

## Scope and intent

Rethink both tabs, primarily the current Feed tab. Rename Feed to **Live**. Later, research whether the tabs could be combined based on the desired feature set, and consider alternative approaches alongside the team's proposed direction. The second tab's redesign and any merger are not yet defined.

The core question is: **What are my people up to?**

The team reports that feedback from users and their own experience over the last week points to the feed as the strongest part of the app. This proposal builds on that learning.

## Core concept: activity first

Make the map about what people are doing around me, rather than a collection of places or recommendations. Inspiration came from a discussion of Instagram's map direction.

- Show recent activity nearby and activity from people the user cares about.
- Make activity recency visually distinct so users can understand what happened in their neighborhood over roughly the last day.
- Include routes, such as walks.
- Represent people and their activity on pins, potentially with small photos and labels such as “Rachel · 4 hours ago.” Exact pin design remains open.
- Provide a chronological feed and a map of the same content.
- Consider recency and relationship relevance when resolving overlapping pins. For example, a close friend's walk could take priority over activity from someone less close. This is an anticipated issue rather than a current scale problem.

## Shared map and feed: Airbnb interaction reference

Use Airbnb's map and draggable results drawer as the interaction reference. The map and list contain the same content, with activity and recency replacing homes and prices.

### Landing / half-sheet state

- A map occupies the visible upper portion of the screen.
- A draggable bottom sheet shows the first items of the feed.
- App navigation tabs remain visible.
- A top search field is undecided; one possibility is a field initially showing “Near me.” Borrowing more of Airbnb's top section is also undecided.
- The floating “Live Map” pill is absent while the map is already exposed in this state.

### Expanded feed state

- Scrolling upward to explore content raises the drawer until it covers the map and becomes the feed list.
- App navigation tabs remain visible.
- A floating liquid-glass-style **Live Map** pill appears above the tabs, with a beacon or similar live icon.
- The pill is available only when the feed is fully exposed.

### Withdrawn drawer / full-map state

- Tapping **Live Map** smoothly lowers the drawer to its lowest position within the same app tab.
- Dragging the drawer down can also enter this state.
- The drawer never dismisses completely: its grab handle and activity-count label remain visible at the bottom.
- App navigation tabs disappear only in this lowest drawer state.
- The drawer remains draggable so the user can return to the other states.

### Drawer count label

Replace Airbnb's count, such as “482 homes,” with an activity count. Candidate wording included “32 recent check-ins,” “32 recent activities,” or “37 new activities.” Final terminology, count scope, and definition of “recent” or “new” remain undecided.

## Tapping an activity

Tapping a map pin opens the existing collapsed place-card sheet, personalized around the selected person's activity. The primary subject is their check-in or wanna, rather than the place itself.

The supplied Airbnb screenshot illustrates a selected map pin and compact property card over the map. Astir would adapt that relationship to a person's activity.

## Wannas becoming plans

Wannas are a major part of the concept, alongside activity that already happened.

- Show the user's own wannas on the map.
- Explore an intentionally unfinished visual treatment for a wanna, potentially grayed out or otherwise distinct from completed activity. This is a design idea, not a decided treatment.
- Tapping a wanna opens a personalized collapsed card with a prominent action such as **Complete the plan**.
- That action could open a half sheet to add details: a time, an invitation to another person, and potentially an itinerary.
- Support moving from “I wanted to try this place” to making a plan with someone.
- A note to the invitee, such as “I'll be 20 minutes late,” was mentioned as a possible capability; its timing and relationship to planning or messaging are unresolved.

## Sparse networks and geographic coverage

Risk: this feels compelling for a group with several nearby people, but may feel sparse for the first users in a new city.

The proposed response is to choose the initial map framing intelligently, zooming out far enough to include meaningful activity. The example was a first user in Las Vegas seeing activity in Los Angeles if necessary.

The team stated that everyone follows the founders, so there should be some activity available if the map is zoomed out enough. Treat this as a product assumption to validate later, not a guaranteed data invariant.

A full-feed fallback when fewer than one or two activities exist was raised, then challenged on the basis of that follow relationship. No final sparse-state rule was settled. The intended benefit of retaining a map is to teach the interface before the user's local network grows.

## Map appearance and technology discussion

The team wants a less visually overpowering map and more control over its appearance. During the discussion, the current map was described as Apple Maps, and switching to MapKit was proposed with the belief that it is open source and would allow arbitrary visual customization.

This records the discussion's technical premise, not a verified finding. The current implementation, MapKit's actual capabilities and licensing, and any alternative mapping technology should be checked during the later spec/research phase before choosing an approach.

## Questions reserved for the spec

- Should the two tabs eventually merge, and what role does each serve if kept separate?
- What other approaches support the same activity and planning goals?
- Which activity types appear, and how do check-ins, routes, and wannas differ visually?
- How do chronological ordering, proximity, relationship relevance, and map framing interact?
- Does panning the map change the feed's content or only its visible geography?
- What time window and audience does the activity count describe?
- How should sparse, remote, or unavailable activity affect the initial viewport?
- Should search appear at the top, and what does “Near me” mean when the map zooms out?
- What exactly is required to turn a wanna into a plan, invitation, or itinerary?
- How does the activity card relate to the existing place card and its actions?
- What map styling is feasible in the current app and with potential alternatives?

These are follow-up questions, not additional agreed requirements.

## Source references

Source: the spoken discussion saved in the Codex task **“Redesign Live feed and tabs”** on September 24, 2026. These notes preserve that discussion for later specification work; they do not authorize implementation or settle the open questions above.

The original task included these Airbnb interaction references:

- Screen recording: `ScreenRecording_09-24-2026 11-23-06_1.mov`
- Screen recording: `ScreenRecording_09-24-2026 11-35-47_1.mov`
- Screenshot: `IMG_9780.PNG`

The reference media remains in its original local storage and is not included in this repository. Ask Joe for the original attachments when reviewing the interactions. The screenshot was supplied inline in the source task; these notes do not claim a frame-by-frame review of either recording.
