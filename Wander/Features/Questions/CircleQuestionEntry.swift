import SwiftUI

struct CircleQuestionEntry: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dismiss) private var dismiss
    @State private var presented = false
    @State private var didPost = false
    @State private var people: [CircleQuestionPerson] = []
    var body: some View {
        Button { presented = true } label: {
            HStack(spacing: 12) {
                CircleQuestionPin()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask your circle").font(AstirTypography.sheetTitle)
                    Text("Good places start with a question.").font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                }
                Spacer(); Image(systemName: "arrow.up.right").font(.body.weight(.semibold))
            }.foregroundStyle(brand.primaryText).padding(14)
                .background(CircleQuestionStyle.lilac.opacity(0.13), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(CircleQuestionStyle.lilac.opacity(0.4), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("circleQuestion.create")
            .fullScreenCover(isPresented: $presented, onDismiss: { if didPost { dismiss() } }) {
                CircleQuestionComposer(state: backend.circleQuestions,
                    author: .init(id: store.currentUser.id, name: store.currentUser.displayName), people: people,
                    onPosted: { didPost = true })
            }
            .task(id: store.currentUser.id) {
                backend.circleQuestions.analytics = store.productAnalytics
                backend.circleQuestions.reset(userID: store.currentUser.id)
                let userID = store.currentUser.id
                if let repository = backend.followRepository {
                    do {
                        let a = try await repository.followers(userID: userID)
                        let b = try await repository.following(userID: userID)
                        guard store.currentUser.id == userID else { return }
                        let friends = Set(a.map(\.id)).intersection(b.map(\.id))
                        var seen = Set<String>()
                        people = (a + b).filter { seen.insert($0.id).inserted }.map {
                            CircleQuestionPerson(id: $0.id, name: $0.displayName, hometown: $0.homeArea, isFriend: friends.contains($0.id))
                        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    } catch { people = [] }
                } else {
                    people = store.followers(of: userID).map { .init(id: $0.id, name: $0.displayName, hometown: $0.homeArea) }
                }
            }
    }
}
