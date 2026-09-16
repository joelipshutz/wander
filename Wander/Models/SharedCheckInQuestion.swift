import Foundation

/// Only explicitly shared custom answers use this envelope. Legacy local
/// custom_question_ records are never interpreted as publication consent.
struct SharedCheckInQuestion: Equatable {
    static let keyPrefix = "place_detail_custom_"

    let question: CheckInCustomQuestion
    let answer: String

    var displayValue: String {
        "\(question.prompt) \(answer == "yes" ? "Yes" : "No")"
    }

    static func isSharedQuestion(_ key: String) -> Bool {
        key.hasPrefix(keyPrefix)
    }

    static func questionKey(for customQuestionID: String) -> String? {
        guard CheckInCustomQuestion.isCustomID(customQuestionID),
              let uuid = UUID(uuidString: String(customQuestionID.dropFirst(CheckInCustomQuestion.idPrefix.count)))
        else { return nil }
        return keyPrefix + uuid.uuidString.lowercased()
    }

    static func customQuestionID(for questionKey: String) -> String? {
        guard isSharedQuestion(questionKey),
              let uuid = UUID(uuidString: String(questionKey.dropFirst(keyPrefix.count)))
        else { return nil }
        return CheckInCustomQuestion.idPrefix + uuid.uuidString.lowercased()
    }

    static func encode(question: CheckInCustomQuestion, answer: String) -> PlaceAttributeDraft? {
        let prompt = CheckInCustomQuestion.normalizedPrompt(question.prompt)
        guard let key = questionKey(for: question.id),
              isValid(prompt: prompt, answer: answer)
        else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Envelope(schemaVersion: 1, prompt: prompt, answer: answer)) else {
            return nil
        }
        return PlaceAttributeDraft(questionKey: key, valueType: "text", valueJSON: String(decoding: data, as: UTF8.self))
    }

    static func decode(_ attribute: PlaceAttributeDraft) -> SharedCheckInQuestion? {
        guard attribute.valueType == "text",
              let id = customQuestionID(for: attribute.questionKey),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(attribute.valueJSON.utf8)),
              envelope.schemaVersion == 1,
              isValid(prompt: envelope.prompt, answer: envelope.answer)
        else { return nil }
        return SharedCheckInQuestion(
            question: CheckInCustomQuestion(id: id, prompt: CheckInCustomQuestion.normalizedPrompt(envelope.prompt)),
            answer: envelope.answer
        )
    }

    static func decode(_ attribute: LocalPlaceAttribute) -> SharedCheckInQuestion? {
        decode(PlaceAttributeDraft(
            questionKey: attribute.questionKey,
            valueType: attribute.valueType,
            valueJSON: attribute.valueJSON
        ))
    }

    private static func isValid(prompt: String, answer: String) -> Bool {
        let normalized = CheckInCustomQuestion.normalizedPrompt(prompt)
        return !normalized.isEmpty
            && normalized.count <= CheckInCustomQuestion.maximumPromptLength
            && (answer == "yes" || answer == "no")
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let prompt: String
        let answer: String

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case prompt, answer
        }
    }
}
