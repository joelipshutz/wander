# Review Astir Live

REC-636 · **Review implementation; physical feedback pending**

**Start with [October feedback coverage and the revised testing instructions](review-feedback-2026-10.md).** That document supersedes the earlier UI script and conflicting interaction descriptions in the original specification/plan. It covers every A–F request, the later beyond-filter pagination decision, changed-only R checks, accessibility A1–A8, private messaging M1–M10 and the three retained manual stress cases. Blank outcomes are not passes.

Use [REC-636](https://linear.app/recme/issue/REC-636) and [PR #736](https://github.com/joelipshutz/wander/pull/736) for the exact published candidate, build, installation/Xcode handoff and actual completed checks. **Wait for the ready handoff and Ryan's prompt before starting.** Do not restart the stopped broad validation sequence or repeat the completed drawing/basic-tab/unchanged Feed/Profile checks.

## Current behavior

- **Live / Lists / Profile** remain the three tabs. Profile retains Your Map, Patterns, history and calendar; only area drawing is reused in Live. Messages is now beside Notifications in the owner Profile header. Contextual replies remain attached to activity.
- **Following / Nearby** use bold Signal styling when selected. Nearby directly applies 10 km: an already-authorized current location can refine the initial map/home-center fallback. It does not open Filters or request a new location permission. Filters retain explicit 5/10/25 km choices, existing audience, type, time, category and person controls; Reset is at the top and the activity choice is **All**.
- **Map search** stages after a pan and commits only when Search this area is tapped. The glass button is visible only in full-map mode, and the rectangular search boundary is removed. Camera movement alone does not replace the committed map/count query.
- **Feed history** loads selected-filter results, then older matching activity after **Showing older activity**. After those results, small print warns that the next posts are outside the selected discovery filters, followed by **Showing all activity** and broader authorized posts. This explicit Feed expansion does not change the committed map/count selection or broaden privacy permissions. Existing cards, grouping, engagement actions and supporting modules remain.
- **Drawer and return** use the compact centered **N place update(s)** count with a small time-range label. It describes loaded matching activity, not an exact server total or unique-place total. Full Feed has a floating **Map** button. Cold start and ordinary destination returns use half map/half Feed; an actually scrolled Feed can restore its position within 30 minutes.
- **Pins and preview** distinguish check-ins, Wannas and list additions. Crowded pins become individual dots; viewed pins mute for 24 hours. Selecting a pin replaces Feed with the photo-led preview, recent filtered activity, compact rating/hours/category and Save/Share/List/Close actions. Card/drawer dismissal and map dragging follow the camera rules in the revised guide.
- **Place actions** reuse the recently chosen/created list for 30 minutes and offer a named toast with Change. Plans is first in the full place-profile action row and uses the existing invitation composer with ranked mutual friends. Opening a picker/composer does not send anything.

The 24-hour/30-minute intervals are explicit Astir review defaults, not universal platform standards. Keep the established 15-minute social Live display lease, account boundaries and Profile/shared-cache behavior. Live remains globally Off; internal review does not authorize global activation, merge or release.

## Open the integrated review

1. Open the isolated review branch's `Wander.xcodeproj`; verify the branch in Xcode rather than switching another checkout.
2. For the simulator-only demonstration, select **Live Experience Review** and an available iPhone Simulator. The shared scheme runs the normal `Wander` target with explicit review fixtures.
3. For fixture messages, open **Profile → Messages**. The UI must say **Demo messages · nothing is delivered** and label acknowledgments **Simulated**. This does not demonstrate real delivery or hosted authorization.
4. For physical review, use the exact installed candidate and normal designated account recorded in the handoff. Remain on the first account until a guided switch. Real messaging additionally waits for a fresh isolated fixture and admitted sessions; do not reuse the aborted trial.

The scheme is defined in `project.yml` and its generated shared scheme. It does not replace the registered feature-flag platform or override an explicit Off in ordinary use. Backend installation and its earlier verification remain separately recorded; this guide does not repeat them or mark the new device cases complete.

## Records and remaining limits

- [October feedback coverage](review-feedback-2026-10.md) is the current interaction contract and manual script. It preserves the three unresolved cases and diagnostic gap explicitly; manual functional confirmation does not supply missing internal measurements.
- [Product specification](product-spec.md) and [engineering plan](engineering-plan.md) retain the underlying architecture, privacy and migration contracts. Their older UI descriptions are superseded where the October feedback revision says otherwise.
- [Integrated validation](review/integrated-validation.md), [integrated captures](review/integrated-captures.md), [earlier validation](review/validation.md) and [prototype captures](review/captures.md) are source-specific historical evidence. They do not become results for this candidate by being linked here.
- Review readiness, real-account messaging, performance/replay evidence and release readiness remain separate conclusions. No merge, global activation or release is part of this feedback handoff.
