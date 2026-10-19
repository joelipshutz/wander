# Contextual share previews (REC-647)

Build 184 supports the native Messages App Clip icon and View button. Its
publisher intentionally produces generic previews. This change adds explicit
owner-selected snapshots and public context for older profile/place links.

## Rollout

1. Apply `20261018185252_contextual_share_snapshots.sql` after the hosted
   rollback suite passes. The old `share_card_preview` response stays generic
   for build 184 compatibility; the new `share_card_context` reader supplies
   website content. Do not reopen the legacy buckets.
2. Deploy the companion astir-site change. Verify real HTML OG metadata, PNG
   retrieval and the unchanged `apple-itunes-app` banner for all five routes.
3. Ship the native publisher in a separately approved app build. In the app,
   explicitly share again to publish a selected preview. An old protected link
   never gains a snapshot retroactively.

## Acceptance

Use two accounts and fresh links. The link alone is the message attachment.
The preview title/artwork must describe the selected item, and View must still
open the same item through ordinary authorization.

| Share | Context to check |
| --- | --- |
| Own profile / Your Map | Discover the owner's world; selected map and avatar |
| Place | Place name, category/locality, selected photo or deliberate fallback |
| Check-in | Actor, place and visit date; selected imagery |
| Wanna | Actor/place and exact planned date, or “On …’s radar” |
| Saved map / list | Selected list name, owner and count; map or collage |
| Empty / one-place list | Empty state / single cover without broken slots |
| List invitation | Inviter and list context; correct Join destination |

Other people's protected activities/lists/maps remain generic. Already-public
profile and canonical-place details may be shown. Verify a readable foreign
protected item cannot publish a snapshot. Anonymous creation, foreign upload
paths and a mismatched token/route/kind must be rejected.

Retry a failed upload/finalization and confirm no link is handed off as if it
succeeded. Cancel or switch accounts during preparation and verify no link is
returned. Existing stored photos and legacy share images stay private.

A published snapshot is a deliberate copy; later source edits/privacy changes
do not rewrite it. Deleting its publisher or revoking/expiring/accepting an
invitation stops new preview resolution. Third-party copies may remain.

Apple controls Messages' layout, subtitle choice and cache. Keep key context in
`og:title` and verify a newly sent link on a physical iPhone; simulator app
captures and website HTTP tests are not proof of the final Messages rendering.
