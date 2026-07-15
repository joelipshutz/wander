# REC-90 Discover design room

Status: mock v1.1, awaiting Joe's visual approval. This package is a design artifact only. It does not authorize engineering implementation.

Open `index.html` through a local HTTP server so the vendored Pretext text-layout module can load:

```bash
cd preview/discover-redesign
python3 -m http.server 4173 --bind 127.0.0.1
```

Then open `http://127.0.0.1:4173/`.

## Main journeys

1. Places default with newest-first Activity and strong place recovery.
2. Empty Activity with the full Discover chrome still present: Places / People, search, and the four-tab navigation.
3. People suggestions with one trust reason, public profile context, and Follow.
4. People search with active-query replacement behavior.
5. Follow success that stays in place for the current appearance.
6. Updated Activity after the new authorized follow.
7. Strong place recovery using `Been` / `Wanna Go` and explicit foreground provenance.
8. Weak place recovery using `Pick Up Where You Left Off`, with no visit claim.
9. Public profile preview with no protected place names, counts, or categories.
10. Signed-out People auth gate with no anonymous lookup or personalized request.

## State boards

- Places: loading, empty, thin, cached offline, no-cache error, and no recovery evidence.
- People: loading, no suggestions, partial shelf failure, cached offline, search loading, and search empty/error.
- Social mutations: ready, in flight, success, rollback, dismissal/Undo, unfollow/access revocation, and hard block.
- Place recovery: strong/weak evidence, duplicate omission, save in flight/failure/success, dismissal/Undo.
- Responsive/accessibility: 320pt, large type, VoiceOver order, non-color state, Reduce Motion, and long/localized identity copy.

State boards are compact body-state comparisons, not full-screen compositions. Shared Discover chrome is intentionally cropped there; Journey 02 is the canonical full-screen Activity-empty state.

## Interaction notes

- Use the left rail to switch full-screen journeys and state boards.
- The `390pt` / `320pt` and `Type 1×` / `Type 1.32×` controls exercise width and type behavior.
- Follow and dismiss actions are clickable. Follow demonstrates in-flight and acknowledged states; dismiss demonstrates the Undo treatment.
- Text marked by the artifact is editable in place. Pretext recalculates minimum text height after edits and resizing.

## Sources of truth

- Product contract: `docs/specs/2026-07-13-rec-90-discover-redesign-product-spec.md`
- App design system: `DESIGN.md`
- Shared mock tokens: `preview/follow-profile-settings-mocks/tokens.css`
- Beli screenshots supplied by Joe in the REC-90 planning conversation.

Fictitious profile and place content in this artifact is preview-only. Production recommendations must use real, eligible, opted-in accounts.
