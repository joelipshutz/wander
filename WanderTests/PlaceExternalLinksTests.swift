import XCTest
@testable import Wander

final class PlaceExternalLinksTests: XCTestCase {
    func testGoogleMapsDirectionsURLUsesCoordinatesWithoutApiKey() throws {
        let url = try XCTUnwrap(
            PlaceExternalLinks.googleMapsDirectionsURL(
                placeName: "Din Tai Fung",
                latitude: 34.0589,
                longitude: -118.4173
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.path, "/maps/dir/")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "api" })?.value, "1")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "destination" })?.value, "34.0589,-118.4173")
        XCTAssertNil(components.queryItems?.first(where: { $0.name.lowercased().contains("key") }))
    }

    func testGoogleMapsDirectionsURLRejectsInvalidCoordinates() {
        XCTAssertNil(
            PlaceExternalLinks.googleMapsDirectionsURL(
                placeName: "Bad Pin",
                latitude: 120,
                longitude: -118
            )
        )
    }

    func testGoogleMapsSearchURLUsesOnlyKnownText() throws {
        let url = try XCTUnwrap(
            PlaceExternalLinks.googleMapsSearchURL(
                placeName: "Woodcat Coffee",
                address: nil,
                locality: "Los Angeles"
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/maps/search/")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "api" })?.value, "1")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "query" })?.value, "Woodcat Coffee Los Angeles")
    }

    func testShareSummaryOmitsMissingMetadata() {
        XCTAssertEqual(
            PlaceExternalLinks.shareSummary(placeName: "Griffith Observatory Trail", locality: nil, status: .been),
            "Griffith Observatory Trail · check-in"
        )
    }

    func testWebsiteURLAcceptsHttpsAndAddsMissingScheme() throws {
        XCTAssertEqual(
            PlaceExternalLinks.websiteURL(from: "https://example.com/menu")?.absoluteString,
            "https://example.com/menu"
        )
        XCTAssertEqual(
            PlaceExternalLinks.websiteURL(from: "example.com")?.absoluteString,
            "https://example.com"
        )
    }

    func testWebsiteURLRejectsUnsafeOrInvalidURLs() {
        XCTAssertNil(PlaceExternalLinks.websiteURL(from: "tel:+15551231234"))
        XCTAssertNil(PlaceExternalLinks.websiteURL(from: "not a url"))
        XCTAssertNil(PlaceExternalLinks.websiteURL(from: ""))
    }

    func testCallURLSanitizesCommonPhoneFormatting() throws {
        let url = try XCTUnwrap(PlaceExternalLinks.callURL(phoneNumber: " +1 (555) 123-4567 "))

        XCTAssertEqual(url.absoluteString, "tel:+15551234567")
    }

    func testCallURLRejectsEmptyOrImplausiblePhoneNumbers() {
        XCTAssertNil(PlaceExternalLinks.callURL(phoneNumber: "call us soon"))
        XCTAssertNil(PlaceExternalLinks.callURL(phoneNumber: "12"))
        XCTAssertNil(PlaceExternalLinks.callURL(phoneNumber: "123456789012345678901"))
    }

    func testVisibleBusinessActionsUseDirectOrderAndSearchLabels() throws {
        let links = [
            PlaceActionLink(
                kind: .order,
                title: "Order now",
                urlString: "https://direct.example/order",
                source: .backendExtraction,
                confidence: .exact
            ),
            PlaceActionLink(
                kind: .reserve,
                title: "Reserve",
                urlString: "https://resy.example/search?q=place",
                source: .providerSearch,
                confidence: .search
            )
        ]

        let actions = PlaceExternalLinks.visibleBusinessActions(
            websiteURLString: "https://restaurant.example",
            phoneNumber: "555-123-4567",
            actionLinksJSON: PlaceActionLink.encode(links)
        )

        XCTAssertEqual(actions.map(\.title), ["Website", "Call", "Order now", "Find reservations"])
        XCTAssertEqual(actions.first { $0.kind == .reserve }, nil)
        XCTAssertEqual(actions.first { $0.kind == .reservationSearch }?.url.absoluteString, "https://resy.example/search?q=place")
    }
}
