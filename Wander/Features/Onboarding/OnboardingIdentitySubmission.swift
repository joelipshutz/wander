import Foundation

enum OnboardingIdentityPhotoError: Error {
    case uploadFailed

    var message: String {
        switch self {
        case .uploadFailed: "Your photo couldn’t be saved. Check your connection and try again."
        }
    }
}

@MainActor
enum OnboardingIdentitySubmission {
    static func save(
        draft: ProfileIdentityDraft,
        photoData: Data?,
        existingAvatarURL: String?,
        updateIdentity: (ProfileDetailsUpdate) async throws -> Void,
        uploadPhoto: (Data) async throws -> Void
    ) async throws {
        if let validation = draft.validationError { throw validation }
        try await updateIdentity(ProfileDetailsUpdate(displayName: draft.normalizedDisplayName, handle: draft.normalizedHandle))
        if let photoData, !photoData.isEmpty {
            do {
                try await uploadPhoto(photoData)
            } catch {
                throw OnboardingIdentityPhotoError.uploadFailed
            }
        }
    }
}
