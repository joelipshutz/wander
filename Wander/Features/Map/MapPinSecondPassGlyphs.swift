#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// The existing annotation contract supplies an emoji as category metadata.
/// Resolve it once into a non-emoji vocabulary shared by all five explorations.
typealias MapPinSecondPassCategory = MapCategoryPictogram

private extension MapCategoryPictogram {
    fileprivate var illustrationColor: Color {
        switch self {
        case .coffee, .bakery: MapPinSecondPassPalette.color(0xD9AB69)
        case .dining, .noodles, .bar: MapPinSecondPassPalette.color(0xF18968)
        case .nature, .trail: MapPinSecondPassPalette.color(0x8BA889)
        case .beach: MapPinSecondPassPalette.color(0x72B5BD)
        case .culture, .stay: MapPinSecondPassPalette.color(0xA1AFC6)
        case .shop, .place: MapPinSecondPassPalette.color(0xDBBD77)
        case .wellness: MapPinSecondPassPalette.color(0xD79D9C)
        }
    }
}

struct MapPinSecondPassGlyph: View {
    let descriptor: NativeMapAnnotationDescriptor
    let style: MapPinLabStyle
    let isDark: Bool

    static func letterpressInitial(for title: String) -> String {
        guard let scalar = title.unicodeScalars.first(where: {
            switch $0.properties.generalCategory {
            case .decimalNumber:
                return true
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                 .modifierLetter, .otherLetter:
                return !$0.properties.isEmoji
            default:
                // Foundation's letter set also accepts some combining marks,
                // including emoji presentation selectors. Those are not initials.
                return false
            }
        }) else { return "P" }
        return String(String(scalar).uppercased().prefix(1))
    }

    private var category: MapPinSecondPassCategory {
        MapPinSecondPassCategory.resolve(emoji: descriptor.emoji)
    }
    private var ink: Color { MapPinSecondPassPalette.ink }
    private var paper: Color { MapPinSecondPassPalette.paper }
    private var primaryColor: Color {
        descriptor.outlines.first.map { MapPinSecondPassStatusStyle.color(for: $0.ownership) } ?? ink
    }

    var body: some View {
        ZStack {
            family
            if descriptor.isSearchResult {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(paper)
                    .frame(width: 13, height: 13)
                    .background(ink, in: RoundedRectangle(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(paper, lineWidth: 1.25) }
                    .offset(x: 13, y: -13)
            }
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var family: some View {
        switch style {
        case .cutout:
            ZStack {
                MapPinCutoutArtwork(category: category)
                    .frame(width: 41, height: 37)
                    .rotationEffect(.degrees(-7))
                rails(width: 25).offset(y: 20)
            }

        case .wayfinder:
            ZStack {
                MapPinWayfinderShape()
                    .fill(ink)
                    .overlay { MapPinWayfinderShape().stroke(paper, lineWidth: 1.7) }
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 2)
                    .frame(width: 36, height: 41)
                    .offset(y: -2)
                Image(systemName: category.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(paper)
                    .offset(y: -3)
                Rectangle()
                    .fill(primaryColor)
                    .frame(width: 14, height: 3)
                    .offset(y: -19)
                rails(width: 28).offset(y: 21)
            }

        case .letterpress:
            ZStack {
                Text(Self.letterpressInitial(for: descriptor.title))
                    .font(.system(size: 39, weight: .bold, design: .serif))
                    .foregroundStyle(isDark ? paper : ink)
                    .shadow(color: isDark ? ink : paper, radius: 0, x: -1.5, y: -1.5)
                    .shadow(color: isDark ? ink : paper, radius: 0, x: 1.5, y: 1.5)
                    .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
                    .rotationEffect(.degrees(-5))
                    .offset(x: -2, y: -1)
                Image(systemName: category.symbolName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isDark ? paper : ink)
                    .padding(2)
                    .background(isDark ? ink : paper, in: RoundedRectangle(cornerRadius: 2))
                    .offset(x: 17, y: -13)
                rails(width: 29).offset(y: 21)
            }

        case .totem:
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(paper)
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 2)
                    .frame(width: 31, height: 45)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ink)
                    .frame(width: 31, height: 45)
                    .mask(alignment: .bottom) { Rectangle().frame(height: 12) }
                Capsule()
                    .fill(ink.opacity(0.28))
                    .frame(width: 8, height: 2)
                    .offset(y: -17)
                Image(systemName: category.symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ink)
                    .offset(y: -4)
                rails(width: 19, backing: ink).offset(y: 17)
            }

        case .contour:
            ZStack {
                MapPinKeylinedSymbol(name: category.outlineSymbolName, isDark: isDark)
                rails(width: 24).offset(y: 21)
            }

        default:
            // Root routes only the second-pass styles here. A neutral symbol
            // keeps accidental future routes legible without rendering emoji.
            Image(systemName: "location.fill")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(ink)
        }
    }

    private func rails(width: CGFloat, backing: Color? = nil) -> some View {
        MapPinSecondPassStatusRails(
            outlines: descriptor.outlines,
            width: width,
            backing: backing ?? paper
        )
    }
}

private enum MapPinSecondPassPalette {
    static let ink = color(0x141714)
    static let paper = color(0xFFF9F0)

    static func color(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// Review-approved Featured color. The existing outline builder supplies this
/// fallback only when no active personal or social Been/Wanna save exists.
enum MapPinSecondPassStatusStyle {
    static func color(for ownership: MapPinSaveOwnership) -> Color {
        switch ownership {
        case .currentUser: WanderTheme.pinYou.color
        case .social: WanderTheme.pinSocial.color
        case .featured: MapPinSecondPassPalette.color(0x6FB985)
        }
    }
}

/// Ownership occupies separate rails. Each status uses the same solid/dotted
/// distinction as the production rings; mixed saves split one rail in two.
private struct MapPinSecondPassStatusRails: View {
    let outlines: [MapPinOutline]
    let width: CGFloat
    let backing: Color

    var body: some View {
        VStack(spacing: 2.8) {
            ForEach(Array(outlines.enumerated()), id: \.offset) { _, outline in
                HStack(spacing: 3) {
                    segment(
                        status: outline.ownership == .featured ? .been : outline.status,
                        color: MapPinSecondPassStatusStyle.color(for: outline.ownership)
                    )
                    if outline.ownership != .featured, let secondary = outline.secondaryStatus {
                        segment(status: secondary, color: MapPinSecondPassStatusStyle.color(for: outline.ownership))
                    }
                }
                .frame(width: width, height: 2.6)
            }
        }
    }

    private func segment(status: PlaceStatus, color: Color) -> some View {
        MapPinStatusLine()
            .stroke(backing, style: StrokeStyle(lineWidth: 4.8, lineCap: .round))
            .overlay {
                MapPinStatusLine()
                    .stroke(color, style: StrokeStyle(
                        lineWidth: 2.8,
                        lineCap: .round,
                        dash: status == .wannaGo ? [0.1, 4.3] : []
                    ))
            }
    }
}

private struct MapPinStatusLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + 1.4, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 1.4, y: rect.midY))
        }
    }
}

private struct MapPinKeylinedSymbol: View {
    let name: String
    let isDark: Bool

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * .pi / 4
                Image(systemName: name)
                    .foregroundStyle(MapPinSecondPassPalette.paper)
                    .offset(x: cos(angle) * 1.6, y: sin(angle) * 1.6)
            }
            Image(systemName: name)
                .foregroundStyle(MapPinSecondPassPalette.ink)
        }
        .font(.system(size: 25, weight: .regular))
        .shadow(color: .black.opacity(isDark ? 0.35 : 0.13), radius: 1, y: 1)
    }
}

private struct MapPinWayfinderShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 9, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - 9, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: 9), control: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 12))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 6, y: rect.maxY - 6),
                              control: CGPoint(x: rect.maxX, y: rect.maxY - 6))
            path.addLine(to: CGPoint(x: rect.midX + 5, y: rect.maxY - 6))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX - 5, y: rect.maxY - 6))
            path.addLine(to: CGPoint(x: 6, y: rect.maxY - 6))
            path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - 12),
                              control: CGPoint(x: 0, y: rect.maxY - 6))
            path.addLine(to: CGPoint(x: 0, y: 9))
            path.addQuadCurve(to: CGPoint(x: 9, y: 0), control: .zero)
            path.closeSubpath()
        }
    }
}

/// Small original vector drawings, deliberately separate from SF Symbols and
/// the Apple emoji font. The white edge follows the object, not a badge cage.
private struct MapPinCutoutArtwork: View {
    let category: MapPinSecondPassCategory

    var body: some View {
        MapPinCutoutShape(category: category, details: false)
            .stroke(MapPinSecondPassPalette.paper, style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            .shadow(color: .black.opacity(0.22), radius: 1.4, y: 1.2)
            .overlay {
                MapPinCutoutShape(category: category, details: false)
                    .fill(category.illustrationColor)
            }
            .overlay {
                MapPinCutoutShape(category: category, details: false)
                    .stroke(MapPinSecondPassPalette.ink.opacity(0.86),
                            style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            }
            .overlay {
                MapPinCutoutShape(category: category, details: true)
                    .stroke(MapPinSecondPassPalette.ink.opacity(0.86),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
    }
}

private struct MapPinCutoutShape: Shape {
    let category: MapPinSecondPassCategory
    let details: Bool

    func path(in rect: CGRect) -> Path {
        let path = details ? detailPath : silhouettePath
        return path.applying(CGAffineTransform(scaleX: rect.width / 40, y: rect.height / 36)
            .translatedBy(x: rect.minX, y: rect.minY))
    }

    private var silhouettePath: Path {
        Path { path in
            switch category {
            case .coffee:
                path.addRoundedRect(in: CGRect(x: 25, y: 10, width: 12, height: 16), cornerSize: CGSize(width: 6, height: 6))
                path.move(to: CGPoint(x: 7, y: 9))
                path.addLine(to: CGPoint(x: 30, y: 9))
                path.addLine(to: CGPoint(x: 28, y: 25))
                path.addQuadCurve(to: CGPoint(x: 23, y: 29), control: CGPoint(x: 28, y: 29))
                path.addLine(to: CGPoint(x: 14, y: 29))
                path.addQuadCurve(to: CGPoint(x: 9, y: 25), control: CGPoint(x: 9, y: 29))
                path.closeSubpath()
                path.addRoundedRect(in: CGRect(x: 5, y: 31, width: 29, height: 2), cornerSize: CGSize(width: 1, height: 1))
            case .dining:
                path.addEllipse(in: CGRect(x: 11, y: 7, width: 21, height: 25))
                path.move(to: CGPoint(x: 2, y: 5))
                for point in [CGPoint(x: 4, y: 5), CGPoint(x: 4, y: 11), CGPoint(x: 5, y: 11),
                              CGPoint(x: 5, y: 5), CGPoint(x: 7, y: 5), CGPoint(x: 7, y: 11),
                              CGPoint(x: 8, y: 11), CGPoint(x: 8, y: 5), CGPoint(x: 10, y: 5),
                              CGPoint(x: 10, y: 14)] {
                    path.addLine(to: point)
                }
                path.addQuadCurve(to: CGPoint(x: 8, y: 17), control: CGPoint(x: 10, y: 17))
                path.addLine(to: CGPoint(x: 8, y: 32))
                path.addLine(to: CGPoint(x: 5, y: 32))
                path.addLine(to: CGPoint(x: 5, y: 17))
                path.addQuadCurve(to: CGPoint(x: 2, y: 14), control: CGPoint(x: 2, y: 17))
                path.closeSubpath()
                path.move(to: CGPoint(x: 37, y: 5))
                path.addCurve(to: CGPoint(x: 34, y: 19), control1: CGPoint(x: 31, y: 8), control2: CGPoint(x: 31, y: 18))
                path.addLine(to: CGPoint(x: 34, y: 32))
                path.addLine(to: CGPoint(x: 37, y: 32))
                path.closeSubpath()
            case .noodles:
                path.move(to: CGPoint(x: 3, y: 14))
                path.addQuadCurve(to: CGPoint(x: 37, y: 14), control: CGPoint(x: 20, y: 8))
                path.addQuadCurve(to: CGPoint(x: 25, y: 31), control: CGPoint(x: 35, y: 29))
                path.addLine(to: CGPoint(x: 15, y: 31))
                path.addQuadCurve(to: CGPoint(x: 3, y: 14), control: CGPoint(x: 5, y: 29))
                path.closeSubpath()
            case .bar:
                path.move(to: CGPoint(x: 5, y: 7))
                path.addLine(to: CGPoint(x: 35, y: 7))
                path.addLine(to: CGPoint(x: 21, y: 23))
                path.addLine(to: CGPoint(x: 21, y: 31))
                path.addLine(to: CGPoint(x: 28, y: 32))
                path.addLine(to: CGPoint(x: 12, y: 32))
                path.addLine(to: CGPoint(x: 19, y: 31))
                path.addLine(to: CGPoint(x: 19, y: 23))
                path.closeSubpath()
            case .bakery:
                path.move(to: CGPoint(x: 3, y: 27))
                path.addCurve(to: CGPoint(x: 20, y: 10), control1: CGPoint(x: 2, y: 11), control2: CGPoint(x: 13, y: 5))
                path.addCurve(to: CGPoint(x: 37, y: 27), control1: CGPoint(x: 29, y: 5), control2: CGPoint(x: 39, y: 13))
                path.addLine(to: CGPoint(x: 29, y: 24))
                path.addQuadCurve(to: CGPoint(x: 11, y: 24), control: CGPoint(x: 20, y: 29))
                path.closeSubpath()
            case .nature:
                path.addRoundedRect(in: CGRect(x: 18, y: 21, width: 4, height: 12), cornerSize: CGSize(width: 1, height: 1))
                path.move(to: CGPoint(x: 10, y: 25))
                path.addCurve(to: CGPoint(x: 10, y: 11), control1: CGPoint(x: 0, y: 25), control2: CGPoint(x: 2, y: 12))
                path.addCurve(to: CGPoint(x: 29, y: 11), control1: CGPoint(x: 8, y: -1), control2: CGPoint(x: 30, y: -1))
                path.addCurve(to: CGPoint(x: 29, y: 25), control1: CGPoint(x: 39, y: 10), control2: CGPoint(x: 40, y: 25))
                path.closeSubpath()
            case .trail:
                path.move(to: CGPoint(x: 2, y: 31))
                path.addLine(to: CGPoint(x: 14, y: 5))
                path.addLine(to: CGPoint(x: 22, y: 19))
                path.addLine(to: CGPoint(x: 28, y: 10))
                path.addLine(to: CGPoint(x: 38, y: 31))
                path.closeSubpath()
            case .beach:
                path.move(to: CGPoint(x: 4, y: 18))
                path.addQuadCurve(to: CGPoint(x: 36, y: 18), control: CGPoint(x: 20, y: -8))
                path.closeSubpath()
                path.addRect(CGRect(x: 19, y: 18, width: 2, height: 13))
                path.addRoundedRect(in: CGRect(x: 6, y: 31, width: 28, height: 2), cornerSize: CGSize(width: 1, height: 1))
            case .culture:
                path.move(to: CGPoint(x: 3, y: 10))
                path.addLine(to: CGPoint(x: 20, y: 2))
                path.addLine(to: CGPoint(x: 37, y: 10))
                path.closeSubpath()
                for x: CGFloat in [7, 17.5, 28] {
                    path.addRect(CGRect(x: x, y: 13, width: 5, height: 15))
                }
                path.addRoundedRect(in: CGRect(x: 4, y: 30, width: 32, height: 3), cornerSize: CGSize(width: 1, height: 1))
            case .stay:
                path.addRoundedRect(in: CGRect(x: 4, y: 8, width: 32, height: 22), cornerSize: CGSize(width: 4, height: 4))
                path.addRect(CGRect(x: 6, y: 29, width: 3, height: 4))
                path.addRect(CGRect(x: 31, y: 29, width: 3, height: 4))
            case .shop:
                path.move(to: CGPoint(x: 8, y: 12))
                path.addLine(to: CGPoint(x: 32, y: 12))
                path.addLine(to: CGPoint(x: 35, y: 32))
                path.addLine(to: CGPoint(x: 5, y: 32))
                path.closeSubpath()
            case .wellness:
                path.move(to: CGPoint(x: 20, y: 32))
                path.addCurve(to: CGPoint(x: 20, y: 9), control1: CGPoint(x: -8, y: 14), control2: CGPoint(x: 9, y: -7))
                path.addCurve(to: CGPoint(x: 20, y: 32), control1: CGPoint(x: 32, y: -7), control2: CGPoint(x: 48, y: 14))
                path.closeSubpath()
            case .place:
                path.move(to: CGPoint(x: 3, y: 9))
                for point in [CGPoint(x: 14, y: 5), CGPoint(x: 26, y: 10), CGPoint(x: 37, y: 6),
                              CGPoint(x: 37, y: 30), CGPoint(x: 26, y: 34), CGPoint(x: 14, y: 29), CGPoint(x: 3, y: 33)] {
                    path.addLine(to: point)
                }
                path.closeSubpath()
            }
        }
    }

    private var detailPath: Path {
        Path { path in
            switch category {
            case .coffee:
                path.addEllipse(in: CGRect(x: 9, y: 9, width: 19, height: 4))
                path.move(to: CGPoint(x: 30, y: 14))
                path.addCurve(to: CGPoint(x: 29, y: 22), control1: CGPoint(x: 36, y: 13), control2: CGPoint(x: 35, y: 23))
                path.move(to: CGPoint(x: 14, y: 5))
                path.addQuadCurve(to: CGPoint(x: 16, y: 1), control: CGPoint(x: 12, y: 3))
                path.move(to: CGPoint(x: 23, y: 5))
                path.addQuadCurve(to: CGPoint(x: 25, y: 1), control: CGPoint(x: 21, y: 3))
            case .dining:
                path.move(to: CGPoint(x: 16, y: 12))
                path.addCurve(to: CGPoint(x: 27, y: 26), control1: CGPoint(x: 10, y: 24), control2: CGPoint(x: 20, y: 31))
            case .noodles:
                path.move(to: CGPoint(x: 5, y: 16))
                path.addQuadCurve(to: CGPoint(x: 35, y: 16), control: CGPoint(x: 20, y: 21))
                path.move(to: CGPoint(x: 15, y: 15))
                path.addLine(to: CGPoint(x: 33, y: 3))
                path.move(to: CGPoint(x: 20, y: 16))
                path.addLine(to: CGPoint(x: 37, y: 6))
                path.move(to: CGPoint(x: 12, y: 13))
                path.addCurve(to: CGPoint(x: 22, y: 14), control1: CGPoint(x: 12, y: 6), control2: CGPoint(x: 21, y: 22))
            case .bar:
                path.move(to: CGPoint(x: 11, y: 13))
                path.addLine(to: CGPoint(x: 29, y: 13))
                path.move(to: CGPoint(x: 24, y: 17))
                path.addLine(to: CGPoint(x: 31, y: 2))
                path.addEllipse(in: CGRect(x: 26, y: 8, width: 3, height: 3))
            case .bakery:
                for x: CGFloat in [10, 17, 24] {
                    path.move(to: CGPoint(x: x, y: 12))
                    path.addQuadCurve(to: CGPoint(x: x + 3, y: 25), control: CGPoint(x: x - 1, y: 19))
                }
            case .nature:
                path.move(to: CGPoint(x: 20, y: 27))
                path.addLine(to: CGPoint(x: 20, y: 12))
                path.move(to: CGPoint(x: 20, y: 21))
                path.addLine(to: CGPoint(x: 12, y: 16))
                path.move(to: CGPoint(x: 20, y: 18))
                path.addLine(to: CGPoint(x: 27, y: 12))
            case .trail:
                path.move(to: CGPoint(x: 10, y: 14))
                path.addLine(to: CGPoint(x: 14, y: 17))
                path.addLine(to: CGPoint(x: 17, y: 12))
                path.move(to: CGPoint(x: 25, y: 16))
                path.addLine(to: CGPoint(x: 28, y: 19))
                path.addLine(to: CGPoint(x: 30, y: 15))
                path.move(to: CGPoint(x: 16, y: 31))
                path.addCurve(to: CGPoint(x: 21, y: 22), control1: CGPoint(x: 25, y: 28), control2: CGPoint(x: 14, y: 26))
            case .beach:
                path.move(to: CGPoint(x: 12, y: 18))
                path.addQuadCurve(to: CGPoint(x: 20, y: 5), control: CGPoint(x: 12, y: 8))
                path.addQuadCurve(to: CGPoint(x: 28, y: 18), control: CGPoint(x: 28, y: 8))
            case .culture:
                path.move(to: CGPoint(x: 12, y: 8))
                path.addLine(to: CGPoint(x: 20, y: 5))
                path.addLine(to: CGPoint(x: 28, y: 8))
            case .stay:
                path.addRoundedRect(in: CGRect(x: 8, y: 11, width: 10, height: 6), cornerSize: CGSize(width: 2, height: 2))
                path.addRoundedRect(in: CGRect(x: 22, y: 11, width: 10, height: 6), cornerSize: CGSize(width: 2, height: 2))
                path.move(to: CGPoint(x: 5, y: 21))
                path.addLine(to: CGPoint(x: 35, y: 21))
            case .shop:
                path.move(to: CGPoint(x: 13, y: 15))
                path.addLine(to: CGPoint(x: 13, y: 10))
                path.addCurve(to: CGPoint(x: 27, y: 10), control1: CGPoint(x: 13, y: 0), control2: CGPoint(x: 27, y: 0))
                path.addLine(to: CGPoint(x: 27, y: 15))
            case .wellness:
                path.move(to: CGPoint(x: 10, y: 13))
                path.addCurve(to: CGPoint(x: 15, y: 24), control1: CGPoint(x: 7, y: 16), control2: CGPoint(x: 12, y: 22))
            case .place:
                path.move(to: CGPoint(x: 14, y: 5))
                path.addLine(to: CGPoint(x: 14, y: 29))
                path.move(to: CGPoint(x: 26, y: 10))
                path.addLine(to: CGPoint(x: 26, y: 34))
                path.move(to: CGPoint(x: 8, y: 22))
                path.addCurve(to: CGPoint(x: 31, y: 16), control1: CGPoint(x: 13, y: 11), control2: CGPoint(x: 22, y: 29))
            }
        }
    }
}
#endif
