# REC-224 invite mockups

This first milestone turns the attached "Add members" recording into a reusable
rec.me SwiftUI pattern. The check-in Friends picker uses the real entry point;
Feed People and list collaborators remain reviewable mock surfaces while native
Contacts, matching, deep-link, and share plumbing are still to come.

## Direction to review

- Keep the invite entry point directly between search and the existing-person
  list in check-in Friends, Feed People, and list collaborators.
- Use one contact picker with surface-specific copy rather than three divergent
  flows.
- Identify contacts who already use rec.me, while preserving the acceptance
  contract: nobody is added or attributed until they accept.
- Ask for Contacts access only after a branded primer, and retain a share-link
  fallback when access is denied.
- Never place contact names, phone numbers, resource ids, or address-book data
  in analytics.

## Gallery

| Check-in entry | Feed People entry | List collaborator entry |
| --- | --- | --- |
| ![Check-in entry](checkInEntry.png) | ![Feed People entry](feedPeopleEntry.png) | ![List collaborator entry](listCollaboratorEntry.png) |

| Permission primer | Contact picker | Selected contacts |
| --- | --- | --- |
| ![Permission primer](permission.png) | ![Contact picker](contacts.png) | ![Selected contacts](selected.png) |

| Permission denied | Invite handoff |
| --- | --- |
| ![Permission denied](denied.png) | ![Invite handoff](success.png) |

Compact-screen checks are captured in `checkInEntry-small.png` and
`contacts-small.png`.

## Debug routes

Launch with `-WanderInviteMockup <page>`, where `<page>` is one of:

`checkInEntry`, `feedPeopleEntry`, `listCollaboratorEntry`, `permission`,
`contacts`, `selected`, `empty`, `denied`, or `success`.

## Intentionally not wired yet

- `CNContactStore` authorization and contact loading
- privacy-preserving phone/email normalization and rec.me account matching
- native share-sheet result and cancellation handling
- scoped invite tokens, deferred deep links, and acceptance reconciliation
- Feed People and list-collaborator production entry-point integration
- PII-free funnel analytics
