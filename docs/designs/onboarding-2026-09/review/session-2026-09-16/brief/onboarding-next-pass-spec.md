# Astir onboarding — next three passes

September 17, 2026 · REC-529 · specification for review

**September 18 next-pass confirmation:** Joe reconfirmed N08 profile, N09 location, N10 contacts, N11 following and N12 notifications after the opening review. Use the focused [N08 account-setup brief](n08-account-setup-pass.md) for current directions and work order. T19 completed fresh no-X native validation; that earlier blocker is resolved.

**September 18 ownership correction:** Joe assigned post-onboarding NUX to Ryan. This document’s old Map-first execution order is historical. Our active next pass is N08–N12 account setup, then its native validation and account recovery; see [the current T18 queue](../TASKS.md). Review-branch “already built” statements below do not mean those refinements shipped to main.

This defines the proposed work after the opening review. It builds on native commit `44376daf78d1a747b8ba3d1260e771f9d181ba6e`. Writing this spec does not mark any of these passes implemented or verified. The opening remains available for Joe and Ryan to review.

## 1. Map walkthrough: finish the first usable Map experience

**Outcome:** a new user understands the main Map controls, can take over immediately, and finishes on a usable Map without being forced to save a place.

**Already built:** the short native Map overview, its six control explanations, the closing overlay, and removal of the required save tutorial. Focused tests have already passed for the sequence, voluntary Plus, real-control dismissal and return to Map. Earlier broader failures include restoring an existing Wanna draft and its remove confirmation. Their relationship to onboarding is not established.

**The sequence being verified:**

| Step | What appears | What the user should learn |
|---|---|---|
| M01 · Featured | Explanation anchored to the actual filter | A starting selection of places chosen for them. |
| M02 · Friends | Explanation anchored to Friends | Places saved by people they follow. |
| M03 · More | The actual filter panel and its explanation | Narrow the Map by category, people, Check Ins or Wanna Go. |
| M04 · Search | Search explanation after More closes | Find a place or search places from their people. The explanation alone does not summon the keyboard. |
| M05 · Plus | Explanation anchored to the real + control | Save a place or bring in saves from another app. Saving stays voluntary. |
| M06 · Pin rings | Native ring legend | Solid rings mean Check Ins; dotted rings mean Wanna Go. |
| N25 · Closing | Existing closing overlay over Map | Finish on the Map. Preserve the current six-second timeout and immediate Skip while the ending copy remains a review choice. |

**Work:** reproduce the unresolved Map/editor failures first and identify whether each is an app defect, a test setup problem, or unrelated to the overview. Fix reproduced onboarding regressions and document any separate Map issue with its exact reproduction. Then check coach placement, entrances/exits, pacing, live targets, Next and user takeover through the entire sequence.

**Behavior requirements:** Next advances exactly one step; a working Map control performs its real action and dismisses guidance that would obstruct it; automatic and manual advancement cannot race into a skipped or repeated step. More closes before the Search explanation. No fake save or forced Add form occurs. Background/foreground, Reduce Motion, larger text, and completion/relaunch must leave the Map usable. Guidance remains scoped to eligible accounts.

**Done means:** the six steps and ending pass their native interaction checks; voluntary Plus and real-control exit work; no duplicate/stranded overlay or unintended save occurs; the reported failures have an evidenced disposition. Deliver light/dark recordings, six step captures plus the ending, and an updated test record. Unresolved unrelated failures remain visible as release limitations.

## 2. Missing native NUX captures: complete the conditional branches

**Outcome:** the review board shows the actual remaining screens, their trigger, and their exact visible copy.

The four missing groups are more specific than the earlier shorthand “permission/loading states”:

| ID | Native branch to capture | Trigger and states |
|---|---|---|
| N37 | Camera permission | The actual in-app camera action, if reachable. Inspect the implementation before choosing the capture route. Include the system request and app denial/recovery behavior where supported. Profile PhotosPicker alone is not a camera request. |
| N38 | Calendar permission | Enable reservation reminders through the real Calendar setup flow. Capture the actual iOS request and the resulting app state. |
| N39 | Save to Photos permission | Use the real share-ticket save flow. Capture the permission request and success/denial handling. Any photo-library write uses an isolated test library; no social post is published. |
| N68 | Account recovery | Capture “Your map is still here” with Retry, its permitted Continue offline variant, and “Sign in isn’t available.” Use controlled failures through the real entry coordinator. |

**Work:** add deterministic debug/test setup only where needed to reach a production screen. Trigger system dialogs through the app's actual APIs. Record the path into each branch, appearance, relevant state, device/OS and source copy. Replace a copy-only board entry with capture evidence only after observing it.

**Behavior requirements:** iOS-owned headings and buttons are transcribed from actual captures. Recovery keeps the account's data and unfinished identity requirements intact. Continue offline appears only when the existing coordinator permits it. These conditional features retain their current triggers and do not become extra mandatory signup steps.

**Done means:** each reachable group has verified light/dark native captures, exact copy and a reproducible trigger. Use a test device if a simulator cannot exercise a required path; if hardware or a reachable production trigger is unavailable, report that specific dependency and keep the card explicitly pending. A copied purpose string is not evidence of a displayed dialog.

## 3. Post-signup polish: profile → permissions → people → Map

**Outcome:** the existing native flow feels coherent and remains usable through empty, busy, failed, denied and successful states.

**Already built:** required photo/name/username, shared live profile preview, upload-failure gates, member search, individual Follow/Following, concise Contacts wording, native location/notification illustrations, and denial recovery. This pass polishes and verifies those implementations.

| Screen | Work and required states |
|---|---|
| N08 · Profile / N67 · Crop | Check empty and edited preview, photo selection, crop Cancel/Choose, replacement photo, invalid/taken/checking username, unreadable photo, saving, upload failure and retry. Name/handle/photo update the shared preview. Continue requires a valid identity and saved photo; failures retain the user's work. |
| N09 · Location / N31 · Denied | Check explanation, requesting, granted, denied and restricted states. Open Settings and Not now/Continue without location must lead somewhere usable. Retain the accepted denial wording. |
| N10 · Contacts / N36 · Purpose | Check the concise connection purpose, actual permission request and return to the app. Verify the next screen after allowing or denying. This pass covers the existing search/follow path; automatic address-book matching remains a separate feature dependency. |
| N11 · People / N33–N34 · Empty/error | Check initial loading, search typing/results/no results/error/retry, and per-row Follow → pending → Following or retry. Stale search responses cannot overwrite a newer query. Continue does not silently follow anyone. |
| N12 · Notifications / N32 · Denied | Check the native example-card sequence, real system request, existing authorization, denial, Settings return and the route onward to Map. Use the accepted denied-state copy. |

**Visual and motion requirements:** consistent current Astir typography, spacing and button treatment in light/dark mode; visible actions on a compact phone and with the keyboard open; readable inline errors; VoiceOver labels/order and Reduce Motion behavior. Check outgoing and incoming content together so transitions do not flash, disappear early, or leave overlapping layers. Retain the existing native component behavior when it already works.

**Copy rule:** current Swift wording is the baseline. Previously accepted denial/empty-state copy stays intact. Any proposed new wording is presented as an explicit alternative with its screen/line reference. The existing fictional activity and notification examples remain identified as samples in the review inventory.

**Done means:** a continuous native recording covers profile setup through arrival on Map; separate clips show crop, failure/retry, Follow and denied-permission branches. Main and compact layouts pass in both appearances. Regression checks verify the required-photo gate, username handling, follow state, permission recovery and preserved account-entry navigation. All new media is added to the existing review board with stable screen IDs and line-by-line copy.

## Delivery and boundaries

Execution order is 1 → 2 → 3. Capture the stabilized Map flow first, complete the missing conditional branches, then record the post-signup sequence and its edge states. Keep the existing opening review and earlier explorations available. Update TASKS.md, native-verification.md, source/media manifests and REC-529 with actual outcomes.

This spec does not select a new N25 quote, profile design alternative, notification material/colorway, or any remaining copy alternative. Contact matching/ranking, curated starter lists, Events/Plans, and the separate Feed/Lists/Plus contextual-hint pass are outside these three passes. Deployment and release are outside this work.

## Source evidence

Verified against the native review branch on September 17:

- `Wander/Features/Onboarding/FirstVisitWalkthrough.swift` — Map steps, contextual timing, eligible surfaces and closing baseline.
- `WanderUITests/OnboardingUITests.swift:697` — native Map sequence, ending, real-control exit and voluntary Plus tests.
- `native-onboarding-build/native-final-onboarding-ui.log` — earlier existing-Wanna editor and remove-confirmation failures; causes not yet established.
- `Wander/Features/Onboarding/OnboardingFlowView.swift` — profile preview, photo/crop, submission and permission screens.
- `Wander/Features/Onboarding/OnboardingFriendSuggestionsView.swift` and `OnboardingFriendSuggestionsModel.swift` — search/follow presentation and state.
- `Wander/App/AppEntryView.swift:123` — recovery and unavailable entry branches.
- `project.yml:95` and `native-copy.json` — permission purposes and the four uncaptured groups.

Paths above are relative to the native worktree unless they name review/build evidence. Native worktree: `/Users/joelipshutz/Documents/ChatGPT/New project/wander-native-onboarding-review`. Review room: `/Users/joelipshutz/Documents/ChatGPT/New project/onboarding-copy-review/session-2026-09-16`.
