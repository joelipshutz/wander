# Planning validation

September 21, 2026 · REC-566 · Source baseline `fb1bad2`

Completed in this planning pass:

- Reviewed current invitation SQL/RPCs, local acceptance, visibility predicates, activity grouping, engagement, deletion, existing tests and related REC-88/REC-493 contracts.
- Verified the isolated Astir account/project and ran only the aggregate SELECTs recorded in `read-only-audit.sql`. No production content or schema writes.
- Used an independent read-only Codex reviewer, then a consistency follow-up. Incorporated parent-metadata preservation, commenter consent, legacy mutation gates, secure replay, nonowner blocking, reinvitation, standalone engagement and surviving-source identity findings.
- Wrote 85 uniquely identified implementation acceptance cases and five implementation tasks. Checked local document links, task JSONL, referenced file paths and review-report ending.
- Updated the fictional interactive preview and visually inspected Joe-first profile contribution ordering at 736px, ten-person Joe activity at 360px in light and dark, the audience explanation, comment notice, 1–5 rating range, and blank acceptance editor. The final dark preview reported no browser console errors.
- Corrected an audience-label icon alignment issue found in the 736px screenshot. Rechecked the resulting 360px layout in light and dark.
- `git diff --check` passed. Only documentation is changed in the planning branch.

The prior preview pass also exercised shared comment addition across profile views, own note/rating edits, ten-person expansion, empty acceptance and decline. The preview has no server connection and does not simulate production authorization or lifecycle mutations.

The 85-case implementation matrix is **not executed yet**. No native build, native UI test, new SQL contract test, concurrent database test, performance measurement, migration rehearsal or production rollout was performed. Those are required after implementation; see `test-plan.md`.

## Engineering refresh requested before implementation

Refreshed against current main `8890e5a`; the planning branch includes that main update. The new `implementation-blueprint.md` identifies the exact schema, RPC boundaries, native files, sync/publication sequence, profile integration, error behavior, batch reads and test/deployment checkpoints.

Code inspection refined the canonical identity: a new group gets its own event in the existing event table while every personal visit keeps its own event. This removes the initial retire-and-replace source-event approach. The existing v1 operation ledger stays unchanged because its accept-only constraint and per-generation uniqueness cannot safely represent repeated group-management operations; a narrow v2 request ledger handles those retries.

The refresh also identifies first-publication atomicity in `syncVisit`/the invitation queue, the separate profile activity renderer, retained staged text/media loading, author-owned comment deletion after lost thread access and the isolated-account rollback-only smoke command path. Local links, review report endings and all 85 unique case IDs were checked. No new preview, app code or production data was changed in this refresh.
