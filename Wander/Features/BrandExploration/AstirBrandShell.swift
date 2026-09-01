#if DEBUG
import MapKit
import SwiftUI
import UIKit

enum AstirBrandShellPage: String, CaseIterable {
    case map
    case feed
    case lists
    case add
    case profile

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AstirBrandShellPage? {
        if let environmentValue = environment["WANDER_ASTIR_BRAND_SHELL"] {
            return AstirBrandShellPage(rawValue: environmentValue) ?? .map
        }

        guard let flagIndex = arguments.firstIndex(of: "-AstirBrandShell") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .map
        }

        return AstirBrandShellPage(rawValue: arguments[valueIndex]) ?? .map
    }

    fileprivate var initialTab: AstirShellTab {
        switch self {
        case .map, .add:
            return .map
        case .feed:
            return .feed
        case .lists:
            return .lists
        case .profile:
            return .profile
        }
    }

    fileprivate var presentsAdd: Bool {
        self == .add
    }
}

private enum AstirShellTab: String, CaseIterable, Hashable {
    case map
    case feed
    case lists
    case profile

    var title: String {
        switch self {
        case .map: "Map"
        case .feed: "Feed"
        case .lists: "Lists"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .map: "map"
        case .feed: "newspaper"
        case .lists: "bookmark.square"
        case .profile: "person.crop.circle"
        }
    }
}

struct AstirBrandShellRoot: View {
    let page: AstirBrandShellPage

    @State private var selectedTab: AstirShellTab
    @State private var isPresentingAdd: Bool

    init(page: AstirBrandShellPage) {
        self.page = page
        _selectedTab = State(initialValue: page.initialTab)
        _isPresentingAdd = State(initialValue: page.presentsAdd)
    }

    var body: some View {
        AstirTabShell(
            selectedTab: $selectedTab,
            presentAdd: { isPresentingAdd = true }
        )
        .sheet(isPresented: $isPresentingAdd) {
            AstirAddView {
                isPresentingAdd = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
            .presentationBackground(AstirPalette.paper)
        }
        .preferredColorScheme(.light)
        .tint(AstirPalette.clay)
        .accessibilityIdentifier("astir.brand.shell")
    }
}

private struct AstirTabShell: View {
    @Binding var selectedTab: AstirShellTab
    let presentAdd: () -> Void

    var body: some View {
        Group {
            switch selectedTab {
            case .map:
                AstirMapView(presentAdd: presentAdd)
            case .feed:
                AstirFeedView(presentAdd: presentAdd)
            case .lists:
                AstirListsView()
            case .profile:
                AstirProfileView()
            }
        }
        .background(AstirPalette.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AstirTabBar(selectedTab: $selectedTab)
        }
    }
}

private struct AstirMapView: View {
    let presentAdd: () -> Void

    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0038, longitude: -118.4861),
            span: MKCoordinateSpan(latitudeDelta: 0.021, longitudeDelta: 0.026)
        )
    )

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                Annotation(
                    "Bar Monette",
                    coordinate: CLLocationCoordinate2D(latitude: 34.0033, longitude: -118.4817)
                ) {
                    AstirMapPin(symbol: "fork.knife", color: AstirPalette.clay, isSelected: true)
                }

                Annotation(
                    "Gjusta",
                    coordinate: CLLocationCoordinate2D(latitude: 33.9958, longitude: -118.4748)
                ) {
                    AstirMapPin(symbol: "cup.and.saucer.fill", color: AstirPalette.pool)
                }

                Annotation(
                    "Heavy Handed",
                    coordinate: CLLocationCoordinate2D(latitude: 34.0105, longitude: -118.4934)
                ) {
                    AstirMapPin(symbol: "takeoutbag.and.cup.and.straw.fill", color: AstirPalette.signal)
                }

                Annotation(
                    "The Rose",
                    coordinate: CLLocationCoordinate2D(latitude: 34.0004, longitude: -118.4761)
                ) {
                    AstirMapPin(symbol: "wineglass.fill", color: AstirPalette.pool)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    AstirWordmark(color: AstirPalette.ink)
                    Spacer()
                    AstirRoundActionButton(
                        systemName: "plus",
                        accessibilityLabel: "Add a place",
                        action: presentAdd
                    )
                }

                AstirSearchField(placeholder: "Search places, people, or a vibe")

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        AstirFilterChip(title: "You", isSelected: true)
                        AstirFilterChip(title: "Following")
                        AstirFilterChip(title: "Friends")
                        AstirFilterChip(title: "Been")
                        AstirFilterChip(title: "Wanna go")
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            VStack {
                Spacer()
                AstirSelectedPlaceCard()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .accessibilityIdentifier("astir.map.screen")
    }
}

private struct AstirMapPin: View {
    let symbol: String
    let color: Color
    var isSelected = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AstirPalette.paper)
            .frame(width: isSelected ? 44 : 38, height: isSelected ? 44 : 38)
            .background(color)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(AstirPalette.paper, lineWidth: isSelected ? 4 : 2)
            }
            .shadow(color: AstirPalette.ink.opacity(0.18), radius: 7, y: 4)
    }
}

private struct AstirSelectedPlaceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 14) {
                AstirCroppedAssetImage(
                    assetName: "PlaceCarouselPhotos",
                    normalizedRect: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
                )
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Bar Monette")
                            .font(AstirType.display(25))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text("PIZZA · OCEAN PARK")
                        .font(AstirType.meta(11))
                        .tracking(1)
                        .foregroundStyle(AstirPalette.clay)
                    Text("Maya, Jonah, and 3 people you follow saved this.")
                        .font(AstirType.ui(12, weight: .medium))
                        .foregroundStyle(AstirPalette.inkMuted)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 10) {
                Label("Been", systemImage: "checkmark")
                    .font(AstirType.ui(12, weight: .bold))
                    .foregroundStyle(AstirPalette.paper)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(AstirPalette.ink)
                    .clipShape(Capsule())

                Label("Wanna go", systemImage: "bookmark")
                    .font(AstirType.ui(12, weight: .bold))
                    .foregroundStyle(AstirPalette.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .overlay { Capsule().stroke(AstirPalette.lineStrong, lineWidth: 1) }

                Spacer()
                AstirAvatarStack(initials: ["MC", "JL", "AR"], size: 28)
            }
        }
        .padding(16)
        .background(AstirPalette.paper.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AstirPalette.line, lineWidth: 1)
        }
        .shadow(color: AstirPalette.ink.opacity(0.12), radius: 14, y: 6)
    }
}

private struct AstirFeedView: View {
    let presentAdd: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                AstirScreenHeader(
                    kicker: "YOUR PEOPLE",
                    actionSystemName: "plus",
                    actionAccessibilityLabel: "Add a place",
                    action: presentAdd
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("Where your people\nhave been.")
                        .font(AstirType.display(39))
                        .foregroundStyle(AstirPalette.ink)
                        .lineSpacing(-2)
                    Text("Real places, from people whose taste you trust.")
                        .font(AstirType.ui(15, weight: .semibold))
                        .foregroundStyle(AstirPalette.inkMuted)
                }

                AstirPeopleRow()
                AstirSectionHeader(number: "01", title: "Recent from friends")

                AstirActivityCard(
                    crop: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                    actor: "Maya",
                    action: "saved a place",
                    initials: "MC",
                    avatarColor: AstirPalette.clay,
                    place: "Bar Monette",
                    metadata: "PIZZA · OCEAN PARK",
                    note: "Tiny room, perfect crust, go early enough to get the counter."
                )

                AstirActivityCard(
                    crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                    actor: "Alex",
                    action: "checked in",
                    initials: "AR",
                    avatarColor: AstirPalette.signal,
                    place: "Gjusta",
                    metadata: "BAKERY · VENICE",
                    note: "The patio is calm before nine. Coffee, sesame croissant, no notes."
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("astir.feed.screen")
    }
}

private struct AstirPeopleRow: View {
    private let people: [(String, String, Color)] = [
        ("Maya", "MC", AstirPalette.clay),
        ("Jonah", "JL", AstirPalette.pool),
        ("Alex", "AR", AstirPalette.signal),
        ("Tessa", "TS", AstirPalette.deepOcean),
    ]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                VStack(spacing: 7) {
                    AstirAvatar(initials: person.1, size: 52, color: person.2)
                    Text(person.0)
                        .font(AstirType.ui(11, weight: .bold))
                        .foregroundStyle(AstirPalette.ink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AstirPalette.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AstirPalette.line, lineWidth: 1)
        }
    }
}

private struct AstirActivityCard: View {
    let crop: CGRect
    let actor: String
    let action: String
    let initials: String
    let avatarColor: Color
    let place: String
    let metadata: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AstirAvatar(initials: initials, size: 38, color: avatarColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(actor)
                        .font(AstirType.ui(14, weight: .bold))
                    Text(action)
                        .font(AstirType.ui(12, weight: .medium))
                        .foregroundStyle(AstirPalette.inkMuted)
                }
                Spacer()
                Text("2H")
                    .font(AstirType.meta(10))
                    .foregroundStyle(AstirPalette.inkMuted)
            }
            .padding(15)

            AstirCroppedAssetImage(assetName: "PlaceCarouselPhotos", normalizedRect: crop)
                .frame(height: 220)

            VStack(alignment: .leading, spacing: 7) {
                Text(place)
                    .font(AstirType.display(27))
                Text(metadata)
                    .font(AstirType.meta(11))
                    .tracking(1)
                    .foregroundStyle(AstirPalette.clay)
                Text("“\(note)”")
                    .font(AstirType.body(15, weight: .medium))
                    .foregroundStyle(AstirPalette.inkMuted)
                    .lineSpacing(3)
                HStack(spacing: 18) {
                    Label("12", systemImage: "heart")
                    Label("3", systemImage: "bubble.left")
                    Spacer()
                    Image(systemName: "bookmark")
                }
                .font(AstirType.ui(12, weight: .bold))
                .foregroundStyle(AstirPalette.ink)
                .padding(.top, 5)
            }
            .padding(16)
        }
        .background(AstirPalette.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AstirPalette.line, lineWidth: 1)
        }
    }
}

private struct AstirListsView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                AstirScreenHeader(
                    kicker: "PLACES WITH A PLAN",
                    actionSystemName: "plus",
                    actionAccessibilityLabel: "New list"
                ) {}

                VStack(alignment: .leading, spacing: 7) {
                    Text("Places, held\nfor later.")
                        .font(AstirType.display(39))
                        .foregroundStyle(AstirPalette.ink)
                        .lineSpacing(-2)
                    Text("Save places into a plan you can actually use.")
                        .font(AstirType.ui(15, weight: .semibold))
                        .foregroundStyle(AstirPalette.inkMuted)
                }

                AstirListCard(
                    crop: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                    title: "Tonight",
                    subtitle: "Easy tables close to home",
                    count: "8 PLACES",
                    initials: ["JL", "MC"]
                )

                AstirSectionHeader(number: "02", title: "Your lists")

                HStack(alignment: .top, spacing: 12) {
                    AstirCompactListCard(
                        crop: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                        title: "Date night",
                        detail: "12 places"
                    )
                    AstirCompactListCard(
                        crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                        title: "Saturday coffee",
                        detail: "6 places"
                    )
                }

                AstirListRow(
                    title: "Parents in town",
                    detail: "9 places · shared with Maya",
                    color: AstirPalette.pool
                )
                AstirListRow(
                    title: "Wanna go",
                    detail: "38 places · private",
                    color: AstirPalette.clay
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("astir.lists.screen")
    }
}

private struct AstirListCard: View {
    let crop: CGRect
    let title: String
    let subtitle: String
    let count: String
    let initials: [String]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AstirCroppedAssetImage(assetName: "PlaceCarouselPhotos", normalizedRect: crop)
            LinearGradient(
                colors: [.clear, AstirPalette.ink.opacity(0.2), AstirPalette.ink.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(count)
                        .font(AstirType.meta(11))
                        .foregroundStyle(AstirPalette.signal)
                    Spacer()
                    AstirAvatarStack(initials: initials, size: 28)
                }
                Text(title)
                    .font(AstirType.display(34))
                    .foregroundStyle(AstirPalette.paper)
                Text(subtitle)
                    .font(AstirType.ui(14, weight: .semibold))
                    .foregroundStyle(AstirPalette.paper.opacity(0.78))
            }
            .padding(18)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AstirCompactListCard: View {
    let crop: CGRect
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AstirCroppedAssetImage(assetName: "PlaceCarouselPhotos", normalizedRect: crop)
                .frame(height: 132)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AstirType.ui(15, weight: .bold))
                    .foregroundStyle(AstirPalette.ink)
                Text(detail.uppercased())
                    .font(AstirType.meta(9))
                    .foregroundStyle(AstirPalette.inkMuted)
            }
            .padding(13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AstirPalette.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AstirPalette.line, lineWidth: 1)
        }
    }
}

private struct AstirListRow: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AstirPalette.paper)
                .frame(width: 42, height: 42)
                .background(color)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AstirType.ui(16, weight: .bold))
                Text(detail)
                    .font(AstirType.ui(12, weight: .medium))
                    .foregroundStyle(AstirPalette.inkMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AstirPalette.inkMuted)
        }
        .padding(.vertical, 4)
    }
}

private struct AstirProfileView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                AstirScreenHeader(
                    kicker: "YOUR PROFILE",
                    actionSystemName: "gearshape",
                    actionAccessibilityLabel: "Settings"
                ) {}

                HStack(alignment: .center, spacing: 16) {
                    AstirAvatar(initials: "JL", size: 78, color: AstirPalette.clay)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Joe")
                            .font(AstirType.display(35))
                            .foregroundStyle(AstirPalette.ink)
                        Text("@joe · Ocean Park")
                            .font(AstirType.ui(13, weight: .semibold))
                            .foregroundStyle(AstirPalette.inkMuted)
                        Text("Always looking for the table outside.")
                            .font(AstirType.ui(13, weight: .medium))
                            .foregroundStyle(AstirPalette.ink)
                    }
                }

                HStack(spacing: 10) {
                    AstirProfileStat(value: "84", label: "Been")
                    AstirProfileStat(value: "38", label: "Wanna")
                    AstirProfileStat(value: "26", label: "Friends")
                }

                AstirSectionHeader(number: "01", title: "This month")
                AstirMonthCard()

                AstirSectionHeader(number: "02", title: "Recent activity")
                VStack(spacing: 16) {
                    AstirRecentPlaceRow(
                        crop: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                        title: "Bar Monette",
                        detail: "Saved · today"
                    )
                    AstirRecentPlaceRow(
                        crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                        title: "Gjusta",
                        detail: "Checked in · Saturday"
                    )
                    AstirRecentPlaceRow(
                        crop: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                        title: "The Rose",
                        detail: "Recommended · Aug 22"
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("astir.profile.screen")
    }
}

private struct AstirProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AstirType.display(29))
                .foregroundStyle(AstirPalette.ink)
            Text(label.uppercased())
                .font(AstirType.meta(10))
                .foregroundStyle(AstirPalette.inkMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AstirPalette.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AstirPalette.line, lineWidth: 1)
        }
    }
}

private struct AstirMonthCard: View {
    private let days = ["M", "T", "W", "T", "F", "S", "S"]
    private let activeDays: Set<Int> = [0, 2, 3, 5]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("AUGUST")
                    .font(AstirType.meta(12))
                    .tracking(1.2)
                    .foregroundStyle(AstirPalette.clay)
                Spacer()
                Text("12 places · 4 check-ins")
                    .font(AstirType.ui(11, weight: .semibold))
                    .foregroundStyle(AstirPalette.inkMuted)
            }

            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 8) {
                        Text(day)
                            .font(AstirType.meta(10))
                            .foregroundStyle(AstirPalette.inkMuted)
                        Circle()
                            .fill(activeDays.contains(index) ? AstirPalette.clay : AstirPalette.line)
                            .frame(
                                width: activeDays.contains(index) ? 18 : 8,
                                height: activeDays.contains(index) ? 18 : 8
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text("You kept close to home and found four places worth returning to.")
                .font(AstirType.display(24))
                .foregroundStyle(AstirPalette.ink)
                .lineSpacing(3)
        }
        .padding(18)
        .background(AstirPalette.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AstirPalette.line, lineWidth: 1)
        }
    }
}

private struct AstirRecentPlaceRow: View {
    let crop: CGRect
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            AstirCroppedAssetImage(assetName: "PlaceCarouselPhotos", normalizedRect: crop)
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AstirType.ui(16, weight: .bold))
                    .foregroundStyle(AstirPalette.ink)
                Text(detail)
                    .font(AstirType.ui(12, weight: .medium))
                    .foregroundStyle(AstirPalette.inkMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AstirPalette.inkMuted)
        }
    }
}

private struct AstirAddView: View {
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    Capsule()
                        .fill(AstirPalette.lineStrong.opacity(0.7))
                        .frame(width: 38, height: 5)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .trailing) {
                            Button(action: dismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AstirPalette.ink)
                                    .frame(width: 40, height: 40)
                                    .background(AstirPalette.paperRaised)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                        }
                }

                AstirWordmark(color: AstirPalette.ink)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add to your map.")
                        .font(AstirType.display(40))
                        .foregroundStyle(AstirPalette.ink)
                    Text("Start with whatever you have. Organize it later.")
                        .font(AstirType.ui(15, weight: .semibold))
                        .foregroundStyle(AstirPalette.inkMuted)
                }

                VStack(spacing: 10) {
                    AstirAddSourceRow(
                        number: "01",
                        symbol: "location.fill",
                        title: "I’m here now",
                        detail: "Find the place around you",
                        color: AstirPalette.clay
                    )
                    AstirAddSourceRow(
                        number: "02",
                        symbol: "link",
                        title: "Paste a link",
                        detail: "Instagram, TikTok, Maps, or a website",
                        color: AstirPalette.pool
                    )
                    AstirAddSourceRow(
                        number: "03",
                        symbol: "magnifyingglass",
                        title: "Search manually",
                        detail: "Look up any place",
                        color: AstirPalette.deepOcean
                    )
                    AstirAddSourceRow(
                        number: "04",
                        symbol: "photo",
                        title: "Add from a photo",
                        detail: "Use a screenshot or camera roll",
                        color: AstirPalette.signal
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    AstirSectionHeader(number: "05", title: "Finish later")
                    Text("Unresolved places stay as drafts. Nothing gets lost because you didn’t have every detail.")
                        .font(AstirType.body(14, weight: .medium))
                        .foregroundStyle(AstirPalette.inkMuted)
                        .lineSpacing(3)
                }
                .padding(16)
                .background(AstirPalette.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AstirPalette.line, lineWidth: 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("astir.add.screen")
    }
}

private struct AstirAddSourceRow: View {
    let number: String
    let symbol: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        Button {} label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AstirPalette.paper)
                    .frame(width: 46, height: 46)
                    .background(color)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AstirType.ui(16, weight: .bold))
                        .foregroundStyle(AstirPalette.ink)
                    Text(detail)
                        .font(AstirType.ui(12, weight: .medium))
                        .foregroundStyle(AstirPalette.inkMuted)
                }
                Spacer()
                Text(number)
                    .font(AstirType.meta(11))
                    .foregroundStyle(color)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AstirPalette.inkMuted)
            }
            .padding(14)
            .background(AstirPalette.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AstirPalette.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AstirScreenHeader: View {
    let kicker: String
    let actionSystemName: String
    let actionAccessibilityLabel: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            AstirWordmark(color: AstirPalette.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(kicker)
                    .font(AstirType.meta(10))
                    .tracking(1.25)
                    .foregroundStyle(AstirPalette.clay)
                AstirRoundActionButton(
                    systemName: actionSystemName,
                    accessibilityLabel: actionAccessibilityLabel,
                    action: action
                )
            }
        }
    }
}

private struct AstirRoundActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AstirPalette.paper)
                .frame(width: 42, height: 42)
                .background(AstirPalette.ink)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct AstirSearchField: View {
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
            Text(placeholder)
                .font(AstirType.ui(13, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(AstirPalette.inkMuted)
        .padding(.horizontal, 15)
        .frame(minHeight: 46)
        .background(AstirPalette.paper.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AstirPalette.line, lineWidth: 1)
        }
        .shadow(color: AstirPalette.ink.opacity(0.08), radius: 8, y: 3)
    }
}

private struct AstirFilterChip: View {
    let title: String
    var isSelected = false

    var body: some View {
        Text(title)
            .font(AstirType.ui(12, weight: .bold))
            .foregroundStyle(isSelected ? AstirPalette.paper : AstirPalette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(isSelected ? AstirPalette.ink : AstirPalette.paper.opacity(0.97))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(isSelected ? .clear : AstirPalette.line, lineWidth: 1)
            }
    }
}

private struct AstirTabBar: View {
    @Binding var selectedTab: AstirShellTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AstirShellTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selectedTab == tab ? "\(tab.symbol).fill" : tab.symbol)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(AstirType.ui(10, weight: .bold))
                    }
                    .foregroundStyle(selectedTab == tab ? AstirPalette.clay : AstirPalette.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(AstirPalette.paper.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle().fill(AstirPalette.line).frame(height: 1)
        }
    }
}

private struct AstirSectionHeader: View {
    let number: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .foregroundStyle(AstirPalette.clay)
            Text(title.uppercased())
                .foregroundStyle(AstirPalette.ink)
            Spacer()
        }
        .font(AstirType.meta(11))
        .tracking(1.15)
    }
}

private struct AstirWordmark: View {
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ASTIR")
                .font(AstirType.wordmark(25))
                .tracking(5.5)
            Text("OCEAN PARK")
                .font(AstirType.meta(8))
                .tracking(2.5)
        }
        .foregroundStyle(color)
    }
}

private struct AstirAvatarStack: View {
    let initials: [String]
    let size: CGFloat

    var body: some View {
        HStack(spacing: -(size * 0.24)) {
            ForEach(Array(initials.enumerated()), id: \.offset) { index, value in
                AstirAvatar(
                    initials: value,
                    size: size,
                    color: AstirPalette.avatarColors[index % AstirPalette.avatarColors.count]
                )
                .overlay {
                    Circle().stroke(AstirPalette.paper, lineWidth: 2)
                }
            }
        }
    }
}

private struct AstirAvatar: View {
    let initials: String
    let size: CGFloat
    let color: Color

    var body: some View {
        Text(initials)
            .font(AstirType.ui(max(9, size * 0.29), weight: .bold))
            .foregroundStyle(AstirPalette.paper)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(Circle())
    }
}

private struct AstirCroppedAssetImage: View {
    let assetName: String
    let normalizedRect: CGRect

    var body: some View {
        GeometryReader { proxy in
            if let image = AstirImageCropper.image(
                named: assetName,
                normalizedRect: normalizedRect
            ) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                AstirPalette.deepOcean
            }
        }
    }
}

private enum AstirImageCropper {
    static func image(named name: String, normalizedRect: CGRect) -> UIImage? {
        guard let source = UIImage(named: name),
              let sourceCGImage = source.cgImage
        else {
            return nil
        }

        let clampedRect = CGRect(
            x: max(0, min(1, normalizedRect.origin.x)),
            y: max(0, min(1, normalizedRect.origin.y)),
            width: max(0.001, min(1 - normalizedRect.origin.x, normalizedRect.width)),
            height: max(0.001, min(1 - normalizedRect.origin.y, normalizedRect.height))
        )
        let pixelRect = CGRect(
            x: clampedRect.origin.x * CGFloat(sourceCGImage.width),
            y: clampedRect.origin.y * CGFloat(sourceCGImage.height),
            width: clampedRect.width * CGFloat(sourceCGImage.width),
            height: clampedRect.height * CGFloat(sourceCGImage.height)
        ).integral

        guard let croppedCGImage = sourceCGImage.cropping(to: pixelRect) else {
            return nil
        }

        return UIImage(
            cgImage: croppedCGImage,
            scale: source.scale,
            orientation: source.imageOrientation
        )
    }
}

private enum AstirPalette {
    static let paper = Color(astirHex: 0xF2E9DB)
    static let paperRaised = Color(astirHex: 0xFFF9EF)
    static let ink = Color(astirHex: 0x141714)
    static let deepOcean = Color(astirHex: 0x0E3033)
    static let clay = Color(astirHex: 0xC65A3C)
    static let signal = Color(astirHex: 0xF05A3C)
    static let pool = Color(astirHex: 0x3D6A78)
    static let inkMuted = Color(astirHex: 0x6F675D)
    static let line = Color(astirHex: 0xD8CCBD)
    static let lineStrong = Color(astirHex: 0xA99B8C)
    static let avatarColors = [clay, pool, signal, deepOcean]
}

private enum AstirType {
    static func wordmark(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("AvenirNext-Medium", size: size).weight(weight)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("AvenirNext-Medium", size: size).weight(weight)
    }

    static func meta(_ size: CGFloat) -> Font {
        .custom("AvenirNextCondensed-DemiBold", size: size)
    }
}

private extension Color {
    init(astirHex value: Int) {
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
#endif
