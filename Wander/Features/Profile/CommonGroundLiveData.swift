#if DEBUG
import Foundation

/// Read-only presentation of the store's authorized profile data. This adapter
/// does not fetch data or replace the store/server's visibility policy.
@MainActor
enum CommonGroundLiveData {
    struct Snapshot {
        let places: [CommonGroundMockPlace]
        let availableCities: [String]
    }

    static func places(store: WanderStore, profileID: String) -> [CommonGroundMockPlace] {
        snapshot(store: store, profileID: profileID).places
    }

    static func availableCities(store: WanderStore, profileID: String) -> [String] {
        snapshot(store: store, profileID: profileID).availableCities
    }

    static func snapshot(store: WanderStore, profileID: String) -> Snapshot {
        guard let partner = store.profile(for: profileID),
              partner.id != store.currentUser.id,
              partner.deletedAt == nil
        else { return Snapshot(places: [], availableCities: []) }
        return snapshot(
            viewerProfile: store.currentUser,
            partnerProfile: partner,
            authorizedPlaces: store.currentUserVisiblePlaces + store.visiblePlaces(for: profileID),
            visitsForUserPlace: { store.visits(for: $0) },
            shouldShowLegacyCheckInSummary: { store.shouldShowLegacyCheckInSummary(for: $0) },
            eligibleWannaEventIDs: { store.wannaSaves(for: $0).map(\.id) }
        )
    }

    /// The event seam receives already-authorized event IDs. The live store
    /// supplies repeat Wannas for every canonical parent row, including Been
    /// summaries; the projection then deduplicates event IDs independently of
    /// check-ins and the legacy Wanna summary.
    static func snapshot(
        viewerProfile: LocalProfile,
        partnerProfile: LocalProfile,
        authorizedPlaces: [VisiblePlace],
        visitsForUserPlace: (String) -> [LocalPlaceVisit],
        shouldShowLegacyCheckInSummary: (String) -> Bool,
        eligibleWannaEventIDs: (LocalUserPlace) -> [String] = { _ in [] }
    ) -> Snapshot {
        guard viewerProfile.id != partnerProfile.id else {
            return Snapshot(places: [], availableCities: [])
        }
        let viewer = CommonGroundPerson(profile: viewerProfile)
        let partner = CommonGroundPerson(profile: partnerProfile)
        let ownerIDs = Set([viewerProfile.id, partnerProfile.id])
        let rows = authorizedPlaces.filter {
            ownerIDs.contains($0.owner.id)
                && $0.owner.id == $0.userPlace.userID
                && $0.owner.deletedAt == nil
                && $0.userPlace.deletedAt == nil
                && !$0.isCommunityAggregate
                && ($0.owner.id == viewerProfile.id || $0.userPlace.visibility != .selfOnly)
        }
        let groups = VisiblePlaceGrouping.groups(from: rows, currentUserID: viewerProfile.id)
        var places: [CommonGroundMockPlace] = []
        var citiesByKey: [String: String] = [:]
        for group in groups {
            let mine = personEvidence(
                rows: group.places.filter { $0.owner.id == viewerProfile.id },
                visitsForUserPlace: visitsForUserPlace,
                shouldShowLegacyCheckInSummary: shouldShowLegacyCheckInSummary,
                eligibleWannaEventIDs: eligibleWannaEventIDs
            )
            let theirs = personEvidence(
                rows: group.places.filter { $0.owner.id == partnerProfile.id },
                visitsForUserPlace: visitsForUserPlace,
                shouldShowLegacyCheckInSummary: shouldShowLegacyCheckInSummary,
                eligibleWannaEventIDs: eligibleWannaEventIDs
            )
            let primary = group.primary
            let city = group.places.compactMap { nonempty($0.place.locality) }.first ?? ""
            if !city.isEmpty && (mine.evidence.visitCount > 0 || theirs.evidence.visitCount > 0) {
                citiesByKey[city.lowercased()] = city
            }
            guard group.places.contains(where: { $0.owner.id == viewerProfile.id }),
                  group.places.contains(where: { $0.owner.id == partnerProfile.id })
            else { continue }
            places.append(CommonGroundMockPlace(
                id: group.key,
                name: primary.place.canonicalName,
                category: primary.effectiveCompactType,
                area: [nonempty(primary.place.locality), nonempty(primary.place.region)]
                    .compactMap { $0 }.joined(separator: ", "),
                city: city,
                systemImage: symbol(for: primary.effectiveCategory),
                youRating: mine.rating,
                joeRating: theirs.rating,
                youEvidence: mine.evidence,
                joeEvidence: theirs.evidence,
                reason: reason(mine: mine, theirs: theirs, partner: partner.shortName),
                viewer: viewer,
                partner: partner,
                photoReference: CommonGroundPlacePhotoReference(place: primary),
                // Native navigation resolves this exact currently authorized
                // VisiblePlace row, rather than an arbitrary canonical save.
                sourcePlaceID: primary.id
            ))
        }
        places.sort {
            let lhsRank = rank($0), rhsRank = rank($1)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if $0.totalVisits != $1.totalVisits { return $0.totalVisits > $1.totalVisits }
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        return Snapshot(
            places: places,
            availableCities: citiesByKey.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
    }

    private struct PersonEvidence {
        let evidence: CommonGroundPersonEvidence
        let rating: Double?
    }

    private static func personEvidence(
        rows: [VisiblePlace],
        visitsForUserPlace: (String) -> [LocalPlaceVisit],
        shouldShowLegacyCheckInSummary: (String) -> Bool,
        eligibleWannaEventIDs: (LocalUserPlace) -> [String]
    ) -> PersonEvidence {
        let parents = aliasGroups(rows.map(\.userPlace)) {
            Set([$0.id, $0.localID, $0.serverID].compactMap { $0 })
        }
        var wannaIDs = Set<String>()
        var legacyVisitIDs = Set<String>()
        var legacyRatings: [Double] = []
        var allVisits: [LocalPlaceVisit] = []
        for parentGroup in parents {
            // Prefer the newest summary when a local/server snapshot overlaps.
            let parent = parentGroup.max { $0.updatedAt < $1.updatedAt }!
            let parentID = parentGroup.compactMap(\.serverID).sorted().first ?? parent.id
            let references = Set(parentGroup.flatMap { [$0.id, $0.localID, $0.serverID].compactMap { $0 } })
            let visits = references.flatMap(visitsForUserPlace).filter { references.contains($0.userPlaceID) }
            allVisits += visits
            let eventIDs = Set(parentGroup.flatMap(eligibleWannaEventIDs))
            wannaIDs.formUnion(eventIDs)
            if parent.status == .wannaGo && eventIDs.isEmpty {
                wannaIDs.insert("legacy-wanna:\(parentID)")
            }
            // historicalWantedAt is a fulfilled snapshot, not a current Wanna.
            // An authoritative empty history must not resurrect a deleted visit.
            if visits.isEmpty && parent.status == .been
                && references.allSatisfy(shouldShowLegacyCheckInSummary) {
                legacyVisitIDs.insert("legacy-check-in:\(parentID)")
                if let rating = validRating(parent.ratingScore) { legacyRatings.append(rating) }
            }
        }
        let visitGroups = aliasGroups(allVisits) {
            Set([$0.id, $0.localID, $0.serverID].compactMap { $0 })
        }
        var visitIDs = legacyVisitIDs
        var ratings = legacyRatings
        for group in visitGroups {
            let visit = group.max { $0.updatedAt < $1.updatedAt }!
            guard visit.deletedAt == nil else { continue }
            visitIDs.insert(group.compactMap(\.serverID).sorted().first ?? visit.id)
            if let rating = validRating(visit.ratingScore) { ratings.append(rating) }
        }
        return PersonEvidence(
            evidence: CommonGroundPersonEvidence(wannaRecordIDs: wannaIDs, visitRecordIDs: visitIDs),
            rating: ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
        )
    }

    /// Merge transitive local/server references before counting either record type.
    private static func aliasGroups<T>(_ records: [T], aliases: (T) -> Set<String>) -> [[T]] {
        var groups: [(ids: Set<String>, records: [T])] = []
        for record in records {
            var ids = aliases(record)
            var members = [record]
            for index in groups.indices.reversed() where !groups[index].ids.isDisjoint(with: ids) {
                ids.formUnion(groups[index].ids)
                members += groups.remove(at: index).records
            }
            groups.append((ids, members))
        }
        return groups.map(\.records)
    }

    private static func validRating(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...5).contains(value) else { return nil }
        return value
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func reason(mine: PersonEvidence, theirs: PersonEvidence, partner: String) -> String {
        let youCount = mine.evidence.visitCount, theirCount = theirs.evidence.visitCount
        if (mine.rating ?? 0) >= 4.5 && (theirs.rating ?? 0) >= 4.5 {
            if youCount >= 3 && theirCount >= 3 {
                return "You: \(youCount) check-ins. \(partner): \(theirCount) check-ins."
            }
            let yours = mine.rating!.formatted(.number.precision(.fractionLength(0...1)))
            let theirs = theirs.rating!.formatted(.number.precision(.fractionLength(0...1)))
            return "Average ratings: you \(yours)/5. \(partner) \(theirs)/5."
        }
        if mine.evidence.hasWanna && theirs.evidence.hasWanna { return "In both of your Wannas" }
        if mine.evidence.hasWanna && theirCount >= 3 && (theirs.rating ?? 0) >= 4.5 {
            return "\(partner): \(theirCount) check-ins. In your Wannas."
        }
        if theirs.evidence.hasWanna && youCount >= 3 && (mine.rating ?? 0) >= 4.5 {
            return "You: \(youCount) check-ins. In \(partner)’s Wannas."
        }
        return "Saved by you and \(partner)."
    }

    private static func rank(_ place: CommonGroundMockPlace) -> Int {
        if place.bothLoved && place.bothRegulars { return 0 }
        if place.bothLoved { return 1 }
        if place.kind == .mutualWanna { return 2 }
        if place.kind == .introduce { return 3 }
        return 4
    }

    private static func symbol(for category: String) -> String {
        switch category {
        case WanderPlaceCategory.coffeeTeaSweets: "cup.and.saucer"
        case WanderPlaceCategory.restaurantsFood: "fork.knife"
        case WanderPlaceCategory.barsNightlife: "wineglass"
        case WanderPlaceCategory.outdoorsNature: "leaf"
        case WanderPlaceCategory.shopping: "bag"
        case WanderPlaceCategory.stays: "bed.double"
        default: "mappin.and.ellipse"
        }
    }
}
#endif
