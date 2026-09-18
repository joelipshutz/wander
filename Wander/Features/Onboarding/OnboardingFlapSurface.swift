import SwiftUI
import UIKit

/// Three native review treatments share the same layout, copy, and mechanism.
/// The default ships without an environment-dependent style choice.
enum OnboardingFlapFinish: String, CaseIterable {
    case station, sculpted, graphic

    static var current: Self {
        #if DEBUG
        return ProcessInfo.processInfo.environment["WANDER_ONBOARDING_FLAP_FINISH"]
            .flatMap(Self.init(rawValue:)) ?? .station
        #else
        return .station
        #endif
    }

    var cornerRadius: CGFloat { self == .sculpted ? 3.2 : (self == .graphic ? 0.8 : 1.4) }
    var depth: CGFloat { self == .sculpted ? 2.4 : (self == .graphic ? 0.4 : 1.4) }
}

/// Rasterize the branded faces only when size or appearance changes. Each flip
/// then moves retained native layers rather than laying out three Text views
/// per cell on every animation frame.
struct OnboardingFlapSurface: UIViewRepresentable {
    let fromRows: [String]
    let toRows: [String]
    let progress: Double
    let isDark: Bool
    var finish: OnboardingFlapFinish = .current
    var minimumColumns: Int = OnboardingBoardCopy.columns
    var outerRowsOpacity: Double = 1
    var flips: Int = 2

    func makeUIView(context: Context) -> OnboardingFlapSurfaceView {
        OnboardingFlapSurfaceView()
    }

    func updateUIView(_ view: OnboardingFlapSurfaceView, context: Context) {
        view.update(from: fromRows, to: toRows, progress: progress, isDark: isDark,
                    finish: finish, minimumColumns: minimumColumns, outerRowsOpacity: outerRowsOpacity, flips: flips)
    }
}

final class OnboardingFlapSurfaceView: UIView {
    private var fromRows = [String]()
    private var toRows = [String]()
    private var source = [Character]()
    private var target = [Character]()
    private var progress = 1.0
    private var isDark = false
    private var finish = OnboardingFlapFinish.station
    private var columns = OnboardingBoardCopy.columns
    private var outerRowsOpacity = 1.0
    private var flips = 2
    private var tiles = [OnboardingFlapTile]()
    private var faces = [Character: CGImage]()
    private var faceSize = CGSize.zero
    private var renderedScale: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(from: [String], to: [String], progress: Double, isDark: Bool,
                finish: OnboardingFlapFinish = .station,
                minimumColumns: Int = OnboardingBoardCopy.columns, outerRowsOpacity: Double = 1, flips: Int = 2) {
        if self.isDark != isDark || self.finish != finish {
            self.isDark = isDark
            self.finish = finish
            faces.removeAll()
            tiles.forEach { $0.lastFrame = nil }
            setNeedsLayout()
        }
        let newColumns = max(max(1, minimumColumns), (from + to).map(\.count).max() ?? 0)
        if fromRows != from || toRows != to || columns != newColumns {
            fromRows = from; toRows = to
            columns = newColumns
            source = (0..<3).flatMap { OnboardingBoardCopy.centered(from.indices.contains($0) ? from[$0] : "", columns: columns) }
            target = (0..<3).flatMap { OnboardingBoardCopy.centered(to.indices.contains($0) ? to[$0] : "", columns: columns) }
            setNeedsLayout()
        }
        self.progress = progress
        self.flips = flips
        self.outerRowsOpacity = outerRowsOpacity.isFinite ? min(1, max(0, outerRowsOpacity)) : 0
        render()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let gap = max(1, bounds.width * 0.004)
        let size = CGSize(width: (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                          height: (bounds.height - gap * 4) / 3)
        let scale = traitCollection.displayScale
        if size != faceSize || renderedScale != scale {
            faceSize = size; renderedScale = scale
            faces.removeAll()
            tiles.forEach { $0.lastFrame = nil }
        }
        if tiles.count != columns * 3 {
            tiles.forEach { $0.removeFromSuperlayer() }
            tiles = (0..<(columns * 3)).map { _ in
                let tile = OnboardingFlapTile()
                layer.addSublayer(tile)
                return tile
            }
        }
        for (index, tile) in tiles.enumerated() {
            tile.frame = CGRect(x: CGFloat(index % columns) * (size.width + gap),
                                y: CGFloat(index / columns) * (size.height + gap * 2),
                                width: size.width, height: size.height)
            tile.arrange(size: size, scale: scale, isDark: isDark, finish: finish)
        }
        // Prepare the small alphabet atlas while the view is being laid out,
        // before any letters need to turn. There is no text drawing mid-flip.
        for glyph in Set(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ ’") + source + target) {
            _ = face(glyph)
        }
        CATransaction.commit()
        render()
    }

    private func render() {
        guard faceSize.width > 0, tiles.count == source.count, source.count == target.count else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for index in tiles.indices {
            let frame = OnboardingSplitFlapFrame.at(progress: progress, from: source[index],
                                                  to: target[index], column: index % columns, flips: flips)
            let tile = tiles[index]
            tile.opacity = index / columns == 1 ? 1 : Float(outerRowsOpacity)
            guard tile.lastFrame != frame else { continue }
            tile.apply(frame, from: face(frame.from), to: face(frame.to))
        }
        CATransaction.commit()
    }

    private func face(_ character: Character) -> CGImage {
        if let cached = faces[character] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = renderedScale
        let image = UIGraphicsImageRenderer(size: faceSize, format: format).image { renderer in
            let cg = renderer.cgContext
            let rect = CGRect(origin: .zero, size: faceSize)
            var colors: [UIColor] = isDark
                ? [UIColor(red: 0.17, green: 0.19, blue: 0.17, alpha: 1),
                   UIColor(red: 0.095, green: 0.11, blue: 0.095, alpha: 1)]
                : [.white, UIColor(red: 0.95, green: 0.945, blue: 0.925, alpha: 1)]
            if finish == .graphic {
                let matte = isDark ? UIColor(red: 0.12, green: 0.135, blue: 0.12, alpha: 1) : UIColor.white
                colors = [matte, matte]
            } else if finish == .sculpted {
                colors = isDark
                    ? [UIColor(red: 0.22, green: 0.24, blue: 0.215, alpha: 1),
                       UIColor(red: 0.075, green: 0.095, blue: 0.075, alpha: 1)]
                    : [.white, UIColor(red: 0.90, green: 0.895, blue: 0.875, alpha: 1)]
            }
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: rect.height), options: [])

            // Keep the earlier monospaced letterforms at their natural aspect
            // ratio. Fit with one font size, never a horizontal-only transform.
            // All three finishes share typography; only the physical face varies.
            let reference = UIFont.monospacedSystemFont(ofSize: 100, weight: .bold)
            let advance = ("W" as NSString).size(withAttributes: [.font: reference]).width
            let availableWidth = rect.width - max(2, rect.width * 0.12)
            let fontSize = 100 * min(availableWidth / advance, rect.height * 0.68 / reference.capHeight)
            let font = reference.withSize(max(1, fontSize))
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(AstirTheme.signal.color)]
            let text = String(character) as NSString
            let width = text.size(withAttributes: attributes).width
            let textHeight = font.lineHeight
            // Center the actual capital height, not the font's descender space.
            let y = (rect.height - font.capHeight) / 2 - (font.ascender - font.capHeight)
            cg.saveGState()
            cg.translateBy(x: rect.midX, y: 0)
            if finish != .graphic {
                cg.setShadow(offset: CGSize(width: 0, height: finish == .sculpted ? 1 : 0.55), blur: 0,
                             color: UIColor.black.withAlphaComponent(isDark ? 0.40 : 0.13).cgColor)
            }
            text.draw(in: CGRect(x: -width / 2, y: y, width: width + 1, height: textHeight), withAttributes: attributes)
            cg.restoreGState()

            // The small bevels and center cut belong to the physical face, so
            // they travel with it and do not require live shadow rendering.
            cg.setStrokeColor(UIColor.white.withAlphaComponent(isDark ? 0.13 : 0.9).cgColor)
            cg.setLineWidth(finish == .sculpted ? 1.1 : 0.6)
            cg.move(to: CGPoint(x: 1, y: 0.5)); cg.addLine(to: CGPoint(x: rect.width - 1, y: 0.5)); cg.strokePath()
            cg.setFillColor(UIColor.black.withAlphaComponent(isDark ? 0.85 : 0.25).cgColor)
            cg.fill(CGRect(x: 0, y: rect.midY - 0.5, width: rect.width, height: 1))
            cg.setFillColor(UIColor.white.withAlphaComponent(isDark ? 0.11 : 0.8).cgColor)
            cg.fill(CGRect(x: 0, y: rect.midY + 0.5, width: rect.width, height: 0.45))
        }.cgImage!
        faces[character] = image
        return image
    }
}

private final class OnboardingFlapTile: CALayer {
    let upper = CALayer()
    let lower = CALayer()
    let turningUpper = CALayer()
    let turningLower = CALayer()
    let upperShade = CALayer()
    let lowerShade = CALayer()
    let axle = CALayer()
    let leftHinge = CALayer()
    let rightHinge = CALayer()
    var lastFrame: OnboardingSplitFlapFrame?

    override init() {
        super.init()
        [upper, lower, turningUpper, turningLower].forEach {
            addSublayer($0)
            $0.isDoubleSided = false
            $0.masksToBounds = true
            $0.cornerRadius = 1.4
        }
        turningUpper.addSublayer(upperShade)
        turningLower.addSublayer(lowerShade)
        [upperShade, lowerShade].forEach { $0.backgroundColor = UIColor.black.cgColor }
        [axle, leftHinge, rightHinge].forEach { addSublayer($0) }
        shadowColor = UIColor.black.cgColor
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func arrange(size: CGSize, scale: CGFloat, isDark: Bool, finish: OnboardingFlapFinish) {
        let half = CGSize(width: size.width, height: size.height / 2)
        for face in [upper, lower, turningUpper, turningLower] {
            face.bounds = CGRect(origin: .zero, size: half)
            face.contentsScale = scale
            face.contentsGravity = .resize
            face.cornerRadius = finish.cornerRadius
        }
        for face in [upper, turningUpper] {
            face.anchorPoint = CGPoint(x: 0.5, y: 1)
            face.position = CGPoint(x: size.width / 2, y: size.height / 2)
            face.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        }
        for face in [lower, turningLower] {
            face.anchorPoint = CGPoint(x: 0.5, y: 0)
            face.position = CGPoint(x: size.width / 2, y: size.height / 2)
            face.contentsRect = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        }
        upperShade.frame = CGRect(origin: .zero, size: half)
        lowerShade.frame = CGRect(origin: .zero, size: half)
        // The axle and clips are fixed hardware. They never rotate with a leaf.
        axle.frame = CGRect(x: 0, y: half.height - 0.45, width: size.width, height: 0.9)
        axle.backgroundColor = UIColor.black.withAlphaComponent(isDark ? 0.95 : 0.5).cgColor
        for (index, hinge) in [leftHinge, rightHinge].enumerated() {
            hinge.frame = CGRect(x: index == 0 ? 0 : size.width - 1.6,
                                 y: half.height - 2.1, width: 1.6, height: 4.2)
            hinge.cornerRadius = 0.6
            hinge.backgroundColor = (isDark ? UIColor(white: 0.34, alpha: 1) : UIColor(white: 0.57, alpha: 1)).cgColor
            hinge.isHidden = finish == .graphic
        }
        shadowOpacity = finish == .graphic ? 0 : (isDark ? 0.5 : 0.18)
        shadowOffset = CGSize(width: 0, height: finish.depth)
        shadowRadius = finish == .sculpted ? 1 : 0.7
        shadowPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: finish.cornerRadius).cgPath
    }

    func apply(_ frame: OnboardingSplitFlapFrame, from: CGImage, to: CGImage) {
        lastFrame = frame
        if frame.from == frame.to || frame.progress >= 1 {
            upper.contents = to; lower.contents = to
            turningUpper.isHidden = true; turningLower.isHidden = true
            return
        }
        upper.contents = to; lower.contents = from
        let firstHalf = frame.progress < 0.5
        turningUpper.isHidden = !firstHalf
        turningLower.isHidden = firstHalf
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / max(1, bounds.height * 3.5)
        if firstHalf {
            let fall = pow(frame.progress * 2, 1.9)
            turningUpper.contents = from
            turningUpper.transform = CATransform3DRotate(perspective, -.pi / 2 * fall, 1, 0, 0)
            upperShade.opacity = Float(fall * 0.55)
        } else {
            let phase = (frame.progress - 0.5) * 2
            // Strike the lower stop, rebound by a few degrees, then lie flat.
            let landing = phase < 0.72 ? pow(1 - phase / 0.72, 2)
                : 0.045 * sin((phase - 0.72) / 0.28 * .pi)
            turningLower.contents = to
            turningLower.transform = CATransform3DRotate(perspective, .pi / 2 * landing, 1, 0, 0)
            lowerShade.opacity = Float(landing * 0.4)
        }
    }
}

@MainActor
final class OnboardingFlapHaptics {
    private var cursor = OnboardingFlapHapticCursor()
    private var generator: UIImpactFeedbackGenerator?

    func advance(to elapsed: Double, playing: Bool, content: OnboardingTickerContent) {
        guard playing else { reset(); return }
        if generator == nil {
            generator = UIImpactFeedbackGenerator(style: .rigid)
            generator?.prepare()
        }
        guard let tap = cursor.advance(to: elapsed, playing: playing, content: content) else { return }
        let intensities: [CGFloat] = [0.38, 0.52, 0.44, 0.64]
        generator?.impactOccurred(intensity: intensities[tap])
        generator?.prepare()
    }

    func reset() {
        cursor.reset()
        generator = nil
    }
}
