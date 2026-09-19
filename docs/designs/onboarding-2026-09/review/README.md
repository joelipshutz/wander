# Astir onboarding copy review · Joe + Ryan

Open `index.html` in a browser. The standalone HTML embeds screenshots and approved brand originals and works offline. The session preview is http://127.0.0.1:8766/ while its local server is running.

- Drag to pan; scroll to pan; pinch or Ctrl + scroll to zoom.
- Use the outline to jump to a screen, or Present for the TV layout. Left/right move between screens; up/down move between copy lines; Escape returns to the canvas.
- Say the screen ID and line number while recording. Existing screen IDs remain stable; opening/loading are N69–N70 and additional identity-state captures are N71–N73.
- Click copy to add drafts and notes. Browser storage keeps these locally; Export review downloads the baseline and changes. Editing text does not alter native screenshots.
- Send the transcript and exported review back to this task for copy revisions.

## Coverage

46 current screens and conditional states have images. 27 retained, disabled NUX lessons remain as clearly marked source-reference cards. Total: 73 cards and 284 numbered copy lines.

The board includes opening/loading, all three welcome stories, account creation and sign-in, verification, profile and photo crop, location/contacts/friends/notifications, the first-save walkthrough including tags, return-visit import and device-feature lessons, contextual prompts, and conditional/system/recovery states. These conditional states are branches, not all mandatory signup steps. Feature-flag availability can vary by account.

29 image placements are captures of the existing native build 174 app. The remaining 17 are labeled native component previews or native system-dialog previews. The isolated component harness uses current Swift view code with fixed local data and no account/backend integration. Sample people are fictional. System dialogs use the current app purpose strings in an isolated preview app; their surroundings are neutral. Opening/loading images are native component references from the current approved asset package.

The tag coach is clipped at the bottom in the captured native simulator layout. Its full source copy appears alongside the screenshot. This is documented rather than silently changing the app image. The friends primary card now shows a successful demo selection; the actual loading-failure capture remains under its own conditional state.

`capture-manifest.json` records image hashes, capture kind, and source commit. `content.json` is the editable copy model; `copy-baseline.md` preserves transcript references. No production app source, accounts, or backend settings were changed.

## Brand shelf

The brand assets remain beneath the flow, with a Brand assets shortcut. The shelf contains the approved wordmark (PNG/SVG), app/profile icons, static splash artwork/references, three color swatches, and six App Store panels from the September 16 approved package. Download links preserve original bytes. Place on board adds a movable reference beside the selected screen; placements persist in browser storage. Source photo, Photoshop, and production kit links point to the existing Drive folder.

## Validation

All current cards have a matched image path, IDs are unique, and the packed document contains all images. New native captures were inspected, system-dialog text was checked, and original brand downloads were verified byte-for-byte. Canvas navigation and TV presentation were exercised after the update. Original copy-edit storage is preserved.
