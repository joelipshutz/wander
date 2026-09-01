import CoreLocation
import Foundation

struct PlaceImportCandidateMatch: Equatable {
    let candidates: [PlaceCandidate]
    let selectedCandidateID: String?
    let bestScore: Double
}

enum PlaceImportCandidateSelectionPolicy {
    case conservative
    case socialGroundedArea
}

struct PlaceImportSearchRegion: Equatable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let latitudeDelta: CLLocationDegrees
    let longitudeDelta: CLLocationDegrees
}

enum PlaceImportGeography {
    private struct USState {
        let name: String
        let code: String
        let latitude: CLLocationDegrees
        let longitude: CLLocationDegrees
    }

    static func stateCode(in value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }

        if let explicitSuffix = explicitStateSuffix(in: value) {
            return explicitSuffix.code
        }

        var words = normalizedWords(value)
        while let last = words.last, Int(last) != nil {
            words.removeLast()
        }
        for countrySuffix in [["united", "states", "of", "america"], ["united", "states"], ["usa"], ["us"]]
            where words.count >= countrySuffix.count
                && words.suffix(countrySuffix.count).elementsEqual(countrySuffix) {
            words.removeLast(countrySuffix.count)
            break
        }

        let namedCodes = Set(states.compactMap { state -> String? in
            let stateWords = normalizedWords(state.name)
            return words.count >= stateWords.count
                && words.suffix(stateWords.count).elementsEqual(stateWords)
                ? state.code
                : nil
        })
        return namedCodes.count == 1 ? namedCodes.first : nil
    }

    static func mentionedStateCodes(in value: String) -> Set<String> {
        let words = normalizedWords(value)
        return Set(states.compactMap { state in
            guard contains(words, sequence: normalizedWords(state.name)) else { return nil }
            if state.code == "GA", !isUnambiguousUSGeorgia(in: value) {
                return nil
            }
            return state.code
        })
    }

    static func canonicalStateName(for code: String) -> String? {
        stateByCode[code.uppercased()]?.name
    }

    static func searchRegion(for area: String?) -> PlaceImportSearchRegion? {
        guard let code = areaStateCode(in: area), let state = stateByCode[code] else { return nil }
        let span: (latitude: CLLocationDegrees, longitude: CLLocationDegrees)
        switch code {
        case "AK":
            span = (24, 50)
        case "HI":
            span = (8, 14)
        default:
            span = (12, 18)
        }
        return PlaceImportSearchRegion(
            latitude: state.latitude,
            longitude: state.longitude,
            latitudeDelta: span.latitude,
            longitudeDelta: span.longitude
        )
    }

    static func localityText(in area: String?) -> String? {
        guard let area = area?.trimmingCharacters(in: .whitespacesAndNewlines),
              !area.isEmpty,
              let code = areaStateCode(in: area)
        else {
            let trimmed = area?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        if let explicitSuffix = explicitStateSuffix(in: area), explicitSuffix.code == code {
            var locality = area
            locality.removeSubrange(explicitSuffix.range)
            locality = locality.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: ",;")
                )
            )
            return locality.isEmpty ? nil : locality
        }

        var rawWords = area.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var foldedWords = rawWords.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
        }

        let countryWords: Set<String> = ["america", "states", "united", "us", "usa"]
        for index in foldedWords.indices.reversed() where countryWords.contains(foldedWords[index]) {
            rawWords.remove(at: index)
            foldedWords.remove(at: index)
        }

        if let stateName = canonicalStateName(for: code) {
            let stateWords = normalizedWords(stateName)
            if foldedWords.count >= stateWords.count,
               foldedWords.suffix(stateWords.count).elementsEqual(stateWords) {
                rawWords.removeLast(stateWords.count)
                foldedWords.removeLast(stateWords.count)
            }
        }

        let locality = rawWords.joined(separator: " ")
        return locality.isEmpty ? nil : locality
    }

    static func candidateConflictsWithArea(_ candidate: PlaceCandidate, areaHint: String?) -> Bool {
        if let expectedCountryCode = explicitInternationalArea(in: areaHint)?.countryCode,
           let candidateCountryCode = SocialImportCountry.isoCode(for: candidate.country),
           expectedCountryCode != candidateCountryCode {
            return true
        }
        guard let requestedState = areaStateCode(in: areaHint),
              let candidateState = candidateStateCode(candidate)
        else { return false }
        return requestedState != candidateState
    }

    static func candidateStronglyMatchesArea(
        _ candidate: PlaceCandidate,
        areaHint: String?
    ) -> Bool {
        guard !candidateConflictsWithArea(candidate, areaHint: areaHint),
              let locality = localityText(in: areaHint)
        else { return false }

        if let internationalMatch = candidateMatchesExplicitInternationalArea(
            candidate,
            areaHint: areaHint
        ) {
            return internationalMatch
        }

        let requestedTokens = requestedLocalityTokens(locality)
        guard !requestedTokens.isEmpty else { return false }

        let candidateTokens = candidateAreaTokens(candidate)
        return requestedTokens.isSubset(of: candidateTokens)
    }

    static func candidateHasCompatibleAreaEvidence(
        _ candidate: PlaceCandidate,
        areaHint: String?
    ) -> Bool {
        guard let areaHint = areaHint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !areaHint.isEmpty
        else { return true }
        guard !candidateConflictsWithArea(candidate, areaHint: areaHint) else { return false }

        if let internationalMatch = candidateMatchesExplicitInternationalArea(
            candidate,
            areaHint: areaHint
        ) {
            return internationalMatch
        }

        if let locality = localityText(in: areaHint),
           !requestedLocalityTokens(locality).isEmpty {
            return candidateStronglyMatchesArea(candidate, areaHint: areaHint)
        }
        if let requestedState = areaStateCode(in: areaHint),
           let candidateState = candidateStateCode(candidate) {
            return requestedState == candidateState
        }
        return candidateStronglyMatchesArea(candidate, areaHint: areaHint)
    }

    static func candidateMatchesExplicitInternationalCountryWithoutRecognizedSubdivision(
        _ candidate: PlaceCandidate,
        areaHint: String?
    ) -> Bool {
        guard let context = explicitInternationalArea(in: areaHint),
              let candidateCountryCode = SocialImportCountry.isoCode(for: candidate.country)
        else { return false }
        guard context.countryCode == candidateCountryCode else { return false }
        return context.details.allSatisfy {
            recognizedSubdivisionCode(
                for: $0,
                countryCode: candidateCountryCode
            ) == nil
        }
    }

    static func candidateMatchesExplicitState(
        _ candidate: PlaceCandidate,
        areaHint: String?
    ) -> Bool {
        guard let requestedState = areaStateCode(in: areaHint),
              let candidateState = candidateStateCode(candidate)
        else { return false }
        return requestedState == candidateState
    }

    static func isDistinctiveLandmarkFeatureName(_ value: String) -> Bool {
        let tokens = normalizedWords(value)
        guard tokens.count >= 2 else { return false }

        if landmarkFeaturePrefixes.contains(tokens[0]), tokens.count == 2 {
            return isDistinctiveLandmarkToken(tokens[1])
        }

        guard let suffix = tokens.last,
              landmarkFeatureSuffixes.contains(suffix)
        else { return false }
        return tokens.dropLast().contains(where: isDistinctiveLandmarkToken)
    }

    static func candidateMatchesDistinctiveFeatureCore(
        _ candidateName: String,
        nameHint: String
    ) -> Bool {
        let hintTokens = normalizedWords(nameHint)
        let candidateTokens = normalizedWords(candidateName)
        guard hintTokens.count >= 3,
              let suffix = hintTokens.last,
              providerCoreRemovableFeatureSuffixes.contains(suffix)
        else { return false }

        let featureCore = Array(hintTokens.dropLast())
        return candidateTokens == featureCore
            && featureCore.count >= 2
            && featureCore.contains(where: isDistinctiveLandmarkToken)
    }

    static func areaTokens(_ value: String) -> Set<String> {
        var result = Set(normalizedWords(value))
        if let stateCode = areaStateCode(in: value) {
            result.insert(stateCode.lowercased())
            if let name = canonicalStateName(for: stateCode) {
                result.formUnion(normalizedWords(name))
            }
        }
        return result
    }

    static func candidateAreaTokens(_ candidate: PlaceCandidate) -> Set<String> {
        let structuredArea = [candidate.address, candidate.locality, candidate.region]
            .compactMap { $0 }
            .joined(separator: " ")
        var result = areaTokens(structuredArea)
        if let country = candidate.country {
            // A provider country code such as CA means Canada, not the U.S.
            // state of California. Preserve it as raw evidence without passing
            // it through the state-code expander.
            result.formUnion(normalizedWords(country))
        }
        return result
    }

    private static func candidateStateCode(_ candidate: PlaceCandidate) -> String? {
        if let countryCode = SocialImportCountry.isoCode(for: candidate.country),
           countryCode != "US" {
            return nil
        }
        return stateCode(in: candidate.region)
            ?? stateCode(in: candidate.address)
            ?? stateCode(in: [candidate.locality, candidate.region]
                .compactMap { $0 }
                .joined(separator: ", "))
    }

    private static func candidateMatchesExplicitInternationalArea(
        _ candidate: PlaceCandidate,
        areaHint: String?
    ) -> Bool? {
        guard let context = explicitInternationalArea(in: areaHint),
              let candidateCountryCode = SocialImportCountry.isoCode(for: candidate.country)
        else { return nil }
        guard context.countryCode == candidateCountryCode else { return false }
        guard !context.details.isEmpty else { return true }

        let candidateTokens = candidateAreaTokens(candidate)
        let candidateSubdivisionKeys = subdivisionKeys(
            for: candidate.region,
            countryCode: candidateCountryCode
        )

        return context.details.contains { detail in
            let requestedTokens = Set(normalizedWords(detail))
                .subtracting(broadAreaQualifierTokens)
            if !requestedTokens.isEmpty,
               requestedTokens.isSubset(of: candidateTokens) {
                return true
            }

            let requestedSubdivisionKeys = subdivisionKeys(
                for: detail,
                countryCode: candidateCountryCode
            )
            return !requestedSubdivisionKeys.isDisjoint(with: candidateSubdivisionKeys)
        }
    }

    private static func explicitInternationalArea(
        in value: String?
    ) -> (countryCode: String, details: [String])? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              areaStateCode(in: value) == nil
        else { return nil }

        let components = value.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let country = components.last,
              let countryCode = SocialImportCountry.isoCode(for: country)
        else { return nil }
        return (countryCode, Array(components.dropLast()))
    }

    private static func subdivisionKeys(
        for value: String?,
        countryCode: String
    ) -> Set<String> {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return [] }

        let normalizedValue = normalizedWords(value).joined()
        guard !normalizedValue.isEmpty else { return [] }
        var keys: Set<String> = [normalizedValue]

        if let aliases = subdivisionCodesByCountry[countryCode],
           let code = recognizedSubdivisionCode(
               for: value,
               countryCode: countryCode
           ) {
            keys.insert(code.lowercased())
            for (name, code) in aliases where code.caseInsensitiveCompare(normalizedValue) == .orderedSame {
                keys.insert(name)
            }
        }

        let words = normalizedWords(value)
        if words.count > 1 {
            keys.insert(words.compactMap(\.first).map(String.init).joined())
        }
        return keys
    }

    private static func recognizedSubdivisionCode(
        for value: String?,
        countryCode: String
    ) -> String? {
        guard let value,
              let aliases = subdivisionCodesByCountry[countryCode]
        else { return nil }
        let normalizedValue = normalizedWords(value).joined()
        if let code = aliases[normalizedValue] {
            return code
        }
        return aliases.values.first {
            $0.caseInsensitiveCompare(normalizedValue) == .orderedSame
        }
    }

    private static func requestedLocalityTokens(_ locality: String) -> Set<String> {
        var tokens = Set(normalizedWords(locality))
            .subtracting(broadAreaQualifierTokens)
        // In an unpunctuated area field, "LA" means Los Angeles (the state
        // parser independently requires explicit Louisiana punctuation).
        if tokens.remove("la") != nil {
            tokens.formUnion(["los", "angeles"])
        }
        return tokens
    }

    private static func isDistinctiveLandmarkToken(_ token: String) -> Bool {
        token.count >= 3
            && !featureConnectorTokens.contains(token)
            && !landmarkFeaturePrefixes.contains(token)
            && !landmarkFeatureSuffixes.contains(token)
    }

    private static func areaStateCode(in value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let code = stateCode(in: value)
        else { return nil }

        if code == "GA" {
            // Georgia is both a country and a U.S. state. A postal-code suffix or
            // explicit U.S./"state of" wording is required before adding a U.S.
            // map region or hard-filtering candidates.
            if explicitStateSuffix(in: value)?.code == "GA" {
                return code
            }
            return isUnambiguousUSGeorgia(in: value) ? code : nil
        }

        // "LA" is overwhelmingly used for Los Angeles in a city/neighborhood field.
        // Only interpret the Louisiana postal code when punctuation makes the intent
        // unambiguous (for example "Baton Rouge, LA"). Full "Louisiana" remains valid.
        guard code == "LA", !contains(normalizedWords(value), sequence: ["louisiana"]) else {
            return code
        }
        let louisianaSuffix = #"(?i),\s*l\.?\s*a\.?(?:\s+\d{5}(?:-\d{4})?)?(?:\s*,?\s*(?:u\.?s\.?a?\.?|united\s+states(?:\s+of\s+america)?))?\s*$"#
        return value.range(of: louisianaSuffix, options: .regularExpression) == nil ? nil : code
    }

    static func isUnambiguousUSGeorgia(in value: String) -> Bool {
        let pattern = #"(?i)(?:\bstate\s+of\s+georgia\b|\bgeorgia\b\s*,?\s*(?:u\.?s\.?a?\.?|united\s+states(?:\s+of\s+america)?))"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalizedWords(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func contains(_ words: [String], sequence: [String]) -> Bool {
        guard !sequence.isEmpty, sequence.count <= words.count else { return false }
        if sequence.count == 1 {
            return words.contains(sequence[0])
        }
        return (0...(words.count - sequence.count)).contains { index in
            Array(words[index..<(index + sequence.count)]) == sequence
        }
    }

    private static func explicitStateSuffix(
        in value: String
    ) -> (code: String, range: Range<String.Index>)? {
        let pattern = #"(?i)(?:^|[,\s])([a-z]\.?\s*[a-z]\.?)"#
            + #"(?:\s+\d{5}(?:-\d{4})?)?"#
            + #"(?:\s*,?\s*(?:u\.?s\.?a?\.?|united\s+states(?:\s+of\s+america)?))?\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let searchRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: searchRange),
              let codeRange = Range(match.range(at: 1), in: value),
              let fullRange = Range(match.range, in: value)
        else { return nil }

        let code = value[codeRange]
            .filter { $0.isLetter }
            .uppercased()
        guard stateCodes.contains(code) else { return nil }
        return (code, fullRange)
    }

    private static let states: [USState] = [
        USState(name: "Alabama", code: "AL", latitude: 32.8067, longitude: -86.7911),
        USState(name: "Alaska", code: "AK", latitude: 61.3707, longitude: -152.4044),
        USState(name: "Arizona", code: "AZ", latitude: 33.7298, longitude: -111.4312),
        USState(name: "Arkansas", code: "AR", latitude: 34.9697, longitude: -92.3731),
        USState(name: "California", code: "CA", latitude: 36.1162, longitude: -119.6816),
        USState(name: "Colorado", code: "CO", latitude: 39.0598, longitude: -105.3111),
        USState(name: "Connecticut", code: "CT", latitude: 41.5978, longitude: -72.7554),
        USState(name: "Delaware", code: "DE", latitude: 39.3185, longitude: -75.5071),
        USState(name: "District of Columbia", code: "DC", latitude: 38.9072, longitude: -77.0369),
        USState(name: "Florida", code: "FL", latitude: 27.7663, longitude: -81.6868),
        USState(name: "Georgia", code: "GA", latitude: 33.0406, longitude: -83.6431),
        USState(name: "Hawaii", code: "HI", latitude: 21.0943, longitude: -157.4983),
        USState(name: "Idaho", code: "ID", latitude: 44.2405, longitude: -114.4788),
        USState(name: "Illinois", code: "IL", latitude: 40.3495, longitude: -88.9861),
        USState(name: "Indiana", code: "IN", latitude: 39.8494, longitude: -86.2583),
        USState(name: "Iowa", code: "IA", latitude: 42.0115, longitude: -93.2105),
        USState(name: "Kansas", code: "KS", latitude: 38.5266, longitude: -96.7265),
        USState(name: "Kentucky", code: "KY", latitude: 37.6681, longitude: -84.6701),
        USState(name: "Louisiana", code: "LA", latitude: 31.1695, longitude: -91.8678),
        USState(name: "Maine", code: "ME", latitude: 44.6939, longitude: -69.3819),
        USState(name: "Maryland", code: "MD", latitude: 39.0639, longitude: -76.8021),
        USState(name: "Massachusetts", code: "MA", latitude: 42.2302, longitude: -71.5301),
        USState(name: "Michigan", code: "MI", latitude: 43.3266, longitude: -84.5361),
        USState(name: "Minnesota", code: "MN", latitude: 45.6945, longitude: -93.9002),
        USState(name: "Mississippi", code: "MS", latitude: 32.7416, longitude: -89.6787),
        USState(name: "Missouri", code: "MO", latitude: 38.4561, longitude: -92.2884),
        USState(name: "Montana", code: "MT", latitude: 46.9219, longitude: -110.4544),
        USState(name: "Nebraska", code: "NE", latitude: 41.1254, longitude: -98.2681),
        USState(name: "Nevada", code: "NV", latitude: 38.3135, longitude: -117.0554),
        USState(name: "New Hampshire", code: "NH", latitude: 43.4525, longitude: -71.5639),
        USState(name: "New Jersey", code: "NJ", latitude: 40.2989, longitude: -74.5210),
        USState(name: "New Mexico", code: "NM", latitude: 34.8405, longitude: -106.2485),
        USState(name: "New York", code: "NY", latitude: 42.1657, longitude: -74.9481),
        USState(name: "North Carolina", code: "NC", latitude: 35.6301, longitude: -79.8064),
        USState(name: "North Dakota", code: "ND", latitude: 47.5289, longitude: -99.7840),
        USState(name: "Ohio", code: "OH", latitude: 40.3888, longitude: -82.7649),
        USState(name: "Oklahoma", code: "OK", latitude: 35.5653, longitude: -96.9289),
        USState(name: "Oregon", code: "OR", latitude: 44.5720, longitude: -122.0709),
        USState(name: "Pennsylvania", code: "PA", latitude: 40.5908, longitude: -77.2098),
        USState(name: "Rhode Island", code: "RI", latitude: 41.6809, longitude: -71.5118),
        USState(name: "South Carolina", code: "SC", latitude: 33.8569, longitude: -80.9450),
        USState(name: "South Dakota", code: "SD", latitude: 44.2998, longitude: -99.4388),
        USState(name: "Tennessee", code: "TN", latitude: 35.7478, longitude: -86.6923),
        USState(name: "Texas", code: "TX", latitude: 31.0545, longitude: -97.5635),
        USState(name: "Utah", code: "UT", latitude: 40.1500, longitude: -111.8624),
        USState(name: "Vermont", code: "VT", latitude: 44.0459, longitude: -72.7107),
        USState(name: "Virginia", code: "VA", latitude: 37.7693, longitude: -78.1700),
        USState(name: "Washington", code: "WA", latitude: 47.4009, longitude: -121.4905),
        USState(name: "West Virginia", code: "WV", latitude: 38.4912, longitude: -80.9545),
        USState(name: "Wisconsin", code: "WI", latitude: 44.2685, longitude: -89.6165),
        USState(name: "Wyoming", code: "WY", latitude: 42.7560, longitude: -107.3025)
    ]

    private static let stateByCode = Dictionary(uniqueKeysWithValues: states.map { ($0.code, $0) })
    private static let stateCodes = Set(states.map(\.code))
    private static let broadAreaQualifierTokens: Set<String> = [
        "area", "county", "greater", "metro", "metropolitan", "region", "vicinity"
    ]
    private static let subdivisionCodesByCountry: [String: [String: String]] = [
        "CA": [
            "alberta": "AB",
            "britishcolumbia": "BC",
            "manitoba": "MB",
            "newbrunswick": "NB",
            "newfoundlandandlabrador": "NL",
            "northwestterritories": "NT",
            "novascotia": "NS",
            "nunavut": "NU",
            "ontario": "ON",
            "princeedwardisland": "PE",
            "quebec": "QC",
            "saskatchewan": "SK",
            "yukon": "YT"
        ]
    ]
    private static let landmarkFeaturePrefixes: Set<String> = ["mount", "mt"]
    private static let landmarkFeatureSuffixes: Set<String> = [
        "beach", "bluff", "bluffs", "canyon", "falls", "hill", "hills", "lake",
        "mountain", "mountains", "observatories", "observatory", "overlook", "overlooks",
        "peak", "peaks", "reservoir", "ridge", "summit", "summits", "trail"
    ]
    private static let featureConnectorTokens: Set<String> = [
        "a", "an", "and", "at", "by", "for", "in", "near", "of", "on", "the", "to"
    ]
    private static let providerCoreRemovableFeatureSuffixes: Set<String> = [
        "bluff", "bluffs", "mountain", "mountains", "observatories", "observatory",
        "overlook", "overlooks", "peak", "peaks", "summit", "summits"
    ]
}

enum PlaceImportCandidateMatcher {
    static func match(
        _ candidates: [PlaceCandidate],
        nameHint: String?,
        areaHint: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        allowNearSpellingMatch: Bool = false,
        maximumNearSpellingEdits: Int = 1,
        selectionPolicy: PlaceImportCandidateSelectionPolicy = .conservative
    ) -> PlaceImportCandidateMatch {
        let geographicallyEligibleCandidates = candidates.filter {
            !PlaceImportGeography.candidateConflictsWithArea($0, areaHint: areaHint)
        }
        guard !geographicallyEligibleCandidates.isEmpty else {
            return PlaceImportCandidateMatch(candidates: [], selectedCandidateID: nil, bestScore: 0)
        }
        guard let nameHint = nameHint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !nameHint.isEmpty
        else {
            let soleCandidate = geographicallyEligibleCandidates.count == 1
                ? geographicallyEligibleCandidates[0]
                : nil
            let canSelectSoleCandidate = soleCandidate.map { candidate in
                selectionPolicy != .socialGroundedArea
                    || PlaceImportGeography.candidateHasCompatibleAreaEvidence(
                        candidate,
                        areaHint: areaHint
                    )
            } ?? false
            return PlaceImportCandidateMatch(
                candidates: geographicallyEligibleCandidates,
                selectedCandidateID: canSelectSoleCandidate ? soleCandidate?.id : nil,
                bestScore: soleCandidate == nil ? 0 : 0.7
            )
        }

        let scored = geographicallyEligibleCandidates.enumerated().map { index, candidate in
            (
                candidate: candidate,
                score: score(
                    candidate,
                    nameHint: nameHint,
                    areaHint: areaHint,
                    latitude: latitude,
                    longitude: longitude,
                    maximumNearSpellingEdits: allowNearSpellingMatch
                        ? max(1, min(2, maximumNearSpellingEdits))
                        : 0
                ),
                index: index
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.index < rhs.index }
            return lhs.score > rhs.score
        }

        let best = scored[0]
        let runnerUpScore = scored.dropFirst().first?.score ?? 0
        let equivalentName = namesAreEquivalentForSelection(
            best.candidate.name,
            nameHint,
            areaHint: areaHint,
            selectionPolicy: selectionPolicy
        )
        let nearSpellingName = allowNearSpellingMatch
            && isNearSpellingMatch(
                best.candidate.name,
                nameHint,
                maximumEdits: maximumNearSpellingEdits
            )
        let exactEquivalentCount = scored.filter { scoredCandidate in
            namesAreEquivalentForSelection(
                scoredCandidate.candidate.name,
                nameHint,
                areaHint: areaHint,
                selectionPolicy: selectionPolicy
            )
                || (allowNearSpellingMatch
                    && isNearSpellingMatch(
                        scoredCandidate.candidate.name,
                        nameHint,
                        maximumEdits: maximumNearSpellingEdits
                    ))
        }.count
        let equivalentCandidates = scored.filter { scoredCandidate in
            namesAreEquivalentForSelection(
                scoredCandidate.candidate.name,
                nameHint,
                areaHint: areaHint,
                selectionPolicy: selectionPolicy
            )
                || (allowNearSpellingMatch
                    && isNearSpellingMatch(
                        scoredCandidate.candidate.name,
                        nameHint,
                        maximumEdits: maximumNearSpellingEdits
                    ))
        }
        let hasClearLead = best.score - runnerUpScore >= 0.08
        let isUniqueExactMatch = (equivalentName || nearSpellingName)
            && exactEquivalentCount == 1
        let strongAreaMatches = scored.filter {
            PlaceImportGeography.candidateStronglyMatchesArea(
                $0.candidate,
                areaHint: areaHint
            )
        }
        let hasUniqueStrongAreaLead = strongAreaMatches.count == 1
            && strongAreaMatches[0].candidate.id == best.candidate.id
        // Social extraction can ground a precise locality even when Apple Maps
        // returns equivalent same-state branches. Treat that unique locality
        // agreement as a categorical lead, but keep the conservative policy for
        // manual entry and retain every ranked alternative for review.
        let isSafeSocialAreaDefault = selectionPolicy == .socialGroundedArea
            && hasUniqueStrongAreaLead
            && best.score >= 0.82
        // MapKit can return several exact records for a named landmark while
        // omitting locality from its preferred result. In the social flow only,
        // a high-confidence provider lead inside the explicitly grounded state
        // is enough to preselect that result while preserving every alternative.
        let isSafeSocialLandmarkProviderDefault = selectionPolicy == .socialGroundedArea
            && PlaceImportGeography.isDistinctiveLandmarkFeatureName(nameHint)
            && equivalentName
            && exactEquivalentCount >= 1
            && best.score >= 0.86
            && (exactEquivalentCount == 1 || best.score - runnerUpScore >= 0.01)
            && PlaceImportGeography.candidateMatchesExplicitState(
                best.candidate,
                areaHint: areaHint
            )
        // Apple Maps occasionally emits two records for the same venue a few
        // metres apart (for example Griffith Observatory). That is provider
        // duplication, not a meaningful user choice, so the social flow may
        // select the first result while still returning both records.
        let isSafeSocialColocatedDuplicateDefault = selectionPolicy == .socialGroundedArea
            && equivalentCandidates.count > 1
            && best.score >= 0.86
            && PlaceImportGeography.candidateStronglyMatchesArea(
                best.candidate,
                areaHint: areaHint
            )
            && equivalentCandidates.allSatisfy {
                candidateDistance($0.candidate, best.candidate) <= 25
            }
        // Some named natural features are indexed by Apple Maps under the
        // distinctive core name only (for example "Paseo del Mar Bluffs" as
        // "Paseo del Mar"). A grounded locality plus a provider-leading exact
        // core match is sufficient to choose the best record while retaining
        // the lower-scoring alternatives for user review.
        let isSafeSocialFeatureCoreDefault = selectionPolicy == .socialGroundedArea
            && PlaceImportGeography.candidateMatchesDistinctiveFeatureCore(
                best.candidate.name,
                nameHint: nameHint
            )
            && best.score >= 0.82
            && best.score - runnerUpScore >= 0.04
            && PlaceImportGeography.candidateStronglyMatchesArea(
                best.candidate,
                areaHint: areaHint
            )
        let selectionHasEnoughEvidence = (
            isUniqueExactMatch
                || (best.score >= 0.82 && hasClearLead)
                || isSafeSocialAreaDefault
                || isSafeSocialLandmarkProviderDefault
                || isSafeSocialColocatedDuplicateDefault
                || isSafeSocialFeatureCoreDefault
        )
        let socialAreaIsCompatible = selectionPolicy != .socialGroundedArea
            || PlaceImportGeography.candidateHasCompatibleAreaEvidence(
                best.candidate,
                areaHint: areaHint
            )
            // Remote resort addresses often name a nearby municipality but
            // omit the creator's broader geographic label (for example,
            // "Cardamom Mountains, Cambodia"). A unique exact venue plus an
            // exact country match is still a safe default; wrong-country
            // results were already removed above.
            || (isUniqueExactMatch
                && PlaceImportGeography.candidateMatchesExplicitInternationalCountryWithoutRecognizedSubdivision(
                    best.candidate,
                    areaHint: areaHint
                ))
            || isSafeSocialLandmarkProviderDefault
            || isSafeSocialColocatedDuplicateDefault
        let selectedID = selectionHasEnoughEvidence && socialAreaIsCompatible
            ? best.candidate.id
            : nil

        return PlaceImportCandidateMatch(
            candidates: scored.map(\.candidate),
            selectedCandidateID: selectedID,
            bestScore: best.score
        )
    }

    static func namesAreEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        if canonicalNameKey(lhs) == canonicalNameKey(rhs) {
            return true
        }
        let lhsCore = coreTokens(lhs)
        let rhsCore = coreTokens(rhs)
        return (!lhsCore.isEmpty && lhsCore == rhsCore)
            || creatorQualifiedVenueNamesMatch(lhs, rhs)
    }

    private static func namesAreEquivalentForSelection(
        _ lhs: String,
        _ rhs: String,
        areaHint: String?,
        selectionPolicy: PlaceImportCandidateSelectionPolicy
    ) -> Bool {
        namesAreEquivalent(lhs, rhs)
            || (selectionPolicy == .socialGroundedArea
                && socialVenueDescriptorVariantsMatch(
                    lhs,
                    rhs,
                    areaHint: areaHint
                ))
    }

    private static func socialVenueDescriptorVariantsMatch(
        _ lhs: String,
        _ rhs: String,
        areaHint: String?
    ) -> Bool {
        let removableTokens = socialVenueDescriptorTokens.union(
            Set(nameWords(areaHint ?? ""))
        )
        let lhsCore = Set(nameWords(lhs)).subtracting(removableTokens)
        let rhsCore = Set(nameWords(rhs)).subtracting(removableTokens)
        guard lhsCore == rhsCore, !lhsCore.isEmpty else { return false }
        return lhsCore.contains { token in
            token.count >= 3 && !socialVenueDescriptorTokens.contains(token)
        }
    }

    private static func candidateDistance(
        _ lhs: PlaceCandidate,
        _ rhs: PlaceCandidate
    ) -> CLLocationDistance {
        guard let lhsLatitude = lhs.latitude,
              let lhsLongitude = lhs.longitude,
              let rhsLatitude = rhs.latitude,
              let rhsLongitude = rhs.longitude else {
            return .infinity
        }

        return CLLocation(latitude: lhsLatitude, longitude: lhsLongitude).distance(
            from: CLLocation(latitude: rhsLatitude, longitude: rhsLongitude)
        )
    }

    private static func score(
        _ candidate: PlaceCandidate,
        nameHint: String,
        areaHint: String?,
        latitude: Double?,
        longitude: Double?,
        maximumNearSpellingEdits: Int
    ) -> Double {
        let hintKey = canonicalNameKey(nameHint)
        let candidateKey = canonicalNameKey(candidate.name)
        let hintTokens = tokens(nameHint)
        let candidateTokens = tokens(candidate.name)
        let hintCore = coreTokens(nameHint)
        let candidateCore = coreTokens(candidate.name)

        var score: Double
        if hintKey == candidateKey {
            score = 0.82
        } else if hintCore == candidateCore, !hintCore.isEmpty {
            score = 0.8
        } else if creatorQualifiedVenueNamesMatch(candidate.name, nameHint) {
            score = 0.8
        } else if maximumNearSpellingEdits > 0,
                  isNearSpellingMatch(
                    candidate.name,
                    nameHint,
                    maximumEdits: maximumNearSpellingEdits
                  ) {
            score = 0.78
        } else if min(hintKey.count, candidateKey.count) >= 5,
                  hintKey.contains(candidateKey) || candidateKey.contains(hintKey) {
            score = 0.72
        } else {
            let intersection = hintTokens.intersection(candidateTokens).count
            let union = hintTokens.union(candidateTokens).count
            score = union == 0 ? 0 : Double(intersection) / Double(union) * 0.68
        }

        if let areaHint = areaHint?.trimmingCharacters(in: .whitespacesAndNewlines), !areaHint.isEmpty {
            let areaTokens = PlaceImportGeography.areaTokens(areaHint)
            let candidateAreaTokens = PlaceImportGeography.candidateAreaTokens(candidate)
            let overlapCount = areaTokens.intersection(candidateAreaTokens).count
            if overlapCount > 0 {
                let denominator = max(1, min(areaTokens.count, candidateAreaTokens.count))
                score += min(0.1, Double(overlapCount) / Double(denominator) * 0.1)
            }
        }

        if hasUnrequestedStreetDesignator(candidate.name, comparedWith: nameHint) {
            score = min(score, 0.45)
        }

        if let latitude,
           let longitude,
           let candidateLatitude = candidate.latitude,
           let candidateLongitude = candidate.longitude {
            let source = CLLocation(latitude: latitude, longitude: longitude)
            let target = CLLocation(latitude: candidateLatitude, longitude: candidateLongitude)
            switch target.distance(from: source) {
            case ...500:
                score += 0.1
            case ...3_000:
                score += 0.06
            case ...10_000:
                score += 0.02
            case 25_000...:
                score -= 0.12
            default:
                break
            }
        }

        return max(0, min(1, score))
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }

    private static func coreTokens(_ value: String) -> Set<String> {
        canonicalNameTokens(value).subtracting([
            "the", "restaurant", "restaurants", "eatery", "company", "co", "inc", "llc",
            "reservoir"
        ])
    }

    private static func canonicalNameTokens(_ value: String) -> Set<String> {
        Set(nameWords(value).map { nameTokenAliases[$0] ?? $0 })
    }

    private static func canonicalNameKey(_ value: String) -> String {
        nameWords(value)
            .map { nameTokenAliases[$0] ?? $0 }
            .joined()
    }

    private static func nameWords(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func creatorQualifiedVenueNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhsWords = nameWords(lhs)
        let rhsWords = nameWords(rhs)
        return creatorQualifiedVenueName(base: lhsWords, qualified: rhsWords)
            || creatorQualifiedVenueName(base: rhsWords, qualified: lhsWords)
    }

    private static func creatorQualifiedVenueName(
        base: [String],
        qualified: [String]
    ) -> Bool {
        guard qualified.count >= base.count + 2,
              Array(qualified.prefix(base.count)) == base,
              qualified[base.count] == "by",
              !Set(base).isDisjoint(with: creatorQualifiedVenueDesignators),
              base.contains(where: isDistinctiveCreatorQualifiedToken)
        else { return false }
        return true
    }

    private static func isDistinctiveCreatorQualifiedToken(_ token: String) -> Bool {
        token.count >= 2
            && !creatorQualifiedVenueDesignators.contains(token)
            && !creatorQualifiedVenueGenericTokens.contains(token)
    }

    private static func hasUnrequestedStreetDesignator(_ candidateName: String, comparedWith hint: String) -> Bool {
        let candidateDesignators = canonicalNameTokens(candidateName).intersection(streetDesignators)
        guard !candidateDesignators.isEmpty else { return false }
        return canonicalNameTokens(hint).intersection(candidateDesignators).isEmpty
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func isNearSpellingMatch(
        _ lhs: String,
        _ rhs: String,
        maximumEdits: Int
    ) -> Bool {
        let lhsCharacters = Array(normalized(lhs))
        let rhsCharacters = Array(normalized(rhs))
        let boundedMaximumEdits = max(1, min(2, maximumEdits))
        guard min(lhsCharacters.count, rhsCharacters.count) >= 8,
              abs(lhsCharacters.count - rhsCharacters.count) <= boundedMaximumEdits
        else { return false }

        var lhsIndex = 0
        var rhsIndex = 0
        var edits = 0
        while lhsIndex < lhsCharacters.count, rhsIndex < rhsCharacters.count {
            if lhsCharacters[lhsIndex] == rhsCharacters[rhsIndex] {
                lhsIndex += 1
                rhsIndex += 1
                continue
            }
            edits += 1
            guard edits <= boundedMaximumEdits else { return false }
            if lhsCharacters.count > rhsCharacters.count {
                lhsIndex += 1
            } else if rhsCharacters.count > lhsCharacters.count {
                rhsIndex += 1
            } else {
                lhsIndex += 1
                rhsIndex += 1
            }
        }
        if lhsIndex < lhsCharacters.count || rhsIndex < rhsCharacters.count {
            edits += 1
        }
        return edits > 0 && edits <= boundedMaximumEdits
    }

    private static let nameTokenAliases = [
        "merc": "mercantile",
        "vgn": "vegan"
    ]

    private static let streetDesignators: Set<String> = [
        "avenue", "ave", "boulevard", "blvd", "court", "ct", "highway", "hwy",
        "lane", "ln", "parkway", "pkwy", "road", "rd", "street", "st", "way"
    ]

    private static let creatorQualifiedVenueDesignators: Set<String> = [
        "bakery", "bar", "brewery", "brewing", "cafe", "coffee", "deli", "eatery",
        "gallery", "grill", "hotel", "inn", "kitchen", "lodge", "market", "museum",
        "pub", "resort", "restaurant", "tavern"
    ]
    private static let socialVenueDescriptorTokens: Set<String> = [
        "a", "an", "and", "at", "by", "camp", "chateau", "chateaux", "hotel",
        "in", "island", "lodge", "of", "on", "private", "relais", "reserve",
        "resort", "spa", "suite", "suites", "the", "treehouse", "treehouses",
        "wilderness"
    ]

    private static let creatorQualifiedVenueGenericTokens: Set<String> = [
        "a", "an", "and", "at", "avenue", "ave", "boulevard", "blvd", "by", "co",
        "coffeehouse", "company", "court", "ct", "highway", "house", "hwy", "in",
        "lane", "ln", "local", "neighborhood", "neighbourhood", "of", "on", "parkway",
        "pkwy", "place", "road", "rd", "shop", "spot", "street", "st", "the", "way"
    ]
}
