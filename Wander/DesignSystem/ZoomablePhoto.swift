import SwiftUI

struct PhotoZoomState: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4

    private(set) var scale: CGFloat = minimumScale
    private(set) var offset: CGSize = .zero

    var isZoomed: Bool {
        scale > Self.minimumScale + 0.001
    }

    static func clampedScale(_ proposedScale: CGFloat) -> CGFloat {
        min(max(proposedScale, minimumScale), maximumScale)
    }

    func scale(applying magnification: CGFloat) -> CGFloat {
        Self.clampedScale(scale * magnification)
    }

    func offset(
        applying translation: CGSize,
        viewportSize: CGSize,
        scale displayedScale: CGFloat
    ) -> CGSize {
        Self.clampedOffset(
            CGSize(
                width: offset.width + translation.width,
                height: offset.height + translation.height
            ),
            viewportSize: viewportSize,
            scale: displayedScale
        )
    }

    mutating func finishMagnification(_ magnification: CGFloat, viewportSize: CGSize) {
        scale = scale(applying: magnification)
        offset = Self.clampedOffset(offset, viewportSize: viewportSize, scale: scale)
        resetIfNeeded()
    }

    mutating func finishDrag(_ translation: CGSize, viewportSize: CGSize) {
        guard isZoomed else {
            offset = .zero
            return
        }
        offset = offset(
            applying: translation,
            viewportSize: viewportSize,
            scale: scale
        )
    }

    mutating func toggleZoom(viewportSize: CGSize) {
        if isZoomed {
            reset()
        } else {
            scale = 2
            offset = Self.clampedOffset(offset, viewportSize: viewportSize, scale: scale)
        }
    }

    mutating func zoomIn(viewportSize: CGSize) {
        scale = Self.clampedScale(scale + 1)
        offset = Self.clampedOffset(offset, viewportSize: viewportSize, scale: scale)
    }

    mutating func zoomOut(viewportSize: CGSize) {
        scale = Self.clampedScale(scale - 1)
        offset = Self.clampedOffset(offset, viewportSize: viewportSize, scale: scale)
        resetIfNeeded()
    }

    mutating func reset() {
        scale = Self.minimumScale
        offset = .zero
    }

    private mutating func resetIfNeeded() {
        if !isZoomed {
            reset()
        }
    }

    private static func clampedOffset(
        _ proposedOffset: CGSize,
        viewportSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        guard scale > minimumScale else { return .zero }

        let horizontalLimit = max(0, viewportSize.width * (scale - minimumScale) / 2)
        let verticalLimit = max(0, viewportSize.height * (scale - minimumScale) / 2)
        return CGSize(
            width: min(max(proposedOffset.width, -horizontalLimit), horizontalLimit),
            height: min(max(proposedOffset.height, -verticalLimit), verticalLimit)
        )
    }
}

struct ZoomablePhoto<Content: View>: View {
    private let content: Content

    @State private var zoom = PhotoZoomState()
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let displayedScale = zoom.scale(applying: magnification)
            let displayedOffset = zoom.offset(
                applying: dragTranslation,
                viewportSize: proxy.size,
                scale: displayedScale
            )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(displayedScale)
                .offset(displayedOffset)
                .contentShape(Rectangle())
                .clipped()
                .simultaneousGesture(magnificationGesture(viewportSize: proxy.size))
                .highPriorityGesture(
                    dragGesture(viewportSize: proxy.size),
                    including: zoom.isZoomed ? .all : .none
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy(duration: 0.24)) {
                        zoom.toggleZoom(viewportSize: proxy.size)
                    }
                }
                .accessibilityHint("Pinch or double-tap to zoom")
                .accessibilityValue("\(Int(displayedScale * 100)) percent")
                .accessibilityAction(named: "Zoom in") {
                    withAnimation(.snappy(duration: 0.24)) {
                        zoom.zoomIn(viewportSize: proxy.size)
                    }
                }
                .accessibilityAction(named: "Zoom out") {
                    withAnimation(.snappy(duration: 0.24)) {
                        zoom.zoomOut(viewportSize: proxy.size)
                    }
                }
        }
    }

    private func magnificationGesture(viewportSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($magnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoom.finishMagnification(value, viewportSize: viewportSize)
            }
    }

    private func dragGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                zoom.finishDrag(value.translation, viewportSize: viewportSize)
            }
    }
}
