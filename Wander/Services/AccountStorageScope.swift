import CryptoKit
import Foundation

/// Creates an opaque, account-specific vault for every authenticated user.
/// Device identifiers are deliberately absent: an authenticated canonical user
/// ID selects a vault only after the server-backed session has been validated.
struct AccountStorageScope: Equatable {
    static let currentVersion = 1

    let userID: String
    let applicationSupportURL: URL

    init(
        userID: String,
        applicationSupportURL: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    ) {
        self.userID = userID
        self.applicationSupportURL = applicationSupportURL
    }

    var accountKey: String {
        let digest = SHA256.hash(data: Data(userID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var directoryURL: URL {
        applicationSupportURL
            .appendingPathComponent("rec-me", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("v\(Self.currentVersion)", isDirectory: true)
            .appendingPathComponent(accountKey, isDirectory: true)
    }

    var storeURL: URL {
        directoryURL.appendingPathComponent("wander-store-v1.json")
    }

    var placeSaveDraftURL: URL {
        directoryURL.appendingPathComponent("place-save-draft-v1.json")
    }

    var placeImportsURL: URL {
        directoryURL.appendingPathComponent("place-imports-v1.json")
    }

    var profileAvatarDirectoryURL: URL {
        directoryURL.appendingPathComponent("profile-avatar", isDirectory: true)
    }

    var visitPhotosDirectoryURL: URL {
        directoryURL.appendingPathComponent("visit-photos", isDirectory: true)
    }

    /// Moves only legacy payloads whose embedded owner matches this validated
    /// account. Unknown or mismatched payloads remain untouched and are never
    /// adopted based on the device alone.
    func migrateMatchingLegacyData(fileManager: FileManager = .default) {
        let markerURL = directoryURL.appendingPathComponent(".legacy-migration-v1")
        guard !fileManager.fileExists(atPath: markerURL.path) else { return }

        let legacyStoreURL = applicationSupportURL
            .appendingPathComponent("Wander", isDirectory: true)
            .appendingPathComponent("wander-store-v1.json")
        let storeMatches = decoded(WanderStoreSnapshot.self, at: legacyStoreURL)?.currentUser.id == userID
        if storeMatches {
            copyIfNeeded(from: legacyStoreURL, to: storeURL, fileManager: fileManager)
        }

        let legacyDraftURL = applicationSupportURL
            .appendingPathComponent("Wander", isDirectory: true)
            .appendingPathComponent("place-save-draft-v1.json")
        if decoded(PlaceSaveDraft.self, at: legacyDraftURL)?.ownerUserID == userID {
            copyIfNeeded(from: legacyDraftURL, to: placeSaveDraftURL, fileManager: fileManager)
        }

        let legacyImportsURL = applicationSupportURL
            .appendingPathComponent("rec-me", isDirectory: true)
            .appendingPathComponent("place-imports-v1.json")
        if decodedImportSnapshot(at: legacyImportsURL)?.ownerUserID == userID {
            copyIfNeeded(from: legacyImportsURL, to: placeImportsURL, fileManager: fileManager)
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            try Data().write(
                to: markerURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            #if DEBUG
            print("Account storage migration marker failed: \(error)")
            #endif
        }
    }

    func removeLocalData(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    private func decoded<Value: Decodable>(_ type: Value.Type, at url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func decodedImportSnapshot(at url: URL) -> PlaceImportSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PlaceImportSnapshot.self, from: data)
    }

    private func copyIfNeeded(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: sourceURL.path),
              !fileManager.fileExists(atPath: destinationURL.path)
        else { return }
        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            #if DEBUG
            print("Account storage migration failed: \(error)")
            #endif
        }
    }
}
