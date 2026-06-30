import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var activeDetail: SettingsDetail?
    @State private var pendingPrivateProfileValue: Bool?
    @State private var showsPrivateProfileWarning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    header
                    accountSection
                    visibilitySection
                    blockedSection
                    groupedRows
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .wanderScreen()
        }
        .sheet(item: $activeDetail) { detail in
            switch detail {
            case .trust:
                TrustAndPrivacySheet()
            }
        }
        .alert(
            SettingsProfilePrivacySurface.warningTitle(enabling: pendingPrivateProfileValue ?? false),
            isPresented: $showsPrivateProfileWarning
        ) {
            Button("Cancel", role: .cancel) {
                pendingPrivateProfileValue = nil
            }
            Button(SettingsProfilePrivacySurface.warningConfirmTitle(enabling: pendingPrivateProfileValue ?? false)) {
                if let pendingPrivateProfileValue {
                    store.setPrivateProfile(pendingPrivateProfileValue)
                }
                pendingPrivateProfileValue = nil
            }
        } message: {
            Text(SettingsProfilePrivacySurface.warningBody(enabling: pendingPrivateProfileValue ?? false))
        }
    }

    private var header: some View {
        Text("settings")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .lineLimit(1)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SettingsSectionTitle("account")

            switch auth.state {
            case .signedIn(let session):
                HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                    WanderAvatar(
                        initials: initials(for: session),
                        avatarURL: store.currentUser.avatarURL,
                        size: 40,
                        color: WanderTheme.pinSocial.color
                    )
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(session.displayName ?? "Signed in")
                            .font(.system(size: 15, weight: .bold))
                        Text(session.handle.map { "@\($0)" } ?? session.userID)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                Button {
                    Task {
                        try? await auth.signOut()
                    }
                } label: {
                    HStack(spacing: WanderTheme.spacing2) {
                        if auth.isSigningOut {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                        Text(auth.isSigningOut ? "signing out" : "sign out")
                    }
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.stateError.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .background(WanderTheme.stateError.color.opacity(0.10))
                    .clipShape(Capsule())
                }
                .disabled(auth.isSigningOut)

                if let signOutError = auth.signOutError {
                    Text(signOutError)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.stateError.color)
                }
            case .signedOut:
                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .frame(width: 38, height: 38)
                        .background(WanderTheme.terracottaTint.color)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text("Signed out")
                            .font(.system(size: 15, weight: .bold))
                        Text("Sign in to sync and follow people.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                    Spacer()
                }

                Button {
                    auth.beginSignIn()
                } label: {
                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("sign in")
                    }
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
                }
            case .loading:
                HStack {
                    ProgressView()
                    Text("Checking account...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            case .unavailable(let message):
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(message)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WanderTheme.stateError.color)
                    Text("Rebuild with local auth config to sign in or out.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SettingsSectionTitle("privacy")

            privateProfileToggle

            Divider()
                .overlay(WanderTheme.borderHairline.color)

            PlaceVisibilityStealthToggle(
                title: SettingsDefaultPlacePrivacySurface.toggleTitle,
                visibility: Binding(
                    get: { store.isPrivateProfile ? .selfOnly : store.defaultVisibility.normalizedForStealthMode },
                    set: { newVisibility in
                        guard !store.isPrivateProfile else { return }
                        store.defaultVisibility = newVisibility
                    }
                ),
                showsContainer: false,
                helperCopy: { visibility in
                    SettingsDefaultPlacePrivacySurface.helperCopy(
                        for: visibility,
                        isLockedByPrivateProfile: store.isPrivateProfile
                    )
                }
            )
            .disabled(store.isPrivateProfile)
            .opacity(store.isPrivateProfile ? 0.56 : 1)
        }
        .onAppear {
            if !store.isPrivateProfile {
                store.defaultVisibility = store.defaultVisibility.normalizedForStealthMode
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var privateProfileToggle: some View {
        Toggle(
            isOn: Binding(
                get: { store.isPrivateProfile },
                set: { nextValue in
                    guard nextValue != store.isPrivateProfile else { return }
                    pendingPrivateProfileValue = nextValue
                    showsPrivateProfileWarning = true
                }
            )
        ) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                Image(systemName: store.isPrivateProfile ? "lock.shield.fill" : "person.crop.circle.badge.questionmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(width: 38, height: 38)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(SettingsProfilePrivacySurface.title)
                        .font(.system(size: 14, weight: .bold))
                    Text(SettingsProfilePrivacySurface.body(isEnabled: store.isPrivateProfile))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(WanderTheme.textInk.color)
        .accessibilityIdentifier(SettingsProfilePrivacySurface.accessibilityID)
    }

    private var blockedSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SettingsSectionTitle("blocked users")
            let blocked = store.blockedProfiles()
            if blocked.isEmpty {
                Text("No one blocked.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            } else {
                ForEach(blocked) { profile in
                    HStack {
                        WanderAvatar(
                            initials: String(profile.displayName.prefix(2)).uppercased(),
                            avatarURL: profile.avatarURL,
                            size: 34,
                            color: WanderTheme.stateError.color
                        )
                        VStack(alignment: .leading) {
                            Text(profile.displayName)
                                .font(.system(size: 14, weight: .bold))
                            Text("@\(profile.handle)")
                                .font(.system(size: 12))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                        Spacer()
                        Button("unblock") {
                            auth.requireSignIn(for: .manageBlocks) {
                                Task {
                                    await store.unblock(userID: profile.id, backend: backend)
                                }
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var groupedRows: some View {
        VStack(spacing: WanderTheme.spacing3) {
            SettingsRow(
                title: SettingsTrustSurface.rowTitle,
                subtitle: SettingsTrustSurface.rowSubtitle,
                systemImage: "shield.lefthalf.filled",
                accessibilityIdentifier: SettingsTrustSurface.rowAccessibilityID
            ) {
                activeDetail = .trust
            }
            SettingsRow(title: "Contacts", subtitle: "planned native permission later", systemImage: "person.crop.rectangle.stack")
            SettingsRow(title: "Notifications", subtitle: "after first save", systemImage: "bell")
            SettingsRow(title: "Data and sync", subtitle: "\(store.pendingSyncCount) pending local item\(store.pendingSyncCount == 1 ? "" : "s")", systemImage: "arrow.triangle.2.circlepath") {
                auth.presentGate(for: .syncPending)
            }
        }
    }

    private func initials(for session: AuthSession) -> String {
        let source = session.displayName ?? session.handle ?? session.userID
        return String(source.prefix(2)).uppercased()
    }
}

private enum SettingsDetail: String, Identifiable {
    case trust

    var id: String { rawValue }
}

private struct SettingsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .black))
    }
}

private struct TrustAndPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text(SettingsTrustSurface.sheetTitle)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .accessibilityAddTraits(.isHeader)
                        Text(SettingsTrustSurface.sheetIntro)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(SettingsTrustSurface.facts) { fact in
                        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                            Image(systemName: fact.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(WanderTheme.terracotta.color)
                                .frame(width: 38, height: 38)
                                .background(WanderTheme.terracottaTint.color)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                                Text(fact.title)
                                    .font(.system(size: 15, weight: .black))
                                Text(fact.body)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(WanderTheme.textMuted.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(WanderTheme.spacing3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WanderTheme.surfaceBone.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(SettingsTrustSurface.factAccessibilityPrefix + fact.id)
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .wanderScreen()
            .accessibilityIdentifier(SettingsTrustSurface.sheetAccessibilityID)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
                }
            }
        }
    }
}

struct SettingsTrustSurface {
    static let rowTitle = "Privacy and trust"
    static let rowSubtitle = "who sees places, location, sources"
    static let rowAccessibilityID = "settings.privacyTrust.row"
    static let sheetAccessibilityID = "settings.privacyTrust.sheet"
    static let factAccessibilityPrefix = "settings.privacyTrust.fact."
    static let sheetTitle = "privacy and trust"
    static let sheetIntro = "quick answers for what rec.me shares, syncs, and keeps private."

    static let facts: [TrustFact] = [
        TrustFact(
            id: "everyone",
            icon: "eye.slash",
            title: "Not private means followers",
            body: "Places saved outside stealth mode are visible to people who follow you. They are not a public internet feed."
        ),
        TrustFact(
            id: "stealth",
            icon: "lock",
            title: "Stealth mode means private",
            body: "Stealth places stay on your map for you only."
        ),
        TrustFact(
            id: "location",
            icon: "location",
            title: "Location is for finding places",
            body: "rec.me uses location when you ask for nearby candidates. It does not broadcast live location."
        ),
        TrustFact(
            id: "extraction",
            icon: "wand.and.stars",
            title: "Extraction asks first",
            body: "Links and photos can create candidates or drafts. Low-confidence results never auto-save to your map."
        ),
        TrustFact(
            id: "blocks",
            icon: "person.crop.circle.badge.xmark",
            title: "Blocks are hard blocks",
            body: "Blocking hides profiles, places, search results, and map content in both directions."
        ),
        TrustFact(
            id: "contacts",
            icon: "person.crop.rectangle.stack",
            title: "Contacts are later",
            body: "Native Contacts permission is planned, but not part of this alpha. Username search works now."
        )
    ]
}

struct SettingsDefaultPlacePrivacySurface {
    static let toggleTitle = "stealth mode for new saves"

    static func helperCopy(for visibility: PlaceVisibility, isLockedByPrivateProfile: Bool = false) -> String {
        if isLockedByPrivateProfile {
            return "Locked on by Private Profile. New places stay hidden while Private Profile is on."
        }

        if visibility.isStealthModeEnabled {
            return "On: new places start private. Only you can see them unless you turn stealth off before saving."
        }

        return "Off: new places are visible to people who follow you. You can still turn stealth on before saving."
    }
}

struct SettingsProfilePrivacySurface {
    static let title = "Private profile"
    static let accessibilityID = "settings.profilePrivacy.explainer"

    static func body(isEnabled: Bool) -> String {
        if isEnabled {
            return "Your saved places are in stealth mode, new places stay stealth, and your username stays out of search. Existing friends and collaborative lists stay unchanged; new collaborative lists are unavailable."
        }

        return "Your username can appear in search and you can collaborate on lists."
    }

    static func warningTitle(enabling: Bool) -> String {
        enabling ? "Turn on Private Profile?" : "Turn off Private Profile?"
    }

    static func warningBody(enabling: Bool) -> String {
        if enabling {
            return "Places saved by you will switch to stealth mode, including your Been and Wanna Go places. Future saves stay stealth and your username will be hidden while Private Profile is on. Your followers and existing collaborative lists stay unchanged, but new collaborative lists are unavailable."
        }

        return "Your existing places will stay in stealth mode. Your username can appear in search again, and future saves will follow your stealth mode for new saves setting."
    }

    static func warningConfirmTitle(enabling: Bool) -> String {
        enabling ? "Turn On" : "Turn Off"
    }
}

struct TrustFact: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let body: String
}

private struct SettingsInlineInfo: View {
    let systemImage: String
    let title: String
    let message: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(width: 38, height: 38)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct SettingsRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var accessibilityIdentifier: String?
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(width: 38, height: 38)
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
                if action != nil {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(WanderTheme.textFaint.color)
                }
            }
            .frame(minHeight: WanderTheme.tapMinimum)
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityIdentifier(accessibilityIdentifier ?? "settings.row.\(title.lowercased().replacingOccurrences(of: " ", with: "."))")
    }
}
