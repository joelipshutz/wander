import SwiftUI

/// Keeps the normal full-screen map available in every build. Content closures
/// stay lazy so an inactive fixture creates no additional map view.
@MainActor
struct YourMapWorkspace<FullScreen: View, Header: View, Canvas: View, EmptyState: View, Footer: View>: View {
    private let fullScreen: () -> FullScreen

    #if DEBUG
    @Environment(\.adaptiveMapFixtureUsesPhysicalViewport) private var usesPhysicalViewport
    private let header: () -> Header
    private let mapCanvas: () -> Canvas
    private let showsEmptyState: () -> Bool
    private let emptyState: () -> EmptyState
    private let footer: () -> Footer
    #endif

    init(
        @ViewBuilder fullScreen: @escaping () -> FullScreen,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder mapCanvas: @escaping () -> Canvas,
        showsEmptyState: @escaping () -> Bool,
        @ViewBuilder emptyState: @escaping () -> EmptyState,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.fullScreen = fullScreen
        #if DEBUG
        self.header = header
        self.mapCanvas = mapCanvas
        self.showsEmptyState = showsEmptyState
        self.emptyState = emptyState
        self.footer = footer
        #endif
    }

    @ViewBuilder
    var body: some View {
        #if DEBUG
        if usesPhysicalViewport {
            // The disposable density fixture has a real native Map viewport;
            // its renderer, annotations and camera requests remain unchanged.
            VStack(spacing: 12) {
                header()
                mapCanvas()
                    .overlay {
                        if showsEmptyState() { emptyState() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                footer()
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing4)
            }
        } else {
            fullScreen()
        }
        #else
        fullScreen()
        #endif
    }
}

#if DEBUG
// Only the disposable density fixture opts in. Release has no fixture key.
private struct AdaptiveMapFixturePhysicalViewportKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var adaptiveMapFixtureUsesPhysicalViewport: Bool {
        get { self[AdaptiveMapFixturePhysicalViewportKey.self] }
        set { self[AdaptiveMapFixturePhysicalViewportKey.self] = newValue }
    }
}
#endif
