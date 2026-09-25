import SwiftUI

#if canImport(PostHog)
import PostHog
#endif

extension View {
    /// Only for individual non-credential inputs approved for readable replay.
    /// Never apply to a container that can contain passwords or sign-in codes.
    @ViewBuilder
    func sessionReplayVisibleInput() -> some View {
        #if canImport(PostHog)
        self.postHogNoMask()
        #else
        self
        #endif
    }

    /// Explicit credential masking remains in place when ordinary app content
    /// is readable. Never apply a no-mask override to an authentication container.
    @ViewBuilder
    func sessionReplayMasked() -> some View {
        #if canImport(PostHog)
        self.postHogMask()
        #else
        self
        #endif
    }
}
