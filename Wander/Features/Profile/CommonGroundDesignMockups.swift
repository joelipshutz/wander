#if DEBUG
import MapKit
import SwiftUI
import UIKit

private enum CommonGroundMockRoute: Hashable {
    case detail, mix
    case shared(String)
    case place(CommonGroundMockPlace)
    case invitation(CommonGroundMockPlace)
    case recipient(CommonGroundMockPlace)
}

/// Isolated native design exploration. No account data, persistence, or delivery.
struct CommonGroundDesignMockupRoot: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var page: CommonGroundMockPage
    @State private var path: [CommonGroundMockRoute]

    init(page: CommonGroundMockPage) {
        _page = State(initialValue: page)
        _path = State(initialValue: Self.routes(for: page))
    }

    var body: some View {
        NavigationStack(path: $path) {
            CommonGroundProfileMockup(isOwner: page == .ownProfile, open: { path.append(.detail) },
                                      openMix: { path.append(.mix) })
                .navigationDestination(for: CommonGroundMockRoute.self) { route in
                    destination(route)
                        .toolbar { previewMenu }
                }
                .toolbar { previewMenu }
        }
        .tint(colorScheme == .dark ? AstirTheme.signal.color : AstirTheme.signalOnPaper.color)
        .astirAdaptiveBrandMode()
    }

    @ViewBuilder private func destination(_ route: CommonGroundMockRoute) -> some View {
        switch route {
        case .detail:
            CommonGroundDetailMockup(state: page, openMix: { path.append(.mix) },
                                     openShared: { path.append(.shared($0)) },
                                     invite: { path.append(.invitation($0)) },
                                     retry: { page = .detail })
        case .mix:
            CommonGroundMixMockup(sparse: page == .sparse,
                                 openPlace: { path.append(.place($0)) },
                                 invite: { path.append(.invitation($0)) })
        case .shared(let filter):
            CommonGroundSharedMockup(initialFilter: filter, openPlace: { path.append(.place($0)) })
        case .place(let place):
            CommonGroundPlaceMockup(place: place) { path.append(.invitation(place)) }
        case .invitation(let place):
            CommonGroundInvitationMockup(placeName: place.name, category: place.category,
                                         systemImage: place.systemImage)
        case .recipient(let place):
            CommonGroundInvitationMockup(placeName: place.name, category: place.category,
                                         systemImage: place.systemImage, opensEnvelope: true)
        }
    }

    private var previewMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(CommonGroundMockPage.allCases, id: \.self) { option in
                    Button(option.previewTitle) {
                        page = option
                        path = Self.routes(for: option)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Design previews")
        }
    }

    private static func routes(for page: CommonGroundMockPage) -> [CommonGroundMockRoute] {
        let place = CommonGroundMockData.places[0]
        switch page {
        case .profile, .ownProfile: return []
        case .detail, .loading, .unavailable, .sparse: return [.detail]
        case .mix: return [.detail, .mix]
        case .invitation: return [.detail, .mix, .invitation(place)]
        case .recipient: return [.detail, .recipient(place)]
        }
    }
}

private extension CommonGroundMockPage {
    var previewTitle: String {
        switch self {
        case .profile: "Joe’s profile"
        case .ownProfile: "Your profile"
        case .detail: "Common Ground"
        case .mix: "For you two"
        case .invitation: "Make an invitation"
        case .recipient: "Receive an invitation"
        case .sparse: "A little common ground"
        case .loading: "Loading"
        case .unavailable: "Unavailable"
        }
    }
}

private struct CommonGroundDetailMockup: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let state: CommonGroundMockPage
    let openMix: () -> Void
    let openShared: (String) -> Void
    let invite: (CommonGroundMockPlace) -> Void
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 14) {
                    CommonGroundAvatarPair()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("You & Joe").font(AstirTypography.sheetTitle)
                        Text("A few things that bring you together.")
                            .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                    }
                }
                if state == .loading {
                    ProgressView("Finding your common ground…")
                        .font(AstirTypography.body).frame(maxWidth: .infinity, minHeight: 220)
                } else if state == .unavailable {
                    ContentUnavailableView {
                        Label("A little out of reach", systemImage: "arrow.triangle.2.circlepath")
                    } description: {
                        Text("Your common ground couldn’t load. Give it another try.")
                    } actions: {
                        Button("Try again", action: retry).buttonStyle(.bordered)
                    }
                } else {
                    sharedFavorite
                    VStack(alignment: .leading, spacing: 16) {
                        CommonGroundSectionHeading(title: "For you two", subtitle: "Good places. Even better company.")
                        CommonGroundMixCover(count: state == .sparse ? 2 : 6, action: openMix)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        CommonGroundSectionHeading(title: "Your common ground")
                        evidenceLink("Both loved", detail: "The ones you’d happily go back to", count: 2, icon: "heart")
                        evidenceLink("Both regulars", detail: "Part of both your routines", count: 2, icon: "arrow.counterclockwise")
                        evidenceLink("Both wanna go", detail: "Already on both your maps", count: 2, icon: "bookmark")
                        evidenceLink("All shared places", detail: "The familiar, the new, the different takes", count: 8, icon: "mappin.and.ellipse")
                    }
                }
                CommonGroundSampleCaption()
            }
            .padding(20).padding(.bottom, 24)
        }
        .navigationTitle("Common Ground")
        .navigationBarTitleDisplayMode(.inline)
        .astirScreen()
    }

    private var sharedFavorite: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A SHARED SOFT SPOT").font(AstirTypography.metadata)
                        .tracking(1.5).foregroundStyle(brand.accentText)
                    Text("You both\nlove Narwhal.")
                        .font(AstirTypography.screenTitle).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    CommonGroundPhoto(tile: 0).frame(width: 90, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .rotationEffect(.degrees(4)).padding(.top, 10)
                }
            }
            ratingLayout {
                rating("You", value: "5.0")
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("·").foregroundStyle(brand.secondaryText)
                }
                rating("Joe", value: "5.0")
            }
            Divider()
            HStack(alignment: .center, spacing: 12) {
                Text("35").font(AstirTypography.screenTitle).monospacedDigit()
                    .foregroundStyle(brand.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("check-ins between you").font(AstirTypography.control)
                    Text("You: 18  ·  Joe: 17").font(AstirTypography.bodySmall)
                        .foregroundStyle(brand.secondaryText)
                }
                Spacer(minLength: 0)
            }
            Button { invite(CommonGroundMockData.places[0]) } label: {
                Label("Go back together", systemImage: "arrow.up.right")
                    .font(AstirTypography.control).frame(minHeight: 44)
            }
            .accessibilityIdentifier("common-ground.return")
        }
        .padding(20)
        .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    private var ratingLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    private func rating(_ name: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(name).foregroundStyle(brand.secondaryText)
            Image(systemName: "star.fill").foregroundStyle(brand.accentText)
            Text(value).font(AstirTypography.control)
        }
        .font(AstirTypography.bodySmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) rated Narwhal \(value) out of 5")
    }

    private func evidenceLink(_ title: String, detail: String, count: Int, icon: String) -> some View {
        Button { openShared(title == "All shared places" ? "All shared" : title) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 26).foregroundStyle(brand.accentText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(AstirTypography.cardTitle)
                    Text(detail).font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                }
                Spacer(minLength: 0)
                Text("\(count)").font(AstirTypography.label)
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(brand.primaryText).padding(.vertical, 12)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct CommonGroundMixCover: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PICKED BY ASTIR").font(AstirTypography.metadata).tracking(1.5)
                        Text("Joe & Ryan’s\nmix").font(AstirTypography.screenTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "map.fill").font(.system(size: 40, weight: .light))
                            .rotationEffect(.degrees(12)).padding(.top, 15).accessibilityHidden(true)
                    }
                }
                Text("A little familiar. A little undiscovered.")
                    .font(AstirTypography.bodySmall)
                HStack {
                    Text("\(count) places · Los Angeles").font(AstirTypography.label)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.title3)
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(brand.primaryText.opacity(0.25)).frame(height: 1) }
            }
            .foregroundStyle(brand.primaryText).padding(22)
            .background(WanderTheme.terracottaTint.color, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open your mix, \(count) places for you and Joe")
        .accessibilityIdentifier("common-ground.open-mix")
    }
}

private struct CommonGroundMixMockup: View {
    @Environment(\.astirBrandMode) private var brand
    @State private var area = "Los Angeles"
    @State private var occasion = CommonGroundMockOccasion.any
    let sparse: Bool
    let openPlace: (CommonGroundMockPlace) -> Void
    let invite: (CommonGroundMockPlace) -> Void

    private var places: [CommonGroundMockPlace] {
        CommonGroundMockData.mix(area: area, occasion: occasion, sparse: sparse)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    CommonGroundAvatarPair()
                    Text("Joe & Ryan’s mix").font(AstirTypography.screenTitle)
                    Text("Places with a reason to go. Pick one and make it a plan.")
                        .font(AstirTypography.body).foregroundStyle(brand.secondaryText)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { areaPicker; occasionPicker }
                    VStack(alignment: .leading, spacing: 8) { areaPicker; occasionPicker }
                }
                Text("\(places.count) PLACES FOR YOU TWO")
                    .font(AstirTypography.metadata).tracking(1.5).foregroundStyle(brand.secondaryText)
                    .accessibilityIdentifier("common-ground.mix-count")
                if places.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing here just yet", systemImage: "map")
                    } description: {
                        Text("Try the area where your maps already overlap.")
                    } actions: {
                        Button("Try Los Angeles") { area = "Los Angeles" }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                    }
                } else {
                    ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 14) {
                                Text(String(format: "%02d", index + 1)).font(AstirTypography.metadata)
                                    .foregroundStyle(brand.secondaryText).padding(.top, 5)
                                Button { openPlace(place) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(place.name).font(AstirTypography.sheetTitle)
                                        Text("\(place.category) · \(place.area)")
                                            .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Image(systemName: place.systemImage)
                                    .font(.title2).foregroundStyle(brand.accentText)
                                    .frame(width: 42, height: 48).accessibilityHidden(true)
                            }
                            Text(place.reason).font(AstirTypography.body)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Label(place.kind.shortLabel, systemImage: place.kind.symbol)
                                    .font(AstirTypography.label).foregroundStyle(brand.secondaryText)
                                Spacer(minLength: 8)
                                Button { invite(place) } label: {
                                    Label("Invite Joe", systemImage: "arrow.up.right")
                                        .font(AstirTypography.control).frame(minHeight: 44)
                                }
                                .accessibilityIdentifier("common-ground.invite.\(place.id)")
                            }
                            Divider()
                        }
                    }
                }
                CommonGroundSampleCaption()
            }
            .padding(20).padding(.bottom, 24)
        }
        .navigationTitle("For you two").navigationBarTitleDisplayMode(.inline)
        .astirScreen()
    }

    private var areaPicker: some View {
        Menu {
            Picker("Area", selection: $area) {
                Text("Los Angeles").tag("Los Angeles")
                Text("San Francisco").tag("San Francisco")
            }
        } label: { filterLabel(area, symbol: "location") }
            .accessibilityIdentifier("common-ground.area")
    }

    private var occasionPicker: some View {
        Menu {
            Picker("Occasion", selection: $occasion) {
                ForEach(CommonGroundMockOccasion.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: { filterLabel(occasion.rawValue, symbol: "sparkle") }
            .accessibilityIdentifier("common-ground.occasion")
    }

    private func filterLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(AstirTypography.label).foregroundStyle(brand.primaryText)
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension CommonGroundMockKind {
    var shortLabel: String {
        switch self {
        case .returnTogether: "Go back together"
        case .mutualWanna: "On both your maps"
        case .introduce: "Worth an introduction"
        case .history: "Both been"
        }
    }
    var symbol: String {
        switch self {
        case .returnTogether: "arrow.counterclockwise"
        case .mutualWanna: "bookmark"
        case .introduce: "person.2"
        case .history: "checkmark"
        }
    }
}

private struct CommonGroundSharedMockup: View {
    @Environment(\.astirBrandMode) private var brand
    @State private var filter = "All shared"
    let openPlace: (CommonGroundMockPlace) -> Void
    private let filters = ["All shared", "Both loved", "Both regulars", "Both wanna go", "Worth introducing", "Both been", "Different takes"]

    init(initialFilter: String, openPlace: @escaping (CommonGroundMockPlace) -> Void) {
        _filter = State(initialValue: initialFilter)
        self.openPlace = openPlace
    }

    private var places: [CommonGroundMockPlace] {
        CommonGroundMockData.places.filter { place in
            switch filter {
            case "Both loved": place.bothLoved
            case "Both regulars": place.bothRegulars
            case "Both wanna go": place.youWanna && place.joeWanna
            case "Worth introducing": place.kind == .introduce
            case "Both been": place.youVisits > 0 && place.joeVisits > 0
            case "Different takes": place.youRating != nil && place.joeRating != nil && abs((place.youRating ?? 0) - (place.joeRating ?? 0)) >= 1
            default: true
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Menu {
                    Picker("Shared places", selection: $filter) {
                        ForEach(filters, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    Label(filter, systemImage: "line.3.horizontal.decrease")
                        .font(AstirTypography.control).frame(minHeight: 44)
                }
                ForEach(places) { place in
                    Button { openPlace(place) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(place.name).font(AstirTypography.sheetTitle)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            CommonGroundEvidence(place: place)
                            Divider()
                        }
                        .contentShape(Rectangle()).foregroundStyle(brand.primaryText)
                    }.buttonStyle(.plain)
                }
                CommonGroundSampleCaption()
            }.padding(20)
        }
        .navigationTitle("Your shared places").navigationBarTitleDisplayMode(.inline).astirScreen()
    }
}

private struct CommonGroundPlaceMockup: View {
    @Environment(\.astirBrandMode) private var brand
    let place: CommonGroundMockPlace
    let invite: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CommonGroundPhoto(tile: place.category == "Bar" ? 3 : 0)
                    .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 8) {
                    Text(place.name).font(AstirTypography.screenTitle)
                    Text("\(place.category) · \(place.area)").font(AstirTypography.bodySmall)
                        .foregroundStyle(brand.secondaryText)
                }
                Text(place.reason).font(AstirTypography.body)
                CommonGroundSectionHeading(title: "You two, here")
                CommonGroundEvidence(place: place)
                Button(action: invite) {
                    Label("I want to go here with Joe", systemImage: "envelope")
                        .font(AstirTypography.control).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent).tint(brand.accent).foregroundStyle(brand.accentForeground)
                CommonGroundSampleCaption()
            }.padding(20)
        }
        .navigationTitle(place.name).navigationBarTitleDisplayMode(.inline).astirScreen()
    }
}

private struct CommonGroundEvidence: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let place: CommonGroundMockPlace
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            person("You", rating: place.youRating, visits: place.youVisits, wanna: place.youWanna)
            person("Joe", rating: place.joeRating, visits: place.joeVisits, wanna: place.joeWanna)
        }.font(AstirTypography.bodySmall)
    }
    private func person(_ name: String, rating: Double?, visits: Int, wanna: Bool) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(name).font(AstirTypography.control).fixedSize()
            Text(wanna ? "Wanna go" : "\(visits) \(visits == 1 ? "check-in" : "check-ins")")
                .foregroundStyle(brand.secondaryText)
            if let rating { Text(String(format: "★ %.1f / 5", rating)).foregroundStyle(brand.accentText) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CommonGroundProfileMockup: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isOwner: Bool
    let open: () -> Void
    let openMix: () -> Void
    private var name: String { isOwner ? "Ryan" : "Joe" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 18) {
                    CommonGroundAvatar(tile: isOwner ? 0 : 1, size: 82)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(AstirTypography.screenTitle)
                        Text("@\(name.lowercased()) · Los Angeles")
                            .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                        Label(isOwner ? "Your profile" : "Friends", systemImage: isOwner ? "person" : "person.2")
                            .font(AstirTypography.label).padding(.top, 4)
                    }
                }
                Text("Good coffee. Long dinners. Places worth going back to.").font(AstirTypography.body)
                statLayout {
                    profileStat("Been", count: "124")
                    profileStat("Wanna", count: "38")
                    profileStat("Friends", count: "64")
                }
                if !isOwner {
                    VStack(alignment: .leading, spacing: 16) {
                        CommonGroundSectionHeading(title: "Common Ground")
                        HStack(spacing: 12) {
                            CommonGroundAvatarPair(size: 34)
                            Text("You both love Narwhal.").font(AstirTypography.cardTitle)
                        }
                        Text("35 check-ins between you. And a few new places to make your own.")
                            .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                        Button(action: openMix) {
                            HStack(spacing: 12) {
                                Image(systemName: "map.fill").font(.title2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Joe & Ryan’s mix").font(AstirTypography.sectionTitle)
                                    Text("6 places picked for you two").font(AstirTypography.bodySmall)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                            }
                            .foregroundStyle(brand.primaryText).padding(16)
                            .background(WanderTheme.terracottaTint.color, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                        Button("See more", action: open).font(AstirTypography.control).frame(minHeight: 44)
                            .accessibilityIdentifier("common-ground.profile-entry")
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    CommonGroundSectionHeading(title: "Activity")
                    HStack(spacing: 14) {
                        CommonGroundPhoto(tile: 1).frame(width: 70, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(name) went to Narwhal").font(AstirTypography.cardTitle)
                            Text("Coffee · Yesterday").font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                            Label("5.0", systemImage: "star.fill").font(AstirTypography.label).foregroundStyle(brand.accentText)
                        }
                        Spacer(minLength: 0)
                    }.padding(14).background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 16) {
                    CommonGroundSectionHeading(title: isOwner ? "Your map" : "Joe’s map")
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 34.02, longitude: -118.47),
                        span: MKCoordinateSpan(latitudeDelta: 0.065, longitudeDelta: 0.065)
                    )), interactionModes: [])
                    .frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Los Angeles map preview")
                }
                VStack(alignment: .leading, spacing: 16) {
                    CommonGroundSectionHeading(title: isOwner ? "Your calendar" : "Joe’s calendar")
                    Text("September 2026").font(AstirTypography.control)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                        ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                            Text(day).font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                        }
                        ForEach(0..<32, id: \.self) { index in
                            if index < 2 { Color.clear.frame(height: 34) }
                            else {
                                Text("\(index - 1)").font(AstirTypography.bodySmall)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background([3, 8, 13, 15].contains(index) ? brand.accentWash : Color.clear, in: Circle())
                            }
                        }
                    }
                }
                CommonGroundSampleCaption()
            }.padding(20).padding(.bottom, 24)
        }
        .navigationTitle(isOwner ? "Your profile" : "Joe’s profile")
        .navigationBarTitleDisplayMode(.inline).astirScreen()
    }
    private var statLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 28))
    }
    private func profileStat(_ title: String, count: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(count).font(AstirTypography.metricDisplay)
            Text(title).font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
        }
    }
}

private struct CommonGroundSectionHeading: View {
    @Environment(\.astirBrandMode) private var brand
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.bottom, 8)
            Text(title).font(AstirTypography.sheetTitle).accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
            }
        }
    }
}

private struct CommonGroundAvatarPair: View {
    var size: CGFloat = 44
    var body: some View {
        HStack(spacing: -10) {
            CommonGroundAvatar(tile: 0, size: size)
            CommonGroundAvatar(tile: 1, size: size)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Ryan and Joe")
    }
}

@MainActor private enum CommonGroundMockImages {
    static let avatars = tiles("PlaceCarouselAvatars")
    static let photos = tiles("PlaceCarouselPhotos")
    private static func tiles(_ name: String) -> [UIImage] {
        guard let source = UIImage(named: name)?.cgImage else { return [] }
        let width = source.width / 2, height = source.height / 2
        return (0..<4).compactMap { index in
            source.cropping(to: CGRect(x: index % 2 * width, y: index / 2 * height, width: width, height: height))
                .map { UIImage(cgImage: $0) }
        }
    }
}

private struct CommonGroundAvatar: View {
    let tile: Int
    let size: CGFloat
    var body: some View {
        Group {
            if CommonGroundMockImages.avatars.indices.contains(tile) {
                Image(uiImage: CommonGroundMockImages.avatars[tile]).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit()
            }
        }.frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().stroke(WanderTheme.canvasWarm.color, lineWidth: 3)).accessibilityHidden(true)
    }
}

private struct CommonGroundPhoto: View {
    let tile: Int
    var body: some View {
        GeometryReader { geometry in
            if CommonGroundMockImages.photos.indices.contains(tile) {
                Image(uiImage: CommonGroundMockImages.photos[tile]).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } else {
                Rectangle().fill(WanderTheme.surfaceSand.color)
                    .overlay { Image(systemName: "mappin.and.ellipse") }
            }
        }.accessibilityHidden(true)
    }
}

private struct CommonGroundSampleCaption: View {
    @Environment(\.astirBrandMode) private var brand
    var body: some View {
        Text("Design preview · sample places, people & photos")
            .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 12)
    }
}

#Preview("Common Ground") { CommonGroundDesignMockupRoot(page: .detail) }
#Preview("For you two") { CommonGroundDesignMockupRoot(page: .mix) }
#Preview("Member profile") { CommonGroundDesignMockupRoot(page: .profile) }
#Preview("Your profile") { CommonGroundDesignMockupRoot(page: .ownProfile) }
#Preview("Common Ground · Dark") { CommonGroundDesignMockupRoot(page: .detail).preferredColorScheme(.dark) }
#endif
