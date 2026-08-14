import Foundation

struct ProfileIdentityDraft: Equatable {
    var displayName: String
    var handle: String

    var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedHandle: String {
        handle
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "@")))
            .lowercased()
    }

    var validationError: ProfileIdentityValidationError? {
        if normalizedDisplayName.isEmpty {
            return .displayNameRequired
        }
        if normalizedDisplayName.count > 80 {
            return .displayNameTooLong
        }
        if normalizedHandle.range(of: "^[a-z0-9_]{2,39}$", options: .regularExpression) == nil {
            return .invalidHandle
        }
        return nil
    }

    var isValid: Bool { validationError == nil }
}

enum ProfileIdentityValidationError: Error, Equatable {
    case displayNameRequired
    case displayNameTooLong
    case invalidHandle

    var message: String {
        switch self {
        case .displayNameRequired:
            "Add your name so friends can recognize you."
        case .displayNameTooLong:
            "Keep your name to 80 characters or fewer."
        case .invalidHandle:
            "Use 2–39 lowercase letters, numbers, or underscores."
        }
    }
}

enum OnboardingHandleAvailabilityPolicy {
    static func shouldCheck(
        normalizedHandle: String,
        originalNormalizedHandle: String,
        hasUserEdited: Bool,
        validationError: ProfileIdentityValidationError?
    ) -> Bool {
        hasUserEdited
            && validationError != .invalidHandle
            && normalizedHandle != originalNormalizedHandle
    }
}

enum ProfileIdentitySubmissionError: Error, Equatable {
    case handleTaken
    case invalidIdentity
    case signedOut
    case unavailable
    case contentNotAllowed

    static func map(_ error: Error) -> ProfileIdentitySubmissionError {
        if error is CommunityContentPolicyError {
            return .contentNotAllowed
        }
        guard let remoteError = error as? WanderRemoteError else {
            return .unavailable
        }
        switch remoteError {
        case .notAuthenticated:
            return .signedOut
        case .invalidResponse(let message):
            let normalized = message.lowercased()
            if normalized.contains("handle_taken") || normalized.contains("23505") {
                return .handleTaken
            }
            if normalized.contains("invalid_handle") || normalized.contains("invalid_display_name") {
                return .invalidIdentity
            }
            if normalized.contains("content_not_allowed") {
                return .contentNotAllowed
            }
            return .unavailable
        case .notConfigured, .notImplemented:
            return .unavailable
        }
    }

    var message: String {
        switch self {
        case .handleTaken:
            "That username was just claimed. Try another one."
        case .invalidIdentity:
            "Check your name and username, then try again."
        case .signedOut:
            "Your session ended. Log in again to continue."
        case .unavailable:
            "We couldn’t save your profile. Check your connection and try again."
        case .contentNotAllowed:
            "That text can’t be shared on rec.me. Please revise it and try again."
        }
    }
}
