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

    func testReservationActionPrefersExactProviderAndUsesRequestedPresentation() throws {
        let links = [
            PlaceActionLink(
                kind: .reservationSearch,
                title: "Search Resy",
                urlString: "https://resy.com/cities/los-angeles-ca/search",
                source: .providerSearch,
                confidence: .search
            ),
            PlaceActionLink(
                kind: .reserve,
                title: "Book on OpenTable",
                urlString: "https://www.opentable.com/r/example",
                source: .backendExtraction,
                confidence: .exact
            )
        ]

        let action = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(actionLinksJSON: PlaceActionLink.encode(links))
        )

        XCTAssertEqual(action.kind, .reserve)
        XCTAssertEqual(action.title, "Reservation")
        XCTAssertEqual(action.systemImage, "calendar")
        XCTAssertEqual(action.url.absoluteString, "https://www.opentable.com/r/example")
    }

    func testReservationActionRejectsProviderSearchLinks() {
        let links = [
            PlaceActionLink(
                kind: .reserve,
                title: "Find a table",
                urlString: "https://resy.com/cities/los-angeles-ca/search?query=Example",
                source: .providerSearch,
                confidence: .search
            )
        ]

        XCTAssertNil(
            PlaceExternalLinks.reservationAction(actionLinksJSON: PlaceActionLink.encode(links))
        )
    }

    func testReservationActionRejectsProviderSearchPageMarkedExact() {
        let links = [
            PlaceActionLink(
                kind: .reserve,
                title: "Reserve on Resy",
                urlString: "https://resy.com/cities/los-angeles-ca/search?query=Example",
                source: .backendExtraction,
                confidence: .exact
            )
        ]

        XCTAssertNil(
            PlaceExternalLinks.reservationAction(actionLinksJSON: PlaceActionLink.encode(links))
        )
    }

    func testReservationActionRejectsExactNonProviderLinks() {
        let links = [
            PlaceActionLink(
                kind: .reserve,
                title: "Reserve",
                urlString: "https://www.google.com/search?q=restaurant+reservation",
                source: .backendExtraction,
                confidence: .exact
            )
        ]

        XCTAssertNil(
            PlaceExternalLinks.reservationAction(actionLinksJSON: PlaceActionLink.encode(links))
        )
    }

    func testReservationActionAcceptsExactResyVenueLink() throws {
        let links = [
            PlaceActionLink(
                kind: .reserve,
                title: "Book on Resy",
                urlString: "https://resy.com/cities/la/venues/example-restaurant",
                source: .backendExtraction,
                confidence: .exact
            )
        ]

        let action = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(actionLinksJSON: PlaceActionLink.encode(links))
        )

        XCTAssertEqual(action.kind, .reserve)
        XCTAssertEqual(action.url.absoluteString, "https://resy.com/cities/la/venues/example-restaurant")
    }

    func testReservationActionAcceptsLegacyResyVenueLink() throws {
        let action = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://resy.com/cities/la/the-dresden-restaurant-and-lounge")
            )
        )

        XCTAssertEqual(
            action.url.absoluteString,
            "https://resy.com/cities/la/the-dresden-restaurant-and-lounge"
        )
    }

    func testReservationActionUpgradesKnownProviderHTTPLinkToHTTPS() throws {
        let action = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "http://resy.com/cities/la/the-dresden-restaurant-and-lounge")
            )
        )

        XCTAssertEqual(action.url.scheme, "https")
        XCTAssertEqual(action.url.host, "resy.com")
    }

    func testReservationActionAcceptsOpenTableWidgetRestaurantIdentifier() throws {
        let action = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.opentable.com/booking/restref/availability?rid=12345")
            )
        )

        XCTAssertEqual(action.kind, .reserve)
        XCTAssertEqual(action.url.host, "www.opentable.com")
    }

    func testReservationActionAcceptsCurrentOpenTableRestaurantSlug() throws {
        let action = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.opentable.com/gjelina")
            )
        )

        XCTAssertEqual(action.url.absoluteString, "https://www.opentable.com/gjelina")
    }

    func testReservationActionRejectsOpenTableDiscoveryPages() {
        XCTAssertNil(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.opentable.com/los-angeles-restaurants")
            )
        )
        XCTAssertNil(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.opentable.com/s?covers=2&metroId=6")
            )
        )
    }

    func testReservationActionAcceptsDirectNatureReservationProviders() throws {
        let recreation = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.recreation.gov/camping/campgrounds/232446")
            )
        )
        let reserveCalifornia = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.reservecalifornia.com/Web/#!park/705/638")
            )
        )
        let reserveAmerica = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.reserveamerica.com/explore/example-state-park/CA/120052/overview")
            )
        )

        XCTAssertEqual(recreation.url.host, "www.recreation.gov")
        XCTAssertEqual(reserveCalifornia.url.host, "www.reservecalifornia.com")
        XCTAssertEqual(reserveAmerica.url.host, "www.reserveamerica.com")
    }

    func testReservationActionRejectsGenericNatureSearchPages() {
        XCTAssertNil(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.recreation.gov/search?q=Yosemite")
            )
        )
        XCTAssertNil(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.reserveamerica.com/")
            )
        )
    }

    func testReservationDiscoveryFindsDirectResyVenueOnOfficialWebsite() async throws {
        let html = """
        <html><body>
          <a href="https://resy.com/cities/los-angeles-ca/venues/example-restaurant?date=2026-08-07">Book a table</a>
        </body></html>
        """

        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://example-restaurant.com",
            pageLoader: { request in
                (Data(html.utf8), request.url)
            }
        )

        XCTAssertEqual(action?.kind, .reserve)
        XCTAssertEqual(
            action?.url.absoluteString,
            "https://resy.com/cities/los-angeles-ca/venues/example-restaurant?date=2026-08-07"
        )
    }

    func testReservationDiscoveryFollowsOfficialReservationPageToOpenTable() async throws {
        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://example-restaurant.com",
            pageLoader: { request in
                if request.url?.path == "/reservations" {
                    return (
                        Data(#"<a href="https://www.opentable.com/r/example-restaurant">Reserve</a>"#.utf8),
                        request.url
                    )
                }
                return (
                    Data(#"<a href="/reservations">Reservations</a>"#.utf8),
                    request.url
                )
            }
        )

        XCTAssertEqual(action?.url.absoluteString, "https://www.opentable.com/r/example-restaurant")
    }

    func testReservationDiscoveryPrefersTheProviderLinkMatchingThePlaceLocality() async throws {
        let html = """
        <section>
          <h2>Gjelina Venice</h2><p>1429 Abbot Kinney Blvd, Venice CA</p>
          <a href="https://www.opentable.com/booking/restref/availability?restRef=76651">Reserve Venice</a>
        </section>
        <section>
          <h2>Gjelina New York</h2><p>45 Bond Street, New York NY</p>
          <a href="https://www.opentable.com/r/gjelina-new-york">Reserve New York</a>
        </section>
        """

        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://gjelina.example",
            placeName: "Gjelina",
            locality: "Venice",
            pageLoader: { request in
                (Data(html.utf8), request.url)
            }
        )

        XCTAssertEqual(
            action?.url.absoluteString,
            "https://www.opentable.com/booking/restref/availability?restRef=76651"
        )
    }

    func testReservationDiscoveryUsesCuratedLinkWhenOfficialWebsiteIsStale() async throws {
        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://stale.example",
            placeName: "Gjelina",
            locality: "Venice",
            region: "CA",
            pageLoader: { _ in
                XCTFail("A curated venue should not need a website request")
                throw URLError(.badURL)
            }
        )

        XCTAssertEqual(action?.url.absoluteString, "https://www.opentable.com/gjelina")
    }

    func testCuratedReservationLinkDoesNotCrossRegions() async {
        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: nil,
            placeName: "Gjelina",
            locality: "New York",
            region: "NY"
        )

        XCTAssertNil(action)
    }

    func testReservationDiscoveryFindsRecreationGovCampgroundFromOfficialParkWebsite() async throws {
        let html = #"<a href="https://www.recreation.gov/camping/campgrounds/234015">Reserve a campsite</a>"#

        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://www.nps.gov/pinn/planyourvisit/campgrounds.htm",
            allowsOfficialReservationPageFallback: true,
            pageLoader: { request in
                (Data(html.utf8), request.url)
            }
        )

        XCTAssertEqual(
            action?.url.absoluteString,
            "https://www.recreation.gov/camping/campgrounds/234015"
        )
    }

    func testNatureDiscoveryFallsBackToOfficialReservationPageOnlyForNaturePlaces() async throws {
        let homeHTML = #"<a href="/camping/reservations">Campground reservations</a>"#
        let loader: PlaceExternalLinks.ReservationPageLoader = { request in
            if request.url?.path == "/camping/reservations" {
                return (Data("Official booking instructions".utf8), request.url)
            }
            return (Data(homeHTML.utf8), request.url)
        }

        let natureAction = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://parks.example.gov",
            allowsOfficialReservationPageFallback: true,
            pageLoader: loader
        )
        let restaurantAction = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://restaurant.example",
            pageLoader: loader
        )

        XCTAssertEqual(natureAction?.url.absoluteString, "https://parks.example.gov/camping/reservations")
        XCTAssertNil(restaurantAction)
    }

    func testNatureDiscoveryUsesTrustedProviderPortalLinkedByOfficialPark() async throws {
        let html = #"<a href="https://www.recreation.gov/">Reserve on Recreation.gov</a>"#

        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://www.nps.gov/example/campground",
            allowsOfficialReservationPageFallback: true,
            pageLoader: { request in
                (Data(html.utf8), request.url)
            }
        )

        XCTAssertEqual(action?.url.absoluteString, "https://www.recreation.gov/")
    }

    func testNatureDiscoveryDoesNotTreatStaticAssetsAsReservationPages() async {
        let html = #"<a href="/assets/icons.svg#campground">Campground icon</a>"#

        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://www.nps.gov/example/campground",
            allowsOfficialReservationPageFallback: true,
            pageLoader: { request in
                (Data(html.utf8), request.url)
            }
        )

        XCTAssertNil(action)
    }

    func testReservationDiscoveryUpgradesHTTPOfficialWebsiteBeforeLoading() async throws {
        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "http://example-restaurant.com",
            pageLoader: { request in
                guard request.url?.scheme == "https" else {
                    throw URLError(.secureConnectionFailed)
                }
                return (
                    Data(#"<a href="https://www.opentable.com/gjelina">Reserve</a>"#.utf8),
                    request.url
                )
            }
        )

        XCTAssertEqual(action?.url.absoluteString, "https://www.opentable.com/gjelina")
    }

    func testReservationDiscoveryRejectsSearchAndGoogleLinksFromOfficialWebsite() async {
        let html = """
        <a href="https://resy.com/cities/los-angeles-ca/search?query=Example">Search Resy</a>
        <a href="https://www.google.com/search?q=Example+reservations">Google</a>
        """

        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://example-restaurant.com",
            pageLoader: { request in
                (Data(html.utf8), request.url)
            }
        )

        XCTAssertNil(action)
    }

    func testReservationActionStaysHiddenWithoutExactProviderLink() {
        XCTAssertNil(PlaceExternalLinks.reservationAction(actionLinksJSON: nil))
    }
}
