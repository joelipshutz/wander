import Foundation

/// Reads the latest explicit answer for each question from available visit
/// history. A later unanswered visit doesn't turn an earlier Yes into No.
enum PlaceCheckInObservationProjection {
    static func attributes(
        base: [LocalPlaceAttribute],
        visits: [LocalPlaceVisit],
        userPlaceID: String,
        status: PlaceStatus,
        hasLoadedVisitHistory: Bool = false
    ) -> [LocalPlaceAttribute] {
        let ordinary = base.filter { !PlaceCheckInQuestionCatalog.isDetailQuestion($0.questionKey) }
        guard status == .been else { return ordinary }
        // A successful history read with no active visits is an authoritative
        // deletion. An unloaded history still needs its cached parent details.
        if hasLoadedVisitHistory && !visits.contains(where: { $0.deletedAt == nil }) {
            return ordinary
        }
        guard !visits.isEmpty else { return base }
        guard visits.contains(where: { $0.attributeAnswersAreComplete == true }) else { return base }
        let activeVisits = visits.filter { $0.deletedAt == nil }
        let incompleteVisits = activeVisits.filter { $0.attributeAnswersAreComplete != true }
        let sortedVisits = activeVisits.filter { $0.attributeAnswersAreComplete == true }.sorted {
            if $0.visitedAt != $1.visitedAt { return $0.visitedAt > $1.visitedAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.localID < $1.localID
        }
        var latest: [String: LocalPlaceAttribute] = [:]
        var sourceVisits: [String: LocalPlaceVisit] = [:]
        for visit in sortedVisits {
            for answer in VisitAttributeAnswers.drafts(fromAttributeAnswersJSON: visit.attributeAnswersJSON)
            where PlaceCheckInQuestionCatalog.isDetailQuestion(answer.questionKey) && latest[answer.questionKey] == nil {
                latest[answer.questionKey] = LocalPlaceAttribute(
                    localID: "visit-detail-\(visit.localID)-\(answer.questionKey)",
                    userPlaceID: userPlaceID,
                    questionKey: answer.questionKey,
                    valueType: answer.valueType,
                    valueJSON: answer.valueJSON,
                    syncState: visit.syncState,
                    createdAt: visit.visitedAt,
                    updatedAt: visit.updatedAt
                )
                sourceVisits[answer.questionKey] = visit
            }
        }
        // An incomplete visit is not evidence that its answers were cleared.
        // The parent may contain a newer observation that history has not yet
        // hydrated. Preserve its payload and original dates; assigning a visit
        // date here would invent an observation time we do not know.
        for attribute in base where PlaceCheckInQuestionCatalog.isDetailQuestion(attribute.questionKey) {
            guard let knownVisit = sourceVisits[attribute.questionKey] else {
                if !incompleteVisits.isEmpty { latest[attribute.questionKey] = attribute }
                continue
            }
            let mayContainLaterAnswer = incompleteVisits.contains { unknownVisit in
                if unknownVisit.visitedAt != knownVisit.visitedAt {
                    return unknownVisit.visitedAt > knownVisit.visitedAt
                }
                // Equal available dates cannot establish that the known
                // observation is newer, so retain the parent conservatively.
                return unknownVisit.createdAt >= knownVisit.createdAt
            }
            if mayContainLaterAnswer { latest[attribute.questionKey] = attribute }
        }
        return ordinary + latest.values.sorted { $0.questionKey < $1.questionKey }
    }
}
