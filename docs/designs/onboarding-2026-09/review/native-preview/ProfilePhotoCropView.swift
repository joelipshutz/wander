import SwiftUI
import UIKit

struct ProfilePhotoCropState: Equatable {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4

    private(set) var scale: CGFloat = minimumScale
    private(set) var offset: CGSize = .zero

    func scale(applying magnification: CGFloat) -> CGFloat {
        Self.clampedScale(scale * magnification)
    }

    func offset(
        applying translation: CGSize,
        imageSize: CGSize,
        viewportSize: CGSize,
        scale displayedScale: CGFloat
    ) -> CGSize {
        Self.clampedOffset(
            CGSize(
                width: offset.width + translation.width,
                height: offset.height + translation.height
            ),
            imageSize: imageSize,
            viewportSize: viewportSize,
            scale: displayedScale
        )
    }

    mutating func finishMagnification(
        _ magnification: CGFloat,
        imageSize: CGSize,
        viewportSize: CGSize
    ) {
        scale = scale(applying: magnification)
        offset = Self.clampedOffset(
            offset,
            imageSize: imageSize,
            viewportSize: viewportSize,
            scale: scale
        )
    }

    mutating func finishDrag(
        _ translation: CGSize,
        imageSize: CGSize,
        viewportSize: CGSize
    ) {
        offset = offset(
            applying: translation,
            imageSize: imageSize,
            viewportSize: viewportSize,
            scale: scale
        )
    }

    mutating func setScale(
        _ proposedScale: CGFloat,
        imageSize: CGSize,
        viewportSize: CGSize
    ) {
        scale = Self.clampedScale(proposedScale)
        offset = Self.clampedOffset(
            offset,
            imageSize: imageSize,
            viewportSize: viewportSize,
            scale: scale
        )
    }

    func sourceCropRect(imageSize: CGSize, viewportSize: CGSize) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              viewportSize.width > 0,
              viewportSize.height > 0
        else { return .zero }

        let baseScale = Self.aspectFillScale(imageSize: imageSize, viewportSize: viewportSize)
        let effectiveScale = baseScale * scale
        let cropSize = CGSize(
            width: viewportSize.width / effectiveScale,
            height: viewportSize.height / effectiveScale
        )
        let centeredOrigin = CGPoint(
            x: (imageSize.width - cropSize.width) / 2,
            y: (imageSize.height - cropSize.height) / 2
        )
        let proposedOrigin = CGPoint(
            x: centeredOrigin.x - (offset.width / effectiveScale),
            y: centeredOrigin.y - (offset.height / effectiveScale)
        )
        let maximumOrigin = CGPoint(
            x: max(0, imageSize.width - cropSize.width),
            y: max(0, imageSize.height - cropSize.height)
        )

        return CGRect(
            x: min(max(proposedOrigin.x, 0), maximumOrigin.x),
            y: min(max(proposedOrigin.y, 0), maximumOrigin.y),
            width: min(cropSize.width, imageSize.width),
            height: min(cropSize.height, imageSize.height)
        )
    }

    static func aspectFillScale(imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(
            viewportSize.width / imageSize.width,
            viewportSize.height / imageSize.height
        )
    }

    static func clampedScale(_ proposedScale: CGFloat) -> CGFloat {
        min(max(proposedScale, minimumScale), maximumScale)
    }

    private static func clampedOffset(
        _ proposedOffset: CGSize,
        imageSize: CGSize,
        viewportSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let baseScale = aspectFillScale(imageSize: imageSize, viewportSize: viewportSize)
        let displayedSize = CGSize(
            width: imageSize.width * baseScale * scale,
            height: imageSize.height * baseScale * scale
        )
        let horizontalLimit = max(0, (displayedSize.width - viewportSize.width) / 2)
        let verticalLimit = max(0, (displayedSize.height - viewportSize.height) / 2)

        return CGSize(
            width: min(max(proposedOffset.width, -horizontalLimit), horizontalLimit),
            height: min(max(proposedOffset.height, -verticalLimit), verticalLimit)
        )
    }
}

struct ProfilePhotoCropSelection: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ProfilePhotoCropView: View {
    let image: UIImage
    let cancel: () -> Void
    let choose: (Data, UIImage) -> Void

    @State private var crop = ProfilePhotoCropState()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let side = max(220, min(proxy.size.width - 32, proxy.size.height * 0.50))
            let viewportSize = CGSize(width: side, height: side)

            VStack(spacing: 0) {
                header(viewportSize: viewportSize)

                Spacer(minLength: WanderTheme.spacing4)

                cropCanvas(viewportSize: viewportSize)
                    .frame(width: side, height: side)

                Text("Pinch to zoom. Drag to reposition.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, WanderTheme.spacing6)

                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "minus")
                    Slider(
                        value: Binding(
                            get: { crop.scale },
                            set: {
                                crop.setScale(
                                    $0,
                                    imageSize: image.size,
                                    viewportSize: viewportSize
                                )
                            }
                        ),
                        in: ProfilePhotoCropState.minimumScale...ProfilePhotoCropState.maximumScale
                    )
                    .tint(WanderTheme.terracotta.color)
                    Image(systemName: "plus")
                }
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white.opacity(0.84))
                .padding(.horizontal, WanderTheme.spacing8)
                .padding(.top, WanderTheme.spacing4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Photo zoom")
                .accessibilityValue("\(Int(crop.scale * 100)) percent")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.stateError.color)
                        .padding(.top, WanderTheme.spacing3)
                }

                Spacer(minLength: WanderTheme.spacing4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
    }

    private func header(viewportSize: CGSize) -> some View {
        ZStack {
            Text("Crop photo")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white)

            HStack {
                Button("Cancel", action: cancel)
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Button(isSaving ? "Saving…" : "Choose") {
                    saveCrop(viewportSize: viewportSize)
                }
                .fontWeight(.black)
                .foregroundStyle(WanderTheme.terracotta.color)
                .disabled(isSaving)
            }
        }
        .font(.system(size: 16, weight: .bold))
        .frame(minHeight: 56)
        .padding(.horizontal, WanderTheme.spacing4)
    }

    private func cropCanvas(viewportSize: CGSize) -> some View {
        let baseScale = ProfilePhotoCropState.aspectFillScale(
            imageSize: image.size,
            viewportSize: viewportSize
        )
        let displayedScale = crop.scale(applying: magnification)
        let displayedOffset = crop.offset(
            applying: dragTranslation,
            imageSize: image.size,
            viewportSize: viewportSize,
            scale: displayedScale
        )

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(
                    width: image.size.width * baseScale,
                    height: image.size.height * baseScale
                )
                .scaleEffect(displayedScale)
                .offset(displayedOffset)

            CircularCropShade()

            Circle()
                .stroke(.white.opacity(0.94), lineWidth: 2)
                .padding(1)
        }
        .contentShape(Rectangle())
        .clipped()
        .simultaneousGesture(magnificationGesture(viewportSize: viewportSize))
        .simultaneousGesture(dragGesture(viewportSize: viewportSize))
        .accessibilityLabel("Profile photo crop")
        .accessibilityHint("Pinch to zoom and drag to reposition the photo inside the circle")
    }

    private func magnificationGesture(viewportSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($magnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                crop.finishMagnification(
                    value,
                    imageSize: image.size,
                    viewportSize: viewportSize
                )
            }
    }

    private func dragGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                crop.finishDrag(
                    value.translation,
                    imageSize: image.size,
                    viewportSize: viewportSize
                )
            }
    }

    private func saveCrop(viewportSize: CGSize) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        do {
            let cropRect = crop.sourceCropRect(
                imageSize: image.size,
                viewportSize: viewportSize
            )
            let data = try WanderImageProcessor.squareJPEGData(
                from: image,
                cropRect: cropRect
            )
            guard let preview = UIImage(data: data) else {
                throw WanderImageProcessingError.invalidImageData
            }
            choose(data, preview)
        } catch {
            errorMessage = "That crop couldn’t be saved. Try again."
            isSaving = false
        }
    }
}

private struct CircularCropShade: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                path.addEllipse(in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 1, dy: 1))
            }
            .fill(.black.opacity(0.52), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }
}
