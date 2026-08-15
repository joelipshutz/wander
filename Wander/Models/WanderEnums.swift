import Foundation

enum PlaceVisibility: String, Codable, CaseIterable, Equatable {
    case followers
    case mutuals
    case selfOnly = "self"
}

enum PlaceStatus: String, Codable, CaseIterable, Equatable {
    case been
    case wannaGo = "wanna_go"
}

enum MapSource: String, Codable, CaseIterable, Equatable, Identifiable {
    case featured
    case friends
    case you

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: "Featured"
        case .friends: "Friends"
        case .you: "You"
        }
    }

    var systemImage: String {
        switch self {
        case .featured: "sparkles"
        case .friends: "person.2.fill"
        case .you: "person.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .featured: "Featured shows you recommendations based on your taste"
        case .friends: "All places from everyone you follow"
        case .you: "Only your check-ins and Wanna Go places"
        }
    }

    var walkthroughTarget: WalkthroughTargetID? {
        switch self {
        case .featured: nil
        case .friends: .mapFriends
        case .you: .mapYou
        }
    }
}

/// Product vocabulary for the repeatable place check-in system.
///
/// Keep this separate from persistence: `PlaceStatus.been` and the backend
/// value `"been"` remain stable compatibility contracts.
enum CheckInCopy {
    static let verb = "check in"
    static let action = "Check in"
    static let pluralTitle = "Check-ins"
    static let noun = "check-in"
    static let pluralNoun = "check-ins"
    static let title = "Check-in"
    static let pastTense = "checked in"
    static let againAction = "Check in again"
    static let editAction = "Edit check-in"
    static let deleteAction = "Delete check-in"

    static func count(_ count: Int) -> String {
        "\(count) \(count == 1 ? noun : pluralNoun)"
    }
}

enum SyncState: String, Codable, CaseIterable, Equatable {
    case localOnly = "local_only"
    case pendingCreate = "pending_create"
    case pendingUpdate = "pending_update"
    case pendingDelete = "pending_delete"
    case synced
    case failed
    case serverDenied = "server_denied"
    case tombstoned
}

struct SaveSyncFeedback: Identifiable, Equatable {
    let id = UUID()
    let syncState: SyncState
    let title: String
    let message: String
    let systemImage: String
    let canSignIn: Bool
    let usesWarningHaptic: Bool
    let dismissDelayNanoseconds: UInt64

    init(syncState: SyncState, canSignIn: Bool) {
        self.syncState = syncState
        self.canSignIn = canSignIn

        switch syncState {
        case .synced:
            title = "saved to your map"
            message = "Synced and ready."
            systemImage = "checkmark"
            usesWarningHaptic = false
            dismissDelayNanoseconds = 2_000_000_000
        case .failed:
            title = "sync failed"
            message = "Saved on this phone. We'll retry automatically."
            systemImage = "exclamationmark.triangle"
            usesWarningHaptic = true
            dismissDelayNanoseconds = 5_000_000_000
        case .pendingCreate, .pendingUpdate, .pendingDelete:
            title = "saved on this phone"
            message = "Sync is queued."
            systemImage = "arrow.triangle.2.circlepath"
            usesWarningHaptic = false
            dismissDelayNanoseconds = 3_500_000_000
        case .localOnly:
            title = "saved on this phone"
            message = canSignIn ? "Sign in to back it up." : "Kept on this phone."
            systemImage = "checkmark"
            usesWarningHaptic = false
            dismissDelayNanoseconds = canSignIn ? 5_000_000_000 : 2_500_000_000
        case .serverDenied:
            title = "needs review"
            message = "Saved on this phone until it can sync."
            systemImage = "exclamationmark.triangle"
            usesWarningHaptic = true
            dismissDelayNanoseconds = 5_000_000_000
        case .tombstoned:
            title = "removed"
            message = "This saved place was removed."
            systemImage = "trash"
            usesWarningHaptic = false
            dismissDelayNanoseconds = 3_500_000_000
        }
    }

    func mapMessage(successMessage: String) -> String {
        switch syncState {
        case .synced:
            successMessage
        case .failed:
            "Saved on this phone, but sync failed. We'll retry."
        case .pendingCreate, .pendingUpdate, .pendingDelete:
            "Saved on this phone. Sync is queued."
        case .localOnly:
            "Saved on this phone."
        case .serverDenied:
            "Saved on this phone, but it needs review before syncing."
        case .tombstoned:
            "This saved place was removed."
        }
    }
}

enum PlaceAttributeValuePresentation {
    static func strings(from valueJSON: String) -> [String] {
        guard let data = valueJSON.data(using: .utf8) else { return [] }

        if let values = try? JSONDecoder().decode([String].self, from: data) {
            return values.compactMap(normalizedValue)
        }

        if let value = try? JSONDecoder().decode(String.self, from: data),
           let normalized = normalizedValue(value) {
            return [normalized]
        }

        return []
    }

    private static func normalizedValue(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum VisitPhotoUploadState: String, Codable, CaseIterable, Equatable {
    case pendingUpload = "pending_upload"
    case uploading
    case uploaded
    case failed
}

enum FollowSource: String, Codable, CaseIterable, Equatable {
    case username
    case contacts
    case profile
    case inviteLinkFuture = "invite_link_future"
}

enum ExtractionStatus: String, Codable, CaseIterable, Equatable {
    case pending
    case running
    case needsConfirmation = "needs_confirmation"
    case complete
    case failed
    case noPlaceFound = "no_place_found"
}

enum ViewerRelationship: String, Codable, Equatable {
    case owner
    case mutual
    case follower
    case nonFollower = "non_follower"
}

enum AddSourceType: String, Codable, CaseIterable, Equatable {
    case currentLocation = "current_location"
    case link
    case manual
    case photo
    case socialSave = "social_save"

    var title: String {
        switch self {
        case .currentLocation: "I'm here right now"
        case .link: "Paste a link"
        case .manual: "Add manually"
        case .photo: "From a photo"
        case .socialSave: "Save from someone"
        }
    }
}

extension PlaceVisibility {
    var normalizedForStealthMode: PlaceVisibility {
        self == .selfOnly ? .selfOnly : .followers
    }

    var isStealthModeEnabled: Bool {
        normalizedForStealthMode == .selfOnly
    }

    static func visibilityForStealthMode(isPrivate: Bool) -> PlaceVisibility {
        isPrivate ? .selfOnly : .followers
    }

    var stealthModeHelperCopy: String {
        if isStealthModeEnabled {
            return "Private. Only you can see this place."
        }

        return "Not private. People who follow you can see it."
    }

    var showsTileLockIndicator: Bool {
        isStealthModeEnabled
    }

    var displayTitle: String {
        switch self {
        case .followers: "Everyone"
        case .mutuals: "Friends"
        case .selfOnly: "Self"
        }
    }

    var helperCopy: String {
        switch self {
        case .followers: "People who follow you can see this."
        case .mutuals: "Only mutual follows can see this."
        case .selfOnly: "Only you can see this."
        }
    }
}

extension PlaceStatus {
    var displayTitle: String {
        switch self {
        case .been: CheckInCopy.noun
        case .wannaGo: "wanna go"
        }
    }
}

extension ViewerRelationship {
    var displayTitle: String {
        switch self {
        case .owner: "you"
        case .mutual: "friend"
        case .follower: "following"
        case .nonFollower: "not following"
        }
    }
}
