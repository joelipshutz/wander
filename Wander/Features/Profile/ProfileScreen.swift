import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct ProfileScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @StateObject private var importStore = PlaceImportStore()
    @State private var showsSettings = false
    @State private var showsProfilePhotoMenu = false
    @State private var showsProfilePhotoLibrary = false
    @State private var showsProfileCamera = false
    @State private var selectedProfilePhotoItem: PhotosPickerItem?
    @State private var isProfilePhotoSaving = false
    @State private var profilePhotoError: String?
    @State private var socialGraphTab: ProfileSocialGraphTab?
    @State private var listMode: GraphListMode?
    @State private var selectedPeopleMode: GraphListMode = .following
    @State private var savedListMode: SavedPlacesListMode?
    @State private var placeCollectionRoute: ProfilePlaceCollectionRoute?
    @State private var showsVisitInvitations = false
    @State private var showsEditProfile = false
    @State private var selectedImportSource: PlaceImportSource?
    @State private var showsImportInbox = false
    @State private var opensImportInboxAfterSource = false
    @State private var selectedMonth = Date.now

    @Binding private var visitInvitationInboxRequestID: UUID?
    let onFindFriends: () -> Void

    private let profilePhotoMenuWidth: CGFloat = 232
    private let profilePhotoMenuAnchorOffsetX: CGFloat = 35
    private let profilePhotoMenuTopGap: CGFloat = 2

    init(
        visitInvitationInboxRequestID: Binding<UUID?> = .constant(nil),
        onFindFriends: @escaping () -> Void = {}
    ) {
        _visitInvitationInboxRequestID = visitInvitationInboxRequestID
        self.onFindFriends = onFindFriends
    }

    var body: some View {
        NavigationStack {
            ProfileOwnerHome(
                profile: store.currentUser,
                mode: .owner,
                stats: profileStats,
                followerCount: store.followers(of: store.currentUser.id).count,
                followingCount: store.following(of: store.currentUser.id).count,
                sharedVisitInvitationCount: store.sharedVisitInvitations.count,
                importSummary: importStore.summary,
                insights: profileInsights,
                selectedMonth: $selectedMonth,
                isAvatarSaving: isProfilePhotoSaving,
                avatarAction: toggleProfilePhotoMenu,
                editAction: { showsEditProfile = true },
                settingsAction: { showsSettings = true },
                relationshipAction: {},
                backAction: nil,
                memberActions: nil,
                graphAction: { socialGraphTab = $0 },
                sharedVisitInvitationsAction: { showsVisitInvitations = true },
                importSourceAction: { selectedImportSource = $0 },
                importInboxAction: { showsImportInbox = true },
                savedPlacesAction: { status in
                    savedListMode = status == .been ? .been : .wanna
                },
                inCommonAction: {},
                calendarDateAction: { date, placeIDs in
                    placeCollectionRoute = .calendar(date: date, placeIDs: placeIDs)
                },
                mapSummaryAction: { kind, item in
                    placeCollectionRoute = .mapSummary(kind: kind, item: item)
                }
            )
                .sheet(isPresented: $showsSettings) {
                    SettingsScreen()
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                        .environmentObject(pushNotifications)
                }
                .sheet(isPresented: $showsProfileCamera) {
                    ProfileCameraPicker { image in
                        Task {
                            await saveProfilePhoto(image: image)
                        }
                    }
                }
                .sheet(item: $socialGraphTab) { tab in
                    ProfileSocialGraphScreen(
                        profileID: store.currentUser.id,
                        initialTab: tab,
                        onFindFriends: onFindFriends
                    )
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
                .sheet(isPresented: $showsEditProfile) {
                    ProfileEditScreen()
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
                .sheet(item: $selectedImportSource, onDismiss: openImportInboxAfterSourceIfNeeded) { source in
                    PlaceImportSourceScreen(
                        source: source,
                        importStore: importStore
                    ) { _ in
                        opensImportInboxAfterSource = true
                    }
                }
                .photosPicker(
                    isPresented: $showsProfilePhotoLibrary,
                    selection: $selectedProfilePhotoItem,
                    matching: .images
                )
                .onChange(of: selectedProfilePhotoItem) { _, item in
                    guard let item else { return }
                    Task {
                        await importProfilePhoto(from: item)
                    }
                }
                .navigationDestination(item: $savedListMode) { mode in
                    SavedPlacesListScreen(mode: mode, profileID: store.currentUser.id)
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
                .navigationDestination(item: $placeCollectionRoute) { route in
                    SavedPlacesListScreen(collection: route, profileID: store.currentUser.id)
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
                .navigationDestination(isPresented: $showsVisitInvitations) {
                    SharedVisitInvitationInboxScreen { invitation in
                        showsVisitInvitations = false
                        pushNotifications.openSharedVisit(
                            participantID: invitation.participantID,
                            generation: invitation.invitationGeneration
                        )
                    }
                    .environmentObject(store)
                    .environmentObject(backend)
                }
                .navigationDestination(isPresented: $showsImportInbox) {
                    PlaceImportInboxScreen(importStore: importStore)
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
                .task(id: auth.isSignedIn) {
                    guard auth.isSignedIn else { return }
                    await store.refreshRemoteCurrentProfile(backend: backend)
                    await store.refreshRemoteSocialGraph(backend: backend)
                    await store.refreshRemoteCurrentUserProfileData(backend: backend)
                    await store.refreshSharedVisitInbox(backend: backend)
                    importStore.resumePendingImports()
                    importStore.reconcileDuplicates(with: importExistingPlaces)
                    handleNotificationRoute(pushNotifications.navigationRequest)
                }
                .onChange(of: pushNotifications.navigationRequest) { _, request in
                    handleNotificationRoute(request)
                }
                .onAppear {
                    openRequestedVisitInvitationInbox()
                    importStore.resumePendingImports()
                    importStore.reconcileDuplicates(with: importExistingPlaces)
                }
                .onChange(of: visitInvitationInboxRequestID) { _, _ in
                    openRequestedVisitInvitationInbox()
                }
                .onChange(of: importStore.items) { _, _ in
                    importStore.reconcileDuplicates(with: importExistingPlaces)
                }
                .confirmationDialog("Profile photo", isPresented: $showsProfilePhotoMenu, titleVisibility: .visible) {
                    if isCameraAvailable {
                        Button("Take Photo") { presentProfileCamera() }
                    }
                    Button("Choose from Library") { presentProfilePhotoLibrary() }
                    if hasProfilePhoto {
                        Button("Delete Photo", role: .destructive) { confirmDeleteProfilePhoto() }
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }

    private func openRequestedVisitInvitationInbox() {
        guard visitInvitationInboxRequestID != nil else { return }
        showsVisitInvitations = true
        visitInvitationInboxRequestID = nil
    }

    private func openImportInboxAfterSourceIfNeeded() {
        guard opensImportInboxAfterSource else { return }
        opensImportInboxAfterSource = false
        showsImportInbox = true
    }

    private var importExistingPlaces: [PlaceImportExistingPlace] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceImportExistingPlace(
                userPlaceID: visiblePlace.userPlace.id,
                name: visiblePlace.place.canonicalName,
                latitude: visiblePlace.place.latitude,
                longitude: visiblePlace.place.longitude,
                sourceProvider: visiblePlace.place.sourceProvider,
                sourceProviderPlaceID: visiblePlace.place.sourceProviderPlaceID
            )
        }
    }

    private var profileInsights: ProfileInsights {
        ProfileInsightsPresenter.present(
            ownerID: store.currentUser.id,
            userPlaces: profileUserPlaces,
            visits: store.placeVisits,
            places: profilePlaces,
            month: selectedMonth
        )
    }

    private var profileStats: ProfileStats {
        var seen: Set<String> = []
        let active = profileUserPlaces.filter {
            $0.userID == store.currentUser.id && $0.deletedAt == nil && seen.insert($0.id).inserted
        }
        return ProfileStats(
            been: active.filter { $0.status == .been }.count,
            wanna: active.filter { $0.status == .wannaGo }.count,
            friends: store.friends(of: store.currentUser.id).count
        )
    }

    private var profileUserPlaces: [LocalUserPlace] {
        store.userPlaces + store.remoteVisiblePlaceCache
            .filter { $0.owner.id == store.currentUser.id }
            .map(\.userPlace)
    }

    private var profilePlaces: [LocalPlace] {
        store.places + store.remoteVisiblePlaceCache
            .filter { $0.owner.id == store.currentUser.id }
            .map(\.place)
    }

    private var pageTitle: some View {
        Text("profile")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .lineLimit(1)
    }

    private var ownerHeader: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top) {
                Button {
                    toggleProfilePhotoMenu()
                } label: {
                    EditableProfileAvatar(
                        initials: store.currentUser.initials,
                        avatarURL: store.currentUser.avatarURL,
                        size: 56,
                        isSaving: isProfilePhotoSaving
                    )
                    .anchorPreference(
                        key: ProfilePhotoAvatarBoundsPreferenceKey.self,
                        value: .bounds
                    ) { bounds in
                        bounds
                    }
                }
                .buttonStyle(.plain)
                .disabled(isProfilePhotoSaving)
                .accessibilityLabel(hasProfilePhoto ? "Change profile photo" : "Add profile photo")
                .accessibilityHint("Opens photo options")

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(store.currentUser.displayName)
                        .font(.system(size: 24, weight: .black))
                    Text("@\(store.currentUser.handle) · \(store.currentUser.homeArea ?? "Los Angeles")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Settings")
            }

            if let profilePhotoError {
                Text(profilePhotoError)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.stateError.color)
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    @ViewBuilder
    private func profilePhotoMenuOverlay(anchor: Anchor<CGRect>?, proxy: GeometryProxy) -> some View {
        if showsProfilePhotoMenu, let anchor {
            let avatarFrame = proxy[anchor]

            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    hideProfilePhotoMenu()
                }
                .accessibilityHidden(true)
                .zIndex(1)

            ProfilePhotoActionMenu(
                isCameraAvailable: isCameraAvailable,
                hasProfilePhoto: hasProfilePhoto,
                takePhoto: {
                    hideProfilePhotoMenu()
                    presentProfileCamera()
                },
                chooseFromLibrary: {
                    hideProfilePhotoMenu()
                    presentProfilePhotoLibrary()
                },
                deletePhoto: {
                    hideProfilePhotoMenu()
                    confirmDeleteProfilePhoto()
                }
            )
            .offset(
                x: profilePhotoMenuLeading(for: avatarFrame, containerWidth: proxy.size.width),
                y: profilePhotoMenuTop(for: avatarFrame)
            )
            .transition(.scale(scale: 0.97, anchor: .topLeading).combined(with: .opacity))
            .zIndex(2)
        }
    }

    private func profilePhotoMenuLeading(for avatarFrame: CGRect, containerWidth: CGFloat) -> CGFloat {
        let preferredLeading = avatarFrame.midX - profilePhotoMenuAnchorOffsetX
        let screenPadding = WanderTheme.spacing4
        let maxLeading = max(screenPadding, containerWidth - profilePhotoMenuWidth - screenPadding)
        return min(max(preferredLeading, screenPadding), maxLeading)
    }

    private func profilePhotoMenuTop(for avatarFrame: CGRect) -> CGFloat {
        avatarFrame.maxY + profilePhotoMenuTopGap
    }

    private var statsGrid: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button {
                savedListMode = .been
            } label: {
                StatTile(
                    value: "\(store.stats.been)",
                    label: "BEEN",
                    color: WanderTheme.stateSuccess.color,
                    fill: WanderTheme.categorySage.color.opacity(0.22)
                )
            }
            .buttonStyle(ProfileStatButtonStyle())
            .accessibilityLabel("Open been places")

            Button {
                savedListMode = .wanna
            } label: {
                StatTile(value: "\(store.stats.wanna)", label: "WANNA", color: WanderTheme.stateWarning.color, fill: WanderTheme.sunTint.color)
            }
            .buttonStyle(ProfileStatButtonStyle())
            .accessibilityLabel("Open wanna places")
        }
    }

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                Text("this month")
                    .font(.system(size: 17, weight: .black))
                Spacer()
                Text("JUN '26")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            HStack(alignment: .center, spacing: WanderTheme.spacing4) {
                Text("\(store.currentUserVisiblePlaces.count)")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                Text("saved places this month.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Spacer()
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
    }

    private var draftsSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("drafts")
                .font(.system(size: 17, weight: .black))

            if store.unresolvedDrafts.isEmpty {
                SmallEmptyRow(title: "No unresolved drafts", subtitle: "link and photo shells land here")
            } else {
                ForEach(store.unresolvedDrafts) { draft in
                    HStack {
                        Image(systemName: draft.sourceType == .link ? "link" : "photo")
                            .foregroundStyle(WanderTheme.terracotta.color)
                        VStack(alignment: .leading) {
                            Text(draft.title)
                                .font(.system(size: 15, weight: .bold))
                            Text(draft.message)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(WanderTheme.spacing3)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .id("profile.draft.\(draft.extractionJobID ?? draft.id)")
                }
            }
        }
        .id("profile.drafts")
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                Text("recent")
                    .font(.system(size: 17, weight: .black))
                Spacer()
            }

            ForEach(store.currentUserVisiblePlaces) { visiblePlace in
                ProfilePlaceRow(visiblePlace: visiblePlace)
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("people")
                .font(.system(size: 17, weight: .black))

            WanderSegmentedSwitch(
                options: GraphListMode.allCases.map { mode in
                    WanderSegmentOption(id: mode.rawValue, title: mode.title)
                },
                selection: Binding(
                    get: { selectedPeopleMode.rawValue },
                    set: { selectedPeopleMode = GraphListMode(rawValue: $0) ?? .following }
                )
            )

            let people = people(for: selectedPeopleMode)
            if people.isEmpty {
                SmallEmptyRow(title: "No \(selectedPeopleMode.title) yet", subtitle: selectedPeopleMode.emptySubtitle)
            } else {
                ForEach(people, id: \.id) { profile in
                    ProfilePersonRow(profile: profile, relationship: store.relationship(to: profile.id)) {
                        listMode = selectedPeopleMode
                    }
                }
            }
        }
        .id("profile.people")
    }

    private func handleNotificationRoute(_ request: NotificationNavigationRequest?) {
        guard let request else { return }

        switch request.destination {
        case .people(let mode):
            socialGraphTab = switch mode {
            case .following: ProfileSocialGraphTab.following
            case .followers: ProfileSocialGraphTab.followers
            case .friends: ProfileSocialGraphTab.friends
            }
        case .drafts:
            break
        default:
            return
        }

        pushNotifications.consumeNavigationRequest(id: request.id)
    }

    private func people(for mode: GraphListMode) -> [LocalProfile] {
        switch mode {
        case .following:
            return store.following(of: store.currentUser.id)
        case .followers:
            return store.followers(of: store.currentUser.id)
        case .friends:
            return store.following(of: store.currentUser.id).filter { store.relationship(to: $0.id) == .mutual }
        }
    }

    private var hasProfilePhoto: Bool {
        guard let avatarURL = store.currentUser.avatarURL else { return false }
        return !avatarURL.isEmpty
    }

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private func toggleProfilePhotoMenu() {
        guard !isProfilePhotoSaving else { return }
        withAnimation(.easeOut(duration: 0.14)) {
            showsProfilePhotoMenu.toggle()
        }
    }

    private func hideProfilePhotoMenu() {
        guard showsProfilePhotoMenu else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            showsProfilePhotoMenu = false
        }
    }

    private func presentProfileCamera() {
        showsProfileCamera = true
    }

    private func presentProfilePhotoLibrary() {
        showsProfilePhotoLibrary = true
    }

    private func confirmDeleteProfilePhoto() {
        Task {
            await deleteProfilePhoto()
        }
    }

    @MainActor
    private func importProfilePhoto(from item: PhotosPickerItem) async {
        defer {
            selectedProfilePhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw WanderImageProcessingError.invalidImageData
            }
            try await saveProfilePhoto(data: data)
        } catch {
            profilePhotoError = "Could not use that photo. Try another one."
        }
    }

    @MainActor
    private func saveProfilePhoto(image: UIImage) async {
        do {
            let jpegData = try WanderImageProcessor.squareJPEGData(from: image)
            await saveProfilePhoto(jpegData: jpegData)
        } catch {
            profilePhotoError = "Could not use that photo. Try another one."
        }
    }

    @MainActor
    private func saveProfilePhoto(data: Data) async throws {
        let jpegData = try await Task.detached(priority: .userInitiated) {
            try WanderImageProcessor.squareJPEGData(from: data)
        }.value
        await saveProfilePhoto(jpegData: jpegData)
    }

    @MainActor
    private func saveProfilePhoto(jpegData: Data) async {
        isProfilePhotoSaving = true
        defer { isProfilePhotoSaving = false }

        do {
            let url = try ProfileAvatarStorage.live.writeAvatarData(jpegData)
            store.updateCurrentUserAvatarURL(url.absoluteString)
            profilePhotoError = nil
        } catch {
            profilePhotoError = "Could not save this photo. Try again."
            return
        }

        guard auth.isSignedIn, backend.canSyncProfileAvatars else { return }

        do {
            let result = try await backend.uploadProfileAvatar(
                jpegData: jpegData,
                userID: store.currentUser.id
            )
            store.updateCurrentUserAvatarURL(result.avatarURL)
            profilePhotoError = nil
        } catch {
            profilePhotoError = "Saved on this phone. Could not sync profile photo yet."
        }
    }

    @MainActor
    private func deleteProfilePhoto() async {
        isProfilePhotoSaving = true
        defer { isProfilePhotoSaving = false }

        if auth.isSignedIn, backend.canSyncProfileAvatars {
            do {
                try await backend.deleteProfileAvatar(userID: store.currentUser.id)
            } catch {
                profilePhotoError = "Could not delete this photo. Try again."
                return
            }
        }

        do {
            try ProfileAvatarStorage.live.deleteAvatar()
            store.updateCurrentUserAvatarURL(nil)
            profilePhotoError = nil
        } catch {
            profilePhotoError = "Could not delete this photo. Try again."
        }
    }
}

private struct ProfilePhotoAvatarBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct ProfilePhotoActionMenu: View {
    let isCameraAvailable: Bool
    let hasProfilePhoto: Bool
    let takePhoto: () -> Void
    let chooseFromLibrary: () -> Void
    let deletePhoto: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfilePhotoMenuCaret()
                .fill(Color(.systemBackground).opacity(0.94))
                .background(.regularMaterial, in: ProfilePhotoMenuCaret())
                .frame(width: 18, height: 9)
                .padding(.leading, 25)

            VStack(spacing: 0) {
                if isCameraAvailable {
                    ProfilePhotoActionMenuButton(
                        title: "Take Photo",
                        systemImage: "camera.fill",
                        action: takePhoto
                    )
                    menuDivider
                }

                ProfilePhotoActionMenuButton(
                    title: "Choose from Library",
                    systemImage: "photo.on.rectangle",
                    action: chooseFromLibrary
                )

                if hasProfilePhoto {
                    menuDivider
                    ProfilePhotoActionMenuButton(
                        title: "Delete Photo",
                        systemImage: "trash",
                        role: .destructive,
                        isDestructive: true,
                        action: deletePhoto
                    )
                }
            }
            .frame(width: 232)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.94))
            )
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
        }
        .accessibilityElement(children: .contain)
    }

    private var menuDivider: some View {
        Divider()
            .padding(.leading, 48)
    }
}

private struct ProfilePhotoActionMenuButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(textColor)

                Spacer(minLength: 0)
            }
            .frame(height: 49)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        isDestructive ? Color(.systemRed) : Color(.systemBlue)
    }

    private var textColor: Color {
        isDestructive ? Color(.systemRed) : Color.primary
    }
}

private struct ProfilePhotoMenuCaret: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct EditableProfileAvatar: View {
    let initials: String
    let avatarURL: String?
    let size: CGFloat
    let isSaving: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WanderAvatar(
                initials: initials,
                avatarURL: avatarURL,
                size: size,
                color: WanderTheme.terracotta.color
            )

            if isSaving {
                ProgressView()
                    .controlSize(.mini)
                    .tint(WanderTheme.textOnAction.color)
                    .frame(width: 22, height: 22)
                    .background(WanderTheme.textInk.color)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 2))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: hasAvatar ? "pencil" : "camera.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(width: 22, height: 22)
                    .background(WanderTheme.textInk.color)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 2))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .contentShape(Rectangle())
    }

    private var hasAvatar: Bool {
        guard let avatarURL else { return false }
        return !avatarURL.isEmpty
    }
}

private struct ProfileCameraPicker: UIViewControllerRepresentable {
    let onImage: @MainActor (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onImage: onImage,
            dismiss: {
                dismiss()
            }
        )
    }

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImage: @MainActor (UIImage) -> Void
        private let dismiss: () -> Void

        init(onImage: @escaping @MainActor (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            if let image {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

struct ProfileDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let profileID: String
    let onBlock: (String) -> Void
    @State private var selectedMonth = Date.now
    @State private var socialGraphTab: ProfileSocialGraphTab?
    @State private var savedListMode: SavedPlacesListMode?
    @State private var placeCollectionRoute: ProfilePlaceCollectionRoute?
    @State private var showBlockConfirm = false
    @State private var showUnfollowConfirm = false
    @State private var isLoading = true

    init(profileID: String, onBlock: @escaping (String) -> Void = { _ in }) {
        self.profileID = profileID
        self.onBlock = onBlock
    }

    private var profile: LocalProfile? {
        store.profile(for: profileID)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Group {
                    if let profile {
                        ProfileOwnerHome(
                            profile: profile,
                            mode: .member(
                                relationship: store.relationship(to: profileID),
                                inCommonCount: inCommonPlaces.count
                            ),
                            stats: profileStats,
                            followerCount: store.followers(of: profileID).count,
                            followingCount: store.following(of: profileID).count,
                            sharedVisitInvitationCount: 0,
                            importSummary: nil,
                            insights: profileInsights,
                            selectedMonth: $selectedMonth,
                            isAvatarSaving: false,
                            avatarAction: {},
                            editAction: {},
                            settingsAction: {},
                            relationshipAction: handleRelationshipAction,
                            backAction: { dismiss() },
                            memberActions: ProfileMemberActions(
                                canUnfollow: store.relationship(to: profileID) == .follower || store.relationship(to: profileID) == .mutual,
                                isMuted: store.isMuted(userID: profileID),
                                unfollowAction: { showUnfollowConfirm = true },
                                toggleMuteAction: toggleMute,
                                blockAction: { showBlockConfirm = true }
                            ),
                            graphAction: { socialGraphTab = $0 },
                            sharedVisitInvitationsAction: {},
                            importSourceAction: { _ in },
                            importInboxAction: {},
                            savedPlacesAction: { status in
                                savedListMode = status == .been ? .been : .wanna
                            },
                            inCommonAction: { savedListMode = .inCommon },
                            calendarDateAction: { date, placeIDs in
                                placeCollectionRoute = .calendar(date: date, placeIDs: placeIDs)
                            },
                            mapSummaryAction: { kind, item in
                                placeCollectionRoute = .mapSummary(kind: kind, item: item)
                            }
                        )
                    } else if isLoading {
                        ProgressView("Loading profile")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .wanderScreen()
                    } else {
                        AccessChangedPanel(
                            title: "This profile isn't available",
                            subtitle: "It may have been removed, blocked, or become unavailable."
                        )
                        .padding(WanderTheme.spacing4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .wanderScreen()
                    }
                }

                if profile == nil {
                    ProfileHeaderActionButton(
                        systemImage: "chevron.left",
                        accessibilityLabel: "Back",
                        action: { dismiss() }
                    )
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing3)
                }
            }
            .navigationDestination(item: $savedListMode) { mode in
                SavedPlacesListScreen(mode: mode, profileID: profileID)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .navigationDestination(item: $placeCollectionRoute) { route in
                SavedPlacesListScreen(collection: route, profileID: profileID)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .sheet(item: $socialGraphTab) { tab in
                ProfileSocialGraphScreen(profileID: profileID, initialTab: tab, onFindFriends: {})
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .alert("Block this person?", isPresented: $showBlockConfirm) {
                Button("Block", role: .destructive) { confirmBlock() }
                Button("Cancel", role: .cancel) { showBlockConfirm = false }
            } message: {
                Text("You won't see each other's profiles, places, or search results.")
            }
            .alert(unfollowConfirmationTitle, isPresented: $showUnfollowConfirm) {
                Button("Yes, unfollow", role: .destructive) { confirmUnfollow() }
                Button("No, cancel", role: .cancel) { showUnfollowConfirm = false }
            } message: {
                Text("Their places will stop appearing in your social map.")
            }
            .task(id: profileID) {
                await refreshRemoteProfile()
                await store.refreshRemoteMutes(backend: backend)
                isLoading = false
            }
        }
    }

    private var profileVisiblePlaces: [VisiblePlace] {
        store.visiblePlaces(for: profileID)
    }

    private var inCommonPlaces: [VisiblePlace] {
        store.placesInCommon(with: profileID)
    }

    private var profileStats: ProfileStats {
        let places = VisiblePlaceGrouping.representativePlaces(
            from: profileVisiblePlaces,
            currentUserID: store.currentUser.id
        )
        return ProfileStats(
            been: places.filter { $0.userPlace.status == .been }.count,
            wanna: places.filter { $0.userPlace.status == .wannaGo }.count,
            friends: store.friends(of: profileID).count
        )
    }

    private var profileInsights: ProfileInsights {
        ProfileInsightsPresenter.present(
            ownerID: profileID,
            userPlaces: profileVisiblePlaces.map(\.userPlace),
            visits: store.placeVisits,
            places: profileVisiblePlaces.map(\.place),
            month: selectedMonth
        )
    }

    private func handleRelationshipAction() {
        switch store.relationship(to: profileID) {
        case .nonFollower:
            auth.requireSignIn(for: .followPeople) {
                Task {
                    await store.follow(userID: profileID, source: .profile, backend: backend)
                    await refreshRemoteProfile()
                }
            }
        case .follower, .mutual:
            showUnfollowConfirm = true
        case .owner:
            break
        }
    }

    private func toggleMute() {
        auth.requireSignIn(for: .manageBlocks) {
            Task {
                if store.isMuted(userID: profileID) {
                    await store.unmute(userID: profileID, backend: backend)
                } else {
                    await store.mute(userID: profileID, backend: backend)
                }
            }
        }
    }

    private func confirmBlock() {
        let shell = profile.map(store.shell(for:))
        showBlockConfirm = false
        auth.requireSignIn(for: .manageBlocks) {
            Task {
                if let shell {
                    await store.block(profile: shell, backend: backend)
                } else {
                    await store.block(userID: profileID, backend: backend)
                }
                await MainActor.run {
                    onBlock(profileID)
                    dismiss()
                }
            }
        }
    }

    private func refreshRemoteProfile() async {
        await store.refreshRemoteProfileData(profileID: profileID, backend: backend)
    }

    private var unfollowConfirmationTitle: String {
        guard let profile else { return "Are you sure you want to unfollow this person" }
        return "Are you sure you want to unfollow \(profile.displayName)"
    }

    private func confirmUnfollow() {
        showUnfollowConfirm = false
        auth.requireSignIn(for: .followPeople) {
            Task {
                await store.unfollow(userID: profileID, backend: backend)
                await refreshRemoteProfile()
            }
        }
    }
}

private enum GraphListMode: String, CaseIterable, Identifiable {
    case following
    case followers
    case friends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .following: "following"
        case .followers: "followers"
        case .friends: "friends"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .following: "follow someone from contacts or username search"
        case .followers: "people who follow you will show up here"
        case .friends: "mutual follows show up here"
        }
    }
}

private enum SavedPlacesListMode: String, Identifiable {
    case been
    case wanna
    case inCommon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .been: "Been"
        case .wanna: "Wanna"
        case .inCommon: "In Common"
        }
    }

    var status: PlaceStatus? {
        switch self {
        case .been: .been
        case .wanna: .wannaGo
        case .inCommon: nil
        }
    }
}

private struct ProfilePlaceCollectionRoute: Identifiable, Hashable {
    let id: String
    let title: String
    let placeIDs: [String]

    static func calendar(date: Date, placeIDs: [String], calendar: Calendar = .current) -> Self {
        let day = calendar.startOfDay(for: date)
        return ProfilePlaceCollectionRoute(
            id: "calendar-\(day.timeIntervalSince1970)",
            title: date.formatted(.dateTime.month(.wide).day().year()),
            placeIDs: placeIDs
        )
    }

    static func mapSummary(kind: ProfileMapSummaryKind, item: ProfileSummaryItem) -> Self {
        ProfilePlaceCollectionRoute(
            id: "map-\(kind.rawValue)-\(item.id)",
            title: item.title,
            placeIDs: item.placeIDs
        )
    }
}

private struct SavedPlacesListScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let mode: SavedPlacesListMode
    let collection: ProfilePlaceCollectionRoute?
    let profileID: String
    @State private var query = ""
    @State private var selectedCategory: String?
    @State private var selectedMetadataTag: String?
    @State private var isTagFilterExpanded = false
    @State private var tagFilterQuery = ""
    @State private var selectedPlace: VisiblePlace?
    @State private var placeSaveFlow: MapPlaceSaveContext?

    init(mode: SavedPlacesListMode, profileID: String) {
        self.mode = mode
        self.collection = nil
        self.profileID = profileID
    }

    init(collection: ProfilePlaceCollectionRoute, profileID: String) {
        self.mode = .been
        self.collection = collection
        self.profileID = profileID
    }

    private var places: [VisiblePlace] {
        modePlaces
            .filter(matchesCollection)
            .filter(matchesSelectedCategory)
            .filter(matchesSelectedMetadataTag)
            .filter(matchesQuery)
            .sorted { lhs, rhs in
                lhs.place.canonicalName.localizedCaseInsensitiveCompare(rhs.place.canonicalName) == .orderedAscending
            }
    }

    private var allModePlaces: [VisiblePlace] {
        modePlaces
            .filter(matchesCollection)
    }

    private var modePlaces: [VisiblePlace] {
        let base = mode == .inCommon
            ? store.placesInCommon(with: profileID)
            : store.visiblePlaces(for: profileID)
        guard let status = mode.status else { return base }
        return base.filter { $0.userPlace.status == status }
    }

    private var categories: [String] {
        Array(Set(allModePlaces.map(\.effectiveCategory))).sorted()
    }

    private var metadataTags: [String] {
        ProfileMetadataTagParser.uniqueTags(allModePlaces.flatMap(metadataTags(for:)))
    }

    private var filteredMetadataTags: [String] {
        let normalized = tagFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return metadataTags }
        return metadataTags.filter { $0.lowercased().contains(normalized) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                searchField
                filterSection(title: "type", values: categories, selectedValue: $selectedCategory)
                tagFilterDropdown

                if places.isEmpty {
                    SmallEmptyRow(title: "No matching places", subtitle: "try clearing search or filters")
                } else {
                    ForEach(places) { visiblePlace in
                        Button {
                            selectedPlace = visiblePlace
                        } label: {
                            ProfilePlaceRow(visiblePlace: visiblePlace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows saved place details")
                    }
                }
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing8)
        }
        .navigationDestination(isPresented: selectedPlaceDestinationBinding) {
            selectedPlaceDestination
        }
        .sheet(item: $placeSaveFlow) { context in
            MapPlaceSaveFlowSheet(context: context) { submission in
                await saveProfileFlowSubmission(submission)
            } onRemove: { context in
                await removeProfileSave(context)
            }
        }
        .wanderScreen()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationTitle: String {
        collection?.title ?? mode.title
    }

    private func matchesCollection(_ visiblePlace: VisiblePlace) -> Bool {
        guard let collection else { return true }
        let acceptedIDs = Set(collection.placeIDs)
        var placeIDs = [visiblePlace.place.id, visiblePlace.place.localID]
        if let serverID = visiblePlace.place.serverID {
            placeIDs.append(serverID)
        }
        return !acceptedIDs.isDisjoint(with: placeIDs)
    }

    private var selectedPlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: {
                selectedPlace != nil
            },
            set: { isPresented in
                if !isPresented {
                    selectedPlace = nil
                }
            }
        )
    }

    @ViewBuilder
    private var selectedPlaceDestination: some View {
        if let selectedPlace {
            PlaceProfileFullScreen(
                place: PlaceSheetPlace(visiblePlace: selectedPlace),
                saves: saveSummaries(for: selectedPlace),
                tasteSaves: tasteSummaries,
                currentUserID: store.currentUser.id,
                action: .addVisit,
                onBack: {
                    self.selectedPlace = nil
                },
                onAction: {
                    beginAddVisitSelectedPlace(selectedPlace)
                }
            )
        }
    }

    private var searchField: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WanderTheme.textMuted.color)
            TextField("search \(navigationTitle.lowercased())", text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }

    private func filterSection(
        title: String,
        values: [String],
        selectedValue: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    Button {
                        selectedValue.wrappedValue = nil
                    } label: {
                        WanderChip(title: "all", isSelected: selectedValue.wrappedValue == nil)
                    }
                    .buttonStyle(.plain)

                    ForEach(values, id: \.self) { value in
                        Button {
                            selectedValue.wrappedValue = selectedValue.wrappedValue == value ? nil : value
                        } label: {
                            WanderChip(
                                title: title == "type" ? WanderPlaceCategory.broadCategory(for: value) : value,
                                isSelected: selectedValue.wrappedValue == value
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var tagFilterDropdown: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("tags")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isTagFilterExpanded.toggle()
                }
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text(selectedMetadataTag ?? "all tags")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(selectedMetadataTag == nil ? WanderTheme.textMuted.color : WanderTheme.textInk.color)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .rotationEffect(.degrees(isTagFilterExpanded ? 180 : 0))
                }
                .frame(minHeight: WanderTheme.tapMinimum)
                .padding(.horizontal, WanderTheme.spacing3)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tag filter")

            if isTagFilterExpanded {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(WanderTheme.textMuted.color)
                        TextField("search tags", text: $tagFilterQuery)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minHeight: 40)
                    .background(WanderTheme.surfaceSand.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))

                    ScrollView {
                        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                            tagOption(title: "all tags", value: nil)

                            if filteredMetadataTags.isEmpty {
                                Text(metadataTags.isEmpty ? "no tags saved yet" : "no matching tags")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(WanderTheme.textMuted.color)
                                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                    .padding(.horizontal, WanderTheme.spacing2)
                            } else {
                                ForEach(filteredMetadataTags, id: \.self) { tag in
                                    tagOption(title: tag, value: tag)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                .padding(WanderTheme.spacing2)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func tagOption(title: String, value: String?) -> some View {
        Button {
            selectedMetadataTag = value
            tagFilterQuery = ""
            withAnimation(.easeOut(duration: 0.16)) {
                isTagFilterExpanded = false
            }
        } label: {
            HStack(spacing: WanderTheme.spacing2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                Spacer()
                if selectedMetadataTag == value {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.stateSuccess.color)
                }
            }
            .frame(minHeight: 40)
            .padding(.horizontal, WanderTheme.spacing2)
            .background(selectedMetadataTag == value ? WanderTheme.categorySage.color.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        }
        .buttonStyle(.plain)
    }

    private func matchesSelectedCategory(_ visiblePlace: VisiblePlace) -> Bool {
        guard let selectedCategory else { return true }
        return visiblePlace.effectiveCategory == selectedCategory
    }

    private func matchesSelectedMetadataTag(_ visiblePlace: VisiblePlace) -> Bool {
        guard let selectedMetadataTag else { return true }
        return metadataTags(for: visiblePlace).contains { $0.caseInsensitiveCompare(selectedMetadataTag) == .orderedSame }
    }

    private func matchesQuery(_ visiblePlace: VisiblePlace) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }

        let searchable = [
            visiblePlace.place.canonicalName,
            visiblePlace.effectiveCategoryDisplay.compactTitle,
            visiblePlace.place.locality,
            visiblePlace.userPlace.note,
            visiblePlace.userPlace.ratingSignal,
            visiblePlace.recommendedScore.map(PlaceRating.averageDisplay)
        ].compactMap { $0?.lowercased() }
        return searchable.contains { $0.contains(normalized) }
            || metadataTags(for: visiblePlace).contains { $0.lowercased().contains(normalized) }
    }

    private func metadataTags(for visiblePlace: VisiblePlace) -> [String] {
        store.attributes(for: visiblePlace.userPlace.id)
            .flatMap { ProfileMetadataTagParser.tags(from: $0.valueJSON) }
    }

    private func saveSummaries(for selectedPlace: VisiblePlace) -> [PlaceSaveSummary] {
        var seen = Set<String>()
        let summaries = store.visiblePlaces()
            .filter { VisiblePlaceGrouping.matches($0, selectedPlace) }
            .filter { visiblePlace in
                guard !seen.contains(visiblePlace.userPlace.id) else { return false }
                seen.insert(visiblePlace.userPlace.id)
                return true
            }
            .map { visiblePlace in
                PlaceSaveSummary(visiblePlace: visiblePlace, attributes: store.attributes(for: visiblePlace.userPlace.id))
            }

        return summaries.sorted { lhs, rhs in
            if lhs.visiblePlace.owner.id == store.currentUser.id { return true }
            if rhs.visiblePlace.owner.id == store.currentUser.id { return false }
            if lhs.visiblePlace.id == selectedPlace.id { return true }
            if rhs.visiblePlace.id == selectedPlace.id { return false }
            return lhs.visiblePlace.owner.displayName.localizedCaseInsensitiveCompare(rhs.visiblePlace.owner.displayName) == .orderedAscending
        }
    }

    private var tasteSummaries: [PlaceSaveSummary] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceSaveSummary(visiblePlace: visiblePlace, attributes: store.attributes(for: visiblePlace.userPlace.id))
        }
    }

    private func beginAddVisitSelectedPlace(_ visiblePlace: VisiblePlace) {
        let context = MapPlaceSaveContext.addVisitVisiblePlace(
            visiblePlace,
            attributes: store.attributes(for: visiblePlace.userPlace.id),
            latestVisit: store.visits(for: visiblePlace.userPlace.id).first
        )
        selectedPlace = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            placeSaveFlow = context
        }
    }

    @MainActor
    private func saveProfileFlowSubmission(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {
        let visitBackend = auth.isSignedIn ? backend : nil
        switch submission.context.mode {
        case .sharedVisit:
            return nil
        case .add(let sourceType):
            let result = await store.saveCandidate(
                submission.candidate,
                status: submission.status,
                visibility: submission.visibility,
                note: submission.note,
                sourceType: sourceType,
                ratingScore: submission.ratingScore,
                attributes: submission.attributes,
                backend: auth.isSignedIn ? backend : nil
            )
            let targetVisit = submission.status == .been ? store.visits(for: result.userPlaceID).first : nil
            await persistVisitPhotoAttachments(
                submission.photoAttachments,
                to: targetVisit,
                store: store,
                backend: visitBackend
            )
            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }
            return result
        case .addVisit, .editVisit, .editWant:
            let (result, targetVisit) = await persistScopedVisitOrWantSubmission(
                submission,
                store: store,
                backend: auth.isSignedIn ? backend : nil
            )
            guard let result else { return nil }
            await persistVisitPhotoAttachments(
                submission.photoAttachments,
                to: targetVisit,
                store: store,
                backend: visitBackend
            )
            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }
            return result
        }
    }

    @MainActor
    private func removeProfileSave(_ context: MapPlaceSaveContext) async -> Bool {
        switch context.mode {
        case .editVisit(_, let visit):
            return await store.deleteVisit(visitID: visit.id, backend: auth.isSignedIn ? backend : nil)
        case .editWant(let visiblePlace):
            guard await store.removeSave(userPlaceID: visiblePlace.userPlace.id, backend: auth.isSignedIn ? backend : nil) != nil else {
                return false
            }
            selectedPlace = nil
            return true
        case .add, .addVisit, .sharedVisit:
            return false
        }
    }
}

enum ProfileMetadataTagParser {
    static func tags(from valueJSON: String) -> [String] {
        guard let data = valueJSON.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return [] }

        if let string = value as? String {
            return uniqueTags([string])
        }
        if let strings = value as? [String] {
            return uniqueTags(strings)
        }
        return []
    }

    static func uniqueTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(trimmed)
        }

        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

private struct GraphListScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let mode: GraphListMode
    @State private var selectedProfile: GraphProfileSelection?
    @State private var pendingUnfollowProfile: LocalProfile?
    @State private var showsUnfollowConfirm = false

    private var profiles: [LocalProfile] {
        switch mode {
        case .followers:
            return store.followers(of: store.currentUser.id)
        case .following:
            return store.following(of: store.currentUser.id)
        case .friends:
            return store.following(of: store.currentUser.id).filter { store.relationship(to: $0.id) == .mutual }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(profiles, id: \.id) { profile in
                    GraphPersonListRow(
                        profile: profile,
                        relationship: store.relationship(to: profile.id),
                        savedPlaceCount: store.visiblePlaces(for: profile.id).count,
                        onOpenProfile: {
                            selectedProfile = GraphProfileSelection(id: profile.id)
                        },
                        onFollowAction: {
                            handleFollowAction(for: profile)
                        }
                    )
                    .listRowBackground(WanderTheme.surfaceBone.color)
                }
            }
            .scrollContentBackground(.hidden)
            .wanderScreen()
            .navigationTitle(mode.rawValue.capitalized)
            .fullScreenCover(item: $selectedProfile) { selection in
                ProfileDetailView(profileID: selection.id)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .alert(pendingUnfollowTitle, isPresented: $showsUnfollowConfirm) {
                Button("Yes, unfollow", role: .destructive) {
                    confirmPendingUnfollow()
                }
                Button("No, cancel", role: .cancel) {
                    pendingUnfollowProfile = nil
                    showsUnfollowConfirm = false
                }
            }
            .task {
                await store.refreshRemoteSocialGraph(backend: backend)
            }
        }
    }

    private var pendingUnfollowTitle: String {
        guard let pendingUnfollowProfile else {
            return "Are you sure you want to unfollow this person"
        }
        return "Are you sure you want to unfollow \(pendingUnfollowProfile.displayName)"
    }

    private func handleFollowAction(for profile: LocalProfile) {
        auth.requireSignIn(for: .followPeople) {
            if store.relationship(to: profile.id) == .nonFollower {
                Task {
                    await store.follow(userID: profile.id, backend: backend)
                }
            } else {
                pendingUnfollowProfile = profile
                showsUnfollowConfirm = true
            }
        }
    }

    private func confirmPendingUnfollow() {
        guard let profile = pendingUnfollowProfile else { return }
        pendingUnfollowProfile = nil
        showsUnfollowConfirm = false

        auth.requireSignIn(for: .followPeople) {
            Task {
                await store.unfollow(userID: profile.id, backend: backend)
            }
        }
    }
}

private struct GraphProfileSelection: Identifiable {
    let id: String
}

private struct GraphPersonListRow: View {
    let profile: LocalProfile
    let relationship: ViewerRelationship
    let savedPlaceCount: Int
    let onOpenProfile: () -> Void
    let onFollowAction: () -> Void

    private var actionTitle: String {
        relationship == .nonFollower ? "follow" : "unfollow"
    }

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: onOpenProfile) {
                HStack(spacing: WanderTheme.spacing3) {
                    WanderAvatar(
                        initials: profile.initials,
                        avatarURL: profile.avatarURL,
                        size: 40,
                        color: WanderTheme.pinSocial.color
                    )

                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(profile.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text("@\(profile.handle) · \(relationship.displayTitle)")
                            .font(.system(size: 13))
                            .foregroundStyle(WanderTheme.textMuted.color)
                        Text(savedPlaceCountLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WanderTheme.textFaint.color)
                    }

                    Spacer(minLength: WanderTheme.spacing2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(actionTitle, action: onFollowAction)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(actionTitle == "unfollow" ? WanderTheme.stateError.color : WanderTheme.terracotta.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: 34)
                .background(
                    Capsule()
                        .fill(actionTitle == "unfollow" ? WanderTheme.surfaceRaised.color : WanderTheme.terracottaTint.color)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            actionTitle == "unfollow" ? WanderTheme.borderHairline.color : WanderTheme.terracotta.color.opacity(0.35),
                            lineWidth: 1
                        )
                )
        }
    }

    private var savedPlaceCountLabel: String {
        switch savedPlaceCount {
        case 0:
            return "no saved places yet"
        case 1:
            return "1 saved place"
        default:
            return "\(savedPlaceCount) saved places"
        }
    }
}

private struct ConnectionRow: View {
    let title: String
    let subtitle: String
    let count: Int
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(width: 40, height: 40)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(count)")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
    }
}

private struct ProfilePersonRow: View {
    let profile: LocalProfile
    let relationship: ViewerRelationship
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                WanderAvatar(
                    initials: profile.initials,
                    avatarURL: profile.avatarURL,
                    size: 40,
                    color: WanderTheme.pinSocial.color
                )

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(profile.displayName)
                        .font(.system(size: 15, weight: .bold))
                    Text("@\(profile.handle) · \(relationship.displayTitle)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let color: Color
    let fill: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                Text(value)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(color)

                Spacer(minLength: WanderTheme.spacing2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .frame(width: 28, height: 28)
                    .background(WanderTheme.surfaceRaised.color.opacity(0.85))
                    .foregroundStyle(color)
                    .clipShape(Circle())
            }

            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(color.opacity(0.28), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct ProfileStatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ProfilePlaceRow: View {
    let visiblePlace: VisiblePlace

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(width: 40, height: 40)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(visiblePlace.place.canonicalName)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            if let recommendedScore = visiblePlace.recommendedScore,
               visiblePlace.recommendedCount > 0 {
                RecommendedScorePill(score: recommendedScore)
            }
            PlaceVisibilityIconPill(visibility: visiblePlace.userPlace.visibility, size: 30)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var icon: String {
        WanderPlaceCategory.symbolName(for: visiblePlace.categoryAssignment)
    }

    private var subtitle: String {
        let locality = visiblePlace.place.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let locality, !locality.isEmpty else {
            return visiblePlace.userPlace.status.displayTitle
        }
        return "\(locality) · \(visiblePlace.userPlace.status.displayTitle)"
    }
}

private struct RecommendedScorePill: View {
    let score: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .black))
            Text(PlaceRating.averageDisplay(score))
                .font(.system(size: 12, weight: .black))
        }
        .foregroundStyle(WanderTheme.terracotta.color)
        .padding(.horizontal, WanderTheme.spacing2)
        .frame(height: 30)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
        .accessibilityLabel("Recommended score \(PlaceRating.averageDisplay(score)) out of 5")
    }
}

private struct SmallEmptyRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct AccessChangedPanel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}
