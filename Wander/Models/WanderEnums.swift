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
        case .been: "been"
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
