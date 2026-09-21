import SwiftUI

#if canImport(PostHog)
import PostHog
#endif

extension View {
    /// Map tiles can expose locations without any text or image view for the
    /// SDK's automatic masking to find. Exclude the complete rendered surface.
    @ViewBuilder
    func sessionReplayMasked() -> some View {
        #if canImport(PostHog)
        self.postHogMask()
        #else
        self
        #endif
    }
}
