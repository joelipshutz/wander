import Foundation

enum CommunityReportSubjectKind: String, Codable, CaseIterable, Equatable {
    case profile
    case activity
    case comment
    case userPlace = "user_place"
    case visitPhoto = "visit_photo"
    case placeList = "place_list"

    var displayName: String {
        switch self {
        case .profile: "profile"
        case .activity: "activity"
        case .comment: "comment"
        case .userPlace: "place memory"
        case .visitPhoto: "photo"
        case .placeList: "list"
        }
    }
}

struct CommunityReportSubject: Identifiable, Equatable {
    let kind: CommunityReportSubjectKind
    let subjectID: String
    let reportedUserID: String
    let context: String

    var id: String {
        "\(kind.rawValue):\(subjectID):\(reportedUserID)"
    }
}

enum CommunityReportReason: String, Codable, CaseIterable, Equatable, Identifiable {
    case spam
    case harassment
    case hateOrAbuse = "hate_or_abuse"
    case sexualContent = "sexual_content"
    case dangerousContent = "dangerous_content"
    case impersonation
    case privacy
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: "Spam or scam"
        case .harassment: "Harassment or bullying"
        case .hateOrAbuse: "Hate or abusive content"
        case .sexualContent: "Sexual content"
        case .dangerousContent: "Threats or dangerous content"
        case .impersonation: "Impersonation"
        case .privacy: "Privacy concern"
        case .other: "Something else"
        }
    }

    var systemImage: String {
        switch self {
        case .spam: "exclamationmark.bubble"
        case .harassment: "person.crop.circle.badge.exclamationmark"
        case .hateOrAbuse: "hand.raised"
        case .sexualContent: "eye.slash"
        case .dangerousContent: "exclamationmark.triangle"
        case .impersonation: "person.crop.circle.badge.questionmark"
        case .privacy: "lock.shield"
        case .other: "ellipsis.circle"
        }
    }
}

struct CommunityReportSubmission: Equatable {
    let subject: CommunityReportSubject
    let reason: CommunityReportReason
    let details: String?
}

struct CommunityReportReceipt: Codable, Equatable {
    let reportID: String
    let status: String
    let createdAt: Date
    let isDuplicate: Bool

    enum CodingKeys: String, CodingKey {
        case reportID = "report_id"
        case status
        case createdAt = "created_at"
        case isDuplicate = "is_duplicate"
    }
}

@MainActor
protocol CommunityReportRepository {
    func submit(_ submission: CommunityReportSubmission) async throws -> CommunityReportReceipt
}

enum CommunityContentPolicyError: LocalizedError, Equatable {
    case prohibitedContent

    var errorDescription: String? {
        "That text can’t be shared on rec.me. Please revise it and try again."
    }
}

/// A deliberately conservative, deterministic first-pass filter for obvious
/// slurs, targeted threats, and sexual exploitation language. Server triggers
/// enforce the same contract; reporting and human review remain authoritative.
enum CommunityContentPolicy {
    private static let blockedTokens: Set<String> = [
        "chink", "faggot", "kike", "kys", "nigga", "nigger", "spic"
    ]

    private static let blockedPhrases = [
        "child porn",
        "child pornography",
        "go kill yourself",
        "heil hitler",
        "i will kill you",
        "kill yourself",
        "rape you"
    ]

    static func allows(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return true }
        let normalized = normalized(text)
        guard !normalized.isEmpty else { return true }
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        if !tokens.isDisjoint(with: blockedTokens) {
            return false
        }
        let padded = " \(normalized) "
        return !blockedPhrases.contains { padded.contains(" \($0) ") }
    }

    static func validate(_ values: String?...) throws {
        if values.contains(where: { !allows($0) }) {
            throw CommunityContentPolicyError.prohibitedContent
        }
    }

    static func validateJSONText(_ json: String) throws {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return
        }
        if flattenedStrings(in: object).contains(where: { !allows($0) }) {
            throw CommunityContentPolicyError.prohibitedContent
        }
    }

    private static func normalized(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let leetMap: [Character: Character] = [
            "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"
        ]
        let mapped = folded.map { leetMap[$0] ?? $0 }
        let words = String(mapped)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.joined(separator: " ")
    }

    private static func flattenedStrings(in value: Any) -> [String] {
        switch value {
        case let string as String:
            [string]
        case let array as [Any]:
            array.flatMap(flattenedStrings)
        case let dictionary as [String: Any]:
            dictionary.values.flatMap(flattenedStrings)
        default:
            []
        }
    }
}
