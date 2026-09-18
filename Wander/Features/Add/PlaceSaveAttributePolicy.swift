import Foundation

/// The composer owns only fields it renders. Other generations' answers must
/// survive an edit without being reinterpreted or coerced to a new value type.
enum PlaceSaveAttributePolicy {
    static func attributes(
        original: [PlaceAttributeDraft],
        answers: [String: Set<String>],
        tags: Set<String>,
        tagKey: String,
        status: PlaceStatus,
        customQuestions: [CheckInCustomQuestion] = [],
        privateQuestionIDs: Set<String> = []
    ) -> [PlaceAttributeDraft] {
        let normalizedTags = Set(tags.map { $0.lowercased() })
        var assignedTags = Set<String>()
        var result: [PlaceAttributeDraft] = []

        for attribute in original {
            if isTagKey(attribute.questionKey) {
                guard let data = attribute.valueJSON.data(using: .utf8),
                      (try? JSONDecoder().decode([String].self, from: data)) != nil
                        || (try? JSONDecoder().decode(String.self, from: data)) != nil
                else {
                    result.append(attribute)
                    continue
                }
                let retained = strings(attribute.valueJSON).filter { normalizedTags.contains($0.lowercased()) }
                assignedTags.formUnion(retained.map { $0.lowercased() })
                if !retained.isEmpty {
                    result.append(PlaceAttributeDraft(
                        questionKey: attribute.questionKey,
                        valueType: attribute.valueType,
                        stringValues: retained
                    ))
                }
            } else if !PlaceCheckInQuestionCatalog.isDetailQuestion(attribute.questionKey)
                        && !CheckInCustomQuestion.isCustomID(attribute.questionKey) {
                result.append(attribute)
            }
        }

        let addedTags = tags.filter { !assignedTags.contains($0.lowercased()) }.sorted()
        if !addedTags.isEmpty {
            // An unknown older tag payload is not ours to coerce. Put new
            // selections in a separate, ordinary tag field in that rare case.
            var destination = tagKey
            while let existing = result.first(where: { $0.questionKey == destination }),
                  !isStringPayload(existing.valueJSON) {
                destination = destination == tagKey ? "place_memory_tags" : destination + "_tags"
            }
            if let index = result.firstIndex(where: { $0.questionKey == destination }),
               isStringPayload(result[index].valueJSON) {
                result[index] = PlaceAttributeDraft(
                    questionKey: destination,
                    valueType: result[index].valueType,
                    stringValues: strings(result[index].valueJSON) + addedTags
                )
            } else {
                result.append(PlaceAttributeDraft(questionKey: destination, valueType: "multi_tag", stringValues: addedTags))
            }
        }

        // Wanna edits retain old observations verbatim, but never create new
        // firsthand answers. Fresh Check-ins start with an empty answer map.
        if status == .wannaGo {
            result += original.filter { PlaceCheckInQuestionCatalog.isDetailQuestion($0.questionKey) }
        } else {
            let originalByKey = Dictionary(original.map { ($0.questionKey, $0) }, uniquingKeysWith: { _, last in last })
            let recovered = original.compactMap { SharedCheckInQuestion.decode($0)?.question }
            let definitions = Dictionary((recovered + customQuestions).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for key in answers.keys.sorted() where CheckInCustomQuestion.isCustomID(key) {
                guard !privateQuestionIDs.contains(key), let values = answers[key],
                      let answer = ["yes", "no"].first(where: { values.contains($0) }),
                      let question = definitions[key],
                      let shared = SharedCheckInQuestion.encode(question: question, answer: answer)
                else { continue }
                result.append(shared)
            }
            for key in answers.keys.sorted()
            where PlaceCheckInQuestionCatalog.isDetailQuestion(key) && !SharedCheckInQuestion.isSharedQuestion(key) {
                guard !privateQuestionIDs.contains(key), let values = answers[key], !values.isEmpty else { continue }
                if let question = PlaceCheckInQuestionCatalog.question(id: key),
                   let answer = question.acceptedOptions.first(where: { values.contains($0) }) {
                    if question.allowsMultipleSelection {
                        result.append(PlaceAttributeDraft(questionKey: key, valueType: question.valueType, stringValues: question.answerOptions.filter(values.contains)))
                    } else {
                        result.append(PlaceAttributeDraft(questionKey: key, valueType: question.valueType, stringValue: answer))
                    }
                } else if let original = originalByKey[key] {
                    result.append(original)
                }
            }
            // Unknown future fields may not decode into the UI's string map.
            result += original.filter {
                guard PlaceCheckInQuestionCatalog.isDetailQuestion($0.questionKey) else { return false }
                let answerKey = SharedCheckInQuestion.customQuestionID(for: $0.questionKey) ?? $0.questionKey
                return !privateQuestionIDs.contains(answerKey) && answers[answerKey] == nil
            }
        }
        return result
    }

    static func isTagKey(_ key: String) -> Bool {
        key.hasSuffix("_tags") || key == PlaceMemoryAttributeKeys.personalLabels
    }

    private static func isStringPayload(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        return (try? JSONDecoder().decode([String].self, from: data)) != nil
            || (try? JSONDecoder().decode(String.self, from: data)) != nil
    }

    private static func strings(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        if let values = try? JSONDecoder().decode([String].self, from: data) { return values }
        if let value = try? JSONDecoder().decode(String.self, from: data) { return [value] }
        return []
    }
}
