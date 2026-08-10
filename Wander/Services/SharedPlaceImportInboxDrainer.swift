import Foundation

enum SharedPlaceImportDrainPolicy {
    static func canDrain(isSessionValidated: Bool, isSignedIn: Bool) -> Bool {
        isSessionValidated && isSignedIn
    }
}

struct SharedPlaceImportDrainReport: Equatable {
    let batchIDs: [String]
    let importedBatchCount: Int
    let duplicateBatchCount: Int
    let failedEnvelopeCount: Int
    let quarantinedEnvelopeCount: Int
    let expiredEnvelopeCount: Int

    static let empty = SharedPlaceImportDrainReport(
        batchIDs: [],
        importedBatchCount: 0,
        duplicateBatchCount: 0,
        failedEnvelopeCount: 0,
        quarantinedEnvelopeCount: 0,
        expiredEnvelopeCount: 0
    )

    var importedOrDuplicateBatchCount: Int {
        importedBatchCount + duplicateBatchCount
    }

    var hasUserVisibleResult: Bool {
        importedOrDuplicateBatchCount > 0
            || failedEnvelopeCount > 0
            || quarantinedEnvelopeCount > 0
            || expiredEnvelopeCount > 0
    }
}

@MainActor
enum SharedPlaceImportInboxDrainer {
    static func drain(
        inbox: SharedPlaceImportInbox,
        into store: PlaceImportStore,
        now: Date = .now
    ) -> SharedPlaceImportDrainReport {
        let scan: SharedPlaceImportInboxScan
        do {
            scan = try inbox.scan(now: now)
        } catch {
            return SharedPlaceImportDrainReport(
                batchIDs: [],
                importedBatchCount: 0,
                duplicateBatchCount: 0,
                failedEnvelopeCount: 1,
                quarantinedEnvelopeCount: 0,
                expiredEnvelopeCount: 0
            )
        }

        var importedBatchCount = 0
        var duplicateBatchCount = 0
        var failedEnvelopeCount = 0
        var batchIDs: [String] = []

        for entry in scan.entries {
            do {
                for (index, item) in entry.envelope.items.enumerated() {
                    let deliveryID = "\(entry.envelope.deliveryID):\(index)"
                    let wasAlreadyImported = store.batch(captureDeliveryID: deliveryID) != nil
                    let source = PlaceImportSource(rawValue: item.source.rawValue) ?? .textNotes
                    let batchID: String
                    if [.instagram, .tiktok].contains(source),
                       let sourceURLString = item.sourceURLString {
                        batchID = try store.enqueueSharedSocialLink(
                            source: source,
                            urlString: sourceURLString,
                            caption: item.contextText,
                            sourceName: item.suggestedName,
                            captureDeliveryID: deliveryID
                        )
                    } else {
                        let contents = try contents(for: item, inbox: inbox)
                        batchID = try store.enqueue(
                            source: source,
                            text: contents.text,
                            sourceName: contents.fileName,
                            captureDeliveryID: deliveryID
                        )
                    }
                    if !batchIDs.contains(batchID) {
                        batchIDs.append(batchID)
                    }
                    if wasAlreadyImported {
                        duplicateBatchCount += 1
                    } else {
                        importedBatchCount += 1
                    }
                }
                try inbox.acknowledge(entry)
            } catch {
                try? inbox.quarantine(entry)
                failedEnvelopeCount += 1
            }
        }

        return SharedPlaceImportDrainReport(
            batchIDs: batchIDs,
            importedBatchCount: importedBatchCount,
            duplicateBatchCount: duplicateBatchCount,
            failedEnvelopeCount: failedEnvelopeCount,
            quarantinedEnvelopeCount: scan.quarantinedCount,
            expiredEnvelopeCount: scan.expiredCount
        )
    }

    private static func contents(
        for item: SharedPlaceImportEnvelopeItem,
        inbox: SharedPlaceImportInbox
    ) throws -> PlaceImportFileContents {
        switch item.kind {
        case .text:
            guard let text = item.text else {
                throw SharedPlaceImportInboxError.invalidEnvelope
            }
            return PlaceImportFileContents(
                text: text,
                fileName: item.suggestedName ?? "Shared places.txt"
            )
        case .file:
            let fileURL = try inbox.attachmentURL(for: item)
            return try PlaceImportFileReader.read(fileURL)
        }
    }
}
