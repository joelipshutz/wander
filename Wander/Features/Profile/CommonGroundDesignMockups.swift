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
    case recipientOpened
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
        Group {
            if page == .messages {
                CommonGroundMessagesMockup(draft: .preview, onClose: {
                    path = []
                    page = .profile
                })
            } else {
                navigation
            }
        }
        .tint(colorScheme == .dark ? AstirTheme.signal.color : AstirTheme.signalOnPaper.color)
        .astirAdaptiveBrandMode()
    }

    private var navigation: some View {
        NavigationStack(path: $path) {
            CommonGroundProfileMockup(isOwner: page == .ownProfile, open: { path.append(.detail) },
                                      openMix: { path.append(.mix) })
                .navigationDestination(for: CommonGroundMockRoute.self) { route in
                    destination(route)
                        .toolbar { previewMenu }
                }
                .toolbar { previewMenu }
        }
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
            CommonGroundInvitationMockup(draft: CommonGroundInvitationDraft(place: place))
        case .recipient(let place):
            CommonGroundInvitationMockup(draft: CommonGroundInvitationDraft(place: place), opensEnvelope: true)
        case .recipientOpened:
            CommonGroundInvitationMockup(draft: .preview, opensEnvelope: true, initiallyOpened: true)
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
        case .messages: return []
        case .recipientOpened: return [.detail, .recipientOpened]
        }
    }
}

private extension CommonGroundMockPage {
    var previewTitle: String {
        switch self {
        case .profile: "Joe’s profile"
        case .ownProfile: "Your profile"
        case .detail: "In Common · Overview"
        case .mix: "In Common · Places"
        case .invitation: "Make an invitation"
        case .recipient: "Receive an invitation"
        case .messages: "In Messages"
        case .recipientOpened: "Opened invitation"
        case .sparse: "In Common · A few places"
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
                    ProgressView("Finding what you have in common…")
                        .font(AstirTypography.body).frame(maxWidth: .infinity, minHeight: 220)
                } else if state == .unavailable {
                    ContentUnavailableView {
                        Label("A little out of reach", systemImage: "arrow.triangle.2.circlepath")
                    } description: {
                        Text("In Common couldn’t load. Give it another try.")
                    } actions: {
                        Button("Try again", action: retry).buttonStyle(.bordered)
                    }
                } else {
                    sharedFavorite
                    VStack(alignment: .leading, spacing: 16) {
                        CommonGroundMixCover(count: CommonGroundMockData.mix(sparse: state == .sparse).count, action: openMix)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        CommonGroundSectionHeading(title: "What you have in common")
                        evidenceLink("Both loved", detail: "The ones you’d happily go back to", count: CommonGroundMockData.places.filter(\.bothLoved).count, icon: "heart")
                        evidenceLink("Both regulars", detail: "Part of both your routines", count: CommonGroundMockData.places.filter(\.bothRegulars).count, icon: "arrow.counterclockwise")
                        evidenceLink("Both Wanna Go", detail: "In both of your Wannas", count: CommonGroundMockData.places.filter { $0.youWanna && $0.joeWanna }.count, icon: "bookmark")
                        evidenceLink("All shared places", detail: "The familiar, the new, the different takes", count: CommonGroundMockData.places.count, icon: "mappin.and.ellipse")
                    }
                }
                CommonGroundSampleCaption()
            }
            .padding(20).padding(.bottom, 24)
        }
        .navigationTitle("In Common")
        .navigationBarTitleDisplayMode(.inline)
        .astirScreen()
    }

    private var sharedFavorite: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("A SHARED SOFT SPOT").font(AstirTypography.metadata)
                    .tracking(1.5).foregroundStyle(brand.accentText)
                Spacer()
                CommonGroundSparkStamp(symbol: "flame.fill")
            }
            Text("You both love Narwhal")
                .font(AstirTypography.screenTitle).fixedSize(horizontal: false, vertical: true)
            Text("18 check-ins for you. 17 for Joe.\nSafe to say you’ve both found your spot.")
                .font(AstirTypography.body).foregroundStyle(brand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                CommonGroundPhoto(tile: 0).frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Narwhal").font(AstirTypography.control)
                    Text("Coffee · Silver Lake").font(AstirTypography.bodySmall)
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
        .padding(22)
        .background(brand.accentWash, in: RoundedRectangle(cornerRadius: 22))
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
                        Text("In Common").font(AstirTypography.screenTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "envelope.open").font(.system(size: 40, weight: .light))
                            .rotationEffect(.degrees(12)).padding(.top, 15).accessibilityHidden(true)
                    }
                }
                Text("A few places that have you both written all over them.")
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
        .accessibilityLabel("In Common, \(count) places for you and Joe")
        .accessibilityIdentifier("common-ground.open-mix")
    }
}

struct CommonGroundMixMockup: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var area: String
    let sparse: Bool
    let livePlaces: [CommonGroundMockPlace]?
    let cities: [String]
    let viewer: CommonGroundPerson
    let partner: CommonGroundPerson
    let openPlace: (CommonGroundMockPlace) -> Void
    let invite: (CommonGroundMockPlace) -> Void

    init(
        sparse: Bool = false,
        livePlaces: [CommonGroundMockPlace]? = nil,
        cities: [String] = CommonGroundMockData.availableCities,
        viewer: CommonGroundPerson = .previewViewer,
        partner: CommonGroundPerson = .previewPartner,
        openPlace: @escaping (CommonGroundMockPlace) -> Void,
        invite: @escaping (CommonGroundMockPlace) -> Void
    ) {
        self.sparse = sparse
        self.livePlaces = livePlaces
        self.cities = cities
        self.viewer = viewer
        self.partner = partner
        self.openPlace = openPlace
        self.invite = invite
        _area = State(initialValue: livePlaces == nil ? "Los Angeles" : "All places")
    }

    private var places: [CommonGroundMockPlace] {
        if let livePlaces {
            return livePlaces.filter { area == "All places" || $0.city == area }
        }
        return CommonGroundMockData.mix(area: area, sparse: sparse)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 16) {
                        Text("\(viewer.shortName) + \(partner.shortName)")
                            .font(AstirTypography.label)
                            .foregroundStyle(brand.primaryText)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        HStack(spacing: -10) {
                            CommonGroundPersonAvatar(person: viewer, size: 52)
                            CommonGroundPersonAvatar(person: partner, size: 52)
                        }
                    }
                    HStack(alignment: .center) {
                        areaPicker
                        Spacer(minLength: 12)
                        Text("\(places.count) places")
                            .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                            .accessibilityIdentifier("common-ground.mix-count")
                    }
                    Rectangle().fill(brand.border).frame(height: 1)
                }
                if places.isEmpty {
                    ContentUnavailableView {
                        Label("A little more to discover", systemImage: "map")
                    } description: {
                        Text(livePlaces == nil ? "There aren’t any picks for you two in this city yet" : "Places you both save will show up here")
                    } actions: {
                        Button(livePlaces == nil ? "Back to Los Angeles" : "All places") { area = livePlaces == nil ? "Los Angeles" : "All places" }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                    }
                } else {
                    ForEach(places) { place in
                        CommonGroundPlaceStory(place: place, openPlace: { openPlace(place) },
                                               invite: { invite(place) })
                        if place.id != places.last?.id {
                            Rectangle().fill(brand.border).frame(height: 1)
                                .padding(.vertical, 4)
                        }
                    }
                }
                if livePlaces == nil { CommonGroundSampleCaption() }
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 32)
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                (Text("In ") + Text("Common").italic())
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(brand.primaryText)
                    .accessibilityLabel("In Common")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("common-ground.collection-title")
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .astirScreen()
        .onChange(of: cities) { _, cities in
            if livePlaces != nil && area != "All places" && !cities.contains(area) { area = "All places" }
        }
    }

    private var areaPicker: some View {
        Menu {
            Picker("City", selection: $area) {
                if livePlaces != nil { Text("All places").tag("All places") }
                ForEach(cities, id: \.self) { city in
                    Text(city).tag(city)
                }
            }
            Text("Cities either of you has been to")
        } label: {
            HStack(spacing: 7) {
                Text(area)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(AstirTypography.label).foregroundStyle(brand.primaryText)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(area)
        .accessibilityHint("Choose a city either of you has visited")
        .accessibilityIdentifier("common-ground.area")
    }
}

/// Open editorial stories: a familiar place, a shared love, a possibility,
/// and introductions in either direction. Each keeps its evidence and action.
private struct CommonGroundPlaceStory: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let place: CommonGroundMockPlace
    let openPlace: () -> Void
    let invite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if place.kind == .introduce {
                introduction
            } else {
                headline
                if place.bothLoved && !place.bothRegulars {
                    sharedRatings
                } else {
                    photo(height: place.kind == .returnTogether ? 212 : 184)
                    if place.kind == .returnTogether {
                        regulars
                    } else {
                        Label(place.kind == .mutualWanna ? "In both of your Wannas" : place.narrativeDetail,
                              systemImage: place.kind == .mutualWanna ? "bookmark.fill" : "mappin.and.ellipse")
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brand.secondaryText)
                            .accessibilityIdentifier("common-ground.wanna.\(place.id)")
                    }
                }
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(place.linkage == .sharedRegulars ? 16 : 0)
        .background {
            if place.linkage == .sharedRegulars {
                RoundedRectangle(cornerRadius: 22)
                    .fill(brand.raisedBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(LinearGradient(
                                stops: [
                                    .init(color: brand.accent.opacity(0.04), location: 0),
                                    .init(color: .white.opacity(0.25), location: 0.34),
                                    .init(color: .white.opacity(0.04), location: 0.52),
                                    .init(color: brand.accent.opacity(0.08), location: 1)
                                ], startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 0.75)
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(place.narrativeTitle)
                .font(.system(place.kind == .introduce ? .title2 : .title, design: .serif).weight(.medium))
                .foregroundStyle(brand.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("common-ground.narrative.\(place.id)")

        }
    }

    private var introduction: some View {
        footerLayout {
            if !dynamicTypeSize.isAccessibilitySize {
                photo(height: 148).frame(width: 112)
            }
            VStack(alignment: .leading, spacing: 12) {
                headline
                Text(place.narrativeDetail)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var regulars: some View {
        footerLayout {
            personEvidence(name: "You", person: place.viewer, value: "\(place.youVisits) check-ins")
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
            personEvidence(name: place.partner.shortName, person: place.partner, value: "\(place.joeVisits) check-ins")
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(place.narrativeDetail)
    }

    private var sharedRatings: some View {
        VStack(alignment: .leading, spacing: 10) {
            footerLayout {
                rating(name: "You", value: place.youRating)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 16) }
                rating(name: place.partner.shortName, value: place.joeRating)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(brand.accentText)
                        .padding(.leading, 8).accessibilityHidden(true)
                }
            }
            Text("A shared soft spot")
                .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(place.narrativeDetail)
    }

    private func personEvidence(name: String, person: CommonGroundPerson, value: String) -> some View {
        HStack(spacing: 9) {
            CommonGroundPersonAvatar(person: person, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                Text(value).font(AstirTypography.label).foregroundStyle(brand.primaryText)
            }
        }
    }

    private func rating(name: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value?.formatted(.number.precision(.fractionLength(0...1))) ?? "—")
                    .font(.system(.largeTitle, design: .serif).weight(.medium))
                Text("/ 5").font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
            }
        }
    }

    private func photo(height: CGFloat) -> some View {
        Button(action: openPlace) {
            CommonGroundPlaceArtwork(place: place)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(brand.primaryText)
                    .frame(width: 36, height: 36)
                    .background(brand.background, in: Circle())
                    .padding(10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(place.name), \(place.category), \(place.area)")
        .accessibilityIdentifier("common-ground.place.\(place.id)")
    }

    private var footer: some View {
        footerLayout {
            Button(action: openPlace) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.category).font(AstirTypography.label)
                    Text(place.area).font(AstirTypography.caption)
                        .foregroundStyle(brand.secondaryText)
                }
                .foregroundStyle(brand.primaryText)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(place.name), \(place.category), \(place.area)")
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Button(action: invite) {
                HStack(spacing: 9) {
                    Text("Invite \(place.partner.shortName)")
                    Image(systemName: "arrow.up.right")
                }
                .font(AstirTypography.control)
                .foregroundStyle(brand.accentForeground)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(brand.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("common-ground.invite.\(place.id)")
        }
    }

    private var footerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }
}

private struct CommonGroundSparkStamp: View {
    @Environment(\.astirBrandMode) private var brand
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(brand.accentText)
            .frame(width: 52, height: 52)
            .background(brand.accentWash, in: Circle())
            .rotationEffect(.degrees(-9))
            .accessibilityHidden(true)
    }
}

private extension CommonGroundMockKind {
    var shortLabel: String {
        switch self {
        case .returnTogether: "Go back together"
        case .mutualWanna: "In both of your Wannas"
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
    private let filters = ["All shared", "Both loved", "Both regulars", "Both Wanna Go", "Worth introducing", "Both been", "Different takes"]

    init(initialFilter: String, openPlace: @escaping (CommonGroundMockPlace) -> Void) {
        _filter = State(initialValue: initialFilter)
        self.openPlace = openPlace
    }

    private var places: [CommonGroundMockPlace] {
        CommonGroundMockData.places.filter { place in
            switch filter {
            case "Both loved": place.bothLoved
            case "Both regulars": place.bothRegulars
            case "Both Wanna Go": place.youWanna && place.joeWanna
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
                CommonGroundPlaceArtwork(place: place)
                    .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 8) {
                    Text(place.name).font(AstirTypography.screenTitle)
                        .accessibilityIdentifier("common-ground.place-profile.name")
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
                .accessibilityIdentifier("common-ground.place-profile.invite")
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
            Text([visits > 0 ? "\(visits) \(visits == 1 ? "check-in" : "check-ins")" : nil,
                  wanna ? "Wanna" : nil].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(brand.secondaryText)
            if let rating { Text(String(format: "★ %.1f / 5", rating)).foregroundStyle(brand.accentText) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Keep the selected place's artwork consistent across its story, profile, and invitation.
struct CommonGroundPlaceArtwork: View {
    @Environment(\.astirBrandMode) private var brand
    let place: CommonGroundMockPlace

    var body: some View {
        Group {
            if let reference = place.photoReference {
                CommonGroundLivePlaceArtwork(reference: reference, systemImage: place.systemImage)
            } else if let tile = place.previewPhotoTile {
                CommonGroundPhoto(tile: tile)
            } else {
                Image(systemName: place.systemImage)
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(brand.accentText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(brand.raisedBackground)
            }
        }
        .accessibilityHidden(true)
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
                        CommonGroundSectionHeading(title: "In Common")
                        HStack(spacing: 12) {
                            CommonGroundAvatarPair(size: 34)
                            Text("You both love Narwhal").font(AstirTypography.cardTitle)
                        }
                        Text("35 check-ins between you. And a few new places to make your own.")
                            .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                        Button(action: openMix) {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.open").font(.title2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("In Common").font(AstirTypography.sectionTitle)
                                    Text("\(CommonGroundMockData.mix().count) places picked for you two").font(AstirTypography.bodySmall)
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

struct CommonGroundAvatar: View {
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

struct CommonGroundPhoto: View {
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

#Preview("In Common · Overview") { CommonGroundDesignMockupRoot(page: .detail) }
#Preview("In Common · Places") { CommonGroundDesignMockupRoot(page: .mix) }
#Preview("Member profile") { CommonGroundDesignMockupRoot(page: .profile) }
#Preview("Your profile") { CommonGroundDesignMockupRoot(page: .ownProfile) }
#Preview("In Common · Dark") { CommonGroundDesignMockupRoot(page: .detail).preferredColorScheme(.dark) }
#endif
