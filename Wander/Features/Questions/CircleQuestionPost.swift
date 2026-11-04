import SwiftUI
import MapKit

struct CircleQuestionCard: View {
    @Environment(\.astirBrandMode) private var brand
    let question: CircleQuestion
    var showActions = true
    var open: () -> Void = {}
    var like: () -> Void = {}
    var comment: () -> Void = {}
    var share: () -> Void = {}
    var privateReply: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(String(question.author.name.prefix(1)))
                    .font(AstirTypography.cardTitle).frame(width: 38, height: 38)
                    .background(CircleQuestionStyle.lilac.opacity(0.3), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(question.author.name).font(AstirTypography.cardTitle)
                    Text("Asked their circle").font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                }
                Spacer()
                if question.draft.stealth { Image(systemName: "eye.slash").accessibilityLabel("Stealth · Tagged people only") }
                Text("?").font(.system(size: 35, weight: .medium, design: .serif))
                    .foregroundStyle(CircleQuestionStyle.plum).frame(width: 46, height: 46)
                    .background(CircleQuestionStyle.lilac, in: RoundedRectangle(cornerRadius: 13))
                    .rotationEffect(.degrees(8)).accessibilityHidden(true)
            }.padding(.bottom, 22)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(question.draft.headline).font(CircleQuestionStyle.headline)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    if !question.draft.note.isEmpty {
                        Text(question.draft.note).font(AstirTypography.body)
                            .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    }
                    if !question.replies.flatMap(\.places).isEmpty {
                        Label("\(question.replies.flatMap(\.places).count) places recommended", systemImage: "mappin.and.ellipse")
                            .font(AstirTypography.label).foregroundStyle(brand.accentText)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHint("Open the question and recommend places")
            if showActions {
                Divider().padding(.top, 22).padding(.bottom, 6)
                HStack {
                    action(question.liked ? "heart.fill" : "heart", label: "Like", count: question.likes, run: like)
                    Spacer()
                    action("bubble.right", label: "Comment", count: question.replies.count, run: comment)
                    Spacer()
                    action("square.and.arrow.up", label: "Share", run: share)
                    Spacer()
                    action("bubble.left.and.bubble.right", label: "Reply privately", run: privateReply)
                }
            }
        }.padding(22).foregroundStyle(brand.primaryText)
            .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(brand.border.opacity(0.8), lineWidth: 0.8))
    }
    private func action(_ symbol: String, label: String, count: Int = 0, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) { Image(systemName: symbol); if count > 0 { Text("\(count)").font(AstirTypography.caption) } }
                .frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(count > 0 ? "\(count)" : "")
    }
}

struct CircleQuestionPreview: View {
    @Environment(\.astirBrandMode) private var brand
    @ObservedObject var state: CircleQuestionStore
    let draft: CircleQuestionDraft
    let author: CircleQuestionPerson
    let posted: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Ready for your circle?").font(.system(.largeTitle, design: .serif).weight(.semibold))
                CircleQuestionCard(question: .init(draft: draft, author: author, createdAt: .now,
                    expiresAt: .now.addingTimeInterval(Double(draft.days) * 86400)), showActions: false)
                Label(draft.stealth ? "Only you and \(draft.recipientIDs.count) tagged people" : "Visible to all your followers",
                      systemImage: draft.stealth ? "eye.slash" : "person.2")
                    .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                if let message = state.message { Text(message).font(AstirTypography.bodySmall).foregroundStyle(brand.accentText) }
                CircleQuestionAction(title: state.isBusy ? "Posting…" : "Post question", disabled: state.isBusy) {
                    Task { if await state.perform(event: .posted, requestID: draft.id, { try await $0.publish(draft) }) { posted() } }
                }
            }.padding(22)
        }.astirScreen().navigationTitle("Preview").navigationBarTitleDisplayMode(.inline)
    }
}

struct CircleQuestionDetail: View {
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var store: WanderStore
    @Environment(\.astirBrandMode) private var brand
    @ObservedObject var state: CircleQuestionStore
    let initial: CircleQuestion
    var initialAction = "open"
    @FocusState private var commentFocused: Bool
    @State private var recommend = false
    @State private var comment = ""
    @State private var commentID = UUID()
    @State private var privateReply = false
    @State private var share = false
    @State private var handledInitialAction = false
    private var question: CircleQuestion { state.items.first { $0.id == initial.id } ?? initial }
    var body: some View {
        Group {
            if state.items.contains(where: { $0.id == initial.id }), !store.isBlockedBetweenCurrentUser(and: initial.author.id) { content }
            else { ContentUnavailableView("Question unavailable", systemImage: "lock.bubble", description: Text("You may no longer have access to this question.")) }
        }.task(id: initial.id) { _ = await state.refreshQuestion(id: initial.id) }
    }
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CircleQuestionCard(question: question, open: { recommend = true }, like: {
                    Task { _ = await state.perform { try await $0.setLike(questionID: question.id, liked: !question.liked) } }
                }, comment: { commentFocused = true }, share: { share = true }, privateReply: { privateReply = true })
                CircleQuestionAction(title: "Recommend places") { recommend = true }
                HStack(alignment: .firstTextBaseline) {
                    Text("Local knowledge").font(AstirTypography.sheetTitle)
                    Spacer(); Text("\(question.replies.flatMap(\.places).count) places").font(AstirTypography.caption)
                }
                if question.replies.isEmpty {
                    Text("Know just the spot? Be the first to put a place on their radar.")
                        .font(AstirTypography.body).foregroundStyle(brand.secondaryText).padding(.vertical, 12)
                }
                ForEach(question.replies) { reply in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(reply.author.name).font(AstirTypography.cardTitle)
                        if !reply.note.isEmpty { Text(reply.note).font(AstirTypography.body) }
                        ForEach(reply.places) { place in
                            Button {
                                let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: place.latitude, longitude: place.longitude)))
                                item.name = place.name; item.openInMaps()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "mappin").frame(width: 32, height: 36)
                                        .background(CircleQuestionStyle.lilac.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.name).font(AstirTypography.cardTitle)
                                        Text(place.detail).font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                                        if !place.note.isEmpty { Text(place.note).font(AstirTypography.bodySmall) }
                                    }
                                    Spacer(); Image(systemName: "arrow.up.right").font(.caption)
                                }.padding(14).background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                    Divider()
                }
                TextField("Add a comment…", text: $comment, axis: .vertical).focused($commentFocused).font(AstirTypography.body)
                    .padding(16).background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 16))
                    .onChange(of: comment) { _, value in if value.count > 1000 { comment = String(value.prefix(1000)) } }
                CircleQuestionAction(title: "Send comment", disabled: comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isBusy) {
                    Task {
                        if await state.perform(event: .answered, requestID: commentID, { try await $0.reply(questionID: question.id, clientID: commentID, places: [], note: comment) }) {
                            comment = ""; commentID = UUID()
                        }
                    }
                }
                if let message = state.message { Text(message).font(AstirTypography.bodySmall).foregroundStyle(brand.accentText) }
            }.padding(22)
        }.astirScreen().navigationTitle("Question").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $recommend) { CircleQuestionRecommendations(state: state, question: question, onCompleted: { recommend = false }) }
            .navigationDestination(isPresented: $privateReply) {
                PrivateMessageThreadScreen(userID: store.currentUser.id, repository: backend.privateMessageRepository,
                    target: .reply(recipientID: question.author.id, context: .init(kind: .question, id: question.id.uuidString)))
            }
            .sheet(isPresented: $share) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Share the question").font(AstirTypography.sheetTitle)
                    Text(question.draft.stealth ? "This link opens only for the tagged people. Sharing it won’t add anyone to the audience." : "The link opens for people who can already see this question.")
                        .font(AstirTypography.body)
                    WanderShareButton(content: .question(id: question.id)) { Label("Share link", systemImage: "square.and.arrow.up") }
                }.padding(26).presentationDetents([.medium]).astirScreen()
            }.task {
                guard !handledInitialAction else { return }
                handledInitialAction = true
                if initialAction == "share" { share = true }
                if initialAction == "private" { privateReply = true }
                if initialAction == "comment" { commentFocused = true }
            }.sessionReplayMasked()
    }
}

struct CircleQuestionFeedSection: View {
    @EnvironmentObject private var store: WanderStore
    @ObservedObject var state: CircleQuestionStore
    let userID: String
    @State private var selected: CircleQuestionPresentation?
    var body: some View {
        VStack(spacing: 16) {
            ForEach(state.items.filter { !store.isBlockedBetweenCurrentUser(and: $0.author.id) }) { question in
                CircleQuestionCard(question: question, open: { selected = .init(question: question, action: "open") }, like: {
                    Task { _ = await state.perform { try await $0.setLike(questionID: question.id, liked: !question.liked) } }
                }, comment: { selected = .init(question: question, action: "comment") }, share: { selected = .init(question: question, action: "share") }, privateReply: { selected = .init(question: question, action: "private") })
            }
        }.task(id: userID) { state.analytics = store.productAnalytics; await state.load(userID: userID) }
            .onChange(of: store.followedFeedPage?.fetchedAt) { _, _ in Task { await state.load(userID: userID) } }
            .sheet(item: $selected) { route in NavigationStack { CircleQuestionDetail(state: state, initial: route.question, initialAction: route.action) } }
    }
}

struct CircleQuestionPresentation: Identifiable { let question: CircleQuestion; let action: String; var id: UUID { question.id } }
