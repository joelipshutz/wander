import Foundation

/// A shortlist for one synchronous import transaction. The final decision still
/// uses the ordinary strict matcher, in the original places-array order.
@MainActor
final class ImportPlaceLookupProjection {
    private struct ProviderKey: Hashable {
        let provider: String
        let placeID: String
    }

    private struct IdentityFields {
        let reference: ObjectIdentifier
        let localID: String
        let serverID: String?
        let name: String
        let provider: String
        let providerPlaceID: String?

        init(_ place: LocalPlace) {
            reference = ObjectIdentifier(place)
            localID = place.localID
            serverID = place.serverID
            name = place.canonicalName
            provider = place.sourceProvider
            providerPlaceID = place.sourceProviderPlaceID
        }

        func matches(_ place: LocalPlace) -> Bool {
            reference == ObjectIdentifier(place)
                && localID == place.localID
                && serverID == place.serverID
                && name == place.canonicalName
                && provider == place.sourceProvider
                && providerPlaceID == place.sourceProviderPlaceID
        }
    }

    private var places: [LocalPlace] = []
    private var identityFields: [IdentityFields] = []
    private var offsetsByAlias: [String: [Int]] = [:]
    private var offsetsByProvider: [ProviderKey: [Int]] = [:]
    private var offsetsByName: [String: [Int]] = [:]
    private var collectionRevision: UInt64 = 0
    private var locale = Locale.current

    init(places: [LocalPlace], collectionRevision: UInt64) {
        rebuild(places: places, collectionRevision: collectionRevision)
    }

    func firstMatch(
        for candidate: PlaceCandidate,
        in currentPlaces: [LocalPlace],
        collectionRevision currentRevision: UInt64
    ) -> LocalPlace? {
        if currentRevision != collectionRevision || locale != Locale.current
            || currentPlaces.count != identityFields.count
            || !zip(identityFields, currentPlaces).allSatisfy({ $0.0.matches($0.1) }) {
            rebuild(places: currentPlaces, collectionRevision: currentRevision)
        }

        let candidateID = VisiblePlaceGrouping.normalizedIdentifier(candidate.id)
        let providerKey = ProviderKey(
            provider: VisiblePlaceGrouping.normalizedIdentifier(candidate.sourceProvider),
            placeID: VisiblePlaceGrouping.normalizedIdentifier(candidate.sourceProviderPlaceID ?? candidate.id)
        )
        let name = VisiblePlaceGrouping.normalizedText(candidate.name, locale: locale)
        var offsets = Set(offsetsByAlias[candidateID] ?? [])
        offsets.formUnion(offsetsByProvider[providerKey] ?? [])
        offsets.formUnion(offsetsByName[name] ?? [])

        // An earlier name/address match must still win over a later provider or
        // ID match. A shortlist entry is never itself evidence of equivalence.
        for offset in offsets.sorted() {
            let place = places[offset]
            if VisiblePlaceGrouping.matches(place, candidate: candidate) {
                return place
            }
        }
        return nil
    }

    func didAppend(_ place: LocalPlace, totalCount: Int, collectionRevision newRevision: UInt64) {
        guard newRevision == collectionRevision &+ 1,
              totalCount == places.count + 1,
              locale == Locale.current
        else {
            // A collection replacement needs a fresh index. The next query
            // sees the unchanged old revision and rebuilds from live values.
            return
        }
        appendKeys(for: place)
        collectionRevision = newRevision
    }

    private func rebuild(places currentPlaces: [LocalPlace], collectionRevision: UInt64) {
        places.removeAll(keepingCapacity: true)
        identityFields.removeAll(keepingCapacity: true)
        offsetsByAlias.removeAll(keepingCapacity: true)
        offsetsByProvider.removeAll(keepingCapacity: true)
        offsetsByName.removeAll(keepingCapacity: true)
        locale = .current
        for place in currentPlaces {
            appendKeys(for: place)
        }
        self.collectionRevision = collectionRevision
    }

    private func appendKeys(for place: LocalPlace) {
        let offset = places.count
        places.append(place)
        identityFields.append(IdentityFields(place))
        let aliases = Set([place.id, place.localID, place.serverID]
            .map(VisiblePlaceGrouping.normalizedIdentifier)
            .filter { !$0.isEmpty })
        for alias in aliases {
            offsetsByAlias[alias, default: []].append(offset)
        }
        let provider = VisiblePlaceGrouping.normalizedIdentifier(place.sourceProvider)
        let providerID = VisiblePlaceGrouping.normalizedIdentifier(place.sourceProviderPlaceID)
        if !provider.isEmpty, !providerID.isEmpty {
            offsetsByProvider[ProviderKey(provider: provider, placeID: providerID), default: []].append(offset)
        }
        let name = VisiblePlaceGrouping.normalizedText(place.canonicalName, locale: locale)
        if !name.isEmpty {
            offsetsByName[name, default: []].append(offset)
        }
    }
}
