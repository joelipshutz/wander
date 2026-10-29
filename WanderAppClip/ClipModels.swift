import Foundation

enum ClipError: Error, Equatable {
    case unavailable, connection, configuration, signIn, verification, profile, privateProfile, server

    var message: String {
        switch self {
        case .unavailable: "This link is no longer available, or your account doesn't have access."
        case .connection: "Check your connection, then try again."
        case .configuration: "This experience isn't available yet. Please try again later."
        case .signIn: "Sign in again to continue."
        case .verification: "Your account needs another verification step. Try your original sign-in method."
        case .profile: "Choose a name and an available username to continue."
        case .privateProfile: "List collaboration requires a public profile. You can change this in Astir Settings."
        case .server: "Couldn't finish that action. Try again."
        }
    }
}

struct ClipPlace: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let address: String?
    let latitude: Double
    let longitude: Double

    init?(id: String, title: String, address: String?, latitude: Double, longitude: Double) {
        guard UUID(uuidString: id) != nil, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        self.id = id; self.title = title; self.address = address
        self.latitude = latitude; self.longitude = longitude
    }
}

struct ClipPreview: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let places: [ClipPlace]
    var needsSignIn: Bool = false
}

struct ClipProfile: Decodable, Equatable, Sendable {
    let id: String
    let displayName: String
    let handle: String
    let isPrivate: Bool
    let onboardedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, handle
        case displayName = "display_name", isPrivate = "is_private_profile"
        case onboardedAt = "onboarding_completed_at"
    }
}

enum ClipAction: Equatable {
    case save(ClipPlace)
    case join
    case viewProtected
}

@MainActor
protocol ClipServing {
    func preview(_ route: AppClipRoute, authenticated: Bool) async throws -> ClipPreview
    func profile() async throws -> ClipProfile?
    func updateProfile(name: String, handle: String) async throws -> ClipProfile
    func save(_ place: ClipPlace) async throws -> Bool
    func join(_ route: AppClipRoute) async throws -> String
}
