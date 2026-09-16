import Foundation

struct CheckInCustomQuestion: Codable, Equatable, Identifiable {
    static let idPrefix = "custom_question_"
    static let maximumPromptLength = 120

    let id: String
    let prompt: String

    static func normalizedPrompt(_ prompt: String) -> String {
        prompt.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func isCustomID(_ id: String) -> Bool {
        guard id.hasPrefix(idPrefix) else { return false }
        return UUID(uuidString: String(id.dropFirst(idPrefix.count))) != nil
    }
}

struct CheckInQuestionConfiguration: Codable, Equatable {
    var orderedQuestionIDs: [String]
    /// Definitions survive removal so historical answers retain their meaning.
    private(set) var customQuestions: [CheckInCustomQuestion]
    private(set) var stealthByQuestionID: [String: Bool]

    init(orderedQuestionIDs: [String], customQuestions: [CheckInCustomQuestion] = [], stealthByQuestionID: [String: Bool] = [:]) {
        var seen = Set<String>()
        self.orderedQuestionIDs = orderedQuestionIDs.filter { seen.insert($0).inserted }
        self.customQuestions = customQuestions
        self.stealthByQuestionID = stealthByQuestionID
    }

    private enum CodingKeys: String, CodingKey {
        case orderedQuestionIDs, customQuestions, stealthByQuestionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderedQuestionIDs = try container.decode([String].self, forKey: .orderedQuestionIDs)
        customQuestions = try container.decodeIfPresent([CheckInCustomQuestion].self, forKey: .customQuestions) ?? []
        stealthByQuestionID = try container.decodeIfPresent([String: Bool].self, forKey: .stealthByQuestionID) ?? [:]
    }

    func isStealth(questionID: String) -> Bool {
        stealthByQuestionID[questionID] ?? CheckInCustomQuestion.isCustomID(questionID)
    }

    mutating func setStealth(_ isStealth: Bool, questionID: String) {
        stealthByQuestionID[questionID] = isStealth
    }

    mutating func addCatalogQuestion(id: String, stealth: Bool = false) {
        guard !orderedQuestionIDs.contains(id) else { return }
        orderedQuestionIDs.append(id)
        setStealth(stealth, questionID: id)
    }

    @discardableResult
    mutating func addCustomQuestion(prompt: String, stealth: Bool = true) throws -> CheckInCustomQuestion {
        let normalized = CheckInCustomQuestion.normalizedPrompt(prompt)
        guard !normalized.isEmpty,
              normalized.count <= CheckInCustomQuestion.maximumPromptLength
        else { throw CheckInQuestionPersistenceError.invalidPrompt }

        let question = customQuestions.first {
            $0.prompt.caseInsensitiveCompare(normalized) == .orderedSame
        } ?? CheckInCustomQuestion(
            id: CheckInCustomQuestion.idPrefix + UUID().uuidString.lowercased(),
            prompt: normalized
        )
        if !customQuestions.contains(where: { $0.id == question.id }) {
            customQuestions.append(question)
        }
        addCatalogQuestion(id: question.id, stealth: stealth)
        return question
    }

    mutating func retainDefinition(_ question: CheckInCustomQuestion) {
        if !customQuestions.contains(where: { $0.id == question.id }) {
            customQuestions.append(question)
        }
    }

    mutating func removeQuestions(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where orderedQuestionIDs.indices.contains(index) {
            orderedQuestionIDs.remove(at: index)
        }
    }

    mutating func moveQuestions(from offsets: IndexSet, to destination: Int) {
        let valid = offsets.filter { orderedQuestionIDs.indices.contains($0) }.sorted()
        guard !valid.isEmpty else { return }
        let moved = valid.map { orderedQuestionIDs[$0] }
        let insertion = destination - valid.filter { $0 < destination }.count
        for index in valid.reversed() {
            orderedQuestionIDs.remove(at: index)
        }
        orderedQuestionIDs.insert(contentsOf: moved, at: max(0, min(insertion, orderedQuestionIDs.count)))
    }

    mutating func restoreSuggestedQuestions(_ ids: [String]) {
        var seen = Set<String>()
        orderedQuestionIDs = ids.filter { seen.insert($0).inserted }
    }
}

enum CheckInQuestionAnswerPolicy {
    static func toggling(_ option: String, selected: Set<String>) -> Set<String> {
        selected.contains(option) ? [] : [option]
    }

    static func togglingPrivate(_ value: String, current: String?) -> String? {
        guard value == "yes" || value == "no" else { return current }
        return current == value ? nil : value
    }
}

enum CheckInQuestionPersistenceError: Error, LocalizedError {
    case invalidAccount
    case invalidScope
    case invalidPrompt
    case invalidConfiguration
    case invalidPrivateAnswer
    case unreadableStorage

    var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            "Write a question using 1–120 characters."
        case .invalidAccount:
            "Sign in to customize your questions."
        case .invalidScope, .invalidConfiguration, .unreadableStorage:
            "Your questions couldn’t be saved on this device. Please try again."
        case .invalidPrivateAnswer:
            "Your private answers couldn’t be saved on this device. Please try again."
        }
    }
}

/// Local account-scoped preferences and private answers. Shared custom answers
/// use an explicit, separate serialization path with the Check-in's audience.
@MainActor
struct CheckInQuestionPreferenceStore {
    static let didChangeNotification = Notification.Name("astir.checkInQuestions.changed")
    private let defaults: UserDefaults
    private static let keyPrefix = "astir.checkInQuestions.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func configuration(
        ownerUserID: String,
        subtypeKey: String,
        defaultQuestionIDs: [String]
    ) -> CheckInQuestionConfiguration {
        guard !ownerUserID.isEmpty, !subtypeKey.isEmpty,
              let account = try? readAccount(ownerUserID: ownerUserID),
              let configuration = account.configurations[subtypeKey]
        else { return CheckInQuestionConfiguration(orderedQuestionIDs: defaultQuestionIDs) }
        return configuration
    }

    func saveConfiguration(
        _ configuration: CheckInQuestionConfiguration,
        ownerUserID: String,
        subtypeKey: String
    ) throws {
        guard !subtypeKey.isEmpty else { throw CheckInQuestionPersistenceError.invalidScope }
        try validate(configuration)
        var account = try readAccount(ownerUserID: ownerUserID)
        // Removed prompts do not remove definitions, even if a caller rebuilt
        // the visible configuration instead of using the provided reducer.
        let retainedDefinitions = account.configurations[subtypeKey]?.customQuestions ?? []
        var definitions = retainedDefinitions
        for question in configuration.customQuestions {
            if let existing = definitions.first(where: { $0.id == question.id }) {
                guard existing == question else {
                    throw CheckInQuestionPersistenceError.invalidConfiguration
                }
            } else {
                guard !account.configurations.values.flatMap(\.customQuestions).contains(where: { $0.id == question.id }) else {
                    throw CheckInQuestionPersistenceError.invalidConfiguration
                }
                definitions.append(question)
            }
        }
        account.configurations[subtypeKey] = CheckInQuestionConfiguration(
            orderedQuestionIDs: configuration.orderedQuestionIDs,
            customQuestions: definitions,
            stealthByQuestionID: configuration.stealthByQuestionID
        )
        try writeAccount(account)
    }

    func allCustomQuestions(ownerUserID: String) -> [CheckInCustomQuestion] {
        guard let account = try? readAccount(ownerUserID: ownerUserID) else { return [] }
        return account.configurations.keys.sorted().flatMap {
            account.configurations[$0]?.customQuestions ?? []
        }
    }

    func configuredSubtypeKeys(ownerUserID: String) -> [String] {
        guard let account = try? readAccount(ownerUserID: ownerUserID) else { return [] }
        return account.configurations.keys.sorted()
    }

    /// Recover definitions from this owner's explicit shared answers when an
    /// editor opens on another device. This never adds a recurring prompt or
    /// changes the privacy of an existing answer.
    func retainRecoveredDefinitions(
        _ questions: [CheckInCustomQuestion],
        ownerUserID: String,
        subtypeKey: String,
        defaultQuestionIDs: [String]
    ) throws {
        guard !questions.isEmpty else { return }
        var value = configuration(ownerUserID: ownerUserID, subtypeKey: subtypeKey, defaultQuestionIDs: defaultQuestionIDs)
        let owned = allCustomQuestions(ownerUserID: ownerUserID)
        var changed = false
        for question in questions {
            if let existing = owned.first(where: { $0.id == question.id }) {
                guard existing == question else { throw CheckInQuestionPersistenceError.invalidConfiguration }
            } else {
                value.retainDefinition(question)
                changed = true
            }
        }
        if changed { try saveConfiguration(value, ownerUserID: ownerUserID, subtypeKey: subtypeKey) }
    }

    func privateAnswers(
        ownerUserID: String,
        userPlaceID: String,
        visitID: String
    ) -> [String: String] {
        (try? loadPrivateAnswers(ownerUserID: ownerUserID, userPlaceID: userPlaceID, visitID: visitID)) ?? [:]
    }

    /// Editors use the throwing loader so unreadable storage cannot look like
    /// an empty answer set and accidentally overwrite previously saved answers.
    func loadPrivateAnswers(
        ownerUserID: String,
        userPlaceID: String,
        visitID: String
    ) throws -> [String: String] {
        guard !userPlaceID.isEmpty, !visitID.isEmpty else {
            throw CheckInQuestionPersistenceError.invalidScope
        }
        var account = try readAccount(ownerUserID: ownerUserID)
        guard var record = account.answers[visitID] else { return [:] }
        do { try validatePrivateAnswers(record.answers, account: account) }
        catch { throw CheckInQuestionPersistenceError.unreadableStorage }
        // The visit UUID survives restoring its parent save with another local
        // ID. Remember that alias for later whole-save deletion, without ever
        // manufacturing a record for an unanswered visit.
        if record.userPlaceIDs.insert(userPlaceID).inserted {
            account.answers[visitID] = record
            try writeAccount(account)
        }
        return record.answers
    }

    /// Validate before submitting the containing check-in, when retrying is
    /// still safe. The commit method repeats validation before its local write.
    func validatePrivateAnswers(_ answers: [String: String], ownerUserID: String) throws {
        let account = try readAccount(ownerUserID: ownerUserID)
        try validatePrivateAnswers(answers, account: account)
    }

    /// Call only after the containing check-in succeeds. Pass its server UUID,
    /// assigned at local visit creation, or its local ID for a legacy visit
    /// without a UUID. Parent local IDs are aliases, never answer identity.
    func savePrivateAnswers(
        _ answers: [String: String],
        ownerUserID: String,
        userPlaceID: String,
        visitID: String
    ) throws {
        guard !userPlaceID.isEmpty, !visitID.isEmpty else {
            throw CheckInQuestionPersistenceError.invalidScope
        }
        var account = try readAccount(ownerUserID: ownerUserID)
        try validatePrivateAnswers(answers, account: account)
        guard !answers.isEmpty else {
            if account.answers.removeValue(forKey: visitID) != nil {
                try writeAccount(account)
            }
            return
        }
        var record = account.answers[visitID] ?? PrivateVisitAnswers(userPlaceIDs: [], answers: [:])
        record.userPlaceIDs.insert(userPlaceID)
        record.answers = answers
        account.answers[visitID] = record
        try writeAccount(account)
    }

    /// Delete only after the corresponding check-in/place deletion succeeds.
    /// A nil visit removes every private answer belonging to this local save.
    func removeAnswers(ownerUserID: String, userPlaceID: String, visitID: String?) throws {
        guard !userPlaceID.isEmpty, visitID?.isEmpty != true else {
            throw CheckInQuestionPersistenceError.invalidScope
        }
        var account = try readAccount(ownerUserID: ownerUserID)
        let countBeforeDeletion = account.answers.count
        if let visitID {
            account.answers.removeValue(forKey: visitID)
        } else {
            account.answers = account.answers.filter { !$0.value.userPlaceIDs.contains(userPlaceID) }
        }
        if account.answers.count != countBeforeDeletion {
            try writeAccount(account)
        }
    }

    /// Promote a legacy local visit key once sync supplies its stable UUID.
    /// Existing destination answers win collisions; all other answers and both
    /// parent associations survive. No source data is removed until encoding
    /// and the replacement account write succeed.
    func migrateAnswers(ownerUserID: String, fromVisitID: String, toVisitID: String) throws {
        guard !fromVisitID.isEmpty, !toVisitID.isEmpty else {
            throw CheckInQuestionPersistenceError.invalidScope
        }
        guard fromVisitID != toVisitID else { return }
        var account = try readAccount(ownerUserID: ownerUserID)
        guard let source = account.answers[fromVisitID] else { return }
        try validatePrivateAnswers(source.answers, account: account)
        var destination = account.answers[toVisitID] ?? PrivateVisitAnswers(userPlaceIDs: [], answers: [:])
        try validatePrivateAnswers(destination.answers, account: account)
        destination.answers = source.answers.merging(destination.answers) { _, existing in existing }
        destination.userPlaceIDs.formUnion(source.userPlaceIDs)
        account.answers[toVisitID] = destination
        account.answers.removeValue(forKey: fromVisitID)
        try writeAccount(account)
    }

    /// Account deletion removes even unreadable local data. Ordinary sign-out
    /// can retain the account-scoped preferences for a future sign-in.
    func removeAccount(ownerUserID: String) throws {
        guard !ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CheckInQuestionPersistenceError.invalidAccount
        }
        defaults.removeObject(forKey: Self.accountKey(ownerUserID))
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func validatePrivateAnswers(_ answers: [String: String], account: Account) throws {
        let ownedIDs = Set(account.configurations.values.flatMap(\.customQuestions).map(\.id))
        guard answers.allSatisfy({ id, value in
            if let question = PlaceCheckInQuestionCatalog.question(id: id) {
                return question.options.contains(value)
            }
            return ownedIDs.contains(id) && CheckInCustomQuestion.isCustomID(id) && (value == "yes" || value == "no")
        }) else { throw CheckInQuestionPersistenceError.invalidPrivateAnswer }
    }

    private struct Account: Codable {
        var schemaVersion = 1
        let ownerUserID: String
        var configurations: [String: CheckInQuestionConfiguration] = [:]
        var answers: [String: PrivateVisitAnswers] = [:]
    }

    private struct PrivateVisitAnswers: Codable {
        var userPlaceIDs: Set<String>
        var answers: [String: String]
    }

    private func readAccount(ownerUserID: String) throws -> Account {
        guard !ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CheckInQuestionPersistenceError.invalidAccount
        }
        guard let data = defaults.data(forKey: Self.accountKey(ownerUserID)) else {
            return Account(ownerUserID: ownerUserID)
        }
        guard let account = try? JSONDecoder().decode(Account.self, from: data),
              account.schemaVersion == 1, account.ownerUserID == ownerUserID
        else { throw CheckInQuestionPersistenceError.unreadableStorage }
        return account
    }

    private func writeAccount(_ account: Account) throws {
        let data = try JSONEncoder().encode(account)
        defaults.set(data, forKey: Self.accountKey(account.ownerUserID))
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func validate(_ configuration: CheckInQuestionConfiguration) throws {
        let customIDs = Set(configuration.customQuestions.map(\.id))
        guard customIDs.count == configuration.customQuestions.count,
              Set(configuration.orderedQuestionIDs).count == configuration.orderedQuestionIDs.count,
              configuration.customQuestions.allSatisfy({ question in
                  CheckInCustomQuestion.isCustomID(question.id)
                      && !CheckInCustomQuestion.normalizedPrompt(question.prompt).isEmpty
                      && question.prompt.count <= CheckInCustomQuestion.maximumPromptLength
              }),
              configuration.orderedQuestionIDs.allSatisfy({ id in
                  id.hasPrefix("place_detail_") || customIDs.contains(id)
              }),
              configuration.stealthByQuestionID.keys.allSatisfy({ id in
                  id.hasPrefix("place_detail_") || customIDs.contains(id)
              })
        else { throw CheckInQuestionPersistenceError.invalidConfiguration }
    }

    private static func accountKey(_ ownerUserID: String) -> String {
        keyPrefix + Data(ownerUserID.utf8).base64EncodedString()
    }

}
