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

struct ContactInvitePrimaryActionState: Equatable {
    let title: String
    let isEnabled: Bool
    let isSubdued: Bool

    static func resolve(
        selectionCount: Int,
        walkthroughSelectionGoal: Int?,
        defaultTitle: String
    ) -> ContactInvitePrimaryActionState {
        if let walkthroughSelectionGoal {
            return ContactInvitePrimaryActionState(
                title: "Next",
                isEnabled: true,
                isSubdued: selectionCount < walkthroughSelectionGoal
            )
        }

        if selectionCount == 0 {
            return ContactInvitePrimaryActionState(
                title: defaultTitle,
                isEnabled: false,
                isSubdued: true
            )
        }

        return ContactInvitePrimaryActionState(
            title: defaultTitle,
            isEnabled: selectionCount > 0,
            isSubdued: false
        )
    }
}

struct InviteEntryPointButton: View {
    @Environment(\.astirBrandMode) private var brandMode
    let surface: InviteSurface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                ZStack {
                    Circle()
                        .fill(brandMode.accentWash)
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(brandMode.accentText)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(surface.entryTitle)
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(brandMode.primaryText)
                    Text(surface.entrySubtitle)
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: WanderTheme.spacing2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(brandMode.accentText)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.vertical, WanderTheme.spacing2)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(brandMode.raisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                    .stroke(brandMode.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(surface.entryTitle)
        .accessibilityHint(surface.entrySubtitle)
    }
}

struct ContactInviteSheet: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    let surface: InviteSurface
    let contactProvider: (any ContactProvider)?
    let senderProfileID: String?
    let canDismiss: Bool
    let walkthroughSelectionGoal: Int?
    let onWalkthroughDismiss: (() -> Void)?
    let onPermissionDenied: (() -> Void)?
    let onWalkthroughSelectionChange: ((Set<String>) -> Void)?
    let analytics: AnalyticsClient

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
        onWalkthroughDismiss: (() -> Void)? = nil,
        onPermissionDenied: (() -> Void)? = nil,
        onWalkthroughSelectionChange: ((Set<String>) -> Void)? = nil,
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.surface = surface
        contactProvider = nil
        self.senderProfileID = senderProfileID
        self.canDismiss = canDismiss
        self.walkthroughSelectionGoal = walkthroughSelectionGoal
        self.onWalkthroughDismiss = onWalkthroughDismiss
        self.onPermissionDenied = onPermissionDenied
        self.onWalkthroughSelectionChange = onWalkthroughSelectionChange
        self.analytics = analytics
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
        onWalkthroughDismiss: (() -> Void)? = nil,
        onPermissionDenied: (() -> Void)? = nil,
        selectedContactIDs: Set<String> = [],
        onWalkthroughSelectionChange: ((Set<String>) -> Void)? = nil,
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.surface = surface
        self.contactProvider = contactProvider
        self.senderProfileID = senderProfileID
        self.canDismiss = canDismiss
        self.walkthroughSelectionGoal = walkthroughSelectionGoal
        self.onWalkthroughDismiss = onWalkthroughDismiss
        self.onPermissionDenied = onPermissionDenied
        self.onWalkthroughSelectionChange = onWalkthroughSelectionChange
        self.analytics = analytics
        _contacts = State(initialValue: [])
        _accessState = State(initialValue: .primer)
        _presentationState = State(initialValue: .choosing)
        _query = State(initialValue: "")
        _selection = State(initialValue: InviteSelection(contactIDs: selectedContactIDs))
    }

    private var sections: [InviteContactSection] {
        InviteContactSection.sections(for: contacts, query: query)
    }

    private var primaryActionState: ContactInvitePrimaryActionState {
        ContactInvitePrimaryActionState.resolve(
            selectionCount: selection.count,
            walkthroughSelectionGoal: walkthroughSelectionGoal,
            defaultTitle: surface.primaryActionTitle
        )
    }

    private var isWalkthroughMode: Bool {
        walkthroughSelectionGoal != nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            brandMode.background
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
            .background(brandMode.raisedBackground)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
            .padding(.top, WanderTheme.spacing2)
        }
        .foregroundStyle(brandMode.primaryText)
        .tint(brandMode.accent)
        .task {
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.contactInviteSheetOpened,
                    properties: ["surface": surface.analyticsValue]
                )
            )
            await refreshProviderState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, contactProvider != nil else { return }
            Task { await refreshProviderState() }
        }
        .onChange(of: selection) { _, selection in
            onWalkthroughSelectionChange?(selection.contactIDs)
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
                guard completed else {
                    trackInviteCompletion(
                        outcome: "cancelled",
                        deliveryMode: "share_sheet",
                        sentCount: 0
                    )
                    return
                }
                completeDelivery(
                    headline: selection.count == 1 ? "invite shared" : "invites shared",
                    detail: "The TestFlight link was handed off successfully.",
                    deliveryMode: "share_sheet",
                    sentCount: selection.count
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
                    .font(AstirTypography.sheetTitle)
                    .foregroundStyle(brandMode.primaryText)
                if presentationState == .choosing && accessState == .authorized {
                    Text("\(selection.count)/\(walkthroughSelectionGoal ?? InviteSelection.maximumCount)")
                        .font(AstirTypography.metadata)
                        .foregroundStyle(brandMode.secondaryText)
                        .monospacedDigit()
                }
            }

            HStack {
                if canDismiss {
                    Button {
                        onWalkthroughDismiss?()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(brandMode.primaryText)
                            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                            .background(brandMode.recessedBackground)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(brandMode.border, lineWidth: 1)
                            }
                            .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        onWalkthroughDismiss == nil ? "Close" : "Dismiss walkthrough"
                    )
                    .accessibilityIdentifier(
                        onWalkthroughDismiss == nil
                            ? "invite.close"
                            : "walkthrough.dismiss.contactInvite"
                    )
                }

                Spacer()

                if presentationState == .choosing && accessState == .authorized {
                    Button {
                        if isWalkthroughMode {
                            dismiss()
                        } else {
                            beginInviteDelivery()
                        }
                    } label: {
                        Text(primaryActionState.title)
                            .font(AstirTypography.control)
                            .foregroundStyle(
                                primaryActionState.isSubdued
                                    ? brandMode.secondaryText
                                    : brandMode.accentForeground
                            )
                            .padding(.horizontal, WanderTheme.spacing3)
                            .frame(minWidth: 64, minHeight: WanderTheme.tapMinimum)
                            .background(
                                primaryActionState.isSubdued
                                    ? brandMode.recessedBackground
                                    : brandMode.accent
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: WanderTheme.radiusMedium,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                if primaryActionState.isSubdued {
                                    RoundedRectangle(
                                        cornerRadius: WanderTheme.radiusMedium,
                                        style: .continuous
                                    )
                                    .stroke(brandMode.border, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!primaryActionState.isEnabled)
                    .accessibilityIdentifier("invite.primaryAction")
                    .accessibilityLabel(primaryActionState.title)
                    .accessibilityHint(
                        isWalkthroughMode
                            ? "Continues the walkthrough"
                            : (primaryActionState.isSubdued
                                ? "Select at least one person to invite"
                                : "Invites the selected people")
                    )
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
                                            .font(AstirTypography.label)
                                            .foregroundStyle(brandMode.secondaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, WanderTheme.spacing1)
                                            .background(brandMode.raisedBackground)
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
                .foregroundStyle(brandMode.secondaryText)

            TextField("Name, number, or @username", text: $query)
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brandMode.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(brandMode.secondaryText.opacity(0.75))
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 48)
        .background(brandMode.recessedBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: WanderTheme.radiusMedium,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: WanderTheme.radiusMedium,
                style: .continuous
            )
            .stroke(brandMode.border, lineWidth: 1)
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
                        .overlay(brandMode.border.opacity(0.72))
                        .padding(.leading, 58)
                }
            }
        }
        .padding(.horizontal, WanderTheme.spacing2)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                .stroke(brandMode.border.opacity(0.75), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func contactRow(_ contact: InviteContact) -> some View {
        if let walkthroughSelectionGoal {
            walkthroughContactRow(contact, goal: walkthroughSelectionGoal)
        } else {
            standardContactRow(contact)
        }
    }

    private func standardContactRow(_ contact: InviteContact) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                _ = selection.toggle(contact.id)
            }
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                contactIdentity(contact)

                Spacer(minLength: WanderTheme.spacing1)

                ZStack {
                    Circle()
                        .fill(selection.contains(contact.id) ? brandMode.accent : Color.clear)
                    Circle()
                        .stroke(
                            selection.contains(contact.id) ? brandMode.accent : brandMode.border,
                            lineWidth: 2
                        )
                    if selection.contains(contact.id) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(brandMode.accentForeground)
                    }
                }
                .frame(width: 25, height: 25)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(contactAccessibilityLabel(for: contact))
        .accessibilityValue(selection.contains(contact.id) ? "Selected" : "Not selected")
        .accessibilityHint(
            selection.contains(contact.id) ? "Double-tap to deselect" : "Double-tap to select"
        )
    }

    private func walkthroughContactRow(_ contact: InviteContact, goal: Int) -> some View {
        let isSent = selection.contains(contact.id)
        let canInvite = ContactInviteWalkthroughProgressReducer.canInvite(
            contactID: contact.id,
            state: selection,
            goal: goal
        )

        return HStack(spacing: WanderTheme.spacing3) {
            contactIdentity(contact)

            Spacer(minLength: WanderTheme.spacing1)

            Button {
                beginWalkthroughInviteDelivery(for: contact)
            } label: {
                Text(isSent ? "Sent" : "Add")
                    .font(AstirTypography.label)
                    .foregroundStyle(
                        isSent
                            ? WanderTheme.stateSuccess.color
                            : (canInvite
                                ? brandMode.accentForeground
                                : brandMode.secondaryText)
                    )
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minWidth: 62, minHeight: WanderTheme.tapMinimum)
                    .background(
                        isSent
                            ? WanderTheme.stateSuccess.color.opacity(0.12)
                            : (canInvite
                                ? brandMode.accent
                                : brandMode.recessedBackground)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusMedium,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusMedium,
                            style: .continuous
                        )
                        .stroke(
                            isSent
                                ? WanderTheme.stateSuccess.color.opacity(0.5)
                                : (canInvite ? Color.clear : brandMode.border),
                            lineWidth: 1
                        )
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canInvite)
            .accessibilityIdentifier("invite.contactAdd.\(contact.id)")
            .accessibilityLabel(isSent ? "Invitation sent to \(contact.displayName)" : "Invite \(contact.displayName)")
            .accessibilityValue(isSent ? "Sent" : "Not sent")
            .accessibilityHint(canInvite ? "Opens a text invitation" : "")
        }
        .frame(minHeight: 56)
    }

    private func contactIdentity(_ contact: InviteContact) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            Text(contact.initials)
                .font(AstirTypography.label)
                .foregroundStyle(avatarForeground(for: contact))
                .frame(width: 40, height: 40)
                .background(avatarBackground(for: contact))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: WanderTheme.spacing1) {
                    Text(contact.displayName)
                        .font(AstirTypography.control)
                        .foregroundStyle(brandMode.primaryText)
                        .lineLimit(1)

                    if contact.relationship.isOnRecme {
                        Text("on rec.me")
                            .font(AstirTypography.metadata)
                            .foregroundStyle(brandMode.accentText)
                            .scaleEffect(0.82)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(brandMode.accentWash)
                            .clipShape(Capsule())
                    }
                }

                if let detail = rowDetail(for: contact) {
                    Text(detail)
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(1)
                }
            }
        }
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
                    .fill(brandMode.accentWash)
                    .frame(width: 104, height: 104)
                Image(systemName: "person.2.crop.square.stack.fill")
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(brandMode.accentText)
            }

            VStack(spacing: WanderTheme.spacing2) {
                Text("find your people")
                    .font(AstirTypography.screenTitle)
                    .foregroundStyle(brandMode.primaryText)
                Text(surface.permissionMessage)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: WanderTheme.spacing2) {
                permissionPromise(icon: "checkmark.shield.fill", text: "You choose who gets an invite")
                permissionPromise(icon: "paperplane.fill", text: "rec.me never messages contacts for you")
                permissionPromise(icon: "lock.fill", text: "Contact details stay out of analytics")
            }
            .padding(WanderTheme.spacing3)
            .background(brandMode.recessedBackground)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                    .stroke(brandMode.border, lineWidth: 1)
            }

            Button {
                Task { await requestContactsAccess() }
            } label: {
                Group {
                    if isLoadingContacts {
                        ProgressView()
                            .tint(brandMode.accentForeground)
                    } else {
                        Text("continue to contacts")
                    }
                }
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.accentForeground)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(brandMode.accent)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: WanderTheme.radiusMedium,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoadingContacts)

            Button("not now") {
                if canDismiss { dismiss() }
            }
            .font(AstirTypography.control)
            .foregroundStyle(brandMode.secondaryText)
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
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.primaryText)
            Spacer()
        }
    }

    private var deniedContent: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(brandMode.accentText)

            VStack(spacing: WanderTheme.spacing2) {
                Text("contacts are off")
                    .font(AstirTypography.screenTitle)
                    .foregroundStyle(brandMode.primaryText)
                Text("Turn on Contacts in Settings to browse your address book, or share a rec.me link instead.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("open settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.accentForeground)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(brandMode.accent)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: WanderTheme.radiusMedium,
                        style: .continuous
                    )
                )

            Button {
                trackInviteDeliveryStarted(mode: "share_sheet", recipientCount: 0)
                sharePresentation = InviteSharePresentation(content: inviteShareContent)
            } label: {
                Label("share an invite link", systemImage: "square.and.arrow.up")
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(brandMode.recessedBackground)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusMedium,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusMedium,
                            style: .continuous
                        )
                        .stroke(brandMode.border, lineWidth: 1)
                    }
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
                .foregroundStyle(brandMode.secondaryText.opacity(0.72))
            Text("no contacts found")
                .font(AstirTypography.sectionTitle)
                .foregroundStyle(brandMode.primaryText)
            Text("Try another name, number, or username.")
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brandMode.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingContacts: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Spacer()
            ProgressView()
                .tint(brandMode.accent)
            Text("loading contacts")
                .font(AstirTypography.cardTitle)
                .foregroundStyle(brandMode.primaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedContacts: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Spacer()
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 42, weight: .black))
                .foregroundStyle(brandMode.accentText)
            Text("contacts couldn’t load")
                .font(AstirTypography.sectionTitle)
                .foregroundStyle(brandMode.primaryText)
            Button("try again") {
                Task { await loadContacts() }
            }
            .font(AstirTypography.control)
            .foregroundStyle(brandMode.accentForeground)
            .padding(.horizontal, WanderTheme.spacing4)
            .frame(minHeight: WanderTheme.tapMinimum)
            .background(brandMode.accent)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: WanderTheme.radiusMedium,
                    style: .continuous
                )
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completionContent: some View {
        VStack(spacing: WanderTheme.spacing4) {
            Spacer()

            ZStack {
                Circle()
                    .fill(brandMode.accentWash)
                    .frame(width: 108, height: 108)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 43, weight: .black))
                    .foregroundStyle(brandMode.accentText)
                    .offset(x: -3, y: 2)
            }

            VStack(spacing: WanderTheme.spacing2) {
                Text(completionHeadline ?? surface.completionTitle)
                    .font(AstirTypography.screenTitle)
                    .foregroundStyle(brandMode.primaryText)
                Text(completionDetail ?? "The TestFlight invitation was shared.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("If they follow you, tap their follow notification to open their profile and follow back.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.primaryText)
                .multilineTextAlignment(.center)
                .padding(WanderTheme.spacing3)
                .background(brandMode.accentWash)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                        .stroke(brandMode.accent.opacity(0.32), lineWidth: 1)
                }

            Button {
                if canDismiss { dismiss() }
            } label: {
                Text("done")
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.accentForeground)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(brandMode.accent)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: WanderTheme.radiusMedium,
                            style: .continuous
                        )
                    )
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
        if contact.relationship.isOnRecme { return brandMode.accentWash }
        let palette = [
            brandMode.accentWash,
            WanderTheme.sunTint.color,
            brandMode.recessedBackground,
            WanderTheme.avatarSofia.color.opacity(0.24)
        ]
        let value = contact.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[value % palette.count]
    }

    private func avatarForeground(for contact: InviteContact) -> Color {
        contact.relationship.isOnRecme ? brandMode.accent : brandMode.primaryText
    }

    private var inviteShareContent: WanderShareContent {
        WanderShareContent.appInvite(
            senderProfileID: senderProfileID,
            contextMessage: isWalkthroughMode
                ? ContactInviteWalkthroughContent.inviteProse
                : surface.inviteMessage,
            includeInstallPrompt: !isWalkthroughMode
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
            trackInviteDeliveryStarted(mode: "share_sheet", recipientCount: recipients.count)
            sharePresentation = InviteSharePresentation(content: inviteShareContent)
            return
        }

        trackInviteDeliveryStarted(mode: "messages", recipientCount: recipients.count)
        messageDeliveryPlan = InviteMessageDeliveryPlan(contacts: recipients)
        presentNextMessageComposer()
    }

    private func beginWalkthroughInviteDelivery(for contact: InviteContact) {
        guard let walkthroughSelectionGoal,
              ContactInviteWalkthroughProgressReducer.canInvite(
                contactID: contact.id,
                state: selection,
                goal: walkthroughSelectionGoal
              ),
              let recipient = contact.contactDetail,
              isLikelyPhoneNumber(recipient)
        else { return }

        guard MFMessageComposeViewController.canSendText() else {
            deliveryErrorMessage = "Messages are not available on this device. Try again on an iPhone that can send texts."
            return
        }

        trackInviteDeliveryStarted(mode: "messages", recipientCount: 1)
        messageDeliveryPlan = InviteMessageDeliveryPlan(contacts: [contact])
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
                    : "The TestFlight link was sent to \(sentCount) people in Messages.",
                deliveryMode: "messages",
                sentCount: sentCount
            )
            return
        }
        messageRecipient = recipient
        isPresentingMessageComposer = true
    }

    private func handleMessageComposerResult(_ result: MessageComposeResult) {
        isPresentingMessageComposer = false
        messageRecipient = nil

        if isWalkthroughMode {
            handleWalkthroughMessageComposerResult(result)
            return
        }

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
            trackInviteCompletion(
                outcome: "cancelled",
                deliveryMode: "messages",
                sentCount: messageDeliveryPlan?.sentCount ?? 0
            )
            messageDeliveryPlan?.cancelRemaining()
            messageDeliveryPlan = nil
        case .failed:
            trackInviteCompletion(
                outcome: "failed",
                deliveryMode: "messages",
                sentCount: messageDeliveryPlan?.sentCount ?? 0
            )
            messageDeliveryPlan?.cancelRemaining()
            messageDeliveryPlan = nil
            deliveryErrorMessage = "Messages could not send this invitation. Try again."
        @unknown default:
            trackInviteCompletion(
                outcome: "failed",
                deliveryMode: "messages",
                sentCount: messageDeliveryPlan?.sentCount ?? 0
            )
            messageDeliveryPlan?.cancelRemaining()
            messageDeliveryPlan = nil
            deliveryErrorMessage = "Messages returned an unknown result. Try again."
        }
    }

    private func handleWalkthroughMessageComposerResult(_ result: MessageComposeResult) {
        guard let walkthroughSelectionGoal,
              let contactID = messageDeliveryPlan?.currentContact?.id
        else {
            messageDeliveryPlan = nil
            return
        }

        let outcome: ContactInviteWalkthroughComposerOutcome
        let analyticsOutcome: String
        let errorMessage: String?
        switch result {
        case .sent:
            // MessageUI's `.sent` is only a successful handoff from the
            // composer. It does not confirm carrier delivery or acceptance.
            outcome = .sent
            analyticsOutcome = "sent"
            errorMessage = nil
        case .cancelled:
            outcome = .cancelled
            analyticsOutcome = "cancelled"
            errorMessage = nil
        case .failed:
            outcome = .failed
            analyticsOutcome = "failed"
            errorMessage = "Messages could not send this invitation. Try again."
        @unknown default:
            outcome = .failed
            analyticsOutcome = "failed"
            errorMessage = "Messages returned an unknown result. Try again."
        }

        let nextSelection = ContactInviteWalkthroughProgressReducer.reduce(
            state: selection,
            action: .messageComposerFinished(contactID: contactID, outcome: outcome),
            goal: walkthroughSelectionGoal
        )
        let didAdvance = nextSelection.count > selection.count
        if didAdvance {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.76)) {
                selection = nextSelection
            }
        }

        if outcome != .sent || didAdvance {
            trackInviteCompletion(
                outcome: analyticsOutcome,
                deliveryMode: "messages",
                sentCount: didAdvance ? 1 : 0
            )
        }
        messageDeliveryPlan?.cancelRemaining()
        messageDeliveryPlan = nil
        deliveryErrorMessage = errorMessage
    }

    private func completeDelivery(
        headline: String,
        detail: String,
        deliveryMode: String,
        sentCount: Int
    ) {
        trackInviteCompletion(
            outcome: "sent",
            deliveryMode: deliveryMode,
            sentCount: sentCount
        )
        completionHeadline = headline
        completionDetail = detail
        withAnimation(.easeInOut(duration: 0.22)) {
            presentationState = .completed
        }
    }

    private func trackInviteDeliveryStarted(mode: String, recipientCount: Int) {
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.contactInviteDeliveryStarted,
                properties: [
                    "surface": surface.analyticsValue,
                    "delivery_mode": mode,
                    "recipient_count": "\(recipientCount)"
                ]
            )
        )
    }

    private func trackInviteCompletion(outcome: String, deliveryMode: String, sentCount: Int) {
        let properties = [
            "surface": surface.analyticsValue,
            "delivery_mode": deliveryMode,
            "outcome": outcome,
            "sent_count": "\(sentCount)"
        ]
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.contactInviteCompleted,
                properties: properties
            )
        )
        if sentCount > 0 {
            analytics.track(
                .engagement(
                    need: .connect,
                    action: .contactInviteSent,
                    surface: surface.analyticsValue,
                    properties: [
                        "delivery_mode": deliveryMode,
                        "sent_count": "\(sentCount)"
                    ]
                )
            )
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
    @Environment(\.astirBrandMode) private var brandMode
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
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(brandMode.primaryText)
                    Text(
                        isComplete
                            ? "Nice. Their saves can make every search more useful."
                            : "Pick up to five people whose taste you already trust. Fewer is fine too."
                    )
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
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
                                    : brandMode.raisedBackground
                            )
                        Circle()
                            .stroke(
                                index < completedCount
                                    ? WanderTheme.stateSuccess.color
                                    : brandMode.border,
                                lineWidth: 2
                            )
                        if index < completedCount {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(brandMode.accentForeground)
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
                : brandMode.accentWash
        )
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                .stroke(
                    isComplete
                        ? WanderTheme.stateSuccess.color.opacity(0.55)
                        : brandMode.accent.opacity(0.3),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completedCount) of \(goal) invitations sent")
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
    @Environment(\.astirBrandMode) private var brandMode
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
                        .foregroundStyle(brandMode.accentText)
                        .scaleEffect(scale)
                        .offset(x: isScrubbing ? horizontalOffset(for: distance) : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(brandMode.raisedBackground.opacity(isScrubbing ? 0.96 : 0.58))
                    .shadow(
                        color: Color.black.opacity(isScrubbing ? 0.10 : 0),
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
