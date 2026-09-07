# Compact Add sheet approval preview

Native SwiftUI design checkpoint for REC-446. Production AddScreen is unchanged.
The preview uses the production typography, colors, and row/button dimensions,
with sample places and a MapKit background. Import brand marks are placeholders.

The proposal removes the flexible spacer between Suggested and Import, uses a
16-point section gap, and measures content to set the resting detent. See more
keeps its 44-point minimum height and expands to `.large`. Back to add options
selects the measured resting detent. Production already uses this restoration
path through `clearInlineCandidateResults()` and `restingDetent`.

This harness is for visual approval; it does not run the production search,
import, or save services. The expanded results are illustrative. Production
integration and its regression suite follow design approval.

The optional `--roundtrip` launch argument invokes the same See more and Back
actions at six-second intervals for deterministic native presentation checking.

Validation: compiled directly with the iOS 26.5 Simulator SDK and rendered on
an iPhone 17 Pro simulator. `compact-initial.png` shows the content-sized sheet.
MapKit tiles were unavailable in that capture. A dedicated iPhone SE simulator
failed to launch the harness twice; small-phone validation remains outstanding.
No production test pass is claimed for this design-only checkpoint.

Decision needed: approve the tighter section spacing and reduced resting height
before integrating the layout into AddScreen. Keep the production See more
handler and Back-to-options restoration behavior intact during integration.
