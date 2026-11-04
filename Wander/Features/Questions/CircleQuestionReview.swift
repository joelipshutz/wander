#if DEBUG
import SwiftUI

/// Explicit simulator review only. The same views are used by the Live/Add/Feed entry points.
@MainActor final class CircleQuestionReviewRepository: CircleQuestionRepository {
    var items: [CircleQuestion] = [sample]
    private var replyIDs = Set<UUID>()
    static let people: [CircleQuestionPerson] = [
        .init(id: "maya", name: "Maya Chen", hometown: "Santa Monica", isFriend: true),
        .init(id: "jules", name: "Jules Bennett", hometown: "Los Angeles", isFriend: true),
        .init(id: "sam", name: "Sam Kim", hometown: "Santa Monica", isFriend: true)
    ]
    static var sample: CircleQuestion {
        var draft = CircleQuestionDraft()
        draft.categories = [WanderPlaceCategory.coffeeTeaSweets]
        draft.subcategories = ["Coffee"]
        draft.area = .init(name: "Santa Monica", detail: "California, United States", latitude: 34.01, longitude: -118.49,
                           city: "Santa Monica", region: "CA", countryCode: "US")
        draft.note = "Somewhere to lose a Sunday morning. Great coffee, a sunny patio, and a pastry worth sharing."
        return .init(draft: draft, author: .init(id: "user_joe", name: "Alex Rivera"), createdAt: .now,
                     expiresAt: .now.addingTimeInterval(7 * 86400))
    }
    func questions() async throws -> [CircleQuestion] { items }
    func publish(_ draft: CircleQuestionDraft) async throws -> CircleQuestion {
        if let previous = items.first(where: { $0.id == draft.id }) { return previous }
        let question = CircleQuestion(draft: draft, author: .init(id: "user_joe", name: "Alex Rivera"), createdAt: .now,
                                      expiresAt: .now.addingTimeInterval(Double(draft.days) * 86400))
        items.insert(question, at: 0); return question
    }
    func reply(questionID: UUID, clientID: UUID, places: [CircleQuestionPlace], note: String) async throws -> CircleQuestion {
        guard let index = items.firstIndex(where: { $0.id == questionID }) else { throw WanderRemoteError.notConfigured }
        if replyIDs.insert(clientID).inserted {
            items[index].replies.append(.init(id: clientID, author: Self.people[0], note: note, places: places, createdAt: .now))
        }
        return items[index]
    }
    func setLike(questionID: UUID, liked: Bool) async throws -> CircleQuestion {
        guard let index = items.firstIndex(where: { $0.id == questionID }) else { throw WanderRemoteError.notConfigured }
        if items[index].liked != liked { items[index].likes += liked ? 1 : -1; items[index].liked = liked }
        return items[index]
    }
}

struct CircleQuestionReviewRoot: View {
    @StateObject private var store = WanderStore(fixtures: WanderFixtures.seed())
    @StateObject private var backend = WanderBackend()
    @StateObject private var state: CircleQuestionStore
    @State private var basket = CircleQuestionBasket()
    private let question: CircleQuestion
    private var scene: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-CircleQuestionScene"), args.indices.contains(index + 1) else { return "composer" }
        return args[index + 1]
    }
    init() {
        let repository = CircleQuestionReviewRepository()
        if ProcessInfo.processInfo.arguments.contains("expired") { repository.items[0].expiresAt = .now.addingTimeInterval(-1) }
        question = repository.items[0]
        _state = StateObject(wrappedValue: CircleQuestionStore(repository: repository))
    }
    var body: some View {
        Group {
            if scene == "composer" {
                CircleQuestionComposer(state: state, author: question.author, people: CircleQuestionReviewRepository.people, draft: question.draft)
            } else {
                NavigationStack {
                    switch scene {
                    case "preview": CircleQuestionPreview(state: state, draft: question.draft, author: question.author, posted: {})
                    case "recommend": CircleQuestionRecommendations(state: state, question: question)
                    case "knowledge": CircleQuestionKnowledge(state: state, question: question, basket: $basket)
                    case "feed", "expired":
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                Text("Your circle").font(.system(.largeTitle, design: .serif).weight(.semibold))
                                CircleQuestionFeedSection(state: state, userID: "user_joe")
                            }.padding(20)
                        }.astirScreen()
                    default: CircleQuestionDetail(state: state, initial: question)
                    }
                }
            }
        }.environmentObject(store).environmentObject(backend).astirAdaptiveBrandMode()
            .task {
                await state.load(userID: "user_joe")
                if basket.places.isEmpty {
                    basket.selectAll([
                        .init(id: "1", name: "Dogtown Coffee", detail: "2003 Main St, Santa Monica", latitude: 34.006, longitude: -118.488),
                        .init(id: "2", name: "Layla Bagels", detail: "1614 Ocean Park Blvd, Santa Monica", latitude: 34.013, longitude: -118.467)
                    ])
                }
            }
    }
}
#endif
