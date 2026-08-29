# REC-357 — Wanna events and Wanna Go With

Status: production implementation ready for review

Linear: [REC-357](https://linear.app/recme/issue/REC-357/make-wanna-event-based-and-add-wanna-go-with-planning)

## Product contract

A Wanna is an immutable moment in activity history. Current place state is a derived relationship:

| Visits | Active Wannas | Current relationship | Filters |
|---:|---:|---|---|
| 0 | 0 | none | neither |
| 0 | 1+ | wants to go | Wanna |
| 1+ | 0 | has been | Been |
| 1+ | 1+ | has been and wants to return | Been and Wanna |

Multiple Wanna moments may exist for the same person and place. Creating another one does not overwrite the earlier event.

## Check-in behavior

| Starting condition | Action | Outcome |
|---|---|---|
| Active Wanna, no prior visit | First check-in | Save the visit and fulfill all active Wannas without a prompt. |
| Active Wanna, prior visit exists | Repeat check-in | Save the visit first, then ask **Keep in Wanna** or **Remove from Wanna**. |
| Repeat prompt dismissed or interrupted | No explicit choice | Keep is the safe default; intent is not silently removed. |
| Remove selected | Resolve active Wannas | They leave the Wanna filter but remain in activity history. |

## Wanna Go With

The ordinary Wanna flow remains valid with no extra requirements. Planning appears progressively when the user selects people.

- Date is optional.
- People are optional; up to 19 invitees may be selected with the existing multi-person picker.
- Feed versus Private appears only for a plan.
- **Share on Feed** means the creator's existing save audience may see the statement.
- **Private** says “Only you and the people invited can see this.”
- A private profile or Self save forces Private.
- Blocks make invitation/acceptance unavailable and remove cross-user projection.

Saving creates the creator's Wanna first, one plan, one creator participant, and one independent pending participant per invitee.

## Acceptance and decline

Acceptance atomically creates the invitee's own Wanna and marks only that participant accepted. It copies place identity and the optional planned date, but never copies notes, ratings, tags, answers, photos, personal labels, or another person's privacy state.

Decline creates no Wanna and does not affect other participants. Retried acceptance is idempotent and generation-scoped.

## Feed and activity

The creator produces one immutable Feed event:

- never visited at event time: **Ryan wants to go to Gnarwhal Coffee**;
- visited before event time: **Ryan wants to go back to Gnarwhal Coffee**.

Copy uses `was_visited_before` captured on the event, not today's mutable relationship. Accepted visible invitees and the optional date decorate that same card. Pending and declined invitees never appear publicly. Acceptance does not create a second Feed post.

Private plans create no follower Feed event, but remain in participant invitation/activity surfaces.

## Map and filters

There is no new plan-specific marker, badge, legend, cluster, or color. Accepting creates an ordinary personal Wanna. When Been and active Wanna coexist, the current marker uses the existing combined solid/dashed outline and appears under both filters.

## Notifications

Wanna invitations reuse the existing invitation notification preference and delivery infrastructure with `recme://wanna-plans/...` deep links. The client routes those links to the combined invitation inbox. Notification payloads do not change the authorization boundary; the inbox RPC revalidates the participant and block state.

## Storage and security

- `place_wanna_events`: immutable moment plus mutable active/fulfilled lifecycle.
- `place_plans`: creator, place, optional date, Feed/Private, lifecycle.
- `place_plan_participants`: independent creator/invitee state and accepted Wanna link.
- `place_plan_operations`: idempotent acceptance ledger.
- Direct table access is denied. Authenticated, security-definer RPCs derive the caller from the JWT and pin their search path.
- Legacy active Wanna summaries receive one backfilled event.
- `user_places` remains a compatibility projection during migration; a Been row is never replaced by a return Wanna.

## Analytics

Only coarse booleans, enums, and count buckets are emitted. Place, participant, plan, invitation, notification, date, note, coordinate, and profile identifiers are prohibited. See `docs/analytics.md`.

## Deferred

The passed-date question **“Did you end up going with Ryan?”**, plan chat, calendar sync, reservations, payments, public joining, and plan-specific map treatment are not in this iteration.

## Acceptance criteria

- Multiple Wanna moments preserve history.
- Been and active Wanna coexist in state, filters, profile counts, activity, and the existing marker grammar.
- First and repeat check-ins follow the rules above.
- Date is optional and multiple people have independent invitation state.
- Acceptance creates an independent Wanna and no duplicate Feed post.
- Public Feed exposes only accepted, visible participants.
- Private/profile-private/Self behavior fails closed.
- Migration/RPC tests run against the hosted schema inside a rolled-back transaction.
