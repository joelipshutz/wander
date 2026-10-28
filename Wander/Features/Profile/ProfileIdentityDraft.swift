import Foundation

struct ProfileIdentityDraft: Equatable {
    var displayName: String
    var handle: String
    var usesAppleSignIn = false

    var normalizedDisplayName: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return usesAppleSignIn && name.isEmpty ? normalizedHandle : name
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
            "Add Your Name So Friends Can Recognize You."
        case .displayNameTooLong:
            "Keep Your Name To 80 Characters Or Fewer."
        case .invalidHandle:
            "Use 2–39 Lowercase Letters, Numbers, Or Underscores."
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
            "That Username Was Just Claimed. Try Another One."
        case .invalidIdentity:
            "Check Your Name And Username, Then Try Again."
        case .signedOut:
            "Your Session Ended. Log In Again To Continue."
        case .unavailable:
            "We Couldn’t Save Your Profile. Check Your Connection And Try Again."
        case .contentNotAllowed:
            "That Text Can’t Be Shared On Astir. Please Revise It And Try Again."
        }
    }
}
