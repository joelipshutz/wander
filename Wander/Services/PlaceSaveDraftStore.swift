import Combine
import Foundation
import UIKit

enum PlaceSaveDraftStep: String, Codable, Equatable {
    case confirm
    case details
}

struct PlaceSaveDraftPhoto: Codable, Equatable, Identifiable {
    let id: UUID
    let contentType: String
    let localAssetRef: String
    let sourcePhotoID: String?
    let byteSize: Int
}

struct PlaceSaveDraftForm: Codable, Equatable {
    var step: PlaceSaveDraftStep
    var selectedAssignment: PlaceCategoryAssignment
    var selectedStatus: PlaceStatus
    var selectedVisibility: PlaceVisibility
    var selectedRatingScore: Double
    var selectedAnswers: [String: Set<String>]
    var unifiedTags: Set<String>
    var selectedCuisine: String?
    var note: String
    var visitedAt: Date
    var plannedDate: Date?
    var photoAttachments: [PlaceSaveDraftPhoto]
    var selectedInviteeUserIDs: [String]
    var isShowingOptionalDetails: Bool
}

struct PlaceSaveDraftUpdate: Equatable {
    let form: PlaceSaveDraftForm
    let submittedAt: Date?
}

struct PlaceSaveDraft: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 1
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    let schemaVersion: Int
    let id: UUID
    let ownerUserID: String
    let createdAt: Date
    var updatedAt: Date
    let sourceType: AddSourceType
    let candidate: PlaceCandidate
    let baselineUserPlaceLocalID: String?
    let baselineVisitLocalID: String?
    var form: PlaceSaveDraftForm
    var submittedAt: Date?
    var recoveryNotice: String?

    init(
        id: UUID = UUID(),
        ownerUserID: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sourceType: AddSourceType,
        candidate: PlaceCandidate,
        baselineUserPlaceLocalID: String?,
        baselineVisitLocalID: String?,
        form: PlaceSaveDraftForm,
        submittedAt: Date? = nil,
        recoveryNotice: String? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.ownerUserID = ownerUserID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceType = sourceType
        self.candidate = candidate
        self.baselineUserPlaceLocalID = baselineUserPlaceLocalID
        self.baselineVisitLocalID = baselineVisitLocalID
        self.form = form
        self.submittedAt = submittedAt
        self.recoveryNotice = recoveryNotice
    }

    func isRestorable(for ownerUserID: String, now: Date) -> Bool {
        schemaVersion == Self.currentSchemaVersion
            && self.ownerUserID == ownerUserID
            && !ownerUserID.isEmpty
            && !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && now.timeIntervalSince(updatedAt) >= 0
            && now.timeIntervalSince(updatedAt) <= Self.maximumAge
    }
}

enum PlaceSaveDraftRestoreOutcome: Equatable {
    case none
    case restored(PlaceSaveDraft)
    case discarded
}

struct PlaceSaveDraftCommitEvidence: Equatable {
    let userPlaceLocalID: String
    let userPlaceUpdatedAt: Date
    let status: PlaceStatus
    let latestVisitLocalID: String?
    let latestVisitCreatedAt: Date?
}

enum PlaceSaveDraftRecoveryOutcome: Equatable {
    case editing
    case committed
    case retry
}

enum PlaceSaveDraftRecoveryPolicy {
    static func outcome(
        for draft: PlaceSaveDraft,
        evidence: PlaceSaveDraftCommitEvidence?
    ) -> PlaceSaveDraftRecoveryOutcome {
        guard let submittedAt = draft.submittedAt else { return .editing }
        guard let evidence else { return .retry }

        switch draft.form.selectedStatus {
        case .wannaGo:
            guard evidence.status == .wannaGo,
                  evidence.userPlaceUpdatedAt >= submittedAt
            else { return .retry }

            if let baseline = draft.baselineUserPlaceLocalID,
               evidence.userPlaceLocalID != baseline {
                return .retry
            }
            return .committed

        case .been:
            guard evidence.status == .been,
                  let latestVisitLocalID = evidence.latestVisitLocalID,
                  let latestVisitCreatedAt = evidence.latestVisitCreatedAt,
                  latestVisitCreatedAt >= submittedAt,
                  latestVisitLocalID != draft.baselineVisitLocalID
            else { return .retry }
            return .committed
        }
    }
}

struct PlaceSaveDraftPersistence {
    let load: () -> PlaceSaveDraft?
    let save: (PlaceSaveDraft?) -> Void
    let flush: () -> Void

    init(
        load: @escaping () -> PlaceSaveDraft?,
        save: @escaping (PlaceSaveDraft?) -> Void,
        flush: @escaping () -> Void = {}
    ) {
        self.load = load
        self.save = save
        self.flush = flush
    }

    @MainActor
    static let live = coalescingFile(
        url: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wander", isDirectory: true)
            .appendingPathComponent("place-save-draft-v1.json")
    )

    static var ephemeral: PlaceSaveDraftPersistence {
        PlaceSaveDraftPersistence(
            load: { nil },
            save: { _ in }
        )
    }

    static func file(url: URL) -> PlaceSaveDraftPersistence {
        PlaceSaveDraftPersistence(
            load: { loadDraft(from: url) },
            save: { saveDraft($0, to: url) }
        )
    }

    static func coalescingFile(url: URL) -> PlaceSaveDraftPersistence {
        let writer = CoalescingPlaceSaveDraftWriter(
            write: { saveDraft($0, to: url) },
            flushOnAppLifecycle: true
        )
        return PlaceSaveDraftPersistence(
            load: {
                writer.flush()
                return loadDraft(from: url)
            },
            save: writer.save,
            flush: writer.flush
        )
    }

    private static func loadDraft(from url: URL) -> PlaceSaveDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let draft = try? JSONDecoder().decode(PlaceSaveDraft.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return draft
    }

    private static func saveDraft(_ draft: PlaceSaveDraft?, to url: URL) {
        do {
            guard let draft else {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            let data = try JSONEncoder().encode(draft)
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            #if DEBUG
            print("Place save draft persistence failed: \(error)")
            #endif
        }
    }
}

private final class CoalescingPlaceSaveDraftWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.grayline.wander.place-save-draft", qos: .utility)
    private let lock = NSLock()
    private let write: (PlaceSaveDraft?) -> Void
    private var pendingWrite: PendingWrite?
    private var isDrainScheduled = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    private enum PendingWrite {
        case save(PlaceSaveDraft)
        case clear
    }

    init(
        write: @escaping (PlaceSaveDraft?) -> Void,
        flushOnAppLifecycle: Bool
    ) {
        self.write = write

        guard flushOnAppLifecycle else { return }
        let notificationCenter = NotificationCenter.default
        lifecycleObservers = [
            notificationCenter.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.flush()
            },
            notificationCenter.addObserver(
                forName: UIApplication.willTerminateNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.flush()
            }
        ]
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func save(_ draft: PlaceSaveDraft?) {
        lock.lock()
        pendingWrite = draft.map(PendingWrite.save) ?? .clear
        guard !isDrainScheduled else {
            lock.unlock()
            return
        }
        isDrainScheduled = true
        lock.unlock()

        queue.async { [self] in
            drain()
        }
    }

    func flush() {
        queue.sync {}
    }

    private func drain() {
        while true {
            lock.lock()
            guard let pendingWrite else {
                isDrainScheduled = false
                lock.unlock()
                return
            }
            self.pendingWrite = nil
            lock.unlock()

            switch pendingWrite {
            case .save(let draft):
                write(draft)
            case .clear:
                write(nil)
            }
        }
    }
}

@MainActor
final class PlaceSaveDraftStore: ObservableObject {
    private(set) var draft: PlaceSaveDraft?

    private let persistence: PlaceSaveDraftPersistence

    init(persistence: PlaceSaveDraftPersistence = .live) {
        self.persistence = persistence
    }

    @discardableResult
    func restore(ownerUserID: String, now: Date = .now) -> PlaceSaveDraftRestoreOutcome {
        guard let persisted = persistence.load() else {
            if draft != nil {
                objectWillChange.send()
            }
            draft = nil
            return .none
        }
        guard persisted.isRestorable(for: ownerUserID, now: now) else {
            clear()
            return .discarded
        }

        if draft?.id != persisted.id {
            objectWillChange.send()
        }
        draft = persisted
        return .restored(persisted)
    }

    func begin(_ draft: PlaceSaveDraft) {
        if self.draft?.id != draft.id {
            objectWillChange.send()
        }
        self.draft = draft
        persistence.save(draft)
    }

    func update(
        draftID: UUID,
        form: PlaceSaveDraftForm,
        submittedAt: Date?,
        now: Date = .now
    ) {
        guard var current = draft, current.id == draftID else { return }
        current.form = form
        current.submittedAt = submittedAt
        current.updatedAt = now
        if submittedAt != nil {
            current.recoveryNotice = nil
        }
        draft = current
        persistence.save(current)
    }

    func prepareRetry(message: String, now: Date = .now) {
        guard var current = draft else { return }
        current.submittedAt = nil
        current.recoveryNotice = message
        current.updatedAt = now
        draft = current
        persistence.save(current)
    }

    func clear() {
        if draft != nil {
            objectWillChange.send()
        }
        draft = nil
        persistence.save(nil)
    }

    func flush() {
        persistence.flush()
    }
}
