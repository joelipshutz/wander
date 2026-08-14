import CoreLocation
import Foundation
import MapKit

struct PlaceBusinessMetadata: Equatable {
    let websiteURLString: String?
    let phoneNumber: String?
    let timeZoneIdentifier: String?

    var needsRecovery: Bool {
        PlaceExternalLinks.websiteURL(from: websiteURLString) == nil
            || PlaceExternalLinks.callURL(phoneNumber: phoneNumber) == nil
    }

    func mergingMissingValues(from recovered: PlaceBusinessMetadata) -> PlaceBusinessMetadata {
        PlaceBusinessMetadata(
            websiteURLString: PlaceExternalLinks.websiteURL(from: websiteURLString) == nil
                ? recovered.validWebsiteURLString
                : websiteURLString,
            phoneNumber: PlaceExternalLinks.callURL(phoneNumber: phoneNumber) == nil
                ? recovered.validPhoneNumber
                : phoneNumber,
            timeZoneIdentifier: validTimeZoneIdentifier ?? recovered.validTimeZoneIdentifier
        )
    }

    private var validWebsiteURLString: String? {
        PlaceExternalLinks.websiteURL(from: websiteURLString) == nil ? nil : trimmed(websiteURLString)
    }

    private var validPhoneNumber: String? {
        PlaceExternalLinks.callURL(phoneNumber: phoneNumber) == nil ? nil : trimmed(phoneNumber)
    }

    private var validTimeZoneIdentifier: String? {
        guard let identifier = trimmed(timeZoneIdentifier), TimeZone(identifier: identifier) != nil else {
            return nil
        }
        return identifier
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct PlaceBusinessMetadataRequest: Equatable {
    let placeID: String
    let name: String
    let address: String?
    let locality: String?
    let region: String?
    let latitude: Double?
    let longitude: Double?
    let sourceProvider: String?
    let sourceProviderPlaceID: String?

    var lookupKey: String {
        var components = [placeID, name]
        components.append(contentsOf: [address, locality, region, sourceProvider, sourceProviderPlaceID].compactMap { $0 })
        if let latitude { components.append(String(latitude)) }
        if let longitude { components.append(String(longitude)) }
        return components.joined(separator: "|")
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }
}

struct PlaceBusinessMetadataCandidate: Equatable {
    let name: String
    let address: String?
    let locality: String?
    let region: String?
    let latitude: Double
    let longitude: Double
    let websiteURLString: String?
    let phoneNumber: String?
    let timeZoneIdentifier: String?

    var metadata: PlaceBusinessMetadata {
        PlaceBusinessMetadata(
            websiteURLString: websiteURLString,
            phoneNumber: phoneNumber,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

enum PlaceBusinessMetadataMatcher {
    static func bestCandidate(
        for request: PlaceBusinessMetadataRequest,
        from candidates: [PlaceBusinessMetadataCandidate]
    ) -> PlaceBusinessMetadataCandidate? {
        candidates
            .compactMap { candidate -> (PlaceBusinessMetadataCandidate, Double)? in
                guard let score = score(candidate, for: request) else { return nil }
                return (candidate, score)
            }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }

    private static func score(
        _ candidate: PlaceBusinessMetadataCandidate,
        for request: PlaceBusinessMetadataRequest
    ) -> Double? {
        guard let requestCoordinate = request.coordinate else { return nil }
        let candidateCoordinate = CLLocationCoordinate2D(
            latitude: candidate.latitude,
            longitude: candidate.longitude
        )
        guard CLLocationCoordinate2DIsValid(candidateCoordinate) else { return nil }

        let requestName = normalized(request.name)
        let candidateName = normalized(candidate.name)
        guard !requestName.isEmpty, !candidateName.isEmpty else { return nil }

        let nameScore: Double
        if requestName == candidateName {
            nameScore = 300
        } else if requestName.count >= 4,
                  candidateName.count >= 4,
                  requestName.contains(candidateName) || candidateName.contains(requestName) {
            nameScore = 220
        } else {
            return nil
        }

        let distance = CLLocation(latitude: requestCoordinate.latitude, longitude: requestCoordinate.longitude)
            .distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))
        guard distance <= maximumDistance(for: request, candidate: candidate) else { return nil }

        var score = nameScore
        switch distance {
        case ...75: score += 160
        case ...250: score += 110
        case ...750: score += 55
        default: score += 10
        }

        let requestAddress = normalized(request.address)
        let candidateAddress = normalized(candidate.address)
        if !requestAddress.isEmpty, requestAddress == candidateAddress {
            score += 100
        } else if let requestNumber = streetNumber(in: requestAddress),
                  let candidateNumber = streetNumber(in: candidateAddress) {
            score += requestNumber == candidateNumber ? 80 : -100
        }

        let requestLocality = normalized(request.locality)
        let candidateLocality = normalized(candidate.locality)
        if !requestLocality.isEmpty, !candidateLocality.isEmpty {
            score += requestLocality == candidateLocality ? 40 : -40
        }

        let requestRegion = normalized(request.region)
        let candidateRegion = normalized(candidate.region)
        if !requestRegion.isEmpty, !candidateRegion.isEmpty, requestRegion == candidateRegion {
            score += 15
        }

        return score >= 300 ? score : nil
    }

    private static func maximumDistance(
        for request: PlaceBusinessMetadataRequest,
        candidate: PlaceBusinessMetadataCandidate
    ) -> CLLocationDistance {
        let requestNumber = streetNumber(in: normalized(request.address))
        let candidateNumber = streetNumber(in: normalized(candidate.address))
        return requestNumber != nil && requestNumber == candidateNumber ? 2_000 : 750
    }

    private static func normalized(_ value: String?) -> String {
        guard let value else { return "" }
        let words = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(separator: " ")
        return words.map(String.init).joined(separator: " ")
    }

    private static func streetNumber(in normalizedAddress: String) -> String? {
        normalizedAddress.split(separator: " ").first.map(String.init).flatMap { value in
            value.allSatisfy(\.isNumber) ? value : nil
        }
    }
}

@MainActor
final class MapKitPlaceBusinessMetadataResolver {
    func resolve(_ request: PlaceBusinessMetadataRequest) async throws -> PlaceBusinessMetadata? {
        guard let coordinate = request.coordinate else { return nil }
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = [name, request.address, request.locality, request.region]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " ")
        searchRequest.resultTypes = [.pointOfInterest, .address]
        searchRequest.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 4_000,
            longitudinalMeters: 4_000
        )

        let response = try await MKLocalSearch(request: searchRequest).start()
        let candidates = response.mapItems.compactMap(candidate(from:))
        return PlaceBusinessMetadataMatcher.bestCandidate(for: request, from: candidates)?.metadata
    }

    private func candidate(from item: MKMapItem) -> PlaceBusinessMetadataCandidate? {
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              CLLocationCoordinate2DIsValid(item.placemark.coordinate)
        else {
            return nil
        }

        return PlaceBusinessMetadataCandidate(
            name: name,
            address: address(for: item.placemark),
            locality: item.placemark.locality,
            region: item.placemark.administrativeArea,
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            websiteURLString: item.url?.absoluteString,
            phoneNumber: item.phoneNumber,
            timeZoneIdentifier: item.timeZone?.identifier
        )
    }

    private func address(for placemark: MKPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        if !street.isEmpty { return street }
        return placemark.title?
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
