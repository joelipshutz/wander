#if DEBUG
import MapKit
import SwiftUI
import UIKit

enum AstirBrandShellPage: String, CaseIterable {
    case intro
    case today
    case map
    case event
    case arrival
    case present
    case memory
    case profile

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AstirBrandShellPage? {
        if let environmentValue = environment["WANDER_ASTIR_BRAND_SHELL"] {
            return AstirBrandShellPage(rawValue: environmentValue) ?? .intro
        }

        guard let flagIndex = arguments.firstIndex(of: "-AstirBrandShell") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .intro
        }

        return AstirBrandShellPage(rawValue: arguments[valueIndex]) ?? .intro
    }

    fileprivate var initialTab: AstirShellTab {
        switch self {
        case .map:
            return .map
        case .memory:
            return .memories
        case .profile:
            return .you
        case .intro, .today, .event, .arrival, .present:
            return .today
        }
    }

    fileprivate var initialRoute: AstirShellRoute? {
        switch self {
        case .event:
            return .event
        case .arrival:
            return .arrival
        case .present:
            return .present
        case .intro, .today, .map, .memory, .profile:
            return nil
        }
    }
}

private enum AstirShellRoute: Hashable {
    case event
    case arrival
    case present
}

private enum AstirShellTab: String, CaseIterable, Hashable {
    case today
    case map
    case memories
    case you

    var title: String {
        switch self {
        case .today: "today"
        case .map: "map"
        case .memories: "memories"
        case .you: "you"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sparkles"
        case .map: "map"
        case .memories: "rectangle.stack"
        case .you: "person.crop.circle"
        }
    }
}

struct AstirBrandShellRoot: View {
    let page: AstirBrandShellPage

    @State private var hasEntered: Bool
    @State private var selectedTab: AstirShellTab
    @State private var path: [AstirShellRoute]

    init(page: AstirBrandShellPage) {
        self.page = page
        _hasEntered = State(initialValue: page != .intro)
        _selectedTab = State(initialValue: page.initialTab)
        _path = State(initialValue: page.initialRoute.map { [$0] } ?? [])
    }

    private var shellColorScheme: ColorScheme {
        switch path.last {
        case .event, .arrival, .present:
            return .dark
        case nil:
            return .light
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hasEntered {
                    AstirTabShell(
                        selectedTab: $selectedTab,
                        openEvent: { path.append(.event) }
                    )
                } else {
                    AstirIntroView {
                        withAnimation(.easeOut(duration: 0.45)) {
                            hasEntered = true
                        }
                    }
                }
            }
            .navigationDestination(for: AstirShellRoute.self) { route in
                switch route {
                case .event:
                    AstirEventDetailView {
                        path.append(.arrival)
                    }
                case .arrival:
                    AstirArrivalView {
                        path.append(.present)
                    }
                case .present:
                    AstirPresenceView {
                        path.removeAll()
                        selectedTab = .memories
                    }
                }
            }
        }
        .preferredColorScheme(shellColorScheme)
        .tint(AstirPalette.clay)
        .accessibilityIdentifier("astir.brand.shell")
    }
}

private struct AstirIntroView: View {
    let enter: () -> Void

    var body: some View {
        ZStack {
            AstirCroppedAssetImage(
                assetName: "AstirWestsideBoard",
                normalizedRect: CGRect(x: 0.667, y: 0, width: 0.333, height: 0.333)
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    AstirPalette.ink.opacity(0.18),
                    AstirPalette.ink.opacity(0.72),
                    AstirPalette.ink.opacity(0.98),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    AstirWordmark(color: AstirPalette.paper)
                    Spacer()
                    AstirFrameMark(color: AstirPalette.paper.opacity(0.82))
                        .frame(width: 36, height: 36)
                }

                Spacer()

                Text("OCEAN PARK · CHAPTER 01")
                    .font(AstirType.meta(13))
                    .tracking(1.9)
                    .foregroundStyle(AstirPalette.signal)

                Text("A story\nyou’re in.")
                    .font(AstirType.display(54))
                    .foregroundStyle(AstirPalette.paper)
                    .lineSpacing(-4)
                    .padding(.top, 12)

                Text("Places you trust. Nights worth leaving home for. People you’ll see again.")
                    .font(AstirType.body(18, weight: .medium))
                    .foregroundStyle(AstirPalette.paper.opacity(0.82))
                    .lineSpacing(5)
                    .padding(.top, 20)
                    .frame(maxWidth: 320, alignment: .leading)

                Button(action: enter) {
                    HStack {
                        Text("Enter Ocean Park")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(AstirType.ui(16, weight: .bold))
                    .foregroundStyle(AstirPalette.ink)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(AstirPalette.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("astir.enter")
                .padding(.top, 32)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }
}

private struct AstirTabShell: View {
    @Binding var selectedTab: AstirShellTab
    let openEvent: () -> Void

    var body: some View {
        Group {
            switch selectedTab {
            case .today:
                AstirTodayView(openEvent: openEvent)
            case .map:
                AstirMapView(openEvent: openEvent)
            case .memories:
                AstirMemoryView()
            case .you:
                AstirProfileView()
            }
        }
        .background(AstirPalette.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AstirTabBar(selectedTab: $selectedTab)
        }
    }
}

private struct AstirTodayView: View {
    let openEvent: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                AstirAppHeader(kicker: "THURSDAY · 6:12 PM")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Close enough\nto become a night.")
                        .font(AstirType.display(38))
                        .foregroundStyle(AstirPalette.ink)
                    Text("Ocean Park, within 12 minutes")
                        .font(AstirType.ui(14, weight: .semibold))
                        .foregroundStyle(AstirPalette.inkMuted)
                }

                AstirEventCard(openEvent: openEvent)

                VStack(alignment: .leading, spacing: 12) {
                    AstirSectionHeader(number: "02", title: "Before the night")

                    AstirPlaceCard(
                        crop: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                        name: "Back Patio",
                        detail: "Dinner · courtyard · 6 min bike",
                        note: "Maya says: take the side table at golden hour."
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    AstirSectionHeader(number: "03", title: "A little farther out")
                    HStack(spacing: 12) {
                        AstirCompactSignal(
                            time: "SAT · 9 AM",
                            title: "Tower 26\nmorning swim",
                            color: AstirPalette.pool
                        )
                        AstirCompactSignal(
                            time: "SUN · 4 PM",
                            title: "Open studio\nat Sunset Ceramics",
                            color: AstirPalette.clay
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }
}

private struct AstirAppHeader: View {
    let kicker: String

    var body: some View {
        HStack(alignment: .top) {
            AstirWordmark(color: AstirPalette.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(kicker)
                Text("OCEAN PARK")
                    .foregroundStyle(AstirPalette.clay)
            }
            .font(AstirType.meta(11))
            .tracking(1.15)
            .foregroundStyle(AstirPalette.inkMuted)
        }
    }
}

private struct AstirEventCard: View {
    let openEvent: () -> Void

    var body: some View {
        Button(action: openEvent) {
            ZStack(alignment: .bottomLeading) {
                AstirCroppedAssetImage(
                    assetName: "PlaceCarouselPhotos",
                    normalizedRect: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
                )

                LinearGradient(
                    colors: [.clear, AstirPalette.ink.opacity(0.22), AstirPalette.ink.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("TONIGHT", systemImage: "circle.fill")
                            .font(AstirType.meta(12))
                            .foregroundStyle(AstirPalette.signal)
                        Spacer()
                        Text("CHAPTER 03")
                            .font(AstirType.meta(11))
                            .foregroundStyle(AstirPalette.paper.opacity(0.68))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Third Thursday")
                            .font(AstirType.display(34))
                        Text("Dinner + Listening")
                            .font(AstirType.ui(17, weight: .semibold))
                    }
                    .foregroundStyle(AstirPalette.paper)

                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SEP 17 · 7–10 PM")
                            Text("BACK PATIO · $32")
                        }
                        .font(AstirType.meta(12))
                        .foregroundStyle(AstirPalette.paper.opacity(0.78))

                        Spacer()

                        AstirAvatarStack(initials: ["MC", "JL", "AR"], size: 29)
                    }
                }
                .padding(20)
            }
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AstirPalette.paper.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("astir.event.card")
        .accessibilityLabel("Third Thursday, Dinner and Listening, tonight from 7 to 10 PM at Back Patio")
    }
}

private struct AstirPlaceCard: View {
    let crop: CGRect
    let name: String
    let detail: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AstirCroppedAssetImage(assetName: "PlaceCarouselPhotos", normalizedRect: crop)
                .frame(height: 190)

            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(AstirType.display(25))
                Text(detail.uppercased())
                    .font(AstirType.meta(11))
                    .foregroundStyle(AstirPalette.clay)
                Text(note)
                    .font(AstirType.body(15, weight: .medium))
                    .foregroundStyle(AstirPalette.inkMuted)
                    .lineSpacing(3)
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

private struct AstirCompactSignal: View {
    let time: String
    let title: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(time)
                .font(AstirType.meta(11))
                .foregroundStyle(color)
            Text(title)
                .font(AstirType.ui(16, weight: .bold))
                .foregroundStyle(AstirPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .foregroundStyle(AstirPalette.inkMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .leading)
        .background(AstirPalette.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AstirPalette.line, lineWidth: 1)
        }
    }
}

private struct AstirMapView: View {
    let openEvent: () -> Void

    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0037, longitude: -118.4865),
            span: MKCoordinateSpan(latitudeDelta: 0.023, longitudeDelta: 0.027)
        )
    )

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                Annotation("Third Thursday", coordinate: CLLocationCoordinate2D(latitude: 34.0022, longitude: -118.4827)) {
                    Button(action: openEvent) {
                        VStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 38, height: 38)
                                .background(AstirPalette.signal)
                                .foregroundStyle(AstirPalette.paper)
                                .clipShape(Circle())
                            Text("TONIGHT")
                                .font(AstirType.meta(9))
                                .foregroundStyle(AstirPalette.ink)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Marker("Record Room", systemImage: "music.note", coordinate: CLLocationCoordinate2D(latitude: 34.0053, longitude: -118.4814))
                    .tint(AstirPalette.pool)
                Marker("Sunset Ceramics", systemImage: "paintpalette.fill", coordinate: CLLocationCoordinate2D(latitude: 34.0092, longitude: -118.4782))
                    .tint(AstirPalette.clay)
                Marker("Tower 26", systemImage: "figure.open.water.swim", coordinate: CLLocationCoordinate2D(latitude: 34.0024, longitude: -118.5002))
                    .tint(AstirPalette.gold)
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 12) {
                AstirAppHeader(kicker: "12 MINUTE RADIUS")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(AstirPalette.paper.opacity(0.95))

                HStack(spacing: 8) {
                    AstirMapFilter(title: "for you", isSelected: true)
                    AstirMapFilter(title: "tonight", isSelected: false)
                    AstirMapFilter(title: "your people", isSelected: false)
                }
                .padding(.horizontal, 16)
            }

            VStack {
                Spacer()
                Button(action: openEvent) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(AstirPalette.signal)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Third Thursday")
                                .font(AstirType.ui(16, weight: .bold))
                            Text("7 PM · Back Patio · 2 friends going")
                                .font(AstirType.ui(12, weight: .semibold))
                                .foregroundStyle(AstirPalette.inkMuted)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(AstirPalette.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 64)
                    .background(AstirPalette.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(AstirPalette.line, lineWidth: 1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct AstirMapFilter: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(AstirType.ui(12, weight: .bold))
            .foregroundStyle(isSelected ? AstirPalette.paper : AstirPalette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(isSelected ? AstirPalette.ink : AstirPalette.paper.opacity(0.94))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(isSelected ? .clear : AstirPalette.line, lineWidth: 1)
            }
    }
}

private struct AstirEventDetailView: View {
    let join: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    AstirCroppedAssetImage(
                        assetName: "PlaceCarouselPhotos",
                        normalizedRect: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
                    )
                    LinearGradient(
                        colors: [.clear, AstirPalette.ink.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ASTIR PRESENTS · CHAPTER 03")
                            .font(AstirType.meta(11))
                            .tracking(1.5)
                            .foregroundStyle(AstirPalette.signal)
                        Text("Third Thursday")
                            .font(AstirType.display(43))
                        Text("Dinner + Listening")
                            .font(AstirType.ui(18, weight: .semibold))
                    }
                    .foregroundStyle(AstirPalette.paper)
                    .padding(22)
                }
                .frame(height: 360)

                VStack(alignment: .leading, spacing: 28) {
                    Text("A shared table, a short vinyl set, and a room designed so arriving alone doesn’t feel like arriving alone.")
                        .font(AstirType.display(26))
                        .foregroundStyle(AstirPalette.paper)
                        .lineSpacing(5)

                    AstirLogisticsGrid()

                    Divider().overlay(AstirPalette.paper.opacity(0.18))

                    VStack(alignment: .leading, spacing: 12) {
                        AstirDarkSectionHeader(number: "01", title: "The room")
                        Text("The side courtyard at Back Patio. Seventy-two seats, candlelight, one long listening set, and enough structure to make conversation easy.")
                            .font(AstirType.body(16, weight: .medium))
                            .foregroundStyle(AstirPalette.paper.opacity(0.72))
                            .lineSpacing(5)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        AstirDarkSectionHeader(number: "02", title: "Familiar faces")
                        HStack(spacing: 14) {
                            AstirAvatarStack(initials: ["MC", "JL", "AR", "TS"], size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Maya and Jonah are going")
                                    .font(AstirType.ui(15, weight: .bold))
                                Text("Plus one person you met at Record Room")
                                    .font(AstirType.ui(13, weight: .medium))
                                    .foregroundStyle(AstirPalette.paper.opacity(0.6))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        AstirDarkSectionHeader(number: "03", title: "Hosted by")
                        Text("Lena Ortiz · Back Patio\nTheo March · Ocean Park Record Room")
                            .font(AstirType.body(16, weight: .semibold))
                            .foregroundStyle(AstirPalette.paper.opacity(0.82))
                            .lineSpacing(7)
                    }
                }
                .padding(22)
                .padding(.bottom, 96)
            }
        }
        .scrollIndicators(.hidden)
        .background(AstirPalette.ink.ignoresSafeArea())
        .toolbarBackground(AstirPalette.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: join) {
                HStack {
                    Text("Join the table")
                    Spacer()
                    Text("$32")
                    Image(systemName: "arrow.right")
                }
                .font(AstirType.ui(16, weight: .bold))
                .foregroundStyle(AstirPalette.ink)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(AstirPalette.paper)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AstirPalette.ink.opacity(0.97))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("astir.join")
        }
    }
}

private struct AstirLogisticsGrid: View {
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            AstirLogistic(label: "WHEN", value: "Thu, Sep 17\n7–10 PM")
            AstirLogistic(label: "WHERE", value: "Back Patio\nOcean Park")
            AstirLogistic(label: "ARRIVAL", value: "Side courtyard\n6 min bike")
            AstirLogistic(label: "GUEST", value: "One welcome\nUntil full")
        }
    }
}

private struct AstirLogistic: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AstirType.meta(10))
                .foregroundStyle(AstirPalette.signal)
            Text(value)
                .font(AstirType.ui(15, weight: .semibold))
                .foregroundStyle(AstirPalette.paper)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AstirArrivalView: View {
    let checkIn: () -> Void

    var body: some View {
        ZStack {
            AstirPalette.deepOcean.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    AstirWordmark(color: AstirPalette.paper)
                    Spacer()
                    Text("ARRIVAL 03")
                        .font(AstirType.meta(11))
                        .tracking(1.3)
                        .foregroundStyle(AstirPalette.signal)
                }

                Spacer()

                Text("6:45")
                    .font(AstirType.meta(94))
                    .foregroundStyle(AstirPalette.paper)
                    .minimumScaleFactor(0.8)
                Text("PM · THURSDAY, SEPTEMBER 17")
                    .font(AstirType.meta(12))
                    .tracking(1.3)
                    .foregroundStyle(AstirPalette.paper.opacity(0.56))

                Text("You’re\nexpected.")
                    .font(AstirType.display(47))
                    .foregroundStyle(AstirPalette.paper)
                    .lineSpacing(-3)
                    .padding(.top, 34)

                VStack(alignment: .leading, spacing: 16) {
                    AstirArrivalRow(symbol: "arrow.turn.down.right", title: "Enter through the side courtyard")
                    AstirArrivalRow(symbol: "bicycle", title: "Bike rack is inside the gate")
                    AstirArrivalRow(symbol: "person.crop.circle.badge.checkmark", title: "Maya and Jonah have arrived")
                }
                .padding(.top, 28)

                Button(action: checkIn) {
                    HStack {
                        Text("I’m here")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(AstirType.ui(16, weight: .bold))
                    .foregroundStyle(AstirPalette.deepOcean)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(AstirPalette.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("astir.arrive")
                .padding(.top, 34)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .toolbarBackground(AstirPalette.deepOcean, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

private struct AstirArrivalRow: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AstirPalette.signal)
                .frame(width: 24)
            Text(title)
                .font(AstirType.ui(15, weight: .semibold))
                .foregroundStyle(AstirPalette.paper.opacity(0.82))
        }
    }
}

private struct AstirPresenceView: View {
    let finishNight: () -> Void

    var body: some View {
        ZStack {
            AstirPalette.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                AstirFrameMark(color: AstirPalette.signal)
                    .frame(width: 56, height: 56)

                Text("You’re here.")
                    .font(AstirType.display(48))
                    .foregroundStyle(AstirPalette.paper)
                    .padding(.top, 24)

                Text("The table is through the courtyard.\nEverything else can wait.")
                    .font(AstirType.body(17, weight: .medium))
                    .foregroundStyle(AstirPalette.paper.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.top, 14)

                HStack(spacing: 9) {
                    Image(systemName: "camera.aperture")
                    Text("Selected moments will appear tomorrow")
                }
                .font(AstirType.ui(12, weight: .semibold))
                .foregroundStyle(AstirPalette.paper.opacity(0.45))
                .padding(.top, 34)

                Spacer()

                Button(action: finishNight) {
                    Text("See the morning after")
                        .font(AstirType.ui(13, weight: .bold))
                        .foregroundStyle(AstirPalette.paper.opacity(0.66))
                        .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("astir.finish.night")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .toolbarBackground(AstirPalette.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

private struct AstirMemoryView: View {
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                AstirAppHeader(kicker: "FRIDAY · 9:14 AM")

                VStack(alignment: .leading, spacing: 8) {
                    Text("MEMORY 03 · SEPTEMBER 17")
                        .font(AstirType.meta(11))
                        .tracking(1.2)
                        .foregroundStyle(AstirPalette.clay)
                    Text("The night, kept.")
                        .font(AstirType.display(40))
                    Text("Third Thursday · Back Patio")
                        .font(AstirType.ui(15, weight: .semibold))
                        .foregroundStyle(AstirPalette.inkMuted)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    AstirMemoryPhoto(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
                    AstirMemoryPhoto(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
                    AstirMemoryPhoto(rect: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
                    AstirMemoryPhoto(rect: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
                }
                .accessibilityIdentifier("astir.memory.photos")

                VStack(alignment: .leading, spacing: 10) {
                    AstirSectionHeader(number: "01", title: "A note from Lena")
                    Text("Thank you for making a long table feel easy. We’ll keep the lamps on for the next one.")
                        .font(AstirType.display(24))
                        .foregroundStyle(AstirPalette.ink)
                        .lineSpacing(4)
                    Text("LENA · BACK PATIO")
                        .font(AstirType.meta(10))
                        .tracking(1.1)
                        .foregroundStyle(AstirPalette.clay)
                }
                .padding(18)
                .background(AstirPalette.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AstirPalette.line, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 14) {
                    AstirSectionHeader(number: "02", title: "People from the night")
                    AstirPersonRow(initials: "TS", name: "Tessa", context: "You talked by the record shelf")
                    AstirPersonRow(initials: "AO", name: "Alex", context: "Maya introduced you")
                }

                VStack(alignment: .leading, spacing: 14) {
                    AstirSectionHeader(number: "03", title: "Now part of your Astir")
                    HStack(spacing: 18) {
                        AstirHistoryStat(value: "19", label: "places")
                        AstirHistoryStat(value: "4", label: "events")
                        AstirHistoryStat(value: "12", label: "people")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(AstirPalette.paper)
    }
}

private struct AstirMemoryPhoto: View {
    let rect: CGRect

    var body: some View {
        AstirCroppedAssetImage(assetName: "PlaceCarouselPhotos", normalizedRect: rect)
            .frame(height: 164)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct AstirPersonRow: View {
    let initials: String
    let name: String
    let context: String

    var body: some View {
        HStack(spacing: 12) {
            AstirAvatar(initials: initials, size: 46, color: AstirPalette.pool)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(AstirType.ui(15, weight: .bold))
                Text(context)
                    .font(AstirType.ui(12, weight: .medium))
                    .foregroundStyle(AstirPalette.inkMuted)
            }
            Spacer()
            Button("Say hi") {}
                .font(AstirType.ui(12, weight: .bold))
                .foregroundStyle(AstirPalette.ink)
                .padding(.horizontal, 13)
                .frame(minHeight: 38)
                .overlay {
                    Capsule().stroke(AstirPalette.lineStrong, lineWidth: 1)
                }
        }
    }
}

private struct AstirProfileView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                AstirAppHeader(kicker: "YOUR ASTIR")

                HStack(alignment: .center, spacing: 16) {
                    AstirAvatar(initials: "JL", size: 76, color: AstirPalette.clay)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Joe")
                            .font(AstirType.display(34))
                        Text("Ocean Park · since chapter 01")
                            .font(AstirType.ui(13, weight: .semibold))
                            .foregroundStyle(AstirPalette.inkMuted)
                    }
                }

                HStack(spacing: 18) {
                    AstirHistoryStat(value: "19", label: "places")
                    AstirHistoryStat(value: "4", label: "events")
                    AstirHistoryStat(value: "12", label: "people")
                }

                VStack(alignment: .leading, spacing: 14) {
                    AstirSectionHeader(number: "01", title: "Your chapters")
                    AstirTimelineRow(number: "04", title: "Third Thursday", detail: "Back Patio · Sep 17", color: AstirPalette.clay)
                    AstirTimelineRow(number: "03", title: "Morning swim", detail: "Tower 26 · Aug 29", color: AstirPalette.pool)
                    AstirTimelineRow(number: "02", title: "Open studio", detail: "Sunset Ceramics · Aug 13", color: AstirPalette.gold)
                }

                VStack(alignment: .leading, spacing: 12) {
                    AstirSectionHeader(number: "02", title: "A pattern forming")
                    Text("You keep returning to small rooms, long tables, and places within biking distance.")
                        .font(AstirType.display(26))
                        .lineSpacing(5)
                    Text("Astir uses this quietly. You control what other people can see.")
                        .font(AstirType.ui(13, weight: .medium))
                        .foregroundStyle(AstirPalette.inkMuted)
                }
                .padding(18)
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
    }
}

private struct AstirTimelineRow: View {
    let number: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Text(number)
                .font(AstirType.meta(14))
                .foregroundStyle(color)
                .frame(width: 28, alignment: .leading)
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
        .padding(.vertical, 7)
    }
}

private struct AstirHistoryStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AstirType.display(30))
            Text(label.uppercased())
                .font(AstirType.meta(10))
                .foregroundStyle(AstirPalette.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .font(.system(size: 16, weight: .semibold))
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
        .background(AstirPalette.paper.opacity(0.97))
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

private struct AstirDarkSectionHeader: View {
    let number: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .foregroundStyle(AstirPalette.signal)
            Text(title.uppercased())
                .foregroundStyle(AstirPalette.paper)
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

private struct AstirFrameMark: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let length = min(size.width, size.height) * 0.35
            let width: CGFloat = 1.5
            var path = Path()
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
            path.move(to: CGPoint(x: size.width - length, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: length))
            path.move(to: CGPoint(x: size.width, y: size.height - length))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: size.width - length, y: size.height))
            path.move(to: CGPoint(x: length, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height - length))
            context.stroke(path, with: .color(color), lineWidth: width)
        }
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
    static let gold = Color(astirHex: 0xC99B3E)
    static let inkMuted = Color(astirHex: 0x6F675D)
    static let line = Color(astirHex: 0xD8CCBD)
    static let lineStrong = Color(astirHex: 0xA99B8C)
    static let avatarColors = [clay, pool, gold, deepOcean]
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
