# Review Astir Live

REC-636 · October 9, 2026 · Product and engineering proposal

Start with the native prototype, then review the decisions against the spec. The prototype uses fictional data, a real MapKit surface and local simulated actions. It is an interaction proposal, not the production app or proof of backend behavior.

## Review order

1. [Product specification](product-spec.md): purpose, navigation, complete destination map, activity/history distinction and user journeys.
2. [SwiftUI prototype](../../../preview/rec-636-live/README.md): build/run instructions and supported demo states.
3. [Engineering plan](engineering-plan.md): current contracts, architecture, work packages, tests and rollout.
4. [Validation record](review/validation.md): what has actually been checked and what remains to prove.
5. [Native capture gallery](review/captures.md): large and compact phone evidence.
6. [Review findings](review/design-review.md): design coverage and outstanding questions.

## The proposed journey in one picture

```text
                  Ordinary authenticated entry
                              |
                        LIVE · half drawer
                         /             \
                   full feed           full map
                         \             /
                     same query + selection
                              |
               person + activity + place + time
                     /                    \
              comment/reply             own Wanna
                     |                    |
           conversation (later)       make a plan
                                          |
                               explicit invitation/share

       Lists tab                         Profile tab
           |                                  |
   existing collections              familiar profile hierarchy
                                      /                \
                                  Your Map           Calendar
                                      |
                              Map / Patterns / history
                                      |
                       selected capabilities MAY be reused
                           in LIVE after feature review
```

## Thirty-minute review script

| Minutes | Journey to try | What to decide |
|---|---|---|
| 0–4 | Land on Live, expand the feed, use Map, restore tabs from peek | Does the first screen communicate people/activity? Is the drawer discoverable? |
| 4–8 | Open the same activity from a pin and card | Do person, place and timestamp stay consistent? Is “Live” misleading? |
| 8–12 | Filter, draw/apply/clear an area, cancel an edit | Are these two controls understandable? Do filters behave predictably? |
| 12–16 | Profile → Your Map → old save; open Patterns; return to Profile | Is the familiar personal-map job intact? Which specific capabilities, if any, also belong in Live? |
| 16–20 | Open a Wanna and make a demo plan; open a demo reply | Is there a useful connection loop? Which phase should ship first? |
| 20–24 | Sparse/empty/offline scenarios; transition card Show me/Not now | Does the experience stay honest and useful without a dense network? |
| 24–28 | Add a demo check-in/Wanna; Lists; larger text/light appearance | Is core utility still obvious and reachable? |
| 28–30 | Record D1–D11 as approve/revise/defer | Agree the first production slice and its gates |

Avoid approving from still images alone. Drag/scroll handoff, keyboard, back navigation, VoiceOver and map gestures need native interaction. Review-menu controls are demo tooling, not proposed production UI.

## Feedback to record

For each decision, record: **decision ID · approve/revise/defer · desired behavior · reason**. A prototype preference is not approval of unrelated data, visibility, messaging or release changes.

Highest-impact choices:

1. **D1:** three destinations (Live/Lists/Profile), with Add as an action.
2. **D2–D3:** Following versus Nearby, seven-day default, all-time personal history.
3. **D4–D5:** area drawing/filtering and selective Your Map capability reuse, with Profile and Your Map preserved by default.
4. **D6–D7:** complete journey in the design; phased production with private messaging reviewed separately.
5. **D9–D10:** gentle migration teaching and separately labelled upcoming plans/events.

## Proposed production sequence

1. Agree experience and query/route contracts; prove the native drawer and map on two phone sizes.
2. Add compatible read/query and route adapters, keeping the old shell usable.
3. Build flagged Live with existing check-ins, Wannas, comments, search and capture. Keep Profile familiar; reuse only the Your Map capabilities explicitly accepted during review.
4. Run migration, access, performance and rollback tests; pilot a small cohort.
5. Extend plans, private replies and Events integration under their separate contracts.

No data wipe, visibility expansion, automatic invitations, map-provider migration or release is required for this review.

## What “ready” means

**Ready for product review:** coherent spec, engineering proposal and runnable isolated prototype, with assumptions marked.

**Ready for implementation:** product choices accepted; native gesture/accessibility spike and route/access contracts proven; tasks assigned against current main.

**Ready to release:** production tests and hosted access verification pass, device evidence is reviewed, analytics is checked, rollout/rollback is rehearsed, and the separate release workflow is authorized.

These are distinct milestones. See the validation record for the current milestone rather than treating a compile as release evidence.

## Confirmed scope

Profile is not being substantially redesigned. Its current identity/social, streak, recent-activity, Your Map and calendar structure stays the baseline. The exact Your Map capabilities to reuse or relocate remain a review decision; removing the entire Your Map experience is not approved. Patterns stays associated with the existing personal-map experience unless a specific later decision changes that.
