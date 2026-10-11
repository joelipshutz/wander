import SwiftUI

/// Works as a NavigationStack destination or inside a presented NavigationStack.
/// `reply` starts/resolves a server-authorized mutual-friend conversation; it
/// does not send anything until the explicit Send action.
struct PrivateMessageThreadScreen: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var state: PrivateMessageThreadState
    @FocusState private var composerFocused: Bool
    let userID: String
    let repository: (any PrivateMessageRepository)?
    let target: PrivateMessageThreadTarget
    var onOpenContext: ((PrivateMessageContext) -> Void)?
    var onOpenProfile: ((String) -> Void)?

    init(userID: String, repository: (any PrivateMessageRepository)?, target: PrivateMessageThreadTarget,
         analytics: any AnalyticsClient = NoopAnalyticsClient(), analyticsSurface: PrivateMessageAnalyticsSurface = .live,
         onOpenContext: ((PrivateMessageContext) -> Void)? = nil,
         onOpenProfile: ((String) -> Void)? = nil) {
        self.userID = userID; self.repository = repository; self.target = target; self.onOpenContext = onOpenContext
        self.onOpenProfile = onOpenProfile
        let isSimulation = (repository as? any PrivateMessageSimulationIdentifying)?.isSimulation == true
        _state = StateObject(wrappedValue: PrivateMessageThreadState(analytics: isSimulation ? NoopAnalyticsClient() : analytics,
                                                                    analyticsSurface: analyticsSurface))
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSimulation {
                PrivateMessagingSimulationLabel().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.top, 12)
            }
            if let conversation = state.conversation {
                PrivateMessagingPersonLabel(name: conversation.participant.displayName,
                                            avatarURL: conversation.participant.avatarURL?.absoluteString)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.vertical, 14)
                Divider().overlay(brand.border.opacity(0.2))
            }
            transcript
        }
        .background(brand.background.ignoresSafeArea())
        .navigationTitle("Private reply").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let conversation = state.conversation, let onOpenProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { onOpenProfile(conversation.participant.id) } label: {
                            Label("View profile", systemImage: "person.crop.circle")
                        }.accessibilityHint("Open profile actions, including Block and Report")
                            .accessibilityIdentifier("messaging.profile")
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.foregroundStyle(brand.accentText)
                        .accessibilityLabel("Conversation actions")
                        .accessibilityIdentifier("messaging.actions")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: refresh) { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .foregroundStyle(brand.accentText).disabled(state.isLoading)
                    .accessibilityLabel("Refresh conversation").accessibilityIdentifier("messaging.thread.refresh")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { composerFocused = false }.foregroundStyle(brand.accentText)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if state.conversation != nil && !state.failed { composer }
        }
        .task(id: "\(userID)|\(target.id)|\(scenePhase == .active)") {
            state.reset(userID: userID, target: target)
            guard scenePhase == .active else { return }
            await state.load(userID: userID, target: target, repository: repository)
        }
        .onChange(of: userID) { _, newID in state.reset(userID: newID, target: target) }
        .modifier(PrivateMessagingInactiveCover())
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if state.isLoading && state.conversation == nil {
                        ProgressView("Opening your conversation…").font(AstirTypography.bodySmall)
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .accessibilityIdentifier("messaging.thread.loading")
                    } else if state.failed {
                        PrivateMessagingNotice(symbol: "lock.bubble",
                                               title: "Conversation unavailable",
                                               detail: "Try again when you’re connected. Private replies are available between mutual friends who can still access this conversation.",
                                               actionTitle: "Try again", action: refresh)
                        if state.pending != nil {
                            Text("Your reply is kept here, but sending has not been confirmed. Refresh to check it before retrying.")
                                .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                        }
                    } else if state.conversation != nil {
                        if state.nextCursor != nil {
                            Button {
                                Task { await state.loadEarlier(repository: repository) }
                            } label: {
                                HStack {
                                    if state.isLoadingEarlier { ProgressView() }
                                    Text(state.isLoadingEarlier ? "Loading earlier messages…" : "Earlier messages")
                                }.frame(maxWidth: .infinity, minHeight: 44)
                            }.font(AstirTypography.control).foregroundStyle(brand.accentText)
                                .disabled(state.isLoadingEarlier || state.isLoading)
                                .accessibilityIdentifier("messaging.thread.earlier")
                        }
                        if state.messages.isEmpty && state.pending == nil {
                            PrivateMessagingNotice(symbol: "bubble.left",
                                                   title: "A private conversation starts here",
                                                   detail: "Your reply goes to this person, not the public activity. Nothing is sent until you tap Send.")
                        }
                        ForEach(state.messages) { message in
                            PrivateMessageBubble(message: message, isOwn: message.senderID == userID,
                                                 isSimulation: isSimulation,
                                                 onOpenContext: onOpenContext)
                                .onAppear {
                                    guard message.id == state.messages.last?.id else { return }
                                    Task { await state.markVisibleRead(through: message.id, repository: repository) }
                                }
                        }
                        if let pending = state.pending { pendingBubble(pending) }
                    }
                    Color.clear.frame(height: 1).id("messaging.latest")
                }.padding(22)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await state.load(userID: userID, target: target, repository: repository) }
            .onChange(of: state.messages.last?.id) { _, _ in
                guard !state.isLoadingEarlier else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("messaging.latest", anchor: .bottom) }
            }
            .onChange(of: state.pending?.id) { _, _ in proxy.scrollTo("messaging.latest", anchor: .bottom) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let context = state.replyContext {
                PrivateMessageContextLabel(context: context, onOpen: onOpenContext)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Reply privately…", text: $state.draft, axis: .vertical)
                    .font(AstirTypography.body).foregroundStyle(brand.primaryText)
                    .lineLimit(1...5).focused($composerFocused)
                    .padding(13).frame(minHeight: 48)
                    .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 18))
                    .disabled(state.pending != nil || state.isLoading)
                    .accessibilityLabel("Private message")
                    .accessibilityIdentifier("messaging.composer")
                    .sessionReplayMasked()
                Button {
                    composerFocused = false
                    Task { await state.send(repository: repository) }
                } label: { Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)) }
                    .buttonStyle(PrivateMessagingPrimaryButtonStyle()).disabled(!state.canSend)
                    .accessibilityLabel("Send private message").accessibilityIdentifier("messaging.send")
            }
            HStack(alignment: .top) {
                Label("Only you and this person", systemImage: "lock.fill")
                Spacer(minLength: 12)
                if state.draft.unicodeScalars.count > 1_800 {
                    Text("\(state.draft.unicodeScalars.count)/\(PrivateMessageDraftPolicy.maximumCharacters)")
                        .foregroundStyle(state.draft.unicodeScalars.count > PrivateMessageDraftPolicy.maximumCharacters ? Color.red : brand.secondaryText)
                }
            }.font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
        .background(brand.background)
        .overlay(alignment: .top) { Rectangle().fill(brand.border.opacity(0.2)).frame(height: 0.5) }
    }

    private func pendingBubble(_ pending: PrivatePendingMessage) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(pending.body).font(AstirTypography.body).foregroundStyle(brand.primaryText)
                .padding(15).background(brand.accentWash, in: RoundedRectangle(cornerRadius: 19))
                .sessionReplayMasked()
            HStack(spacing: 8) {
                if pending.status == .sending { ProgressView().controlSize(.small) }
                Text(pending.status == .sending ? "Sending…" : "Not confirmed")
                    .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                if pending.status == .unconfirmed {
                    Button("Retry") { Task { await state.retryPending(repository: repository) } }
                        .font(AstirTypography.control).foregroundStyle(brand.accentText).frame(minHeight: 44)
                        .disabled(state.isLoading).accessibilityIdentifier("messaging.send.retry")
                }
            }
            if pending.status == .unconfirmed {
                Text(state.sendFailure == .rateLimited ? "Please wait a moment before trying again." : "Retry checks the same reply, so it won’t send a duplicate.")
                    .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 28)
    }

    private func refresh() { Task { await state.load(userID: userID, target: target, repository: repository) } }
    private var isSimulation: Bool { (repository as? any PrivateMessageSimulationIdentifying)?.isSimulation == true }
}

private struct PrivateMessageBubble: View {
    @Environment(\.astirBrandMode) private var brand
    let message: PrivateMessage
    let isOwn: Bool
    let isSimulation: Bool
    var onOpenContext: ((PrivateMessageContext) -> Void)?

    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 7) {
            if let context = message.context { PrivateMessageContextLabel(context: context, onOpen: onOpenContext) }
            Text(message.body).font(AstirTypography.body).foregroundStyle(brand.primaryText)
                .textSelection(.enabled)
                .padding(15)
                .background(isOwn ? brand.accentWash : brand.raisedBackground, in: RoundedRectangle(cornerRadius: 19))
            HStack(spacing: 5) {
                if isOwn { Text(isSimulation ? "Simulated" : "Sent") }
                Text(message.sentAt, format: .dateTime.month(.abbreviated).day().hour().minute())
            }.font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
        .padding(isOwn ? .leading : .trailing, 28)
        .accessibilityElement(children: .contain)
        .sessionReplayMasked()
    }
}

struct PrivateMessageContextLabel: View {
    @Environment(\.astirBrandMode) private var brand
    let context: PrivateMessageContext
    var onOpen: ((PrivateMessageContext) -> Void)?

    var body: some View {
        Group {
            if context.title != nil, let onOpen {
                Button { onOpen(context) } label: { label.frame(minHeight: 44, alignment: .leading) }
                    .buttonStyle(.plain).accessibilityHint("Opens the original place or activity")
            } else { label }
        }.sessionReplayMasked()
    }

    private var label: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: context.kind == .activity ? "quote.bubble" : "mappin.and.ellipse").accessibilityHidden(true)
            Text(context.title.map { "About \($0)" } ?? "Original \(context.kind == .activity ? "activity" : "place") unavailable")
                .fixedSize(horizontal: false, vertical: true)
        }.font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
    }
}
