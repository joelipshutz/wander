#if DEBUG
import SwiftUI

enum InCommonDesignMockupPage: String, CaseIterable {
    case profile
    case overlap
    case tasteReceipt
    case sharedMap
    case nonFriend
    case empty
    case loading
    case error

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> InCommonDesignMockupPage? {
        if let environmentValue = environment["WANDER_IN_COMMON_MOCKUP"] {
            return InCommonDesignMockupPage(rawValue: environmentValue) ?? .profile
        }

        guard let flagIndex = arguments.firstIndex(of: "-WanderInCommonMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .profile
        }

        return InCommonDesignMockupPage(rawValue: arguments[valueIndex]) ?? .profile
    }

    fileprivate var initialDirection: InCommonMockupDirection {
        switch self {
        case .tasteReceipt:
            return .tasteReceipt
        case .sharedMap:
            return .sharedMap
        case .profile, .overlap, .nonFriend, .empty, .loading, .error:
            return .overlap
        }
    }

    fileprivate var relationship: InCommonMockupRelationship {
        self == .nonFriend ? .following : .friend
    }

    fileprivate var loadState: InCommonMockupLoadState {
        switch self {
        case .empty:
            return .empty
        case .loading:
            return .loading
        case .error:
            return .error
        case .profile, .overlap, .tasteReceipt, .sharedMap, .nonFriend:
            return .loaded
        }
    }

    fileprivate var startsAtDestination: Bool {
        self != .profile
    }
}

enum InCommonMockupDirection: String, CaseIterable, Hashable {
    case overlap
    case tasteReceipt
    case sharedMap

    var title: String {
        switch self {
        case .overlap: "overlap"
        case .tasteReceipt: "taste receipt"
        case .sharedMap: "shared map"
        }
    }
}

enum InCommonMockupRelationship: Equatable {
    case friend
    case following

    var visiblePlaceCount: Int {
        self == .friend ? 18 : 8
    }

    var score: Int {
        self == .friend ? 86 : 72
    }

    var label: String {
        self == .friend ? "Friends" : "Following"
    }
}

enum InCommonMockupLoadState: Equatable {
    case loaded
    case empty
    case loading
    case error
}

struct InCommonDesignMockupRoot: View {
    let page: InCommonDesignMockupPage

    @State private var path: [InCommonMockupDirection]
    @State private var selectedDirection: InCommonMockupDirection
    @State private var relationship: InCommonMockupRelationship
    @State private var loadState: InCommonMockupLoadState

    init(page: InCommonDesignMockupPage) {
        self.page = page
        let direction = page.initialDirection
        _selectedDirection = State(initialValue: direction)
        _relationship = State(initialValue: page.relationship)
        _loadState = State(initialValue: page.loadState)
        _path = State(initialValue: page.startsAtDestination ? [direction] : [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            InCommonProfileEntryMockup(
                selectedDirection: $selectedDirection,
                relationship: relationship
            ) {
                path.append(selectedDirection)
            }
            .navigationDestination(for: InCommonMockupDirection.self) { direction in
                InCommonDestinationMockup(
                    direction: direction,
                    relationship: relationship,
                    loadState: loadState,
                    openSharedMap: {
                        path.append(.sharedMap)
                    }
                )
            }
        }
        .tint(WanderTheme.terracottaDark.color)
        .preferredColorScheme(.light)
    }
}

private struct InCommonProfileEntryMockup: View {
    @Binding var selectedDirection: InCommonMockupDirection
    let relationship: InCommonMockupRelationship
    let openInCommon: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                profileHeader
                inCommonButton
                directionPicker
                recentActivity
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing12)
        }
        .scrollIndicators(.hidden)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var profileHeader: some View {
        VStack(spacing: WanderTheme.spacing3) {
            HStack {
                Text("profile")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .black))
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .wanderGlassCapsule()
            }

            WanderAvatar(
                initials: "MP",
                size: 92,
                color: WanderTheme.avatarSofia.color
            )

            VStack(spacing: WanderTheme.spacing1) {
                Text("Maya Patel")
                    .font(WanderTypography.editorialTitle)
                Text("@mayap  •  Los Angeles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text("Always looking for a patio, a trail, or really good noodles.")
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .padding(.top, WanderTheme.spacing1)
            }

            HStack(spacing: WanderTheme.spacing2) {
                Label(relationship.label, systemImage: relationship == .friend ? "person.2.fill" : "person.crop.circle.badge.checkmark")
                Text("128 followers")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(WanderTheme.textMuted.color)
        }
    }

    private var inCommonButton: some View {
        Button(action: openInCommon) {
            HStack(spacing: WanderTheme.spacing3) {
                InCommonAvatarPair(size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(relationship.visiblePlaceCount) places in common")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("See where your maps overlap")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer(minLength: WanderTheme.spacing2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .frame(maxWidth: .infinity, minHeight: 76)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .wanderGlassPanel(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(relationship.visiblePlaceCount) places in common with Maya Patel")
        .accessibilityHint("Opens the In Common page")
    }

    private var directionPicker: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("mockup direction")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            HStack(spacing: WanderTheme.spacing2) {
                ForEach(InCommonMockupDirection.allCases, id: \.self) { direction in
                    Button {
                        selectedDirection = direction
                    } label: {
                        Text(direction.title)
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(
                                selectedDirection == direction
                                    ? WanderTheme.textOnAction.color
                                    : WanderTheme.textMuted.color
                            )
                            .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                            .background(
                                selectedDirection == direction
                                    ? WanderTheme.textInk.color
                                    : WanderTheme.surfaceSand.color
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("recent activity")
                .font(.system(size: 18, weight: .black))

            ForEach(Array(InCommonMockData.places.prefix(2))) { place in
                HStack(spacing: WanderTheme.spacing3) {
                    Text(place.emoji)
                        .font(.system(size: 26))
                        .frame(width: 48, height: 48)
                        .background(place.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.system(size: 15, weight: .black))
                        Text("Maya saved this  •  \(place.area)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }
            }
        }
    }
}

private struct InCommonDestinationMockup: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let direction: InCommonMockupDirection
    let relationship: InCommonMockupRelationship
    let loadState: InCommonMockupLoadState
    let openSharedMap: () -> Void

    @State private var searchText = ""
    @State private var selectedType = InCommonPlaceType.all
    @State private var selectedTag = InCommonPlaceTag.all
    @State private var selectedCategory: String?
    @State private var expandedPlaceID: String?
    @State private var selectedMapPlaceID = InCommonMockData.places[0].id
    @State private var didRevealScore = false
    @State private var showsActionConfirmation = false

    var body: some View {
        Group {
            switch loadState {
            case .loaded:
                loadedContent
            case .empty:
                InCommonStateMockup(
                    symbol: "circle.dashed",
                    title: "Your maps haven’t crossed yet",
                    message: "When you save the same place, it’ll show up here.",
                    actionTitle: "Explore Maya’s map",
                    action: performPrimaryAction
                )
            case .loading:
                InCommonLoadingMockup()
            case .error:
                InCommonStateMockup(
                    symbol: "arrow.clockwise.circle",
                    title: "Couldn’t compare maps",
                    message: "Your saves are safe. Try the comparison again.",
                    actionTitle: "Try again",
                    action: performPrimaryAction
                )
            }
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .navigationTitle("in common")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(WanderTheme.canvasWarm.color, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .overlay(alignment: .top) {
            if showsActionConfirmation {
                Label(actionConfirmationCopy, systemImage: "sparkles")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .padding(.horizontal, WanderTheme.spacing4)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .background(WanderTheme.textInk.color)
                    .clipShape(Capsule())
                    .shadow(color: WanderTheme.textInk.color.opacity(0.18), radius: 12, y: 5)
                    .padding(.top, WanderTheme.spacing2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            guard loadState == .loaded else { return }
            revealScore()
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        switch direction {
        case .overlap:
            overlapDirection
        case .tasteReceipt:
            tasteReceiptDirection
        case .sharedMap:
            sharedMapDirection
        }
    }

    private var overlapDirection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                privacyNotice
                InCommonOverlapHero(
                    score: relationship.score,
                    isRevealed: didRevealScore,
                    relationship: relationship,
                    replayScore: revealScore
                )
                similaritySignals
                overlapFilters
                overlapPlaceResults
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InCommonPrimaryButton(
                title: "Open your shared map",
                systemImage: "map.fill",
                action: openSharedMap
            )
        }
    }

    private var tasteReceiptDirection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                privacyNotice

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(relationship.score >= 80 ? "Taste twins." : "Plenty to compare.")
                            .font(WanderTypography.editorialDisplay)
                            .foregroundStyle(WanderTheme.textInk.color)

                        Spacer(minLength: WanderTheme.spacing2)

                        Text(relationship.score >= 80 ? "👯" : "🤝")
                            .font(.system(size: 34))
                            .scaleEffect(didRevealScore ? 1 : 0.55)
                            .rotationEffect(.degrees(didRevealScore ? 0 : -12))
                    }

                    Text("A quick read on where you and Maya line up.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                InCommonTasteReceipt(
                    score: relationship.score,
                    selectedCategory: $selectedCategory
                )

                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    Text(selectedCategory.map { "shared \($0.lowercased()) spots" } ?? "the receipts")
                        .font(WanderTypography.editorialCardTitle)

                    placeList(categoryFilteredPlaces)
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InCommonPrimaryButton(title: "Pick from your shared favorites", systemImage: "sparkles", action: performPrimaryAction)
        }
    }

    private var sharedMapDirection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                privacyNotice

                HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                    InCommonAvatarPair(size: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(relationship.score)% map overlap")
                            .font(WanderTypography.editorialCardTitle)
                        Text("Strongest around Silver Lake")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }

                    Spacer()

                    Text(relationship.score >= 80 ? "🔥" : "✨")
                        .font(.system(size: 28))
                        .scaleEffect(didRevealScore ? 1 : 0.6)
                }

                InCommonSharedMap(
                    places: InCommonMockData.places,
                    selectedPlaceID: $selectedMapPlaceID
                )

                neighborhoodChips

                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    Text("where you agree")
                        .font(WanderTypography.editorialCardTitle)

                    placeList(mapOrderedPlaces)
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InCommonPrimaryButton(title: "Open the full shared map", systemImage: "arrow.up.right", action: performPrimaryAction)
        }
    }

    @ViewBuilder
    private var privacyNotice: some View {
        if relationship == .following {
            HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.stateInfo.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Based on places visible to you")
                        .font(.system(size: 13, weight: .black))
                    Text("Friends-only and private saves stay out of this comparison.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WanderTheme.skyTint.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        }
    }

    private var similaritySignals: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("you both keep coming back for")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            ScrollView(.horizontal) {
                HStack(spacing: WanderTheme.spacing2) {
                    InCommonSignalChip(
                        emoji: "☕️",
                        title: "coffee",
                        detail: relationship == .friend ? "6 matches" : "3 visible"
                    )
                    InCommonSignalChip(
                        emoji: "🌶️",
                        title: "spicy",
                        detail: relationship == .friend ? "4 matches" : "2 visible"
                    )
                    InCommonSignalChip(
                        emoji: "🥾",
                        title: "outdoors",
                        detail: relationship == .friend ? "3 matches" : "2 visible"
                    )
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var overlapFilters: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing2) {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)

                    TextField("search in common", text: $searchText)
                        .font(.system(size: 15, weight: .semibold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(WanderTheme.textFaint.color)
                                .frame(width: 32, height: WanderTheme.tapMinimum)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.leading, WanderTheme.spacing3)
                .padding(.trailing, searchText.isEmpty ? WanderTheme.spacing3 : 2)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )

                Menu {
                    ForEach(InCommonPlaceTag.allCases, id: \.self) { tag in
                        Button {
                            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.18)) {
                                selectedTag = tag
                            }
                        } label: {
                            if selectedTag == tag {
                                Label(tag.title, systemImage: "checkmark")
                            } else {
                                Text(tag.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: WanderTheme.spacing1) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(selectedTag.title)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .black))
                    }
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .padding(.horizontal, WanderTheme.spacing2)
                    .frame(minWidth: 112, minHeight: 48)
                    .background(
                        selectedTag == .all
                            ? WanderTheme.surfaceBone.color
                            : WanderTheme.sunTint.color
                    )
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                            .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                    )
                }
                .accessibilityLabel("Tag filter, \(selectedTag.title)")
            }

            ScrollView(.horizontal) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(InCommonPlaceType.allCases, id: \.self) { type in
                        typeFilterChip(type)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func typeFilterChip(_ type: InCommonPlaceType) -> some View {
        Button {
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.18)) {
                selectedType = type
            }
        } label: {
            HStack(spacing: WanderTheme.spacing1) {
                if let emoji = type.emoji {
                    Text(emoji)
                }
                Text(type.title)
            }
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(
                selectedType == type
                    ? WanderTheme.textOnAction.color
                    : WanderTheme.textInk.color
            )
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: WanderTheme.tapMinimum)
            .background(
                selectedType == type
                    ? WanderTheme.textInk.color
                    : WanderTheme.surfaceSand.color
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.title) type filter")
        .accessibilityAddTraits(selectedType == type ? .isSelected : [])
    }

    @ViewBuilder
    private var overlapPlaceResults: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .firstTextBaseline) {
                Text("places you agree on")
                    .font(WanderTypography.editorialCardTitle)

                Spacer()

                if hasActiveOverlapFilters {
                    Button("clear") {
                        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.18)) {
                            searchText = ""
                            selectedType = .all
                            selectedTag = .all
                        }
                    }
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(minHeight: WanderTheme.tapMinimum)
                } else {
                    Text("\(filteredPlaces.count) shown")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }

            if filteredPlaces.isEmpty {
                VStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text("No shared places match")
                        .font(.system(size: 15, weight: .black))
                    Text("Try another type, tag, or search.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
            } else {
                placeList(filteredPlaces)
            }
        }
    }

    private var hasActiveOverlapFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedType != .all
            || selectedTag != .all
    }

    private func placeList(_ places: [InCommonMockPlace]) -> some View {
        VStack(spacing: WanderTheme.spacing2) {
            ForEach(places) { place in
                InCommonPlaceRow(
                    place: place,
                    isExpanded: expandedPlaceID == place.id,
                    isSelected: selectedMapPlaceID == place.id && direction == .sharedMap
                ) {
                    withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) {
                        expandedPlaceID = expandedPlaceID == place.id ? nil : place.id
                        selectedMapPlaceID = place.id
                    }
                }
            }
        }
    }

    private var neighborhoodChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WanderTheme.spacing2) {
                neighborhoodChip("Silver Lake", count: 7, placeID: "dayglow")
                neighborhoodChip("Los Feliz", count: 5, placeID: "maru")
                neighborhoodChip("Arts District", count: 4, placeID: "bestia")
            }
        }
        .scrollIndicators(.hidden)
    }

    private func neighborhoodChip(_ title: String, count: Int, placeID: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) {
                selectedMapPlaceID = placeID
                expandedPlaceID = placeID
            }
        } label: {
            HStack(spacing: WanderTheme.spacing1) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(WanderTheme.textInk.color)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: WanderTheme.tapMinimum)
            .background(
                selectedMapPlaceID == placeID
                    ? WanderTheme.sunTint.color
                    : WanderTheme.surfaceBone.color
            )
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var filteredPlaces: [InCommonMockPlace] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return InCommonMockData.places.filter { place in
            let matchesSearch = query.isEmpty
                || place.searchableText.localizedCaseInsensitiveContains(query)
            let matchesType = selectedType == .all || place.type == selectedType
            let matchesTag = selectedTag == .all || place.tags.contains(selectedTag)
            return matchesSearch && matchesType && matchesTag
        }
    }

    private var categoryFilteredPlaces: [InCommonMockPlace] {
        guard let selectedCategory else { return InCommonMockData.places }
        return InCommonMockData.places.filter { $0.category == selectedCategory }
    }

    private var mapOrderedPlaces: [InCommonMockPlace] {
        InCommonMockData.places.sorted { lhs, _ in
            lhs.id == selectedMapPlaceID
        }
    }

    private var actionConfirmationCopy: String {
        switch direction {
        case .overlap, .sharedMap:
            return "Shared map ready"
        case .tasteReceipt:
            return "18 good options, narrowed down"
        }
    }

    private func performPrimaryAction() {
        guard !showsActionConfirmation else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) {
            showsActionConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) {
                showsActionConfirmation = false
            }
        }
    }

    private func revealScore() {
        if reduceMotion {
            didRevealScore = true
            return
        }

        didRevealScore = false
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 1.2)) {
                didRevealScore = true
            }
        }
    }
}

private struct InCommonOverlapHero: View {
    let score: Int
    let isRevealed: Bool
    let relationship: InCommonMockupRelationship
    let replayScore: () -> Void

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            HStack(alignment: .center, spacing: WanderTheme.spacing4) {
                Button(action: replayScore) {
                    InCommonAnimatedScoreRing(
                        score: score,
                        progress: isRevealed ? 1 : 0
                    )
                }
                .buttonStyle(.plain)
                .frame(width: 112, height: 112)
                .accessibilityLabel("\(score) percent map overlap")
                .accessibilityHint("Replays the score animation")

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    InCommonAvatarPair(size: 38)
                    Text(score >= 80 ? "Your maps really click ✨" : "You’ve got common ground")
                        .font(WanderTypography.editorialCardTitle)
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("\(relationship.visiblePlaceCount) shared places, with the strongest match in coffee and casual dinners.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: .infinity)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }
}

private struct InCommonAnimatedScoreRing: View, @MainActor Animatable {
    let score: Int
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(WanderTheme.surfaceSand.color, lineWidth: 10)

            Circle()
                .trim(from: 0, to: CGFloat(clampedProgress) * CGFloat(score) / 100)
                .stroke(
                    AngularGradient(
                        colors: [
                            WanderTheme.terracotta.color,
                            WanderTheme.categorySun.color,
                            WanderTheme.pinSocial.color
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(InCommonScoreAnimation.displayedScore(target: score, progress: clampedProgress))%")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text("overlap")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}

enum InCommonScoreAnimation {
    static func displayedScore(target: Int, progress: Double) -> Int {
        let clampedProgress = min(max(progress, 0), 1)
        return Int((Double(target) * clampedProgress).rounded())
    }
}

private struct InCommonTasteReceipt: View {
    let score: Int
    @Binding var selectedCategory: String?

    private let categories = [
        ("Coffee", 94, "☕️"),
        ("Dinner", 88, "🍝"),
        ("Outdoors", 76, "🥾")
    ]

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REC.ME / MATCH 018")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text("\(score) / 100")
                        .font(.system(size: 34, weight: .black, design: .monospaced))
                }

                Spacer()

                Text("GOOD TASTE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .padding(.horizontal, WanderTheme.spacing2)
                    .frame(minHeight: 30)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(Capsule())
            }

            InCommonDashedDivider()

            ForEach(categories, id: \.0) { category, value, emoji in
                Button {
                    selectedCategory = selectedCategory == category ? nil : category
                } label: {
                    VStack(spacing: WanderTheme.spacing2) {
                        HStack {
                            Text("\(emoji) \(category.uppercased())")
                            Spacer()
                            Text("\(value)%")
                        }
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(WanderTheme.textInk.color)

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(WanderTheme.surfaceSand.color)
                                Capsule()
                                    .fill(selectedCategory == category ? WanderTheme.terracotta.color : WanderTheme.textInk.color)
                                    .frame(width: geometry.size.width * CGFloat(value) / 100)
                            }
                        }
                        .frame(height: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(category), \(value) percent match")
                .accessibilityHint("Filters shared places by this category")
            }

            InCommonDashedDivider()

            HStack {
                Text("18 SHARED PLACES")
                Spacer()
                Text("THANK YOU, NEXT REC →")
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .shadow(color: WanderTheme.textInk.color.opacity(0.08), radius: 12, y: 6)
    }
}

private struct InCommonDashedDivider: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay {
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: 600, y: 0))
                }
                .stroke(
                    WanderTheme.borderStrong.color,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
            }
    }
}

private struct InCommonSharedMap: View {
    let places: [InCommonMockPlace]
    @Binding var selectedPlaceID: String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(WanderTheme.skyTint.color)

                Circle()
                    .fill(WanderTheme.categorySage.color.opacity(0.65))
                    .frame(width: 118, height: 118)
                    .offset(x: -geometry.size.width * 0.25, y: -36)

                Path { path in
                    path.move(to: CGPoint(x: -20, y: geometry.size.height * 0.28))
                    path.addCurve(
                        to: CGPoint(x: geometry.size.width + 20, y: geometry.size.height * 0.68),
                        control1: CGPoint(x: geometry.size.width * 0.28, y: geometry.size.height * 0.12),
                        control2: CGPoint(x: geometry.size.width * 0.72, y: geometry.size.height * 0.84)
                    )
                }
                .stroke(WanderTheme.surfaceRaised.color.opacity(0.95), style: StrokeStyle(lineWidth: 16, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: geometry.size.width * 0.72, y: -20))
                    path.addLine(to: CGPoint(x: geometry.size.width * 0.3, y: geometry.size.height + 20))
                }
                .stroke(WanderTheme.surfaceBone.color.opacity(0.82), style: StrokeStyle(lineWidth: 11, lineCap: .round))

                ForEach(Array(places.prefix(5).enumerated()), id: \.element.id) { index, place in
                    let point = InCommonMockData.mapPoints[index]
                    Button {
                        selectedPlaceID = place.id
                    } label: {
                        ZStack {
                            Circle()
                                .fill(selectedPlaceID == place.id ? WanderTheme.textInk.color : WanderTheme.surfaceRaised.color)
                                .frame(width: selectedPlaceID == place.id ? 48 : 42, height: selectedPlaceID == place.id ? 48 : 42)
                                .shadow(color: WanderTheme.textInk.color.opacity(0.18), radius: 6, y: 3)
                            Text(place.emoji)
                                .font(.system(size: selectedPlaceID == place.id ? 22 : 19))
                        }
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: geometry.size.width * point.x,
                        y: geometry.size.height * point.y
                    )
                    .accessibilityLabel(place.name)
                    .accessibilityHint("Selects this shared place")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("SILVER LAKE")
                        .font(.system(size: 10, weight: .black))
                    Text("7 overlaps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                .padding(.horizontal, WanderTheme.spacing2)
                .padding(.vertical, WanderTheme.spacing1)
                .background(WanderTheme.surfaceBone.color.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall, style: .continuous))
                .position(x: geometry.size.width * 0.24, y: geometry.size.height * 0.18)
            }
        }
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }
}

private struct InCommonSignalChip: View {
    let emoji: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Text(emoji)
                .font(.system(size: 21))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .black))
                Text(detail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 54)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
    }
}

private struct InCommonPlaceRow: View {
    let place: InCommonMockPlace
    let isExpanded: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: isExpanded ? WanderTheme.spacing3 : 0) {
                HStack(spacing: WanderTheme.spacing3) {
                    Text(place.emoji)
                        .font(.system(size: 25))
                        .frame(width: 50, height: 50)
                        .background(place.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(WanderTypography.editorialSmallNamedContent)
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(1)
                        Text("\(place.category)  •  \(place.area)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }

                    Spacer(minLength: WanderTheme.spacing2)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(place.sharedState.label)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(place.sharedState.foreground)
                            .padding(.horizontal, WanderTheme.spacing2)
                            .padding(.vertical, WanderTheme.spacing1)
                            .background(place.sharedState.background)
                            .clipShape(Capsule())
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(WanderTheme.textFaint.color)
                    }
                }

                if isExpanded {
                    HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WanderTheme.terracotta.color)
                        Text(place.reason)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 62)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? WanderTheme.sunTint.color.opacity(0.78) : WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                    .stroke(isSelected ? WanderTheme.categorySun.color : WanderTheme.borderHairline.color, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(place.name), \(place.category), \(place.sharedState.label)")
        .accessibilityHint(isExpanded ? "Collapses match details" : "Shows why this place matches")
    }
}

private struct InCommonPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(WanderTheme.textOnAction.color)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(WanderTheme.terracotta.color)
                .clipShape(Capsule())
                .shadow(color: WanderTheme.terracottaDark.color.opacity(0.28), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing2)
        .background(WanderTheme.canvasWarm.color.opacity(0.96))
    }
}

private struct InCommonAvatarPair: View {
    let size: CGFloat

    var body: some View {
        HStack(spacing: -size * 0.28) {
            WanderAvatar(initials: "RL", size: size, color: WanderTheme.avatarRyan.color)
                .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 2))
                .zIndex(1)
            WanderAvatar(initials: "MP", size: size, color: WanderTheme.avatarSofia.color)
                .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 2))
        }
        .frame(width: size * 1.72, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct InCommonStateMockup: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Spacer()

            ZStack {
                Circle()
                    .fill(WanderTheme.terracottaTint.color)
                    .frame(width: 104, height: 104)
                Image(systemName: symbol)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
            }

            VStack(spacing: WanderTheme.spacing2) {
                Text(title)
                    .font(WanderTypography.editorialDisplay)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            InCommonPrimaryButton(title: actionTitle, systemImage: "arrow.right", action: action)
        }
        .padding(.horizontal, WanderTheme.spacing4)
    }
}

private struct InCommonLoadingMockup: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                HStack(spacing: WanderTheme.spacing4) {
                    Circle()
                        .fill(WanderTheme.surfaceSand.color)
                        .frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        InCommonSkeleton(width: 168, height: 22)
                        InCommonSkeleton(width: 210, height: 14)
                        InCommonSkeleton(width: 128, height: 14)
                    }
                }
                .padding(WanderTheme.spacing4)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: WanderTheme.spacing3) {
                        InCommonSkeleton(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                            InCommonSkeleton(width: 160, height: 16)
                            InCommonSkeleton(width: 112, height: 12)
                        }
                    }
                    .padding(WanderTheme.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
                }
            }
            .padding(WanderTheme.spacing4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Comparing your maps")
    }
}

private struct InCommonSkeleton: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: min(height / 2, 8), style: .continuous)
            .fill(WanderTheme.surfaceSand.color)
            .frame(width: width, height: height)
    }
}

private enum InCommonPlaceType: CaseIterable {
    case all
    case coffee
    case dinner
    case outdoors

    var title: String {
        switch self {
        case .all: "all"
        case .coffee: "coffee & sweets"
        case .dinner: "dinner & drinks"
        case .outdoors: "outdoors & nature"
        }
    }

    var emoji: String? {
        switch self {
        case .all: nil
        case .coffee: "☕️"
        case .dinner: "🍝"
        case .outdoors: "🥾"
        }
    }
}

private enum InCommonPlaceTag: CaseIterable {
    case all
    case patio
    case workFriendly
    case spicy
    case goodForGroups
    case weekend

    var title: String {
        switch self {
        case .all: "all tags"
        case .patio: "patio"
        case .workFriendly: "work-friendly"
        case .spicy: "spicy"
        case .goodForGroups: "good for groups"
        case .weekend: "weekend"
        }
    }
}

private enum InCommonSharedState {
    case bothBeen
    case sharedWanna
    case crossedPaths

    var label: String {
        switch self {
        case .bothBeen: "BOTH BEEN"
        case .sharedWanna: "WANNA GO"
        case .crossedPaths: "YOU + MAYA"
        }
    }

    var foreground: Color {
        switch self {
        case .bothBeen: WanderTheme.stateSuccess.color
        case .sharedWanna: WanderTheme.stateWarning.color
        case .crossedPaths: WanderTheme.stateInfo.color
        }
    }

    var background: Color {
        switch self {
        case .bothBeen: WanderTheme.categorySage.color.opacity(0.22)
        case .sharedWanna: WanderTheme.sunTint.color
        case .crossedPaths: WanderTheme.skyTint.color
        }
    }
}

private struct InCommonMockPlace: Identifiable {
    let id: String
    let name: String
    let category: String
    let area: String
    let emoji: String
    let reason: String
    let sharedState: InCommonSharedState
    let tint: Color
    let type: InCommonPlaceType
    let tags: [InCommonPlaceTag]

    var searchableText: String {
        ([name, category, area, reason] + tags.map(\.title)).joined(separator: " ")
    }
}

private enum InCommonMockData {
    static let places = [
        InCommonMockPlace(
            id: "dayglow",
            name: "Dayglow Coffee",
            category: "Coffee",
            area: "Silver Lake",
            emoji: "☕️",
            reason: "You both saved it for bright coffee and an easy catch-up.",
            sharedState: .bothBeen,
            tint: WanderTheme.sunTint.color,
            type: .coffee,
            tags: [.patio, .workFriendly]
        ),
        InCommonMockPlace(
            id: "maru",
            name: "Maru Coffee",
            category: "Coffee",
            area: "Los Feliz",
            emoji: "🫘",
            reason: "Maya called it a reliable morning stop; it’s on your wanna-go map.",
            sharedState: .crossedPaths,
            tint: WanderTheme.terracottaTint.color,
            type: .coffee,
            tags: [.workFriendly, .weekend]
        ),
        InCommonMockPlace(
            id: "bestia",
            name: "Bestia",
            category: "Dinner",
            area: "Arts District",
            emoji: "🍝",
            reason: "You both picked it for a lively dinner with friends.",
            sharedState: .bothBeen,
            tint: WanderTheme.skyTint.color,
            type: .dinner,
            tags: [.goodForGroups, .weekend]
        ),
        InCommonMockPlace(
            id: "griffith",
            name: "Fern Dell Trail",
            category: "Outdoors",
            area: "Griffith Park",
            emoji: "🥾",
            reason: "It’s on both of your maps for an easy weekend walk.",
            sharedState: .sharedWanna,
            tint: WanderTheme.categorySage.color.opacity(0.28),
            type: .outdoors,
            tags: [.weekend]
        ),
        InCommonMockPlace(
            id: "nightmarket",
            name: "Night + Market Song",
            category: "Dinner",
            area: "Silver Lake",
            emoji: "🌶️",
            reason: "You both tagged it spicy, loud, and good for groups.",
            sharedState: .bothBeen,
            tint: WanderTheme.terracottaTint.color,
            type: .dinner,
            tags: [.spicy, .goodForGroups]
        )
    ]

    static let mapPoints = [
        UnitPoint(x: 0.66, y: 0.27),
        UnitPoint(x: 0.34, y: 0.57),
        UnitPoint(x: 0.78, y: 0.72),
        UnitPoint(x: 0.18, y: 0.78),
        UnitPoint(x: 0.52, y: 0.47)
    ]
}

#Preview("In Common · Overlap") {
    InCommonDesignMockupRoot(page: .overlap)
}

#Preview("In Common · Taste Receipt") {
    InCommonDesignMockupRoot(page: .tasteReceipt)
}

#Preview("In Common · Shared Map") {
    InCommonDesignMockupRoot(page: .sharedMap)
}
#endif
