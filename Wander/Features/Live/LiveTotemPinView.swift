import SwiftUI

/// Category pictograms shared by production Live pins and simulator design reviews.
/// Emoji are input metadata only; the pin renders native monochrome symbols.
enum MapCategoryPictogram: String, CaseIterable {
    case coffee, dining, noodles, bar, bakery, nature, trail, beach, culture, stay, shop, wellness, place

    static func resolve(emoji: String) -> Self {
        let key = emoji.replacingOccurrences(of: "\u{FE0F}", with: "")
            .replacingOccurrences(of: "\u{FE0E}", with: "")
        switch key {
        case "☕", "🫖", "🧋", "🥤", "🧃": return .coffee
        case "🍽", "🍴", "🍕", "🍔", "🌭", "🌮", "🌯", "🥪", "🥗", "🥞", "🍗", "🦪", "🐟", "🥩",
             "🥟", "🧆", "🥙", "🥡", "🍱", "🍣", "🍝", "🥘", "🍛", "🍚", "🍤": return .dining
        case "🍜", "🍲": return .noodles
        case "🍸", "🍹", "🍷", "🍺", "🍻", "🥃", "🍶", "🪩": return .bar
        case "🥐", "🥯", "🍩", "🎂", "🍰", "🍦", "🍨", "🍫", "🍬", "🧁", "🍪": return .bakery
        case "🌳", "🌲", "🌴", "🌿", "🌻", "🌷", "🌺", "🌱", "🧺", "🛝", "🐕", "🐾", "🦌": return .nature
        case "🥾", "🏔", "⛰", "🏞", "🌄", "⛺", "🪨", "🧗", "🚴", "🎿": return .trail
        case "🏖", "🏝", "🌊", "💦", "🏄", "🛶", "⚓", "🎣": return .beach
        case "🏛", "🎨", "🎭", "🎟", "🎫", "🎵", "🎶", "🎷", "🎧", "🎤", "🎙", "🎬", "🎪", "🏰", "🗿", "⛲", "🎡", "🎢", "🔭": return .culture
        case "🏨", "🛏", "🏡", "🛖", "🏠": return .stay
        case "🛍", "🛒", "🏬", "👕", "👗", "👟", "📚", "💐", "🎁": return .shop
        case "🧘", "💆", "🧖", "💪", "💈", "💇", "💅", "💄", "♨", "🩺", "🏥", "💊", "🦷", "🧠": return .wellness
        default: return .place
        }
    }

    var symbolName: String {
        switch self {
        case .coffee: "cup.and.saucer.fill"
        case .dining: "fork.knife"
        case .noodles: "takeoutbag.and.cup.and.straw.fill"
        case .bar: "wineglass.fill"
        case .bakery: "birthday.cake.fill"
        case .nature: "leaf.fill"
        case .trail: "mountain.2.fill"
        case .beach: "beach.umbrella.fill"
        case .culture: "building.columns.fill"
        case .stay: "bed.double.fill"
        case .shop: "bag.fill"
        case .wellness: "heart.fill"
        case .place: "location.fill"
        }
    }

    var outlineSymbolName: String {
        switch self {
        case .coffee: "cup.and.saucer"
        case .dining: "fork.knife"
        case .noodles: "takeoutbag.and.cup.and.straw"
        case .bar: "wineglass"
        case .bakery: "birthday.cake"
        case .nature: "leaf"
        case .trail: "mountain.2"
        case .beach: "beach.umbrella"
        case .culture: "building.columns"
        case .stay: "bed.double"
        case .shop: "bag"
        case .wellness: "heart"
        case .place: "location"
        }
    }

}

/// A single place tile. Ownership and save status live in the footing; list
/// membership is a separate cap mark, never another tile or invented count.
struct LiveTotemPinView: View {
    let state: LiveTotemState
    let categoryEmoji: String
    let selected: Bool
    let viewed: Bool
    let compact: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDark: Bool { colorScheme == .dark }
    private var isCompact: Bool { compact && !selected }
    private var isSoftened: Bool { viewed && !selected }
    private var tileWidth: CGFloat { selected ? 32 : 29 }
    private var tileHeight: CGFloat { selected ? 44 : 40 }
    private var footingHeight: CGFloat { 10 }
    private var footingCenter: CGFloat { (tileHeight - footingHeight) / 2 }
    private var category: MapCategoryPictogram { .resolve(emoji: categoryEmoji) }
    private var selectionColor: Color { isDark ? AstirTheme.paperRaised.color : AstirTheme.ink.color }

    var body: some View {
        ZStack {
            if isCompact {
                compactDot
            } else {
                if selected {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(selectionColor.opacity(isDark ? 0.13 : 0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(selectionColor, lineWidth: 2)
                        }
                        .frame(width: tileWidth + 8, height: tileHeight + 8)
                }
                tile
            }
        }
        // The density fallback changes only the drawing, never its tap target
        // or the map coordinate at the center of the category pictogram.
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityHidden(true) // The annotation Button supplies place + semantic state.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isCompact)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: selected)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isSoftened)
    }

    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LiveTotemPinPalette.body(isDark: isDark, softened: isSoftened))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isDark ? AstirTheme.paperRaised.color.opacity(0.35) : AstirTheme.ink.color.opacity(0.12),
                            lineWidth: 0.6
                        )
                }
                .shadow(color: .black.opacity(isSoftened ? 0.14 : (isDark ? 0.4 : 0.23)),
                        radius: selected ? 4 : 2, y: selected ? 3 : 2)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AstirTheme.ink.color)
                .mask(alignment: .bottom) { Rectangle().frame(height: footingHeight) }

            Image(systemName: category.symbolName)
                .resizable()
                .scaledToFit()
                .font(.system(size: selected ? 22 : 20, weight: .medium))
                .foregroundStyle(AstirTheme.ink.color.opacity(isSoftened ? 0.58 : 1))
                .frame(width: tileWidth - 7, height: selected ? 22 : 20)

            if state.hasListMembership {
                Image(systemName: PlaceListSymbol.systemImage)
                    .font(.system(size: selected ? 7.5 : 7, weight: .heavy))
                    .foregroundStyle(AstirTheme.ink.color)
                    .offset(y: selected ? -16.5 : -14.5)
            }

            LiveTotemStatusRails(outlines: state.rails)
                .frame(width: selected ? 22 : 20)
                .offset(y: footingCenter)
        }
        .frame(width: tileWidth, height: tileHeight)
    }

    private var compactDot: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let circle = Path(ellipseIn: bounds)
            if state.rails.isEmpty {
                context.fill(circle, with: .color(AstirTheme.ink.color))
            } else {
                // Tiny dots need explicit segment widths in both MapKit and
                // ImageRenderer; flexible child layout can lose one color.
                context.clip(to: circle)
                let segmentWidth = size.width / CGFloat(state.rails.count)
                for (index, outline) in state.rails.enumerated() {
                    let segment = CGRect(x: CGFloat(index) * segmentWidth, y: 0,
                                         width: segmentWidth, height: size.height)
                    context.fill(Path(segment), with: .color(
                        LiveTotemPinPalette.color(for: outline.ownership)
                    ))
                }
            }
        }
        .frame(width: 10, height: 10)
        .overlay { Circle().strokeBorder(AstirTheme.paperRaised.color, lineWidth: 1.4) }
        .shadow(color: .black.opacity(isDark ? 0.4 : 0.22), radius: 1.5, y: 1)
    }
}

/// Pin and source-filter accents share the same semantic colors. Featured is a
/// fallback supplied by LiveTotemState, never inferred from absent save rows.
enum LiveTotemPinPalette {
    static func color(for ownership: MapPinSaveOwnership) -> Color {
        switch ownership {
        case .currentUser: WanderTheme.pinYou.color
        case .social: WanderTheme.pinSocial.color
        case .featured: Color(red: 111.0 / 255, green: 185.0 / 255, blue: 133.0 / 255)
        }
    }

    static func body(isDark: Bool, softened: Bool) -> Color {
        switch (isDark, softened) {
        case (false, false): AstirTheme.paperRaised.color
        case (false, true): AstirTheme.paperRecessed.color
        case (true, false): AstirTheme.paper.color
        case (true, true): Color(red: 216.0 / 255, green: 206.0 / 255, blue: 189.0 / 255)
        }
    }
}

private struct LiveTotemStatusRails: View {
    let outlines: [MapPinOutline]

    var body: some View {
        VStack(spacing: 2.5) {
            ForEach(Array(outlines.enumerated()), id: \.offset) { _, outline in
                HStack(spacing: 3) {
                    segment(outline.status, ownership: outline.ownership)
                    if let secondary = outline.secondaryStatus {
                        segment(secondary, ownership: outline.ownership)
                    }
                }
                .frame(height: 2.5)
            }
        }
    }

    private func segment(_ status: PlaceStatus, ownership: MapPinSaveOwnership) -> some View {
        LiveTotemRailLine()
            .stroke(LiveTotemPinPalette.color(for: ownership), style: StrokeStyle(
                lineWidth: 2.5,
                lineCap: .round,
                dash: status == .wannaGo ? [0.1, 3.8] : []
            ))
    }
}

private struct LiveTotemRailLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + 1.25, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 1.25, y: rect.midY))
        }
    }
}
