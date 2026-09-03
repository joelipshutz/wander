import CryptoKit
import Foundation

enum SharedPlaceImportSource: String, Codable, Equatable, Sendable {
    case googleMaps = "google_maps"
    case instagram
    case tiktok
    case snapchat
    case textNotes = "text_notes"
}

enum SharedPlaceImportPayloadKind: String, Codable, Equatable, Sendable {
    case text
    case file
}

enum SharedPlaceImportSaveMode: String, Codable, Equatable, Sendable {
    case wanna
    case checkIn = "check_in"
}

struct SharedPlaceImportSaveIntent: Codable, Equatable, Sendable {
    let mode: SharedPlaceImportSaveMode
    let ratingScore: Double?

    init(mode: SharedPlaceImportSaveMode = .wanna, ratingScore: Double? = nil) {
        self.mode = mode
        self.ratingScore = mode == .checkIn
            ? ratingScore.map { min(5, max(1, $0)) }
            : nil
    }

    static let wanna = SharedPlaceImportSaveIntent()
}

struct SharedPlaceImportEnvelopeItem: Codable, Equatable, Sendable {
    let kind: SharedPlaceImportPayloadKind
    let source: SharedPlaceImportSource
    let contentHash: String
    let suggestedName: String?
    let text: String?
    let relativeFilePath: String?
    let contentTypeIdentifier: String?
    let sourceURLString: String?
    let contextText: String?

    init(
        kind: SharedPlaceImportPayloadKind,
        source: SharedPlaceImportSource,
        contentHash: String,
        suggestedName: String?,
        text: String?,
        relativeFilePath: String?,
        contentTypeIdentifier: String?,
        sourceURLString: String? = nil,
        contextText: String? = nil
    ) {
        self.kind = kind
        self.source = source
        self.contentHash = contentHash
        self.suggestedName = suggestedName
        self.text = text
        self.relativeFilePath = relativeFilePath
        self.contentTypeIdentifier = contentTypeIdentifier
        self.sourceURLString = sourceURLString
        self.contextText = contextText
    }
}

struct SharedPlaceImportEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 3
    static let supportedVersions = 1...currentVersion

    let version: Int
    let deliveryID: String
    let createdAt: Date
    let items: [SharedPlaceImportEnvelopeItem]
    let saveIntent: SharedPlaceImportSaveIntent?

    init(
        version: Int = SharedPlaceImportEnvelope.currentVersion,
        deliveryID: String = UUID().uuidString.lowercased(),
        createdAt: Date = .now,
        items: [SharedPlaceImportEnvelopeItem],
        saveIntent: SharedPlaceImportSaveIntent? = nil
    ) {
        self.version = version
        self.deliveryID = deliveryID
        self.createdAt = createdAt
        self.items = items
        self.saveIntent = saveIntent
    }

    /// Version 1 and 2 captures predate extension auto-save and must retain
    /// their original review-before-save behavior.
    var requestsAutomaticSave: Bool {
        version >= 3 && saveIntent != nil
    }
}

enum SharedPlaceImportCaptureInput: Equatable, Sendable {
    case text(String, suggestedName: String?)
    case sharedLink(URL, contextText: String?, suggestedName: String?)
    case file(Data, fileName: String, contentTypeIdentifier: String?)
}

enum SharedPlaceImportPayloadBudget {
    static func adding(_ nextBytes: Int, to currentBytes: Int) throws -> Int {
        let (total, overflowed) = currentBytes.addingReportingOverflow(nextBytes)
        guard !overflowed, total <= SharedPlaceImportInbox.maximumTotalBytes else {
            throw SharedPlaceImportInboxError.totalPayloadTooLarge
        }
        return total
    }
}

struct SharedPlaceImportInboxEntry: Equatable, Sendable {
    let envelope: SharedPlaceImportEnvelope
    let envelopeURL: URL
}

struct SharedPlaceImportInboxScan: Equatable, Sendable {
    let entries: [SharedPlaceImportInboxEntry]
    let quarantinedCount: Int
    let expiredCount: Int
}

enum SharedPlaceImportInboxError: Error, Equatable, LocalizedError {
    case appGroupUnavailable
    case noSupportedContent
    case tooManyItems
    case textTooLarge
    case fileTooLarge
    case totalPayloadTooLarge
    case unsupportedFile
    case invalidEnvelope
    case missingAttachment

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "rec.me could not access its shared inbox. Check the app and extension App Group signing."
        case .noSupportedContent:
            "Share a public link, place text, or a supported place file."
        case .tooManyItems:
            "Share 20 or fewer items at a time."
        case .textTooLarge:
            "The shared text is too large. Try a shorter selection or a supported file."
        case .fileTooLarge:
            "That file is over 10 MB. Choose a smaller CSV, JSON, text, Markdown, or RTF file."
        case .totalPayloadTooLarge:
            "This share is over 25 MB. Share fewer files at a time."
        case .unsupportedFile:
            "Choose a CSV, JSON, TXT, Markdown, or RTF file."
        case .invalidEnvelope:
            "The shared import was damaged before rec.me could read it."
        case .missingAttachment:
            "A shared file is no longer available. Share it to rec.me again."
        }
    }
}

enum SharedPlaceImportSourceDetector {
    static func source(for text: String, fileName: String? = nil) -> SharedPlaceImportSource {
        for url in webURLs(in: text) {
            guard let host = url.host?.lowercased() else { continue }
            if host == "instagram.com" || host.hasSuffix(".instagram.com") || host == "instagr.am" {
                return .instagram
            }
            if host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
                return .tiktok
            }
            if host == "snapchat.com" || host.hasSuffix(".snapchat.com") {
                return .snapchat
            }
            if isGoogleMapsURL(url, host: host) {
                return .googleMaps
            }
        }

        let normalizedFileName = fileName?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased() ?? ""
        if normalizedFileName.contains("google maps")
            || normalizedFileName.contains("saved places")
            || normalizedFileName.contains("maps saved places") {
            return .googleMaps
        }
        return .textNotes
    }

    private static func webURLs(in text: String) -> [URL] {
        guard let expression = try? NSRegularExpression(pattern: #"https?://[^\s]+"#) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let value = String(text[swiftRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
            return URL(string: value)
        }
    }

    private static func isGoogleMapsURL(_ url: URL, host: String) -> Bool {
        if ["maps.app.goo.gl", "goo.gl", "g.co", "maps.google.com"].contains(host) {
            return true
        }
        return (host == "google.com" || host.hasSuffix(".google.com"))
            && url.path.lowercased().contains("/maps")
    }
}

struct SharedPlaceImportInbox: Sendable {
    static let appGroupIdentifier = "group.com.grayline.wander.shared"
    static let maximumItemCount = 20
    static let maximumTextBytes = 256 * 1_024
    static let maximumFileBytes = 10 * 1_024 * 1_024
    static let maximumTotalBytes = 25 * 1_024 * 1_024
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    private static let supportedFileExtensions = Set([
        "csv", "json", "txt", "md", "markdown", "rtf"
    ])

    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    static func live(fileManager: FileManager = .default) throws -> SharedPlaceImportInbox {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedPlaceImportInboxError.appGroupUnavailable
        }
        return SharedPlaceImportInbox(rootURL: containerURL)
    }

    @discardableResult
    func capture(
        _ inputs: [SharedPlaceImportCaptureInput],
        saveIntent: SharedPlaceImportSaveIntent? = nil,
        deliveryID: String = UUID().uuidString.lowercased(),
        createdAt: Date = .now,
        fileManager: FileManager = .default
    ) throws -> SharedPlaceImportEnvelope {
        guard !inputs.isEmpty else {
            throw SharedPlaceImportInboxError.noSupportedContent
        }
        guard inputs.count <= Self.maximumItemCount else {
            throw SharedPlaceImportInboxError.tooManyItems
        }
        guard Self.isValidDeliveryID(deliveryID) else {
            throw SharedPlaceImportInboxError.invalidEnvelope
        }

        try prepareDirectories(fileManager: fileManager)
        let deliveryAttachmentDirectory = attachmentsDirectory
            .appendingPathComponent(deliveryID, isDirectory: true)
        var envelopeItems: [SharedPlaceImportEnvelopeItem] = []
        var seenContentHashes = Set<String>()
        var totalBytes = 0

        do {
            for (index, input) in inputs.enumerated() {
                switch input {
                case .text(let rawText, let suggestedName):
                    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let data = Data(text.utf8)
                    guard data.count <= Self.maximumTextBytes else {
                        throw SharedPlaceImportInboxError.textTooLarge
                    }
                    totalBytes = try SharedPlaceImportPayloadBudget.adding(
                        data.count,
                        to: totalBytes
                    )
                    let contentHash = Self.sha256(data)
                    guard seenContentHashes.insert(contentHash).inserted else { continue }
                    envelopeItems.append(
                        SharedPlaceImportEnvelopeItem(
                            kind: .text,
                            source: SharedPlaceImportSourceDetector.source(
                                for: text,
                                fileName: suggestedName
                            ),
                            contentHash: contentHash,
                            suggestedName: Self.normalizedName(suggestedName),
                            text: text,
                            relativeFilePath: nil,
                            contentTypeIdentifier: nil
                        )
                    )

                case .sharedLink(let rawURL, let rawContextText, let suggestedName):
                    guard let scheme = rawURL.scheme?.lowercased(),
                          ["http", "https"].contains(scheme),
                          rawURL.host?.isEmpty == false
                    else {
                        throw SharedPlaceImportInboxError.noSupportedContent
                    }
                    let urlString = rawURL.absoluteString
                    let contextText = Self.normalizedName(rawContextText)
                    let content = [urlString, contextText]
                        .compactMap { $0 }
                        .joined(separator: "\n")
                    let data = Data(content.utf8)
                    guard data.count <= Self.maximumTextBytes else {
                        throw SharedPlaceImportInboxError.textTooLarge
                    }
                    totalBytes = try SharedPlaceImportPayloadBudget.adding(
                        data.count,
                        to: totalBytes
                    )
                    let contentHash = Self.sha256(data)
                    guard seenContentHashes.insert(contentHash).inserted else { continue }
                    envelopeItems.append(
                        SharedPlaceImportEnvelopeItem(
                            kind: .text,
                            source: SharedPlaceImportSourceDetector.source(for: content),
                            contentHash: contentHash,
                            suggestedName: Self.normalizedName(suggestedName),
                            text: urlString,
                            relativeFilePath: nil,
                            contentTypeIdentifier: nil,
                            sourceURLString: urlString,
                            contextText: contextText
                        )
                    )

                case .file(let data, let rawFileName, let contentTypeIdentifier):
                    guard data.count <= Self.maximumFileBytes else {
                        throw SharedPlaceImportInboxError.fileTooLarge
                    }
                    totalBytes = try SharedPlaceImportPayloadBudget.adding(
                        data.count,
                        to: totalBytes
                    )
                    let fileName = Self.safeFileName(rawFileName)
                    guard Self.supportedFileExtensions.contains(
                        URL(fileURLWithPath: fileName).pathExtension.lowercased()
                    ) else {
                        throw SharedPlaceImportInboxError.unsupportedFile
                    }
                    let contentHash = Self.sha256(data)
                    guard seenContentHashes.insert(contentHash).inserted else { continue }

                    try fileManager.createDirectory(
                        at: deliveryAttachmentDirectory,
                        withIntermediateDirectories: true
                    )
                    let storedName = "\(index)-\(fileName)"
                    let fileURL = deliveryAttachmentDirectory
                        .appendingPathComponent(storedName, isDirectory: false)
                    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    Self.excludeFromBackup(fileURL)
                    let relativePath = "attachments/\(deliveryID)/\(storedName)"
                    envelopeItems.append(
                        SharedPlaceImportEnvelopeItem(
                            kind: .file,
                            source: SharedPlaceImportSourceDetector.source(
                                for: "",
                                fileName: fileName
                            ),
                            contentHash: contentHash,
                            suggestedName: fileName,
                            text: nil,
                            relativeFilePath: relativePath,
                            contentTypeIdentifier: contentTypeIdentifier
                        )
                    )
                }
            }

            guard !envelopeItems.isEmpty else {
                throw SharedPlaceImportInboxError.noSupportedContent
            }

            let envelope = SharedPlaceImportEnvelope(
                deliveryID: deliveryID,
                createdAt: createdAt,
                items: envelopeItems,
                saveIntent: saveIntent
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let envelopeData = try encoder.encode(envelope)
            let envelopeURL = inboxDirectory
                .appendingPathComponent("\(deliveryID).json", isDirectory: false)
            try envelopeData.write(
                to: envelopeURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            Self.excludeFromBackup(envelopeURL)
            return envelope
        } catch {
            try? fileManager.removeItem(at: deliveryAttachmentDirectory)
            throw error
        }
    }

    func scan(
        now: Date = .now,
        fileManager: FileManager = .default
    ) throws -> SharedPlaceImportInboxScan {
        try prepareDirectories(fileManager: fileManager)
        let urls = try fileManager.contentsOfDirectory(
            at: inboxDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [SharedPlaceImportInboxEntry] = []
        var quarantinedCount = 0
        var expiredCount = 0

        for url in urls {
            do {
                let envelope = try decoder.decode(
                    SharedPlaceImportEnvelope.self,
                    from: Data(contentsOf: url)
                )
                guard SharedPlaceImportEnvelope.supportedVersions.contains(envelope.version),
                      Self.isValidDeliveryID(envelope.deliveryID),
                      !envelope.items.isEmpty,
                      envelope.items.count <= Self.maximumItemCount
                else {
                    throw SharedPlaceImportInboxError.invalidEnvelope
                }
                if now.timeIntervalSince(envelope.createdAt) > Self.retentionInterval {
                    try acknowledge(
                        SharedPlaceImportInboxEntry(envelope: envelope, envelopeURL: url),
                        fileManager: fileManager
                    )
                    expiredCount += 1
                } else {
                    entries.append(
                        SharedPlaceImportInboxEntry(envelope: envelope, envelopeURL: url)
                    )
                }
            } catch {
                try quarantineEnvelope(at: url, fileManager: fileManager)
                quarantinedCount += 1
            }
        }

        try cleanupExpiredOrphanAttachments(now: now, fileManager: fileManager)
        return SharedPlaceImportInboxScan(
            entries: entries,
            quarantinedCount: quarantinedCount,
            expiredCount: expiredCount
        )
    }

    func attachmentURL(
        for item: SharedPlaceImportEnvelopeItem,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard item.kind == .file,
              let relativeFilePath = item.relativeFilePath
        else {
            throw SharedPlaceImportInboxError.missingAttachment
        }
        let fileURL = baseDirectory.appendingPathComponent(relativeFilePath, isDirectory: false)
            .standardizedFileURL
        let attachmentRoot = attachmentsDirectory.standardizedFileURL.path + "/"
        guard fileURL.path.hasPrefix(attachmentRoot),
              fileManager.fileExists(atPath: fileURL.path)
        else {
            throw SharedPlaceImportInboxError.missingAttachment
        }
        return fileURL
    }

    func acknowledge(
        _ entry: SharedPlaceImportInboxEntry,
        fileManager: FileManager = .default
    ) throws {
        guard Self.isValidDeliveryID(entry.envelope.deliveryID) else {
            throw SharedPlaceImportInboxError.invalidEnvelope
        }
        let attachmentDirectory = attachmentsDirectory
            .appendingPathComponent(entry.envelope.deliveryID, isDirectory: true)
        if fileManager.fileExists(atPath: attachmentDirectory.path) {
            try fileManager.removeItem(at: attachmentDirectory)
        }
        if fileManager.fileExists(atPath: entry.envelopeURL.path) {
            try fileManager.removeItem(at: entry.envelopeURL)
        }
    }

    func quarantine(
        _ entry: SharedPlaceImportInboxEntry,
        fileManager: FileManager = .default
    ) throws {
        try prepareDirectories(fileManager: fileManager)
        try quarantineEnvelope(at: entry.envelopeURL, fileManager: fileManager)
    }

    private var baseDirectory: URL {
        rootURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("rec-me-share-imports", isDirectory: true)
    }

    private var inboxDirectory: URL {
        baseDirectory.appendingPathComponent("inbox", isDirectory: true)
    }

    private var attachmentsDirectory: URL {
        baseDirectory.appendingPathComponent("attachments", isDirectory: true)
    }

    private var quarantineDirectory: URL {
        baseDirectory.appendingPathComponent("quarantine", isDirectory: true)
    }

    private func prepareDirectories(fileManager: FileManager) throws {
        for directory in [baseDirectory, inboxDirectory, attachmentsDirectory, quarantineDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            Self.excludeFromBackup(directory)
        }
    }

    private func quarantineEnvelope(at url: URL, fileManager: FileManager) throws {
        let destination = quarantineDirectory.appendingPathComponent(
            "\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.lowercased()).json"
        )
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.moveItem(at: url, to: destination)
            Self.excludeFromBackup(destination)
        }
    }

    private func cleanupExpiredOrphanAttachments(now: Date, fileManager: FileManager) throws {
        let directories = try fileManager.contentsOfDirectory(
            at: attachmentsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        for directory in directories {
            let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modifiedAt = values?.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) > Self.retentionInterval
            else {
                continue
            }
            try? fileManager.removeItem(at: directory)
        }
    }

    private static func safeFileName(_ value: String) -> String {
        let lastPathComponent = URL(fileURLWithPath: value).lastPathComponent
        let cleaned = lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Shared places.txt" : cleaned
    }

    private static func isValidDeliveryID(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
