import Foundation
import UIKit

enum VisitPhotoLocalFileStore {
    private static let prefix = "local_file:"
    private static let scopedPrefix = "local_file_v2:"
    private static let directoryName = "VisitPhotos"

    static func save(data: Data, id: UUID, contentType: String) -> String? {
        guard let directory = directoryURL() else { return nil }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let filename = "\(id.uuidString.lowercased()).\(fileExtension(for: contentType))"
            try data.write(to: directory.appendingPathComponent(filename), options: [.atomic])
            return "\(prefix)\(filename)"
        } catch {
            return nil
        }
    }

    static func save(
        data: Data,
        id: UUID,
        contentType: String,
        ownerUserID: String
    ) -> String? {
        let scope = AccountStorageScope(userID: ownerUserID)
        let directory = scope.visitPhotosDirectoryURL
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            let filename = "\(id.uuidString.lowercased()).\(fileExtension(for: contentType))"
            try data.write(
                to: directory.appendingPathComponent(filename),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            return "\(scopedPrefix)\(scope.accountKey)/\(filename)"
        } catch {
            return nil
        }
    }

    static func image(from localAssetRef: String?) -> UIImage? {
        guard let fileURL = fileURL(from: localAssetRef) else { return nil }
        return UIImage(contentsOfFile: fileURL.path)
    }

    static func data(from localAssetRef: String?) -> Data? {
        guard let fileURL = fileURL(from: localAssetRef) else { return nil }
        return try? Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    private static func fileURL(from localAssetRef: String?) -> URL? {
        guard let localAssetRef else { return nil }
        if localAssetRef.hasPrefix(scopedPrefix) {
            let relativePath = String(localAssetRef.dropFirst(scopedPrefix.count))
            let components = relativePath.split(separator: "/").map(String.init)
            guard components.count == 2,
                  components[0].count == 64,
                  components[0].allSatisfy({ $0.isHexDigit }),
                  components[1] == URL(fileURLWithPath: components[1]).lastPathComponent
            else { return nil }
            guard let root = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else { return nil }
            return root
                .appendingPathComponent("rec-me", isDirectory: true)
                .appendingPathComponent("accounts", isDirectory: true)
                .appendingPathComponent("v\(AccountStorageScope.currentVersion)", isDirectory: true)
                .appendingPathComponent(components[0], isDirectory: true)
                .appendingPathComponent("visit-photos", isDirectory: true)
                .appendingPathComponent(components[1], isDirectory: false)
        }

        guard let filename = filename(from: localAssetRef),
              let directory = directoryURL()
        else { return nil }
        return directory.appendingPathComponent(filename)
    }

    private static func filename(from localAssetRef: String?) -> String? {
        guard let localAssetRef,
              localAssetRef.hasPrefix(prefix)
        else {
            return nil
        }

        return String(localAssetRef.dropFirst(prefix.count))
    }

    private static func directoryURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func fileExtension(for contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/png":
            "png"
        case "image/heic", "image/heif":
            "heic"
        default:
            "jpg"
        }
    }
}
