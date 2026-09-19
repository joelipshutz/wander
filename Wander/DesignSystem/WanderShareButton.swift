import Foundation
import SwiftUI
import UIKit

struct WanderShareContent: Equatable {
    static let publicTestFlightURL = URL(string: "https://testflight.apple.com/join/knEhRa6t")!

    let item: URL
    let additionalItems: [URL]
    let subject: String
    let message: String

    var items: [URL] { [item] + additionalItems }

    static func profile(serverID: String?, displayName: String, handle: String) -> WanderShareContent? {
        guard let serverID,
              let item = WanderDeepLinkRoute.sharedProfile(profileID: serverID).url
        else { return nil }
        return WanderShareContent(
            item: item,
            subject: "Discover \(displayName.split(separator: " ").first.map(String.init) ?? displayName)’s world",
            message: "See @\(handle) on Astir"
        )
    }

    static func profileMap(
        serverID: String?,
        displayName: String,
        handle: String,
        imageFileURL: URL,
        filterTitle: String? = nil
    ) -> WanderShareContent? {
        guard imageFileURL.isFileURL, imageFileURL.pathExtension.lowercased() == "png" else { return nil }
        guard let serverID,
              let item = WanderDeepLinkRoute.sharedProfile(profileID: serverID).url
        else { return nil }
        let trimmedFilterTitle = filterTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFilterTitle = trimmedFilterTitle?.isEmpty == false ? trimmedFilterTitle : nil
        return WanderShareContent(
            item: item,
            additionalItems: [imageFileURL],
            subject: normalizedFilterTitle.map { "\(displayName)'s \($0) map" } ?? "\(displayName)'s map",
            message: normalizedFilterTitle.map { "Explore \($0) on @\(handle)'s Astir map" }
                ?? "Explore @\(handle)'s saved places on Astir"
        )
    }

    static func place(item: URL, name: String, message: String) -> WanderShareContent {
        WanderShareContent(item: item, subject: name, message: message)
    }

    static func place(serverID: String?, name: String, message: String) -> WanderShareContent? {
        guard let serverID,
              UUID(uuidString: serverID) != nil,
              let item = WanderDeepLinkRoute.sharedPlace(placeID: serverID).url
        else { return nil }
        return WanderShareContent(item: item, subject: name, message: message)
    }

    static func activity(
        activityID: String,
        placeName: String,
        message: String
    ) -> WanderShareContent? {
        guard UUID(uuidString: activityID) != nil,
              let activityURL = WanderDeepLinkRoute.sharedActivity(activityID: activityID).url
        else { return nil }
        return WanderShareContent(
            item: activityURL,
            subject: placeName,
            message: message
        )
    }

    static func list(serverID: String?, name: String) -> WanderShareContent? {
        guard let serverID,
              UUID(uuidString: serverID) != nil,
              let item = WanderDeepLinkRoute.sharedList(listID: serverID).url
        else { return nil }
        return WanderShareContent(
            item: item,
            subject: name,
            message: "See \(name) on Astir"
        )
    }

    static func listInvite(token: String, name: String) -> WanderShareContent? {
        guard let item = WanderDeepLinkRoute.listInvite(token: token).url else { return nil }
        return WanderShareContent(
            item: item,
            subject: "Join \(name)",
            message: "You’re invited to build \(name) together on Astir"
        )
    }

    static func appInvite(
        senderProfileID: String?,
        contextMessage: String? = nil,
        includeInstallPrompt: Bool = true
    ) -> WanderShareContent {
        let profileURL = senderProfileID.flatMap {
            WanderDeepLinkRoute.sharedProfile(profileID: $0).url
        }
        let opening = contextMessage ?? "Join me on Astir."
        let message: String
        if includeInstallPrompt {
            message = profileURL == nil
                ? "\(opening) Install the TestFlight beta to get started."
                : "\(opening) Install the TestFlight beta, then open my profile to connect."
        } else {
            message = opening
        }
        return WanderShareContent(
            item: publicTestFlightURL,
            additionalItems: [profileURL].compactMap { $0 },
            subject: "Join me on Astir",
            message: message
        )
    }

    var messageBody: String {
        ([message] + items.filter { !$0.isFileURL }.map(\.absoluteString)).joined(separator: "\n\n")
    }

    func attachingPNG(at fileURL: URL) -> WanderShareContent? {
        guard fileURL.isFileURL, fileURL.pathExtension.lowercased() == "png" else { return nil }
        return WanderShareContent(
            item: item,
            additionalItems: additionalItems + [fileURL],
            subject: subject,
            message: message
        )
    }

    private init(item: URL, additionalItems: [URL] = [], subject: String, message: String) {
        self.item = item
        self.additionalItems = additionalItems
        self.subject = subject
        self.message = message
    }

}

struct WanderShareSheet: UIViewControllerRepresentable {
    let content: WanderShareContent
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var activityItems: [Any] = [
            WanderShareActivityItemSource(
                message: content.message,
                subject: content.subject
            )
        ]
        activityItems.append(contentsOf: content.items)
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

final class WanderShareActivityItemSource: NSObject, UIActivityItemSource {
    let message: String
    let subject: String

    init(message: String, subject: String) {
        self.message = message
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        message
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        message
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }
}

enum WanderShareAttachmentStore {
    enum AttachmentError: Error {
        case invalidPNG
    }

    static let directoryName = "recme-share-attachments"
    static let retentionInterval: TimeInterval = 24 * 60 * 60
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// Encoding and writing are synchronous work. Keep both away from the
    /// main actor so preparing an attachment cannot interrupt scrolling.
    static func preparePNG(_ image: UIImage) async -> URL? {
        guard !Task.isCancelled else { return nil }
        let fileURL = await Task.detached(priority: .utility) {
            guard let data = image.pngData() else { return nil as URL? }
            return try? persistPNG(data)
        }.value
        guard !Task.isCancelled else {
            if let fileURL { await removePreparedPNG(at: fileURL) }
            return nil
        }
        return fileURL
    }

    static func preparePNG(_ data: Data) async -> URL? {
        guard !Task.isCancelled else { return nil }
        let fileURL = await Task.detached(priority: .utility) {
            try? persistPNG(data)
        }.value
        guard !Task.isCancelled else {
            if let fileURL {
                await removePreparedPNG(at: fileURL)
            }
            return nil
        }
        return fileURL
    }

    static func removePreparedPNG(at fileURL: URL) async {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let attachmentDirectory = fileManager.temporaryDirectory
                .appendingPathComponent(directoryName, isDirectory: true)
                .standardizedFileURL
            let standardizedFileURL = fileURL.standardizedFileURL
            guard standardizedFileURL.deletingLastPathComponent() == attachmentDirectory else { return }
            try? fileManager.removeItem(at: standardizedFileURL)
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

@MainActor
enum WanderSharePreviewArtwork {
    // Symbol-backed SwiftUI Images do not supply bitmap data to ShareLink.
    // Render this small placeholder once, without fetching profile artwork.
    static let profile: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            UIImage(systemName: "person.crop.circle.fill")?
                .withTintColor(.black, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 16, y: 16, width: 64, height: 64))
        }
    }()
}

struct WanderShareButton<Label: View>: View {
    let content: WanderShareContent
    private let preview: SharePreview<Image, Never>?
    private let onTap: () -> Void
    private let label: () -> Label

    init(
        content: WanderShareContent,
        preview: SharePreview<Image, Never>? = nil,
        onTap: @escaping () -> Void = {},
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.content = content
        self.preview = preview
        self.onTap = onTap
        self.label = label
    }

    @ViewBuilder
    var body: some View {
        if let preview, content.additionalItems.isEmpty {
            // Supplying a preview avoids waiting for remote link metadata.
            // The shared URL, subject, and message remain unchanged.
            ShareLink(
                item: content.item,
                subject: Text(content.subject),
                message: Text(content.message),
                preview: preview,
                label: label
            )
            .simultaneousGesture(TapGesture().onEnded { _ in onTap() })
        } else if content.additionalItems.isEmpty {
            ShareLink(
                item: content.item,
                subject: Text(content.subject),
                message: Text(content.message),
                label: label
            )
            .simultaneousGesture(TapGesture().onEnded { _ in onTap() })
        } else {
            ShareLink(
                items: content.items,
                subject: Text(content.subject),
                message: Text(content.message),
                label: label
            )
            .simultaneousGesture(TapGesture().onEnded { _ in onTap() })
        }
    }
}
