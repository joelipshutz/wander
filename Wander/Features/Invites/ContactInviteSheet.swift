import MessageUI
import SwiftUI
import UIKit

enum ContactInviteAccessState: Equatable {
    case primer
    case authorized
    case denied
}

enum ContactInvitePresentationState: Equatable {
    case choosing
    case completed
}

struct InviteEntryPointButton: View {
    let surface: InviteSurface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                ZStack {
                    Circle()
                        .fill(WanderTheme.terracottaTint.color)
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(surface.entryTitle)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(surface.entrySubtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                }

                Spacer(minLength: WanderTheme.spacing2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.vertical, WanderTheme.spacing2)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(surface.entryTitle)
        .accessibilityHint(surface.entrySubtitle)
    }
}

struct ContactInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    let surface: InviteSurface
    let contactProvider: (any ContactProvider)?
    let senderProfileID: String?
    let canDismiss: Bool
    let walkthroughSelectionGoal: Int?
    let onPermissionDenied: (() -> Void)?

    @State private var contacts: [InviteContact]
    @State private var accessState: ContactInviteAccessState
    @State private var presentationState: ContactInvitePresentationState
    @State private var query: String
    @State private var selection: InviteSelection
    @State private var isLoadingContacts = false
    @State private var didFailLoadingContacts = false
    @State private var isPresentingMessageComposer = false
    @State private var messageRecipient: String?
    @State private var messageDeliveryPlan: InviteMessageDeliveryPlan?
    @State private var sharePresentation: InviteSharePresentation?
    @State private var deliveryErrorMessage: String?
    @State private var completionHeadline: String?
    @State private var completionDetail: String?
    @State private var didHandleWalkthroughPermissionDenial = false

    init(
        surface: InviteSurface,
        contacts: [InviteContact],
        accessState: ContactInviteAccessState = .authorized,
        presentationState: ContactInvitePresentationState = .choosing,
        selectedContactIDs: Set<String> = [],
        query: String = "",
        senderProfileID: String? = nil,
        canDismiss: Bool = true,
        walkthroughSelectionGoal: Int? = nil,
        onPermissionDenied: (() -> Void)? = nil
    ) {
        self.surface = surface
        contactProvider = nil
        self.senderProfileID = senderProfileID
        self.canDismiss = canDismiss
        self.walkthroughSelectionGoal = walkthroughSelectionGoal
        self.onPermissionDenied = onPermissionDenied
        _contacts = State(initialValue: contacts)
        _accessState = State(initialValue: accessState)
        _presentationState = State(initialValue: presentationState)
        _query = State(initialValue: query)
        _selection = State(initialValue: InviteSelection(contactIDs: selectedContactIDs))
    }

    init(
        surface: InviteSurface,
        contactProvider: any ContactProvider,
        senderProfileID: String? = nil,
        canDismiss: Bool = true,
        walkthroughSelectionGoal: Int? = nil,
        onPermissionDenied: (() -> Void)? = nil
    ) {
        self.surface = surface
        self.contactProvider = contactProvider
        self.senderProfileID = senderProfileID
        self.canDismiss = canDismiss
        self.walkthroughSelectionGoal = walkthroughSelectionGoal
        self.onPermissionDenied = onPermissionDenied
        _contacts = State(initialValue: [])
        _accessState = State(initialValue: .primer)
        _presentationState = State(initialValue: .choosing)
        _query = State(initialValue: "")
        _selection = State(initialValue: InviteSelection())
    }

    private var sections: [InviteContactSection] {
        InviteContactSection.sections(for: contacts, query: query)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            WanderTheme.canvasWarm.color
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                switch presentationState {
                case .completed:
                    completionContent
                case .choosing:
                    switch accessState {
                    case .primer:
                        permissionPrimer
                    case .authorized:
                        contactsContent
                    case .denied:
                        deniedContent
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
            .padding(.top, WanderTheme.spacing2)
        }
        .preferredColorScheme(.light)
        .task {
            await refreshProviderState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, contactProvider != nil else { return }
            Task { await refreshProviderState() }
        }
        .sheet(isPresented: $isPresentingMessageComposer) {
            if let messageRecipient {
                ContactInviteMessageComposer(
                    recipients: [messageRecipient],
                    body: inviteShareContent.messageBody,
                    onFinish: handleMessageComposerResult
                )
            }
        }
        .sheet(item: $sharePresentation) { presentation in
            WanderShareSheet(content: presentation.content) { completed in
                guard completed else { return }
                completeDelivery(
                    headline: selection.count == 1 ? "invite shared" : "invites shared",
                    detail: "The TestFlight link was handed off successfully."
                )
            }
        }
        .alert("Invite wasn’t sent", isPresented: deliveryErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deliveryErrorMessage ?? "Messages could not send this invitation. Try again.")
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(surface.sheetTitle)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                if presentationState == .choosing && accessState == .authorized {
                    Text("\(selection.count)/\(walkthroughSelectionGoal ?? InviteSelection.maximumCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .monospacedDigit()
                }
            }

            HStack {
                Button {
                    if canDismiss { dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                        .background(WanderTheme.surfaceRaised.color)
                        .clipShape(Circle())
                        .shadow(color: WanderTheme.textInk.color.opacity(0.08), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                Spacer()

                if presentationState == .choosing && accessState == .authorized {
                    Button {
                        guard selection.count > 0 else { return }
                        beginInviteDelivery()
                    } label: {
                        Text(surface.primaryActionTitle)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(selection.count == 0 ? WanderTheme.textFaint.color : WanderTheme.textOnAction.color)
                            .padding(.horizontal, WanderTheme.spacing3)
                            .frame(minWidth: 64, minHeight: WanderTheme.tapMinimum)
                            .background(selection.count == 0 ? WanderTheme.surfaceSand.color : WanderTheme.terracotta.color)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selection.count == 0)
                    .accessibilityLabel("\(surface.primaryActionTitle) selected people")
                } else {
                    Color.clear.frame(width: 64, height: WanderTheme.tapMinimum)
                }
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing2)
    }

    private var contactsContent: some View {
        VStack(spacing: 0) {
            if let walkthroughSelectionGoal {
                ContactInviteWalkthroughGoalBanner(
                    selectedCount: selection.count,
                    goal: walkthroughSelectionGoal
                )
                .padding(.horizontal, WanderTheme.spacing3)
                .padding(.bottom, WanderTheme.spacing3)
            }

            searchField

            if isLoadingContacts {
                loadingContacts
            } else if didFailLoadingContacts {
                failedContacts
            } else if sections.isEmpty {
                emptyResults
            } else {
                ScrollViewReader { proxy in
                    ZStack(alignment: .trailing) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3, pinnedViews: [.sectionHeaders]) {
                                ForEach(sections) { section in
                                    Section {
                                        contactGroup(section.contacts)
                                    } header: {
                                        Text(section.title)
                                            .font(.system(size: 13, weight: .black))
                                            .foregroundStyle(WanderTheme.textMuted.color)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, WanderTheme.spacing1)
                                            .background(WanderTheme.surfaceBone.color)
                                            .id(section.id)
                                    }
                                }
                            }
                            .padding(.horizontal, WanderTheme.spacing3)
                            .padding(.trailing, WanderTheme.spacing4)
                            .padding(.bottom, WanderTheme.spacing8)
                        }
                        .scrollDismissesKeyboard(.interactively)

                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            AlphabetScrubber(letters: alphabetLetters) { letter in
                                guard let targetID = scrollTargetID(for: letter) else { return }
                                withAnimation(.snappy(duration: 0.18)) {
                                    proxy.scrollTo(targetID, anchor: .top)
                                }
                            }
                            .padding(.trailing, 2)
                        }
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            TextField("Name, number, or @username", text: $query)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WanderTheme.textInk.color)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(WanderTheme.textFaint.color)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 48)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.bottom, WanderTheme.spacing3)
    }

    private func contactGroup(_ contacts: [InviteContact]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                contactRow(contact)
                if index < contacts.count - 1 {
                    Divider()
                        .overlay(WanderTheme.borderHairline.color.opacity(0.72))
                        .padding(.leading, 58)
                }
            }
        }
        .padding(.horizontal, WanderTheme.spacing2)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color.opacity(0.75), lineWidth: 1)
        }
    }

    private func contactRow(_ contact: InviteContact) -> some View {
        Button {
            if !selection.contains(contact.id),
               let walkthroughSelectionGoal,
               selection.count >= walkthroughSelectionGoal {
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                _ = selection.toggle(contact.id)
            }
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                Text(contact.initials)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(avatarForeground(for: contact))
                    .frame(width: 40, height: 40)
                    .background(avatarBackground(for: contact))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: WanderTheme.spacing1) {
                        Text(contact.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(1)

                        if contact.relationship.isOnRecme {
                            Text("on rec.me")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(WanderTheme.stateInfo.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(WanderTheme.skyTint.color)
                                .clipShape(Capsule())
                        }
                    }

                    if let detail = rowDetail(for: contact) {
                        Text(detail)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: WanderTheme.spacing1)

                ZStack {
                    Circle()
                        .fill(selection.contains(contact.id) ? WanderTheme.terracotta.color : Color.clear)
                    Circle()
                        .stroke(
                            selection.contains(contact.id) ? WanderTheme.terracotta.color : WanderTheme.borderStrong.color,
                            lineWidth: 2
                        )
                    if selection.contains(contact.id) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(WanderTheme.textOnAction.color)
                    }
                }
                .frame(
                    width: walkthroughSelectionGoal == nil ? 25 : 32,
                    height: walkthroughSelectionGoal == nil ? 25 : 32
                )
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(contactAccessibilityLabel(for: contact))
        .accessibilityValue(selection.contains(contact.id) ? "Selected" : "Not selected")
        .accessibilityHint(selection.contains(contact.id) ? "Double-tap to deselect" : "Double-tap to select")
    }

    private var alphabetLetters: [String] {
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#").map(String.init)
    }

    private func scrollTargetID(for requestedLetter: String) -> String? {
        let letterSections = sections.filter { $0.id.hasPrefix("letter-") }
        if let exact = letterSections.first(where: { $0.title == requestedLetter }) {
            return exact.id
        }
        if let next = letterSections.first(where: { $0.title >= requestedLetter }) {
            return next.id
        }
        return letterSections.last?.id
    }

    private var permissionPrimer: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Spacer()

            ZStack {
                Circle()
                    .fill(WanderTheme.terracottaTint.color)
                    .frame(width: 104, height: 104)
                Image(systemName: "person.2.crop.square.stack.fill")
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
            }

            VStack(spacing: WanderTheme.spacing2) {
                Text("find your people")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(surface.permissionMessage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: WanderTheme.spacing2) {
                permissionPromise(icon: "checkmark.shield.fill", text: "You choose who gets an invite")
                permissionPromise(icon: "paperplane.fill", text: "rec.me never messages contacts for you")
                permissionPromise(icon: "lock.fill", text: "Contact details stay out of analytics")
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceSand.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))

            Button {
                Task { await requestContactsAccess() }
            } label: {
                Group {
                    if isLoadingContacts {
                        ProgressView()
                            .tint(WanderTheme.textOnAction.color)
                    } else {
                        Text("continue to contacts")
                    }
                }
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.textOnAction.color)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(WanderTheme.terracotta.color)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLoadingContacts)

            Button("not now") {
                if canDismiss { dismiss() }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(WanderTheme.textMuted.color)
            .frame(minHeight: WanderTheme.tapMinimum)

            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing4)
    }

    private func permissionPromise(icon: String, text: String) -> some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.stateSuccess.color)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
            Spacer()
        }
    }

    private var deniedContent: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)

            VStack(spacing: WanderTheme.spacing2) {
                Text("contacts are off")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("Turn on Contacts in Settings to browse your address book, or share a rec.me link instead.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("open settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.textOnAction.color)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(WanderTheme.terracotta.color)
                .clipShape(Capsule())

            Button {
                sharePresentation = InviteSharePresentation(content: inviteShareContent)
            } label: {
                Label("share an invite link", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(WanderTheme.surfaceSand.color)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing4)
    }

    private var emptyResults: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(WanderTheme.textFaint.color)
            Text("no contacts found")
                .font(.system(size: 20, weight: .black, design: .rounded))
            Text("Try another name, number, or username.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingContacts: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Spacer()
            ProgressView()
                .tint(WanderTheme.terracotta.color)
            Text("loading contacts")
                .font(.system(size: 17, weight: .black, design: .rounded))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedContacts: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Spacer()
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 42, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
            Text("contacts couldn’t load")
                .font(.system(size: 20, weight: .black, design: .rounded))
            Button("try again") {
                Task { await loadContacts() }
            }
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(WanderTheme.textOnAction.color)
            .padding(.horizontal, WanderTheme.spacing4)
            .frame(minHeight: WanderTheme.tapMinimum)
            .background(WanderTheme.terracotta.color)
            .clipShape(Capsule())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completionContent: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Spacer()

            ZStack {
                Circle()
                    .fill(WanderTheme.terracottaTint.color)
                    .frame(width: 108, height: 108)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 43, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .offset(x: -3, y: 2)
            }

            VStack(spacing: WanderTheme.spacing2) {
                Text(completionHeadline ?? surface.completionTitle)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(completionDetail ?? "The TestFlight invitation was shared.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("If they follow you, tap their follow notification to open their profile and follow back.")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
                .multilineTextAlignment(.center)
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.skyTint.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))

            Button {
                if canDismiss { dismiss() }
            } label: {
                Text("done")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, WanderTheme.spacing4)
    }

    private func rowDetail(for contact: InviteContact) -> String? {
        if case .recmeUser(let handle, _) = contact.relationship {
            return "@\(handle)"
        }
        return contact.contactDetail
    }

    private func avatarBackground(for contact: InviteContact) -> Color {
        if contact.relationship.isOnRecme { return WanderTheme.skyTint.color }
        let palette = [
            WanderTheme.terracottaTint.color,
            WanderTheme.sunTint.color,
            WanderTheme.surfaceSand.color,
            WanderTheme.avatarSofia.color.opacity(0.24)
        ]
        let value = contact.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[value % palette.count]
    }

    private func avatarForeground(for contact: InviteContact) -> Color {
        contact.relationship.isOnRecme ? WanderTheme.stateInfo.color : WanderTheme.terracottaDark.color
    }

    private var inviteShareContent: WanderShareContent {
        WanderShareContent.appInvite(
            senderProfileID: senderProfileID,
            contextMessage: surface.inviteMessage
        )
    }

    private var selectedContacts: [InviteContact] {
        contacts.filter { selection.contains($0.id) }
    }

    private func beginInviteDelivery() {
        let recipients = selectedContacts
        guard !recipients.isEmpty else { return }

        let canAddressEveryRecipient = recipients.allSatisfy {
            guard let detail = $0.contactDetail else { return false }
            return isLikelyPhoneNumber(detail)
        }
        guard MFMessageComposeViewController.canSendText(), canAddressEveryRecipient else {
            sharePresentation = InviteSharePresentation(content: inviteShareContent)
            return
        }

        messageDeliveryPlan = InviteMessageDeliveryPlan(contacts: recipients)
        presentNextMessageComposer()
    }

    private func presentNextMessageComposer() {
        guard let nextContact = messageDeliveryPlan?.currentContact,
              let recipient = nextContact.contactDetail
        else {
            let sentCount = messageDeliveryPlan?.sentCount ?? 0
            guard sentCount > 0 else { return }
            completeDelivery(
                headline: sentCount == 1 ? "invite sent" : "invites sent",
                detail: sentCount == 1
                    ? "The TestFlight link was sent in Messages."
                    : "The TestFlight link was sent to \(sentCount) people in Messages."
            )
            return
        }
        messageRecipient = recipient
        isPresentingMessageComposer = true
    }

    private func handleMessageComposerResult(_ result: MessageComposeResult) {
        isPresentingMessageComposer = false
        messageRecipient = nil

        switch result {
        case .sent:
            if let sentContact = messageDeliveryPlan?.markCurrentSent() {
                selection.remove(sentContact.id)
            }
            if messageDeliveryPlan?.currentContact == nil {
                presentNextMessageComposer()
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    presentNextMessageComposer()
                }
            }
        case .cancelled:
            messageDeliveryPlan?.cancelRemaining()
        case .failed:
            messageDeliveryPlan?.cancelRemaining()
            deliveryErrorMessage = "Messages could not send this invitation. Try again."
        @unknown default:
            messageDeliveryPlan?.cancelRemaining()
            deliveryErrorMessage = "Messages returned an unknown result. Try again."
        }
    }

    private func completeDelivery(headline: String, detail: String) {
        completionHeadline = headline
        completionDetail = detail
        withAnimation(.easeInOut(duration: 0.22)) {
            presentationState = .completed
        }
    }

    private func isLikelyPhoneNumber(_ value: String) -> Bool {
        guard !value.contains("@") else { return false }
        return value.filter(\.isNumber).count >= 3
    }

    private var deliveryErrorBinding: Binding<Bool> {
        Binding(
            get: { deliveryErrorMessage != nil },
            set: { if !$0 { deliveryErrorMessage = nil } }
        )
    }

    private func contactAccessibilityLabel(for contact: InviteContact) -> String {
        let detail = rowDetail(for: contact)
        let relationship = contact.relationship.isOnRecme ? "Already on rec.me" : "Phone contact"
        return [contact.displayName, detail, relationship].compactMap { $0 }.joined(separator: ", ")
    }

    @MainActor
    private func refreshProviderState() async {
        guard let contactProvider else { return }
        switch await contactProvider.authorization() {
        case .notDetermined:
            accessState = .primer
        case .authorized:
            accessState = .authorized
            await loadContacts()
        case .denied:
            accessState = .denied
            finishWalkthroughAfterDeniedPermission()
        }
    }

    @MainActor
    private func requestContactsAccess() async {
        guard let contactProvider else {
            withAnimation(.easeInOut(duration: 0.22)) {
                accessState = .authorized
            }
            return
        }

        isLoadingContacts = true
        let authorization = await contactProvider.requestAccess()
        switch authorization {
        case .authorized:
            accessState = .authorized
            await loadContacts()
        case .notDetermined:
            accessState = .primer
            isLoadingContacts = false
        case .denied:
            accessState = .denied
            isLoadingContacts = false
            finishWalkthroughAfterDeniedPermission()
        }
    }

    private func finishWalkthroughAfterDeniedPermission() {
        guard onPermissionDenied != nil, !didHandleWalkthroughPermissionDenial else { return }
        didHandleWalkthroughPermissionDenial = true
        onPermissionDenied?()
        dismiss()
    }

    @MainActor
    private func loadContacts() async {
        guard let contactProvider else { return }
        isLoadingContacts = true
        didFailLoadingContacts = false
        defer { isLoadingContacts = false }
        do {
            contacts = try await contactProvider.matches().map(InviteContact.init(contactMatch:))
        } catch {
            didFailLoadingContacts = true
        }
    }
}

private struct ContactInviteWalkthroughGoalBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCelebrating = false

    let selectedCount: Int
    let goal: Int

    private var completedCount: Int {
        min(selectedCount, goal)
    }

    private var isComplete: Bool {
        completedCount >= goal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isComplete ? "Your circle is ready" : "Start with five people")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(
                        isComplete
                            ? "Nice. Their saves can make every search more useful."
                            : "Pick up to five people whose taste you already trust. Fewer is fine too."
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: WanderTheme.spacing2)

                if isComplete {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(WanderTheme.stateSuccess.color)
                        .scaleEffect(reduceMotion ? 1 : (isCelebrating ? 1.12 : 0.92))
                }
            }

            HStack(spacing: WanderTheme.spacing2) {
                ForEach(0..<goal, id: \.self) { index in
                    ZStack {
                        Circle()
                            .fill(
                                index < completedCount
                                    ? WanderTheme.stateSuccess.color
                                    : WanderTheme.surfaceRaised.color
                            )
                        Circle()
                            .stroke(
                                index < completedCount
                                    ? WanderTheme.stateSuccess.color
                                    : WanderTheme.borderStrong.color,
                                lineWidth: 2
                            )
                        if index < completedCount {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(WanderTheme.textOnAction.color)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isComplete
                ? WanderTheme.stateSuccess.color.opacity(0.12)
                : WanderTheme.terracottaTint.color.opacity(0.72)
        )
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(
                    isComplete
                        ? WanderTheme.stateSuccess.color.opacity(0.55)
                        : WanderTheme.terracotta.color.opacity(0.3),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completedCount) of \(goal) people selected")
        .onChange(of: isComplete, initial: true) { _, complete in
            guard complete, !reduceMotion else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                isCelebrating = true
            }
        }
    }
}

private struct InviteSharePresentation: Identifiable {
    let id = UUID()
    let content: WanderShareContent
}

private struct ContactInviteMessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMessageComposeViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onFinish(result)
        }
    }
}

private struct AlphabetScrubber: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var selectedIndex = 0
    @State private var isScrubbing = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(letters.indices, id: \.self) { index in
                    let distance = abs(index - selectedIndex)
                    let scale = isScrubbing ? magnification(for: distance) : 1

                    Text(letters[index])
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .scaleEffect(scale)
                        .offset(x: isScrubbing ? horizontalOffset(for: distance) : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(WanderTheme.surfaceRaised.color.opacity(isScrubbing ? 0.96 : 0.58))
                    .shadow(
                        color: WanderTheme.textInk.color.opacity(isScrubbing ? 0.10 : 0),
                        radius: 6,
                        x: -2,
                        y: 2
                    )
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        isScrubbing = true
                        updateSelection(at: value.location.y, height: geometry.size.height)
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.16)) {
                            isScrubbing = false
                        }
                    }
            )
        }
        .frame(width: WanderTheme.tapMinimum, height: 324)
        .accessibilityElement()
        .accessibilityLabel("Contact index")
        .accessibilityValue(letters[selectedIndex])
        .accessibilityHint("Swipe up or down to jump through contact sections")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                selectedIndex = min(selectedIndex + 1, letters.count - 1)
            case .decrement:
                selectedIndex = max(selectedIndex - 1, 0)
            @unknown default:
                return
            }
            onSelect(letters[selectedIndex])
        }
    }

    private func updateSelection(at yPosition: CGFloat, height: CGFloat) {
        guard !letters.isEmpty, height > 0 else { return }
        guard let nextIndex = InviteAlphabetIndex.index(
            yPosition: yPosition,
            height: height,
            itemCount: letters.count
        ) else { return }
        guard nextIndex != selectedIndex else { return }

        selectedIndex = nextIndex
        UISelectionFeedbackGenerator().selectionChanged()
        onSelect(letters[nextIndex])
    }

    private func magnification(for distance: Int) -> CGFloat {
        switch distance {
        case 0: 2.15
        case 1: 1.72
        case 2: 1.38
        case 3: 1.16
        default: 1
        }
    }

    private func horizontalOffset(for distance: Int) -> CGFloat {
        switch distance {
        case 0: -14
        case 1: -10
        case 2: -6
        case 3: -3
        default: 0
        }
    }
}
