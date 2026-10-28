#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import UIKit

/// Review-only silhouettes. These are immutable launch options, never account settings.
enum MapPinLabStyle: String, CaseIterable {
    case porcelain
    case signal
    case bookmark
    case ticket
    case compass

    static func resolve(arguments: [String]) -> Self? {
        guard arguments.contains("-WanderMapCapture"),
              arguments.contains("-WanderAuthenticatedUITest"),
              arguments.contains("-WanderUseDemoFixtures")
                || arguments.contains("-WanderUseStorefrontFixtures"),
              let selector = arguments.firstIndex(of: "-WanderPinDesign"),
              arguments.indices.contains(selector + 1)
        else { return nil }
        return Self(rawValue: arguments[selector + 1])
    }
}

@MainActor
enum MapPinDesignLab {
    static let style = MapPinLabStyle.resolve(arguments: ProcessInfo.processInfo.arguments)

    static func image(for descriptor: NativeMapAnnotationDescriptor, isDark: Bool) -> UIImage? {
        guard let style else { return nil }
        return render(for: descriptor, isDark: isDark, style: style)
    }

    static func centerOffset(for descriptor: NativeMapAnnotationDescriptor) -> CGPoint? {
        guard style != nil, descriptor.resolvedDetail != .dot else { return nil }
        return offset(for: descriptor)
    }

    /// MapKit offsets the image's midpoint; compensate for the selected title
    /// so the emoji, map coordinate, and native hit-test center remain aligned.
    static func offset(for descriptor: NativeMapAnnotationDescriptor) -> CGPoint {
        let metrics = MapPinCanvasMetrics.resolve(for: descriptor)
        return CGPoint(x: 0, y: metrics.size.height / 2 - metrics.pinCenter.y)
    }

    static func render(
        for descriptor: NativeMapAnnotationDescriptor,
        isDark: Bool,
        style: MapPinLabStyle
    ) -> UIImage? {
        guard descriptor.resolvedDetail != .dot else { return nil }
        let size = MapPinCanvasMetrics.resolve(for: descriptor).size
        let renderer = ImageRenderer(content:
            MapPinLabCanvas(descriptor: descriptor, style: style, isDark: isDark)
                .environment(\.colorScheme, isDark ? .dark : .light)
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = false
        return renderer.uiImage
    }
}

private enum MapPinLabPalette {
    static func color(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

private struct MapPinLabCanvas: View {
    let descriptor: NativeMapAnnotationDescriptor
    let style: MapPinLabStyle
    let isDark: Bool

    private var center: CGPoint {
        MapPinCanvasMetrics.resolve(for: descriptor).pinCenter
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if descriptor.isSelected {
                Circle()
                    .fill(WanderTheme.pinYou.color.opacity(isDark ? 0.20 : 0.14))
                    .overlay {
                        Circle().stroke(WanderTheme.pinYou.color, lineWidth: 2)
                    }
                    .frame(width: 64, height: 64)
                    .position(center)
            }

            MapPinLabGlyph(descriptor: descriptor, style: style, isDark: isDark)
                // The existing 1.45 enlargement would crowd the title and exceed
                // the coordinate-centered 34pt tap radius with these silhouettes.
                .scaleEffect(descriptor.isSelected ? 1.18 : MapPinSelectionMotionStyle.inactiveScale)
                .position(center)

            if descriptor.isSelected {
                Text(descriptor.title)
                    .font(.custom("AvenirNext-DemiBold", size: MapPinVisualMetrics.activeTitleFontSize))
                    .foregroundStyle(MapPinLabPalette.color(0xFFF9F0))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 5)
                    .frame(width: MapPinCanvasMetrics.resolve(for: descriptor).size.width - 2)
                    .frame(height: 20)
                    .background(MapPinLabPalette.color(0x141714), in: Capsule())
                    .overlay {
                        Capsule().stroke(MapPinLabPalette.color(0xFFF9F0).opacity(0.8), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .position(x: center.x, y: MapPinCanvasMetrics.resolve(for: descriptor).titleTop + 10)
            }
        }
    }
}

private struct MapPinLabGlyph: View {
    let descriptor: NativeMapAnnotationDescriptor
    let style: MapPinLabStyle
    let isDark: Bool

    private var ink: Color { MapPinLabPalette.color(0x141714) }
    private var paper: Color { MapPinLabPalette.color(0xFFF9F0) }
    private var surface: Color { isDark ? MapPinLabPalette.color(0x2B322C) : paper }
    private var edge: Color { isDark ? paper.opacity(0.38) : ink.opacity(0.18) }
    private var accent: Color { descriptor.outlines.first?.color ?? (isDark ? paper : ink) }

    private var ringDiameter: CGFloat {
        switch style {
        case .porcelain: 35
        case .signal: 33
        case .bookmark: 29
        case .ticket: 25
        case .compass: 30
        }
    }

    private var ringSpacing: CGFloat {
        style == .ticket ? 6 : 7
    }

    private var emojiSize: CGFloat {
        switch style {
        case .porcelain, .signal: MapPinVisualMetrics.emojiDiameter
        case .bookmark, .compass: 22
        case .ticket: 20
        }
    }

    var body: some View {
        ZStack {
            silhouette
                .shadow(color: .black.opacity(isDark ? 0.38 : 0.19), radius: 3, y: 2)

            // Every family keeps the same ownership and Been / Wanna / mixed
            // vocabulary. The decorative silhouette has no status meaning.
            ForEach(Array(descriptor.outlines.enumerated()), id: \.offset) { index, outline in
                MapPinOutlineStroke(outline: outline, lineWidth: 2.5)
                    .frame(
                        width: ringDiameter + CGFloat(index) * ringSpacing,
                        height: ringDiameter + CGFloat(index) * ringSpacing
                    )
            }

            if descriptor.isSearchResult && descriptor.outlines.isEmpty {
                Circle()
                    .stroke(style == .signal ? paper.opacity(0.75) : edge, lineWidth: 1.2)
                    .frame(width: ringDiameter, height: ringDiameter)
            }

            WanderCategoryEmoji(emoji: descriptor.emoji, size: emojiSize)
                .frame(width: emojiSize + 1, height: emojiSize + 1)

            if descriptor.isSearchResult {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(paper)
                    .frame(width: 15, height: 15)
                    .background(ink, in: Circle())
                    .overlay { Circle().stroke(paper, lineWidth: 1.25) }
                    .offset(x: style == .ticket ? 21 : 17, y: style == .ticket ? 11 : 17)
            }
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var silhouette: some View {
        switch style {
        case .porcelain:
            Circle()
                .fill(LinearGradient(
                    colors: isDark
                        ? [MapPinLabPalette.color(0x3A423B), MapPinLabPalette.color(0x202620)]
                        : [MapPinLabPalette.color(0xFFFDF7), MapPinLabPalette.color(0xECE2D3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay { Circle().stroke(paper.opacity(isDark ? 0.3 : 0.95), lineWidth: 1.5) }
                .overlay { Circle().stroke(edge, lineWidth: 0.65).padding(2) }
                .frame(width: 47, height: 47)

        case .signal:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ink)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isDark ? paper.opacity(0.52) : paper, lineWidth: 1.3)
                    }
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(paper.opacity(0.16), lineWidth: 0.8)
                    .padding(3)
                Circle()
                    .fill(paper)
                    .frame(width: 27, height: 27)
                Capsule()
                    .fill(WanderTheme.pinYou.color)
                    .frame(width: 12, height: 2)
                    .offset(y: -20)
            }
            .frame(width: 46, height: 46)

        case .bookmark:
            ZStack {
                MapPinLabBookmark()
                    .fill(surface)
                    .overlay { MapPinLabBookmark().stroke(edge, lineWidth: 1) }
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent.opacity(0.8))
                    .frame(width: 18, height: 2)
                    .offset(y: -20)
                Circle()
                    .fill(isDark ? ink.opacity(0.3) : .white.opacity(0.6))
                    .frame(width: 25, height: 25)
                    .offset(y: -3)
            }
            .frame(width: 43, height: 49)
            .offset(y: 3)

        case .ticket:
            ZStack {
                Capsule()
                    .fill(surface)
                    .overlay { Capsule().stroke(edge, lineWidth: 1) }
                Capsule()
                    .stroke(paper.opacity(isDark ? 0.15 : 0.85), lineWidth: 1)
                    .padding(2)
                HStack {
                    Capsule().fill(accent).frame(width: 2, height: 10)
                    Spacer()
                    Capsule().fill(accent).frame(width: 2, height: 10)
                }
                .padding(.horizontal, 5)
            }
            .frame(width: 52, height: 36)

        case .compass:
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(edge, lineWidth: 1.2)
                    }
                    .frame(width: 35, height: 35)
                    .rotationEffect(.degrees(45))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
                    .frame(width: 29, height: 29)
                    .rotationEffect(.degrees(45))
                Circle()
                    .fill(isDark ? ink.opacity(0.25) : .white.opacity(0.6))
                    .frame(width: 26, height: 26)
            }
            .frame(width: 50, height: 50)
        }
    }
}

/// A shallow V signals a saved place-memory without adding a geographic stem.
private struct MapPinLabBookmark: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 10
        return Path { path in
            path.move(to: CGPoint(x: radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 3, y: rect.maxY),
                              control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 7))
            path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 3),
                              control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
        }
    }
}
#endif
