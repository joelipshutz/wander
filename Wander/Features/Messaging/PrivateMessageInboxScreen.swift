import SwiftUI

/// Embed in the host NavigationStack. The host supplies its authenticated
/// viewer ID and repository; changing that ID invalidates all visible state.
struct PrivateMessageInboxScreen: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var state = PrivateMessageInboxState()
    let userID: String
    let repository: (any PrivateMessageRepository)?
    var analytics: any AnalyticsClient = NoopAnalyticsClient()
    var onOpenContext: ((PrivateMessageContext) -> Void)?
    var onOpenProfile: ((String) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Messages").font(AstirTypography.screenTitle).foregroundStyle(brand.primaryText)
                    Label("Private · between mutual friends", systemImage: "lock.fill")
                        .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                }
                if (repository as? any PrivateMessageSimulationIdentifying)?.isSimulation == true {
                    PrivateMessagingSimulationLabel()
                }
                if state.isLoading && state.conversations.isEmpty {
                    ProgressView("Loading conversations…")
                        .font(AstirTypography.bodySmall)
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .accessibilityIdentifier("messaging.inbox.loading")
                } else if state.failed {
                    PrivateMessagingNotice(symbol: "bubble.left.and.exclamationmark.bubble.right",
                                           title: "Couldn’t load messages",
                                           detail: "Try again when you’re connected. Only conversations you can still access will appear.",
                                           actionTitle: "Try again", action: refresh)
                } else if state.hasLoaded && state.conversations.isEmpty {
                    PrivateMessagingNotice(symbol: "bubble.left.and.bubble.right",
                                           title: "Start with a place",
                                           detail: "Reply privately to an activity from a mutual friend. Your conversations will appear here.")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(state.conversations) { conversation in
                            NavigationLink {
                                PrivateMessageThreadScreen(userID: userID, repository: repository,
                                                           target: .conversation(conversation.id),
                                                           analytics: analytics, analyticsSurface: .messages,
                                                           onOpenContext: onOpenContext, onOpenProfile: onOpenProfile)
                            } label: {
                                PrivateConversationRow(conversation: conversation)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("messaging.conversation.\(conversation.id.uuidString)")
                            Divider().overlay(brand.border.opacity(0.2))
                        }
                    }
                    if state.nextCursor != nil {
                        Button {
                            Task { await state.loadMore(userID: userID, repository: repository) }
                        } label: {
                            HStack {
                                if state.isLoadingMore { ProgressView() }
                                Text(state.isLoadingMore ? "Loading…" : "More conversations")
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .font(AstirTypography.control).foregroundStyle(brand.accentText)
                        .disabled(state.isLoadingMore || state.isLoading)
                        .accessibilityIdentifier("messaging.inbox.more")
                    }
                }
            }.padding(22)
        }
        .background(brand.background.ignoresSafeArea())
        .navigationTitle("Messages").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: refresh) { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .foregroundStyle(brand.accentText).disabled(state.isLoading)
                    .accessibilityLabel("Refresh messages").accessibilityIdentifier("messaging.inbox.refresh")
            }
        }
        .refreshable { await state.refresh(userID: userID, repository: repository) }
        .task(id: "\(userID)|\(scenePhase == .active)") {
            state.reset(for: userID)
            guard scenePhase == .active else { return }
            await state.refresh(userID: userID, repository: repository)
        }
        .onChange(of: userID) { _, newID in state.reset(for: newID) }
        .modifier(PrivateMessagingInactiveCover())
    }

    private func refresh() { Task { await state.refresh(userID: userID, repository: repository) } }
}

private struct PrivateConversationRow: View {
    @Environment(\.astirBrandMode) private var brand
    let conversation: PrivateConversationSummary

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            WanderAvatar(initials: initials, avatarURL: conversation.participant.avatarURL?.absoluteString, size: 46)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(conversation.participant.displayName)
                        .font(AstirTypography.cardTitle).foregroundStyle(brand.primaryText)
                    Spacer(minLength: 0)
                    if let date = conversation.lastMessageAt {
                        Text(date, style: .relative).font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                    }
                }
                Text(conversation.lastMessagePreview ?? "No messages yet")
                    .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText).lineLimit(2)
            }
            if conversation.unreadCount > 0 {
                Circle().fill(brand.accent).frame(width: 8, height: 8).padding(.top, 7).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(.vertical, 16).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(conversation.unreadCount > 0 ? "\(conversation.unreadCount) unread messages" : "No unread messages")
        .accessibilityHint("Opens your private conversation")
        .sessionReplayMasked()
    }

    private var initials: String {
        String(conversation.participant.displayName.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)).uppercased()
    }
}
