#if DEBUG
import SwiftUI

enum AddLauncherMockupPage: String, CaseIterable {
    case quickGrid
    case sourceTabs
    case smartInput
    case actionDock

    static func resolved(from arguments: [String] = ProcessInfo.processInfo.arguments) -> AddLauncherMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderAddLauncherMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .quickGrid
        }

        return AddLauncherMockupPage(rawValue: arguments[valueIndex]) ?? .quickGrid
    }

    var reviewTitle: String {
        switch self {
        case .quickGrid: "A · quick grid"
        case .sourceTabs: "B · source tabs"
        case .smartInput: "C · smart input"
        case .actionDock: "D · action dock"
        }
    }
}

struct AddLauncherMockupRoot: View {
    let page: AddLauncherMockupPage
    @State private var isPresentingAdd = false

    var body: some View {
        AddLauncherMapBackdrop(page: page, isPresentingAdd: isPresentingAdd)
            .preferredColorScheme(.light)
            .onAppear {
                isPresentingAdd = true
            }
            .sheet(isPresented: $isPresentingAdd) {
                AddLauncherSheetMockup(page: page) {
                    isPresentingAdd = false
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(WanderTheme.surfaceBone.color)
                .presentationContentInteraction(.scrolls)
            }
    }
}

private struct AddLauncherMapBackdrop: View {
    let page: AddLauncherMockupPage
    let isPresentingAdd: Bool

    var body: some View {
        ZStack {
            WanderTheme.canvasWarm.color.ignoresSafeArea()
            AddLauncherMapCanvas().ignoresSafeArea()

            VStack(spacing: 0) {
                reviewBadge
                mapSearch
                filterChips
                Spacer()
                mapAttribution
                mockTabBar
            }
        }
    }

    private var reviewBadge: some View {
        Text(page.reviewTitle.uppercased())
            .font(.system(size: 11, weight: .black))
            .tracking(0.8)
            .foregroundStyle(WanderTheme.terracottaDark.color)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(WanderTheme.terracottaTint.color.opacity(0.94))
    }

    private var mapSearch: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Text("search a place, vibe, or person")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(height: 46)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing3)
    }

    private var filterChips: some View {
        HStack(spacing: WanderTheme.spacing2) {
            AddLauncherMapChip(title: "you", isSelected: true)
            AddLauncherMapChip(title: "friends", isSelected: false)
            AddLauncherMapChip(title: "wanna go", isSelected: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
    }

    private var mapAttribution: some View {
        HStack {
            Spacer()
            Text("Los Angeles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .padding(.horizontal, WanderTheme.spacing2)
                .padding(.vertical, WanderTheme.spacing1)
                .background(WanderTheme.surfaceBone.color.opacity(0.88))
                .clipShape(Capsule())
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.bottom, WanderTheme.spacing2)
    }

    private var mockTabBar: some View {
        HStack {
            AddLauncherTabItem(title: "Map", systemImage: "map", isSelected: !isPresentingAdd)
            AddLauncherTabItem(title: "Discover", systemImage: "sparkle.magnifyingglass", isSelected: false)
            AddLauncherTabItem(title: "Add", systemImage: "plus", isSelected: isPresentingAdd)
            AddLauncherTabItem(title: "Lists", systemImage: "bookmark.square", isSelected: false)
            AddLauncherTabItem(title: "Profile", systemImage: "person.crop.circle", isSelected: false)
        }
        .padding(.horizontal, WanderTheme.spacing2)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing3)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WanderTheme.borderHairline.color.opacity(0.7))
                .frame(height: 0.5)
        }
    }
}

private struct AddLauncherMapCanvas: View {
    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(red: 0.93, green: 0.88, blue: 0.80))
            )

            var park = Path()
            park.addEllipse(in: CGRect(x: size.width * 0.56, y: size.height * 0.12, width: 190, height: 250))
            context.fill(park, with: .color(WanderTheme.categorySage.color.opacity(0.34)))

            let roadColor = Color.white.opacity(0.82)
            drawRoad(in: &context, size: size, start: CGPoint(x: -20, y: size.height * 0.34), end: CGPoint(x: size.width + 20, y: size.height * 0.54), bend: -70, color: roadColor, width: 14)
            drawRoad(in: &context, size: size, start: CGPoint(x: size.width * 0.25, y: -20), end: CGPoint(x: size.width * 0.62, y: size.height + 20), bend: 100, color: roadColor, width: 11)
            drawRoad(in: &context, size: size, start: CGPoint(x: -20, y: size.height * 0.72), end: CGPoint(x: size.width + 20, y: size.height * 0.66), bend: 55, color: roadColor, width: 9)

            for index in 0..<6 {
                let y = size.height * (0.18 + CGFloat(index) * 0.105)
                drawRoad(in: &context, size: size, start: CGPoint(x: 0, y: y), end: CGPoint(x: size.width, y: y + 32), bend: CGFloat(index.isMultiple(of: 2) ? 18 : -12), color: roadColor.opacity(0.54), width: 4)
            }
        }
        .overlay {
            ZStack {
                AddLauncherMapPin(emoji: "☕️", color: WanderTheme.terracotta.color, isDashed: false)
                    .offset(x: -92, y: -96)
                AddLauncherMapPin(emoji: "🍜", color: WanderTheme.pinSocial.color, isDashed: false)
                    .offset(x: 88, y: -38)
                AddLauncherMapPin(emoji: "🌳", color: WanderTheme.terracotta.color, isDashed: true)
                    .offset(x: 52, y: 98)
                AddLauncherMapPin(emoji: "🍸", color: WanderTheme.pinSocial.color, isDashed: true)
                    .offset(x: -110, y: 128)
            }
        }
    }

    private func drawRoad(
        in context: inout GraphicsContext,
        size: CGSize,
        start: CGPoint,
        end: CGPoint,
        bend: CGFloat,
        color: Color,
        width: CGFloat
    ) {
        var road = Path()
        road.move(to: start)
        road.addCurve(
            to: end,
            control1: CGPoint(x: size.width * 0.33, y: start.y + bend),
            control2: CGPoint(x: size.width * 0.67, y: end.y - bend)
        )
        context.stroke(road, with: .color(color), lineWidth: width)
    }
}

private struct AddLauncherMapPin: View {
    let emoji: String
    let color: Color
    let isDashed: Bool

    var body: some View {
        Text(emoji)
            .font(.system(size: 19))
            .frame(width: 40, height: 40)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, dash: isDashed ? [4, 3] : []))
            }
            .shadow(color: Color.black.opacity(0.16), radius: 7, x: 0, y: 4)
    }
}

private struct AddLauncherMapChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(height: 36)
            .background(isSelected ? WanderTheme.terracotta.color : WanderTheme.surfaceBone.color.opacity(0.94))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: isSelected ? 0 : 1))
    }
}

private struct AddLauncherTabItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: isSelected ? .black : .semibold))
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
        }
        .foregroundStyle(isSelected ? WanderTheme.terracotta.color : WanderTheme.textMuted.color)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

private struct AddLauncherSheetMockup: View {
    let page: AddLauncherMockupPage
    let dismiss: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                header

                switch page {
                case .quickGrid:
                    QuickGridDirection()
                case .sourceTabs:
                    SourceTabsDirection()
                case .smartInput:
                    SmartInputDirection()
                case .actionDock:
                    ActionDockDirection()
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing1)
            .padding(.bottom, WanderTheme.spacing4)
        }
        .scrollIndicators(.hidden)
        .background(WanderTheme.surfaceBone.color)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("add a place")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("pick the fastest way")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .frame(width: 30, height: 30)
                    .background(WanderTheme.surfaceSand.color)
                    .clipShape(Circle())
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close add place")
        }
    }
}

private struct QuickGridDirection: View {
    private let columns = [
        GridItem(.flexible(), spacing: WanderTheme.spacing2),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            AddLauncherSearchField(placeholder: "search a place or area")

            LazyVGrid(columns: columns, spacing: WanderTheme.spacing2) {
                AddLauncherActionTile(title: "I'm here now", systemImage: "location.fill", emphasis: .primary)
                AddLauncherActionTile(title: "Paste a link", systemImage: "link", emphasis: .plain)
                AddLauncherActionTile(title: "Coordinates", systemImage: "mappin.and.ellipse", emphasis: .plain)
                AddLauncherActionTile(title: "From a photo", systemImage: "photo", emphasis: .plain)
            }

            AddLauncherPrivacyNote()
        }
    }
}

private struct SourceTabsDirection: View {
    @State private var selection = AddLauncherSourceTab.hereNow

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            AddLauncherSearchField(placeholder: "search a place or area")

            HStack(spacing: WanderTheme.spacing1) {
                ForEach(AddLauncherSourceTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 14, weight: .bold))
                            Text(tab.title)
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selection == tab ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(selection == tab ? WanderTheme.terracotta.color : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(WanderTheme.spacing1)
            .background(WanderTheme.surfaceSand.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))

            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: selection.systemImage)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                Text(selection.helper)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
                Spacer(minLength: WanderTheme.spacing2)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 48)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium).stroke(WanderTheme.borderHairline.color))

            Button {} label: {
                Label("From a photo", systemImage: "photo")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .background(WanderTheme.surfaceSand.color)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private enum AddLauncherSourceTab: String, CaseIterable, Identifiable {
    case hereNow
    case link
    case coordinates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hereNow: "Here now"
        case .link: "Link"
        case .coordinates: "Coords"
        }
    }

    var systemImage: String {
        switch self {
        case .hereNow: "location.fill"
        case .link: "link"
        case .coordinates: "mappin.and.ellipse"
        }
    }

    var helper: String {
        switch self {
        case .hereNow: "Show nearby places. Your location stays private."
        case .link: "Paste an Apple Maps, Google Maps, or social link."
        case .coordinates: "Paste latitude and longitude."
        }
    }
}

private struct SmartInputDirection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("Search, link, or coordinates")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text("Place, link, or coordinates")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textFaint.color)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("Paste")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .padding(.horizontal, WanderTheme.spacing2)
                    .frame(height: 32)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 54)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderStrong.color))

            HStack(spacing: WanderTheme.spacing2) {
                AddLauncherCompactAction(title: "I'm here now", systemImage: "location.fill", isPrimary: true)
                AddLauncherCompactAction(title: "From a photo", systemImage: "photo", isPrimary: false)
            }

            Text("One box recognizes a place name, map link, or coordinates.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct ActionDockDirection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            AddLauncherSearchField(placeholder: "search for a place")

            VStack(spacing: 0) {
                AddLauncherDockRow(
                    title: "I'm here now",
                    subtitle: "find nearby places",
                    systemImage: "location.fill",
                    isPrimary: true
                )
                Divider().background(WanderTheme.borderHairline.color)
                AddLauncherDockRow(
                    title: "Paste link or coordinates",
                    subtitle: "we'll figure out the format",
                    systemImage: "doc.on.clipboard",
                    isPrimary: false
                )
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderHairline.color))

            Button {} label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "photo")
                        .font(.system(size: 14, weight: .black))
                    Text("From a photo")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text("scan text")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .foregroundStyle(WanderTheme.textInk.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceSand.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AddLauncherSearchField: View {
    let placeholder: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Text(placeholder)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WanderTheme.textFaint.color)
            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: WanderTheme.tapMinimum)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
    }
}

private enum AddLauncherActionEmphasis {
    case primary
    case plain
}

private struct AddLauncherActionTile: View {
    let title: String
    let systemImage: String
    let emphasis: AddLauncherActionEmphasis

    var body: some View {
        Button {} label: {
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .black))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(emphasis == .primary ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(emphasis == .primary ? WanderTheme.terracotta.color : WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .overlay {
                if emphasis == .plain {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                        .stroke(WanderTheme.borderHairline.color)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AddLauncherCompactAction: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool

    var body: some View {
        Button {} label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isPrimary ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .background(isPrimary ? WanderTheme.terracotta.color : WanderTheme.surfaceSand.color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct AddLauncherDockRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isPrimary: Bool

    var body: some View {
        Button {} label: {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(isPrimary ? WanderTheme.textOnAction.color : WanderTheme.terracottaDark.color)
                    .frame(width: 34, height: 34)
                    .background(isPrimary ? WanderTheme.terracotta.color : WanderTheme.terracottaTint.color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AddLauncherPrivacyNote: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .black))
            Text("Nearby only. Your location stays private.")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(WanderTheme.textMuted.color)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
#endif
