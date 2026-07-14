# REC-89 iOS Design Review

Date: 2026-07-13
Branch: `codex/rec-89-profile-redesign`
Scope: current Profile and Settings surfaces plus the six supplied Beli references

## Review Method

The paired iPhone 15 Pro was listed as unavailable and this checkout intentionally has no debug-only `DebugBridge` / `StateServer` wiring. The review therefore uses the current SwiftUI source, rec.me `DESIGN.md`, the supplied reference screenshots, and the existing launch-argument mockup harness. Real-device interaction review remains a later validation step; no QA instrumentation was added to this design branch.

Reference screenshots:

- `/Users/ryanlieblein/Library/Messages/Attachments/0d/13/9FB6F886-9C0A-4854-81BE-31B88DFC2EE1/Screenshot 2026-07-13 at 13.41.05.png`
- `/Users/ryanlieblein/Library/Messages/Attachments/77/07/794959CD-776D-4BD1-A874-8FF237317C44/IMG_8364.png`
- `/Users/ryanlieblein/Library/Messages/Attachments/ee/14/9C20B2C7-DC56-4195-8B2A-04D92B0DA9B3/IMG_8363.PNG`
- `/Users/ryanlieblein/Library/Messages/Attachments/72/02/CFED8BEE-A621-4F18-9AD3-1B91CBD07B34/Screenshot 2026-07-13 at 13.56.34.png`
- `/Users/ryanlieblein/Library/Messages/Attachments/b7/07/73996A9B-ECCB-429C-92EA-E5715A8C8CB1/Screenshot 2026-07-13 at 14.19.24.png`
- `/Users/ryanlieblein/Library/Messages/Attachments/c4/04/F7E9EB08-F05D-44C2-ADC6-C1AFFECA30FE/Screenshot 2026-07-13 at 14.19.10.png`

## Current Profile Scores

| Dimension | Score | What would make it a 10 |
|---|---:|---|
| Typography hierarchy | 6/10 | Keep the 30pt rounded page title, use a clear 24pt owner name, remove 12pt body copy, and separate identity, stats, history, and geography with consistent section headings. |
| Spacing rhythm | 6/10 | Preserve the 4/8pt token grid but remove nested card-on-card composition and give the identity header a stable, centered vertical rhythm. |
| Color hierarchy | 7/10 | Keep rec.me warm canvas, bone surfaces, terracotta actions, sage Been, and sun Wanna. Use color to encode states, not as decoration. |
| Touch targets | 7/10 | Increase 40pt icon controls to at least 44pt and make each social count a full-width button target. |
| Loading, empty, error states | 5/10 | Add explicit loading/error/empty states for graph lists, calendar, and dining summaries. The current graph list can render as a blank list. |
| Accessibility | 6/10 | Remove 12pt body text, keep VoiceOver labels on icon actions, announce selected tabs/month, and verify Dynamic Type through XXL without clipped stat labels. |
| Animation discipline | 8/10 | Keep short menu transitions and use restrained month/tab transitions with Reduce Motion support. |
| iOS idiom alignment | 6/10 | Use `NavigationStack`, `ShareLink`, searchable lists, native alerts, and navigation destinations. Avoid turning Profile into a custom web dashboard. |
| Information density | 4/10 | Remove This Month, Drafts, Recent, and People. Keep the first viewport focused on identity, social graph, and Been/Wanna. |
| AI-slop check | 7/10 | Retain rec.me's specific map-first visual language and avoid generic gradient dashboards, giant marketing copy, or excessive floating cards. |

Biggest leverage fix: replace `ownerHeader + monthCard + draftsSection + recentSection + peopleSection` with one identity-first profile flow, then move history and geography into two full-width sections below the unchanged Been/Wanna tiles.

## Current Settings Scores

| Dimension | Score | What would make it a 10 |
|---|---:|---|
| Typography hierarchy | 6/10 | Use 17pt section labels and 15-17pt rows; reserve 12-13pt for supporting copy only. |
| Spacing rhythm | 7/10 | Keep token spacing but replace unrelated stacked cards with grouped navigation sections and clear dividers. |
| Color hierarchy | 7/10 | Keep the warm theme, reserve red for sign-out/delete, and keep privacy actions visually neutral until destructive confirmation. |
| Touch targets | 8/10 | Make every settings row at least 52pt and keep switches/buttons at least 44pt. |
| Loading, empty, error states | 7/10 | Preserve account loading/error handling and add recoverable progress/error states for account changes and deletion. |
| Accessibility | 6/10 | Give detail rows explicit values and hints, ensure warning copy scales, and avoid relying on muted color alone. |
| Animation discipline | 9/10 | Native navigation and alerts are sufficient; no custom animation is needed. |
| iOS idiom alignment | 5/10 | Move Privacy & Trust and Blocked & Muted into pushed destinations instead of nested sheets, and use native two-step destructive alerts. |
| Information density | 5/10 | Keep the settings home scannable: account security, privacy/trust, blocked/muted, notifications/data, sign out, delete account. |
| AI-slop check | 7/10 | Use compact native rows and rec.me tokens rather than oversized illustrative cards. |

Biggest leverage fix: make Settings a navigation hub. Privacy controls and blocked accounts belong on dedicated pages; account deletion belongs at the bottom with two explicit confirmations.

## Reference Adaptation

Reuse from Beli:

- Large centered profile photo and identity-first hierarchy.
- Member-since metadata, social counts, edit/share affordances.
- Compact calendar summary with marked visit dates.
- Non-interactive geographic summary followed by segmented breakdowns.
- Direct edit-profile field list.
- Clear blocked/muted empty-state hierarchy.

Do not copy:

- White-only palette; rec.me keeps the warm canvas and bone surfaces.
- Five-tab/navigation model; rec.me keeps its existing tab contract.
- Gray low-contrast metadata and tiny body copy.
- Hamburger navigation; Profile keeps direct edit, share, and settings icons.
- Beli-specific Rank, streak, goals, school, social links, and account-settings placement.
- Giant custom empty-state illustration; rec.me uses a compact SF Symbol composition that scales and remains accessible.

## Mockup Acceptance Bar

- Profile first viewport shows `profile`, the member name, edit/share/settings icons, a 120-132pt avatar, metadata, Followers/Following/Friends, and unchanged Been/Wanna tiles.
- Calendar is a real month grid built from deterministic visit dates; Been visits receive a dining underlay and Wanna saves never do.
- Map is fixed and non-interactive, plots Been saves only, and has Places/Cities/Countries summaries.
- Social graph has three tabs, search, a Find Friends action, populated rows, and an intentional zero-state.
- Edit Profile contains only photo, name, username, home city, and bio.
- Settings home links to account security, Privacy & Trust, and Blocked & Muted; destructive deletion uses two native confirmations.
- Privacy & Trust begins with Private Profile and stealth mode for new saves.
- Blocked & Muted has two tabs, populated states, and the requested empty-state copy.
- All mockups support safe areas, 44pt targets, VoiceOver labels, and Dynamic Type through XXL.

## Status

`DONE_WITH_CONCERNS`: static/source review completed. Live-device scoring is blocked by unavailable hardware and absent debug bridge instrumentation; simulator captures will be produced for the REC-89 mockup pages.

## Simulator Validation Addendum

The complete approval set was rendered and visually inspected on both an iPhone 17 Pro and the smaller iPhone 17e using deterministic 9:41 status-bar state. The 14 reviewed pages are:

- Owner profile, dedicated calendar review, and dedicated dining-map review
- Populated and empty Followers / Following / Friends views
- Edit Profile, Settings, and Privacy & Trust
- Populated and empty Blocked Accounts views
- Populated and empty Muted Accounts views
- First and final native account-deletion confirmations

The small-device pass confirmed that the owner actions remain tappable, the calendar heading wraps without collision, graph tabs and search remain legible, edit-profile values do not truncate, settings rows and destructive actions stay reachable, and all requested empty-state copy fits without overlap. The native alerts fit at both sizes.

Two defects were found and fixed during capture: repeated weekday symbols initially used duplicate SwiftUI identities, and the first dining-map camera region hid most fixture annotations. The final calendar uses stable enumerated identities; the final fixed, noninteractive map shows all five Been-only fixture locations. No production navigation, persistence, or backend behavior was exercised or changed.

`DONE_WITH_CONCERNS` remains the final status because physical-device and Dynamic Type XXL validation still require available hardware. The simulator acceptance bar is met on both reviewed phone sizes.
