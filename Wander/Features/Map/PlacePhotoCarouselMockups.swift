#if DEBUG
import SwiftUI
import UIKit

enum PlacePhotoCarouselMockupPage: String, CaseIterable {
    case card
    case viewer
    case hundredPhotos

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PlacePhotoCarouselMockupPage? {
        if let environmentValue = environment["WANDER_PLACE_PHOTO_CAROUSEL_MOCKUP"] {
            return PlacePhotoCarouselMockupPage(rawValue: environmentValue) ?? .card
        }

        guard let flagIndex = arguments.firstIndex(of: "-WanderPlacePhotoCarouselMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .card
        }

        return PlacePhotoCarouselMockupPage(rawValue: arguments[valueIndex]) ?? .card
    }
}

struct PlacePhotoCarouselMockupRoot: View {
    let page: PlacePhotoCarouselMockupPage
    @State private var viewerSelection: PlacePhotoCarouselViewerSelection?

    var body: some View {
        Group {
            switch page {
            case .card:
                PlacePhotoCarouselCardMockup(
                    photos: PlacePhotoCarouselMockData.visiblePhotos,
                    onOpenPhoto: openPhoto
                )
            case .viewer:
                PlacePhotoCarouselFullscreenHost(
                    photos: PlacePhotoCarouselMockData.viewerPhotos,
                    initialPhotoID: PlacePhotoCarouselMockData.viewerPhotos[1].id,
                    onClose: {}
                )
            case .hundredPhotos:
                PlacePhotoCarouselCardMockup(
                    photos: PlacePhotoCarouselMockData.hundredVisiblePhotos,
                    onOpenPhoto: openPhoto
                )
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(item: $viewerSelection) { selection in
            PlacePhotoCarouselFullscreenHost(
                photos: selection.photos,
                initialPhotoID: selection.photoID,
                onClose: { viewerSelection = nil }
            )
        }
    }

    private func openPhoto(_ photo: PlacePhotoCarouselMockPhoto, in photos: [PlacePhotoCarouselMockPhoto]) {
        viewerSelection = PlacePhotoCarouselViewerSelection(photoID: photo.id, photos: photos)
    }
}

enum PlacePhotoCarouselMockSaveVisibility: Equatable {
    case shared
    case stealth
}

enum PlacePhotoCarouselMockProfileVisibility: Equatable {
    case publicProfile
    case privateProfile
}

struct PlacePhotoCarouselMockProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let handle: String
    let city: String
    let bio: String
    let avatarTileIndex: Int
}

enum PlacePhotoCarouselMockPhotoSource: Equatable {
    case google
    case user(PlacePhotoCarouselMockProfile)
}

struct PlacePhotoCarouselMockCandidate: Identifiable, Equatable {
    let id: String
    let source: PlacePhotoCarouselMockPhotoSource
    let imageTileIndex: Int
    let saveVisibility: PlacePhotoCarouselMockSaveVisibility
    let profileVisibility: PlacePhotoCarouselMockProfileVisibility
    let isBlocked: Bool
}

struct PlacePhotoCarouselMockPhoto: Identifiable, Equatable {
    let id: String
    let source: PlacePhotoCarouselMockPhotoSource
    let imageTileIndex: Int
}

enum PlacePhotoCarouselMockPrivacyFilter {
    static func visiblePhotos(from candidates: [PlacePhotoCarouselMockCandidate]) -> [PlacePhotoCarouselMockPhoto] {
        let googlePhoto = candidates.first { candidate in
            if case .google = candidate.source {
                return true
            }
            return false
        }

        let userPhotos = candidates.filter { candidate in
            guard case .user = candidate.source else {
                return false
            }
            return candidate.saveVisibility == .shared
                && candidate.profileVisibility == .publicProfile
                && !candidate.isBlocked
        }

        return ([googlePhoto].compactMap { $0 } + userPhotos)
            .map {
                PlacePhotoCarouselMockPhoto(
                    id: $0.id,
                    source: $0.source,
                    imageTileIndex: $0.imageTileIndex
                )
            }
    }
}

enum PlacePhotoCarouselMockData {
    static let currentUser = PlacePhotoCarouselMockProfile(
        id: "current-user",
        name: "You",
        handle: "ryan_lieblein",
        city: "Los Angeles, CA",
        bio: "Saving the places I actually want to remember.",
        avatarTileIndex: 0
    )

    static let maya = PlacePhotoCarouselMockProfile(
        id: "maya",
        name: "Maya Patel",
        handle: "mayap",
        city: "Los Angeles, CA",
        bio: "Neighborhood dinners, long walks, and places worth bringing friends.",
        avatarTileIndex: 0
    )

    static let andrew = PlacePhotoCarouselMockProfile(
        id: "andrew",
        name: "Andrew Chen",
        handle: "andrewc",
        city: "Los Angeles, CA",
        bio: "Coffee shops, patios, and low-key weeknight favorites.",
        avatarTileIndex: 1
    )

    static let joe = PlacePhotoCarouselMockProfile(
        id: "joe",
        name: "Joe Lipshutz",
        handle: "joelipshutz",
        city: "Los Angeles, CA",
        bio: "Saving the places I actually want to remember.",
        avatarTileIndex: 2
    )

    static let sofia = PlacePhotoCarouselMockProfile(
        id: "sofia",
        name: "Sofia Martinez",
        handle: "sofia_eats",
        city: "Los Angeles, CA",
        bio: "Share plates, sunny rooms, and a very serious patio opinion.",
        avatarTileIndex: 3
    )

    static let candidates: [PlacePhotoCarouselMockCandidate] = [
        PlacePhotoCarouselMockCandidate(
            id: "stealth-photo",
            source: .user(joe),
            imageTileIndex: 2,
            saveVisibility: .stealth,
            profileVisibility: .publicProfile,
            isBlocked: false
        ),
        PlacePhotoCarouselMockCandidate(
            id: "maya-photo",
            source: .user(maya),
            imageTileIndex: 1,
            saveVisibility: .shared,
            profileVisibility: .publicProfile,
            isBlocked: false
        ),
        PlacePhotoCarouselMockCandidate(
            id: "google-photo",
            source: .google,
            imageTileIndex: 0,
            saveVisibility: .shared,
            profileVisibility: .publicProfile,
            isBlocked: false
        ),
        PlacePhotoCarouselMockCandidate(
            id: "private-profile-photo",
            source: .user(andrew),
            imageTileIndex: 3,
            saveVisibility: .shared,
            profileVisibility: .privateProfile,
            isBlocked: false
        ),
        PlacePhotoCarouselMockCandidate(
            id: "sofia-photo",
            source: .user(sofia),
            imageTileIndex: 2,
            saveVisibility: .shared,
            profileVisibility: .publicProfile,
            isBlocked: false
        ),
        PlacePhotoCarouselMockCandidate(
            id: "andrew-photo",
            source: .user(andrew),
            imageTileIndex: 3,
            saveVisibility: .shared,
            profileVisibility: .publicProfile,
            isBlocked: false
        ),
        PlacePhotoCarouselMockCandidate(
            id: "blocked-photo",
            source: .user(joe),
            imageTileIndex: 1,
            saveVisibility: .shared,
            profileVisibility: .publicProfile,
            isBlocked: true
        )
    ]

    static let visiblePhotos = PlacePhotoCarouselMockPrivacyFilter.visiblePhotos(from: candidates)

    static let viewerPhotos: [PlacePhotoCarouselMockPhoto] = visiblePhotos.map { photo in
        guard photo.id == "maya-photo" else {
            return photo
        }
        return PlacePhotoCarouselMockPhoto(
            id: photo.id,
            source: .user(currentUser),
            imageTileIndex: photo.imageTileIndex
        )
    }

    static let hundredVisiblePhotos: [PlacePhotoCarouselMockPhoto] = {
        let userPhotos = Array(visiblePhotos.dropFirst())
        let repeatedUserPhotos = (0..<99).map { index in
            let source = userPhotos[index % userPhotos.count]
            return PlacePhotoCarouselMockPhoto(
                id: "gallery-photo-\(index + 2)",
                source: source.source,
                imageTileIndex: source.imageTileIndex
            )
        }
        return [visiblePhotos[0]] + repeatedUserPhotos
    }()
}

private struct PlacePhotoCarouselViewerSelection: Identifiable {
    let photoID: String
    let photos: [PlacePhotoCarouselMockPhoto]
    var id: String { photoID }
}

private struct PlacePhotoCarouselCardMockup: View {
    let photos: [PlacePhotoCarouselMockPhoto]
    let onOpenPhoto: (PlacePhotoCarouselMockPhoto, [PlacePhotoCarouselMockPhoto]) -> Void
    @State private var selectedPhotoID: String?

    init(
        photos: [PlacePhotoCarouselMockPhoto],
        onOpenPhoto: @escaping (PlacePhotoCarouselMockPhoto, [PlacePhotoCarouselMockPhoto]) -> Void
    ) {
        self.photos = photos
        self.onOpenPhoto = onOpenPhoto
        _selectedPhotoID = State(initialValue: photos.first?.id)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    PlacePhotoCarouselHero(
                        photos: photos,
                        selectedPhotoID: $selectedPhotoID,
                        topInset: max(proxy.safeAreaInsets.top, 54),
                        onOpenPhoto: { onOpenPhoto($0, photos) }
                    )

                    VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                        heading
                        placeTags
                        ratingRow
                        fitCard
                        communityCard
                        detailsCard
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing4)
                    .padding(.bottom, max(88, proxy.safeAreaInsets.bottom + WanderTheme.spacing8))
                    .background(WanderTheme.surfaceBone.color)
                }
            }
            .background(WanderTheme.surfaceBone.color)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text("Saffron House")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("Mediterranean · Silver Lake · $$")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer(minLength: WanderTheme.spacing3)

                Text(CheckInCopy.noun.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, WanderTheme.spacing2)
                    .frame(height: 30)
                    .background(WanderTheme.terracottaTint.color)
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .clipShape(Capsule())
            }

            Text("A sunny neighborhood room for share plates and an easy patio dinner.")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var placeTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WanderTheme.spacing2) {
                ForEach(["date night", "patio", "share plates", "worth a detour"], id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 13, weight: .black))
                        .padding(.horizontal, WanderTheme.spacing3)
                        .frame(height: 34)
                        .background(WanderTheme.surfaceSand.color)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
                }
            }
        }
    }

    private var ratingRow: some View {
        HStack(spacing: WanderTheme.spacing2) {
            PlacePhotoCarouselMetric(
                icon: "star.fill",
                label: "YOUR RATING",
                value: "4.5 / 5",
                tint: WanderTheme.stateWarning.color
            )
            PlacePhotoCarouselMetric(
                icon: "person.2.fill",
                label: "REC.ME",
                value: "4.7 / 5",
                tint: WanderTheme.pinSocial.color
            )
        }
    }

    private var fitCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("WHY IT FITS")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
            Text("Three people you trust saved this for relaxed dinners, and Maya called out the patio.")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WanderTheme.terracottaTint.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var communityCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("PEOPLE YOU FOLLOW")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            HStack(spacing: WanderTheme.spacing2) {
                HStack(spacing: -8) {
                    ForEach([
                        PlacePhotoCarouselMockData.maya,
                        PlacePhotoCarouselMockData.sofia,
                        PlacePhotoCarouselMockData.andrew
                    ]) { profile in
                        PlacePhotoCarouselAvatar(profile: profile, size: 38)
                            .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 2))
                    }
                }

                Text("Maya, Sofia + Andrew saved this")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)

                Spacer()
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("DETAILS")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
            Label("2814 Sunset Blvd, Los Angeles", systemImage: "mappin.and.ellipse")
            Label("Open until 10:00 PM", systemImage: "clock.fill")
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(WanderTheme.textInk.color)
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct PlacePhotoCarouselHero: View {
    let photos: [PlacePhotoCarouselMockPhoto]
    @Binding var selectedPhotoID: String?
    let topInset: CGFloat
    let onOpenPhoto: (PlacePhotoCarouselMockPhoto) -> Void

    var body: some View {
        ZStack {
            PlacePhotoCarouselPager(
                photos: photos,
                selectedPhotoID: $selectedPhotoID,
                imageContentMode: .fill,
                onTapPhoto: onOpenPhoto
            )

            LinearGradient(
                colors: [.black.opacity(0.42), .clear, .black.opacity(0.46)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack {
                HStack {
                    PlacePhotoCarouselRoundButton(systemImage: "chevron.left", accessibilityLabel: "Close place")
                    Spacer()
                    HStack(spacing: WanderTheme.spacing2) {
                        PlacePhotoCarouselRoundButton(systemImage: "plus", isPrimary: true, accessibilityLabel: "Check in again")
                        PlacePhotoCarouselRoundButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share place")
                    }
                }

                Spacer()

                HStack(alignment: .bottom) {
                    if let selectedPhoto {
                        PlacePhotoCarouselSourceBadge(photo: selectedPhoto)
                    }
                    Spacer()
                    PlacePhotoCarouselCountBadge(
                        current: selectedIndex + 1,
                        total: photos.count
                    )
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, topInset + WanderTheme.spacing2)
            .padding(.bottom, WanderTheme.spacing3)
        }
        .frame(height: 250 + topInset)
        .background(WanderTheme.surfaceSand.color)
        .clipped()
    }

    private var selectedIndex: Int {
        photos.firstIndex { $0.id == selectedPhotoID } ?? 0
    }

    private var selectedPhoto: PlacePhotoCarouselMockPhoto? {
        guard photos.indices.contains(selectedIndex) else { return nil }
        return photos[selectedIndex]
    }
}

private struct PlacePhotoCarouselPager: View {
    let photos: [PlacePhotoCarouselMockPhoto]
    @Binding var selectedPhotoID: String?
    let imageContentMode: ContentMode
    var horizontalImageInset: CGFloat = 0
    let onTapPhoto: (PlacePhotoCarouselMockPhoto) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(photos) { photo in
                    PlacePhotoCarouselContactSheetImage(
                        assetName: "PlaceCarouselPhotos",
                        tileIndex: photo.imageTileIndex,
                        contentMode: imageContentMode
                    )
                    .padding(.horizontal, horizontalImageInset)
                    .containerRelativeFrame(.horizontal)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTapPhoto(photo)
                    }
                    .accessibilityLabel(accessibilityLabel(for: photo))
                    .accessibilityHint("Opens the full-screen photo viewer")
                    .id(photo.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selectedPhotoID, anchor: .center)
    }

    private func accessibilityLabel(for photo: PlacePhotoCarouselMockPhoto) -> String {
        switch photo.source {
        case .google:
            "Place photo"
        case let .user(profile):
            "Place photo by \(profile.name)"
        }
    }
}

private struct PlacePhotoCarouselFullscreenHost: View {
    let photos: [PlacePhotoCarouselMockPhoto]
    let initialPhotoID: String
    let onClose: () -> Void
    @State private var profilePath: [PlacePhotoCarouselMockProfile] = []

    var body: some View {
        NavigationStack(path: $profilePath) {
            PlacePhotoCarouselFullscreenMockup(
                photos: photos,
                initialPhotoID: initialPhotoID,
                onClose: onClose,
                onOpenProfile: { profilePath.append($0) }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PlacePhotoCarouselMockProfile.self) { profile in
                PlacePhotoCarouselProfileMockup(profile: profile)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}

private struct PlacePhotoCarouselFullscreenMockup: View {
    let photos: [PlacePhotoCarouselMockPhoto]
    let onClose: () -> Void
    let onOpenProfile: (PlacePhotoCarouselMockProfile) -> Void
    @State private var selectedPhotoID: String?

    init(
        photos: [PlacePhotoCarouselMockPhoto],
        initialPhotoID: String,
        onClose: @escaping () -> Void,
        onOpenProfile: @escaping (PlacePhotoCarouselMockProfile) -> Void
    ) {
        self.photos = photos
        self.onClose = onClose
        self.onOpenProfile = onOpenProfile
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.055, green: 0.044, blue: 0.037)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    viewerHeader(topInset: proxy.safeAreaInsets.top)

                    Spacer(minLength: WanderTheme.spacing3)

                    PlacePhotoCarouselPager(
                        photos: photos,
                        selectedPhotoID: $selectedPhotoID,
                        imageContentMode: .fit,
                        horizontalImageInset: WanderTheme.spacing2,
                        onTapPhoto: { _ in }
                    )
                    .frame(maxHeight: min(580, proxy.size.height * 0.66))

                    pageIndicator
                        .padding(.top, WanderTheme.spacing4)
                        .padding(.bottom, WanderTheme.spacing4)

                    attribution
                        .padding(.horizontal, WanderTheme.spacing4)
                        .padding(.bottom, max(WanderTheme.spacing3, proxy.safeAreaInsets.bottom))
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func viewerHeader(topInset: CGFloat) -> some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(Color.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close photo viewer")

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, topInset + WanderTheme.spacing2)
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if photos.count <= 5 {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    Circle()
                        .fill(photo.id == selectedPhotoID ? Color.white : Color.white.opacity(0.38))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityLabel("Photo \(selectedIndex + 1) of \(photos.count)")
        } else {
            Text("\(selectedIndex + 1) of \(photos.count)")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.white.opacity(0.86))
        }
    }

    @ViewBuilder
    private var attribution: some View {
        if let selectedPhoto {
            switch selectedPhoto.source {
            case .google:
                EmptyView()
            case let .user(profile):
                HStack(spacing: WanderTheme.spacing3) {
                    PlacePhotoCarouselAvatar(profile: profile, size: 48)

                    VStack(alignment: .leading, spacing: 0) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                mockAttributionName(profile.name)
                                mockAttributionTimestamp
                            }
                            .fixedSize(horizontal: true, vertical: false)

                            VStack(alignment: .leading, spacing: 2) {
                                mockAttributionName(profile.name)
                                mockAttributionTimestamp
                            }
                        }

                        Button {
                            onOpenProfile(profile)
                        } label: {
                            Text("@\(profile.handle)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WanderTheme.stateSuccess.color)
                                .underline()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .allowsTightening(true)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open @\(profile.handle)'s profile")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    Spacer(minLength: WanderTheme.spacing2)

                    Text("check-in")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.40))
                        .padding(.horizontal, WanderTheme.spacing3)
                        .frame(height: 38)
                        .background(Color(red: 0.88, green: 0.94, blue: 0.91))
                        .clipShape(Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: 96)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
    }

    private func mockAttributionName(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 16, weight: .black))
            .foregroundStyle(WanderTheme.textInk.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var mockAttributionTimestamp: some View {
        Text("Jun 25, 2026 at 12:23")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WanderTheme.textMuted.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var selectedIndex: Int {
        photos.firstIndex { $0.id == selectedPhotoID } ?? 0
    }

    private var selectedPhoto: PlacePhotoCarouselMockPhoto? {
        guard photos.indices.contains(selectedIndex) else { return nil }
        return photos[selectedIndex]
    }
}

private struct PlacePhotoCarouselProfileMockup: View {
    let profile: PlacePhotoCarouselMockProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: WanderTheme.spacing4) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .black))
                            .frame(width: 44, height: 44)
                            .background(WanderTheme.surfaceSand.color)
                            .foregroundStyle(WanderTheme.textInk.color)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close profile")

                    Spacer()

                    Text("PROFILE")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }

                PlacePhotoCarouselAvatar(profile: profile, size: 112)
                    .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: 4))
                    .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 16, y: 8)

                VStack(spacing: WanderTheme.spacing1) {
                    Text(profile.name)
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("@\(profile.handle)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Label(profile.city, systemImage: "mappin")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Text(profile.bio)
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .padding(.horizontal, WanderTheme.spacing4)

                HStack(spacing: WanderTheme.spacing2) {
                    PlacePhotoCarouselProfileStat(value: "84", label: "check-ins")
                    PlacePhotoCarouselProfileStat(value: "31", label: "wanna")
                    PlacePhotoCarouselProfileStat(value: "22", label: "friends")
                }

                Button(action: {}) {
                    Text("following")
                        .font(.system(size: 15, weight: .black))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(WanderTheme.textInk.color)
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                HStack(spacing: WanderTheme.spacing2) {
                    PlacePhotoCarouselContactSheetImage(
                        assetName: "PlaceCarouselPhotos",
                        tileIndex: 1,
                        contentMode: .fill
                    )
                    PlacePhotoCarouselContactSheetImage(
                        assetName: "PlaceCarouselPhotos",
                        tileIndex: 2,
                        contentMode: .fill
                    )
                    PlacePhotoCarouselContactSheetImage(
                        assetName: "PlaceCarouselPhotos",
                        tileIndex: 3,
                        contentMode: .fill
                    )
                }
                .frame(height: 112)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing2)
            .padding(.bottom, WanderTheme.spacing8)
        }
        .background(WanderTheme.surfaceBone.color)
        .preferredColorScheme(.light)
    }
}

private struct PlacePhotoCarouselMetric: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: WanderTheme.spacing2) {
            Label(label, systemImage: icon)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
            Text(value)
                .font(.system(size: 21, weight: .black))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 98)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }
}

private struct PlacePhotoCarouselProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: WanderTheme.spacing1) {
            Text(value)
                .font(.system(size: 23, weight: .black))
            Text(label)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .foregroundStyle(WanderTheme.textInk.color)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct PlacePhotoCarouselRoundButton: View {
    let systemImage: String
    var isPrimary = false
    let accessibilityLabel: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .black))
                .frame(width: 44, height: 44)
                .background(isPrimary ? WanderTheme.terracotta.color : WanderTheme.surfaceBone.color.opacity(0.96))
                .foregroundStyle(isPrimary ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PlacePhotoCarouselCountBadge: View {
    let current: Int
    let total: Int

    var body: some View {
        Text("\(current) of \(total)")
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(Color.black.opacity(0.66))
            .clipShape(Capsule())
            .accessibilityLabel("Photo \(current) of \(total)")
    }
}

private struct PlacePhotoCarouselSourceBadge: View {
    let photo: PlacePhotoCarouselMockPhoto

    var body: some View {
        switch photo.source {
        case .google:
            EmptyView()
        case let .user(profile):
            HStack(spacing: 7) {
                PlacePhotoCarouselAvatar(profile: profile, size: 24)
                Text("\(profile.name.components(separatedBy: " ").first ?? profile.name)'s photo")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(minHeight: 36)
            .background(Color.black.opacity(0.66))
            .clipShape(Capsule())
        }
    }
}

private struct PlacePhotoCarouselAvatar: View {
    let profile: PlacePhotoCarouselMockProfile
    let size: CGFloat

    var body: some View {
        PlacePhotoCarouselContactSheetImage(
            assetName: "PlaceCarouselAvatars",
            tileIndex: profile.avatarTileIndex,
            contentMode: .fill
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("\(profile.name)'s profile photo")
    }
}

private struct PlacePhotoCarouselContactSheetImage: View {
    let assetName: String
    let tileIndex: Int
    let contentMode: ContentMode

    var body: some View {
        GeometryReader { proxy in
            if let croppedImage {
                Image(uiImage: croppedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [WanderTheme.terracottaTint.color, WanderTheme.skyTint.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipped()
    }

    private var croppedImage: UIImage? {
        guard
            let sourceImage = UIImage(named: assetName),
            let sourceCGImage = sourceImage.cgImage
        else {
            return nil
        }

        let normalizedIndex = max(0, min(tileIndex, 3))
        let tileWidth = sourceCGImage.width / 2
        let tileHeight = sourceCGImage.height / 2
        let column = normalizedIndex % 2
        let row = normalizedIndex / 2
        let cropRect = CGRect(
            x: column * tileWidth,
            y: row * tileHeight,
            width: tileWidth,
            height: tileHeight
        )

        guard let croppedCGImage = sourceCGImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(
            cgImage: croppedCGImage,
            scale: sourceImage.scale,
            orientation: sourceImage.imageOrientation
        )
    }
}
#endif
