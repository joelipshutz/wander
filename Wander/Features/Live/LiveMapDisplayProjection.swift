import Foundation

/// Replace this value whenever authorized map content is rebuilt. Its generation
/// lets the native map reuse indexes across drawer, camera and modal updates.
/// SwiftData objects remain actor-owned; model mutations still rebuild projection.
struct LiveMapDisplayProjection {
    let revision = UUID()
    let pins: [LivePlacePin]
    let pinIDs: [String]
    let persistedPlaceIDs: [String]
    let activityIDs: Set<String>
    private let pinByID: [String: LivePlacePin]

    init(pins: [LivePlacePin] = [], activities: [FeedActivity] = []) {
        self.pins = pins
        pinIDs = pins.map(\.id)
        persistedPlaceIDs = Array(Set(pins.flatMap { $0.identity.persistedPlaceIDs })).sorted()
        activityIDs = Set(activities.map(\.id))
        pinByID = Dictionary(pins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func pin(id: String?) -> LivePlacePin? { id.flatMap { pinByID[$0] } }
}
