# Compact native onboarding QA

## Final-build visual pass — September 17, 2026

Installed the final local app from `native-onboarding-build/Build/Products/Debug-iphonesimulator/Wander.app` on **only** compact simulator `7BE74040-8A1F-40AF-994D-7EBDD9E17194`. The simulator was booted for this pass. The built Info.plist contains the new N36 purpose: **“Astir uses your contacts to help you connect with people you know.”** This confirms the bundled string, not the as-yet-separate system-dialog capture.

The four files below are direct native simulator screenshots, 1170 × 2532 pixels, visually inspected after capture. They were taken with `capture_native.py --device 7BE74040-8A1F-40AF-994D-7EBDD9E17194 --wait 25`. No phone UI was reconstructed and no image pixels were edited.

| Capture | Final visual finding |
| --- | --- |
| [N04-compact.png](N04-compact.png) | **Pass.** Approved logo is legible against its dark backdrop. Full account headline, body, Apple/Google buttons, email form, legal links and Log in fit without clipping or overlap. |
| [N10-compact.png](N10-compact.png) | **Pass.** Exact new “Connect with your people” headline and “Use your contacts to connect with people you know.” body are visible. No old disclosure bullets appear. Both lines wrap cleanly; the neutral Continue footer is fully visible. |
| [M01-compact.png](M01-compact.png) | **Pass.** Complete Featured coach title/body and Next arrow fit. Actual Map filters, search, + and bottom navigation remain readable. Visible native UIKit coffee pins render category symbols inside their blue/orange rings; no boxed placeholder glyphs appear. |
| [N25-compact.png](N25-compact.png) | **Pass.** Full two-line title, quote, attribution, closing copy and Skip action fit inside the native finale card. No quote/body truncation or overlapping action. The actual Map and native category pin remain underneath. This is the retained baseline ending, not approval of a new ending. |

Map captures use an explicitly **simulated sample location** (`34.075, -118.285`) and the existing demo fixtures. Location permission was granted only to `com.grayline.wander` on this compact simulator. These captures do not represent the user’s real location. `-WanderHoldWalkthroughStep` holds M01/N25 for reading; this still-image check does not measure automatic motion timing.

### Capture provenance

| ID | Recorded capture time | Dimensions | SHA-256 |
| --- | --- | --- | --- |
| N04 | 2026-09-17T09:33:52-0700 | 1170 × 2532 | `45d0834ff2b716c0d274455ebbea4f63534caf37ebd2862598392e56c06b07c1` |
| N10 | 2026-09-17T09:34:19-0700 | 1170 × 2532 | `054598d037ede131896271ef39970d09918ced9605eb79a355af4e03b56d69a6` |
| M01 | 2026-09-17T09:35:00-0700 | 1170 × 2532 | `13fa5d9200d5408d05a06e32dcffb772378048580a30b445d39052c43b909be3` |
| N25 | 2026-09-17T09:35:26-0700 | 1170 × 2532 | `e4f8afa97fa11a3c617916cc00ad05681d38c56eb714a578ca0dacce7464e8cc` |

The main recording simulator and separate UI-test simulator were not operated or changed by this pass. No app source was edited.

## Earlier visual coverage retained

The prior pass inspected W01/W02, N08/N09/N11 and N12 compact states, plus N08/N12 in dark appearance. Those files were not replaced in this final four-screen pass. Root confirmed N12 dark remains valid because its source is unchanged. The earlier signup contrast concern is closed by the new N04 capture above; the UIKit Map glyph concern is visually closed for the visible M01/N25 compact pins.

N12 repeat captures require the existing `-WanderBypassProductUpsellFrequencyCap` debug argument; production eligibility remains unchanged. The board must label notification names and member/example content as sample data.

## Scope of verification

This pass establishes native visual layout and legibility at the compact simulator’s default text size. It does not claim a new full test-suite pass, external-provider login, system permission button interaction, screen-reader order, Dynamic Type coverage, or animation timing. Those checks have separate evidence and remain tracked in `../native-verification.md`.
