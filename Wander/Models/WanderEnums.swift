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
        case .featured: "Featured Shows You Recommendations Based On Your Taste"
        case .friends: "All Places From Everyone You Follow"
        case .you: "Only Your Check-Ins And Wanna Go Places"
        }
    }

    var walkthroughTarget: WalkthroughTargetID? {
        switch self {
        case .featured: .mapFeatured
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
    static let verb = "Check In"
    static let action = "Check In"
    static let pluralTitle = "Check-Ins"
    static let noun = "Check-In"
    static let pluralNoun = "Check-Ins"
    static let title = "Check-In"
    static let pastTense = "Checked In"
    static let againAction = action
    static let editAction = "Edit Check-In"
    static let deleteAction = "Delete Check-In"

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
            title = "Saved To Your Map"
            message = "Synced And Ready."
            systemImage = "checkmark"
            usesWarningHaptic = false
            dismissDelayNanoseconds = 2_000_000_000
        case .failed:
            title = "Sync Failed"
            message = "Saved On This Phone. We'll Retry Automatically."
            systemImage = "exclamationmark.triangle"
            usesWarningHaptic = true
            dismissDelayNanoseconds = 5_000_000_000
        case .pendingCreate, .pendingUpdate, .pendingDelete:
            title = "Saved On This Phone"
            message = "Sync Is Queued."
            systemImage = "arrow.triangle.2.circlepath"
            usesWarningHaptic = false
            dismissDelayNanoseconds = 3_500_000_000
        case .localOnly:
            title = "Saved On This Phone"
            message = canSignIn ? "Sign In To Back It Up." : "Kept On This Phone."
            systemImage = "checkmark"
            usesWarningHaptic = false
            dismissDelayNanoseconds = canSignIn ? 5_000_000_000 : 2_500_000_000
        case .serverDenied:
            title = "Needs Review"
            message = "Saved On This Phone Until It Can Sync."
            systemImage = "exclamationmark.triangle"
            usesWarningHaptic = true
            dismissDelayNanoseconds = 5_000_000_000
        case .tombstoned:
            title = "Removed"
            message = "This Saved Place Was Removed."
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
            "Saved On This Phone, But Sync Failed. We'll Retry."
        case .pendingCreate, .pendingUpdate, .pendingDelete:
            "Saved On This Phone. Sync Is Queued."
        case .localOnly:
            "Saved On This Phone."
        case .serverDenied:
            "Saved On This Phone, But It Needs Review Before Syncing."
        case .tombstoned:
            "This Saved Place Was Removed."
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

enum VisitPhotoUploadState: String, Codable, CaseIterable, Equatable, Sendable {
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
        case .currentLocation: "I'm Here Right Now"
        case .link: "Paste A Link"
        case .manual: "Add Manually"
        case .photo: "From A Photo"
        case .socialSave: "Save From Someone"
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
            return "Private. Only You Can See This Place."
        }

        return "Not Private. People Who Follow You Can See It."
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
        case .followers: "People Who Follow You Can See This."
        case .mutuals: "Only Mutual Follows Can See This."
        case .selfOnly: "Only You Can See This."
        }
    }
}

extension PlaceStatus {
    var displayTitle: String {
        switch self {
        case .been: CheckInCopy.noun
        case .wannaGo: "Wanna Go"
        }
    }
}

extension ViewerRelationship {
    var displayTitle: String {
        switch self {
        case .owner: "You"
        case .mutual: "Friend"
        case .follower: "Following"
        case .nonFollower: "Not Following"
        }
    }
}
