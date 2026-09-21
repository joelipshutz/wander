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
