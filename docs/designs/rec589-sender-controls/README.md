# Native sender Silent review

These are Astir's real SwiftUI screens, rendered with isolated sample data.
[Open the native screenshot gallery](index.html) for every placement on both phone sizes.
Run the **Sender Silent Review** Xcode scheme on an iPhone Simulator to open the
interactive scenario gallery. The scheme uses DEBUG-only fixture routing; it
never uses the signed-in account or a remote write repository. Returning to a
scenario resets its sample state. Close a save form, then use **Back to scenarios**
to return to the gallery; import/list screens have the same return button.

For a single route, use launch arguments `-WanderSenderReview <route>`.
`-WanderSenderDark` selects dark appearance. Source:
`Wander/Features/Settings/SenderNotificationReviewHost.swift`.

## Placement decisions

| Scenario / route | Actual placement and interaction |
| --- | --- |
| First / repeat check-in (`checkIn`, `repeatCheckIn`) | Silent switch in the final form, outside More, below optional details and above audience. Initially off. Scroll to reach it on shorter screens. Save remains in the fixed footer. |
| Historical check-in (`historical`) | Same location, initially on. An explicit change overrides the date-derived default for this draft. |
| First / repeat Wanna (`wanna`, `repeatWanna`) | Same form location, initially off. Covers eligible source/list companion announcements; plain Wanna has no follower check-in alert. |
| Save from a person (`sourceSave`) | Same final-form switch; suppresses source attribution as well. |
| Discover quick Wanna (`discover`) | Native normal/silent confirmation at the final quick-save action. Dismissal cancels. On iOS 26 the native popover can dismiss by tapping outside. |
| One / many places to lists (`listPicker`, `multiListPicker`) | Silent lives in the fixed footer directly above Add. Its opaque background prevents scrolling list rows showing through. One choice applies to every membership and new-list save. |
| Direct list suggestions/search (`lists`) | Native Add / Add silently choice after selecting the direct action. Covers list-detail suggestions, Add Places suggestions, and search results. |
| Lists staged inside a save | The picker has no competing switch. Choose lists, return, and set Silent once in the parent form. |
| Existing content edit (`edit`) | No Silent control because changing a note/rating does not announce a new check-in. |
| Edit plus new lists (`editWithLists`) | Switch appears when new list memberships are staged; it governs those additions. |
| Shared-visit acceptance (`sharedVisit`) | Switch in the acceptance form before final Save. The mock verifies the submitted choice; authenticated SQL verifies the server transaction. |
| Explicit friends (`friends`) | Same switch with helper: invited people still receive invitations. |
| One / ten-place import (`importOne`, `importTen`) | Final Save opens the native three-action alert. Yes, save silently is the default; No, notify followers opts into one grouped announcement; Cancel saves nothing. No extra inline switch. |
| Later import save (`importConsumed`) | Existing intent remains consumed. No second alert or announcement. |
| Inline import details (`importDetails`) | No item-level Silent switch; outer import choice owns the policy. |

Silent changes notifications only. Audience, Feed, profile, and map access retain
their existing behavior. The form helper states this explicitly.

## Behavioral checks behind the mockups

`SenderNotificationFlowUITests` uses the production forms/coordinator and asserts
actual store results after saving. In particular: first three imports save three
silent individual visits and one Notify manifest; later seven increase visits to
ten while the same three manifest IDs remain frozen. Cancel creates neither a
save nor a ledger. Wanna-only first saves and consumed imports cannot announce
later. Other scenarios assert saved visit/source/list policy, parent inheritance,
and native submission at shared acceptance.

Visual coverage includes a large and compact phone, plus dark appearance and
accessibility text. Screenshots document layout; they do not prove APNs delivery.
See the [manual device tests](../../plans/rec589-sender-notification-testing.md)
and [engineering review](../../reviews/2026-09-23-rec589-engineering-review.md).
