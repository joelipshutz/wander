import SwiftUI

struct CircleQuestionLink: Identifiable { let id: UUID }

struct CircleQuestionDestination: View {
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var question: CircleQuestion?
    @State private var loading = true
    var body: some View {
        NavigationStack {
            Group {
                if let question { CircleQuestionDetail(state: backend.circleQuestions, initial: question) }
                else if loading { ProgressView("Opening question…") }
                else { ContentUnavailableView("Question unavailable", systemImage: "lock.bubble", description: Text("This question may be private or no longer available to you.")) }
            }.astirScreen().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.task(id: id) {
            loading = true
            question = await backend.circleQuestions.refreshQuestion(id: id)
            loading = false
        }
    }
}

struct CircleQuestionInboxSection: View {
    var onCountChange: (Int) -> Void = { _ in }
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @Environment(\.astirBrandMode) private var brand
    @State private var items: [CircleQuestionInboxItem] = []
    @State private var selected: CircleQuestionLink?
    private var visibleItems: [CircleQuestionInboxItem] {
        items.filter { !store.isBlockedBetweenCurrentUser(and: $0.question.author.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleItems) { item in
                Button {
                    selected = .init(id: item.id)
                    Task {
                        do {
                            try await backend.circleQuestionRepository?.markRead(id: item.id)
                            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].isRead = true }
                        } catch { }
                    }
                } label: {
                    HStack(spacing: 12) {
                        CircleQuestionPin()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(item.question.author.name) asked for your local knowledge").font(AstirTypography.cardTitle)
                            Text(item.question.draft.headline.replacingOccurrences(of: "\n", with: " "))
                                .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                        }
                        Spacer()
                        if !item.isRead { Circle().fill(brand.accent).frame(width: 8, height: 8) }
                    }.padding(14).foregroundStyle(brand.primaryText)
                        .background(brand.raisedBackground, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            }
        }.onChange(of: visibleItems.count, initial: true) { _, count in onCountChange(count) }
            .task(id: store.currentUser.id) {
            let user = store.currentUser.id; items = []
            do {
                let result = try await backend.circleQuestionRepository?.inbox() ?? []
                if user == store.currentUser.id { items = result }
            } catch { items = [] }
        }.sheet(item: $selected) { CircleQuestionDestination(id: $0.id) }.sessionReplayMasked()
    }
}
