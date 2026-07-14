import Foundation
import UIKit

enum VisitPhotoLocalFileStore {
    private static let prefix = "local_file:"
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

    static func image(from localAssetRef: String?) -> UIImage? {
        guard let filename = filename(from: localAssetRef),
              let directory = directoryURL()
        else {
            return nil
        }

        return UIImage(contentsOfFile: directory.appendingPathComponent(filename).path)
    }

    static func data(from localAssetRef: String?) -> Data? {
        guard let filename = filename(from: localAssetRef),
              let directory = directoryURL()
        else {
            return nil
        }
        return try? Data(contentsOf: directory.appendingPathComponent(filename), options: .mappedIfSafe)
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
