import Foundation

/// A repeat Wanna is an event, not a change to the user's place summary.
/// The UUID also identifies its Feed event and survives offline retries.
struct PlaceWannaSave: Identifiable, Codable, Equatable {
    let id: String
    let ownerID: String
    var userPlaceID: String
    let occurredAt: Date
    let note: String?
    let visibility: PlaceVisibility
    let plannedDate: Date?
    let attributeAnswersJSON: String
    var isSynced: Bool = false
}

@MainActor
protocol WannaSaveRepository {
    func saveWanna(_ wanna: PlaceWannaSave) async throws
    func wannaSaves(userPlaceIDs: [String]) async throws -> [PlaceWannaSave]
}
