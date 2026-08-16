import SwiftUI

struct AccountSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSessionStore

    let flushCurrentAccount: () -> Void
    let addAccount: () -> Void

    @State private var isManaging = false
    @State private var accountPendingRemoval: AuthSession?
    @State private var showsSignOutAllConfirmation = false

    private var activeUserID: String? {
        auth.state.session?.userID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WanderTheme.spacing4) {
                    accountCard
                    actionsCard

                    if let error = auth.accountManagementError {
                        Text(error)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, WanderTheme.spacing1)
                    }

                    Text("Each account keeps its own map, drafts, photos, and settings on this device.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, WanderTheme.spacing1)
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing3)
            }
            .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isManaging ? "Finish" : "Manage") {
                        withAnimation(.snappy) { isManaging.toggle() }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .disabled(auth.isSwitchingAccount)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            "Remove @\(accountPendingRemoval?.handle ?? "this account") from this device?",
            isPresented: Binding(
                get: { accountPendingRemoval != nil },
                set: { if !$0 { accountPendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: accountPendingRemoval
        ) { account in
            Button("Remove account", role: .destructive) {
                remove(account)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the saved login. Local map data stays isolated on this phone and returns only after this account signs in again.")
        }
        .confirmationDialog(
            "Sign out of all accounts?",
            isPresented: $showsSignOutAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign out all", role: .destructive) {
                flushCurrentAccount()
                Task { try? await auth.signOutAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All saved logins will be removed from rec.me on this device.")
        }
    }

    private var accountCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(auth.availableSessions.enumerated()), id: \.element.id) { index, account in
                accountRow(account)
                if index < auth.availableSessions.count - 1 {
                    Divider()
                        .overlay(WanderTheme.borderHairline.color)
                        .padding(.leading, 70)
                }
            }
        }
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }

    private func accountRow(_ account: AuthSession) -> some View {
        Button {
            guard !isManaging, account.userID != activeUserID else { return }
            flushCurrentAccount()
            Task {
                if await auth.switchAccount(to: account.userID) {
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: WanderTheme.spacing3) {
                AccountSwitcherAvatar(account: account)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName ?? account.handle ?? "rec.me account")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                    if let handle = account.handle {
                        Text("@\(handle)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: WanderTheme.spacing2)

                if isManaging {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .accessibilityHidden(true)
                } else if auth.isSwitchingAccount && account.userID != activeUserID {
                    ProgressView()
                        .tint(WanderTheme.terracotta.color)
                } else if account.userID == activeUserID {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(auth.isSwitchingAccount)
        .accessibilityLabel(accessibilityLabel(for: account))
        .simultaneousGesture(
            TapGesture().onEnded {
                if isManaging {
                    accountPendingRemoval = account
                }
            }
        )
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            Button {
                dismiss()
                addAccount()
            } label: {
                Label("Add account", systemImage: "plus.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, WanderTheme.spacing3)
            }
            .buttonStyle(.plain)

            Divider().overlay(WanderTheme.borderHairline.color)

            Button(role: .destructive) {
                showsSignOutAllConfirmation = true
            } label: {
                Label("Sign out of all accounts", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, WanderTheme.spacing3)
            }
            .buttonStyle(.plain)
        }
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }

    private func remove(_ account: AuthSession) {
        if account.userID == activeUserID {
            flushCurrentAccount()
        }
        Task {
            _ = await auth.removeAccount(userID: account.userID)
        }
    }

    private func accessibilityLabel(for account: AuthSession) -> String {
        let name = account.displayName ?? account.handle ?? "Account"
        if isManaging { return "Remove \(name) from this device" }
        if account.userID == activeUserID { return "\(name), current account" }
        return "Switch to \(name)"
    }
}

private struct AccountSwitcherAvatar: View {
    let account: AuthSession

    private var initials: String {
        let source = account.displayName ?? account.handle ?? "R"
        let words = source.split(separator: " ")
        let characters = words.prefix(2).compactMap(\.first)
        return String(characters).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(WanderTheme.terracottaTint.color)
            Text(initials)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(WanderTheme.terracottaDark.color)
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().stroke(WanderTheme.terracotta.color.opacity(0.3), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
