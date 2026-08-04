import SwiftUI

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

    let surface: InviteSurface
    let contacts: [InviteContact]
    let canDismiss: Bool

    @State private var accessState: ContactInviteAccessState
    @State private var presentationState: ContactInvitePresentationState
    @State private var query: String
    @State private var selection: InviteSelection

    init(
        surface: InviteSurface,
        contacts: [InviteContact],
        accessState: ContactInviteAccessState = .authorized,
        presentationState: ContactInvitePresentationState = .choosing,
        selectedContactIDs: Set<String> = [],
        query: String = "",
        canDismiss: Bool = true
    ) {
        self.surface = surface
        self.contacts = contacts
        self.canDismiss = canDismiss
        _accessState = State(initialValue: accessState)
        _presentationState = State(initialValue: presentationState)
        _query = State(initialValue: query)
        _selection = State(initialValue: InviteSelection(contactIDs: selectedContactIDs))
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
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(surface.sheetTitle)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                if presentationState == .choosing && accessState == .authorized {
                    Text("\(selection.count)/20")
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
                        withAnimation(.easeInOut(duration: 0.22)) {
                            presentationState = .completed
                        }
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
            searchField

            if sections.isEmpty {
                emptyResults
            } else {
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
                                }
                            }
                        }
                        .padding(.horizontal, WanderTheme.spacing3)
                        .padding(.trailing, WanderTheme.spacing2)
                        .padding(.bottom, WanderTheme.spacing8)
                    }
                    .scrollDismissesKeyboard(.interactively)

                    alphabetIndex
                        .padding(.trailing, 3)
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
                        .frame(width: 32, height: 32)
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
            withAnimation(.easeInOut(duration: 0.15)) {
                selection.toggle(contact.id)
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
                .frame(width: 25, height: 25)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(contact.displayName)
        .accessibilityValue(selection.contains(contact.id) ? "Selected" : "Not selected")
    }

    private var alphabetIndex: some View {
        VStack(spacing: 0) {
            ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#").map(String.init), id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(height: 12)
            }
        }
        .accessibilityHidden(true)
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
                withAnimation(.easeInOut(duration: 0.22)) {
                    accessState = .authorized
                }
            } label: {
                Text("continue to contacts")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

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

            Button("open settings") {}
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.textOnAction.color)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(WanderTheme.terracotta.color)
                .clipShape(Capsule())

            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    presentationState = .completed
                }
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
                Text(surface.completionTitle)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(completionMessage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Nothing is added or attributed until each person accepts.")
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

    private var completionMessage: String {
        if selection.count == 0 {
            return "Use the native share sheet to send the right link in the app you prefer."
        }
        return "Choose how to share with \(selection.count) selected \(selection.count == 1 ? "person" : "people")."
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
}
