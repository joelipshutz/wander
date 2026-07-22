import Foundation
import SwiftUI

struct WanderShareContent: Equatable {
    let item: URL
    let additionalItems: [URL]
    let subject: String
    let message: String

    var items: [URL] { [item] + additionalItems }

    static func profile(serverID: String?, displayName: String, handle: String) -> WanderShareContent? {
        guard let item = appURL(host: "profiles", pathComponent: serverID) else { return nil }
        return WanderShareContent(
            item: item,
            subject: displayName,
            message: "See @\(handle) on rec.me"
        )
    }

    static func profileMap(
        serverID: String?,
        displayName: String,
        handle: String,
        imageFileURL: URL
    ) -> WanderShareContent? {
        guard imageFileURL.isFileURL, imageFileURL.pathExtension.lowercased() == "png" else { return nil }
        guard let item = appURL(host: "profiles", pathComponent: serverID) else { return nil }
        return WanderShareContent(
            item: item,
            additionalItems: [imageFileURL],
            subject: "\(displayName)'s map",
            message: "Explore @\(handle)'s saved places on rec.me"
        )
    }

    static func place(item: URL, name: String, message: String) -> WanderShareContent {
        WanderShareContent(item: item, subject: name, message: message)
    }

    private init(item: URL, additionalItems: [URL] = [], subject: String, message: String) {
        self.item = item
        self.additionalItems = additionalItems
        self.subject = subject
        self.message = message
    }

    private static func appURL(host: String, pathComponent: String?) -> URL? {
        guard let pathComponent,
              !pathComponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        var components = URLComponents()
        components.scheme = "recme"
        components.host = host
        components.path = "/\(pathComponent)"
        return components.url
    }
}

enum WanderShareAttachmentStore {
    enum AttachmentError: Error {
        case invalidPNG
    }

    static let directoryName = "recme-share-attachments"
    static let retentionInterval: TimeInterval = 24 * 60 * 60
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    static func preparePNG(_ data: Data) async -> URL? {
        await Task.detached(priority: .utility) {
            try? persistPNG(data)
        }.value
    }

    static func persistPNG(
        _ data: Data,
        baseDirectory: URL = FileManager.default.temporaryDirectory,
        now: Date = .now,
        identifier: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws -> URL {
        guard data.starts(with: pngSignature) else {
            throw AttachmentError.invalidPNG
        }

        let directory = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        pruneExpiredAttachments(in: directory, now: now, fileManager: fileManager)

        let fileURL = directory
            .appendingPathComponent("recme-profile-map-\(identifier.uuidString.lowercased())")
            .appendingPathExtension("png")
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: fileURL.path
        )
        return fileURL
    }

    static func pruneExpiredAttachments(
        in directory: URL,
        now: Date = .now,
        fileManager: FileManager = .default
    ) {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for fileURL in fileURLs {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ),
            values.isRegularFile == true,
            let modifiedAt = values.contentModificationDate,
            now.timeIntervalSince(modifiedAt) > retentionInterval
            else { continue }

            try? fileManager.removeItem(at: fileURL)
        }
    }
}

struct WanderShareButton<Label: View>: View {
    let content: WanderShareContent
    private let label: () -> Label

    init(content: WanderShareContent, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
    }

    @ViewBuilder
    var body: some View {
        if content.additionalItems.isEmpty {
            ShareLink(
                item: content.item,
                subject: Text(content.subject),
                message: Text(content.message),
                label: label
            )
        } else {
            ShareLink(
                items: content.items,
                subject: Text(content.subject),
                message: Text(content.message),
                label: label
            )
        }
    }
}
