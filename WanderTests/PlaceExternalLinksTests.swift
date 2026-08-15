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

    func testReservationActionAcceptsDirectStateReservationProvidersOutsideCalifornia() throws {
        let providerURLs = [
            "https://www.midnrreservations.com/FacilityDetails.aspx?facid=93",
            "https://reserve.southcarolinaparks.com/hunting-island/camping/",
            "https://reservevaparks.com/web/",
            "https://campsd.com/campground/123",
            "https://recreation.exploremoreil.com/location/244",
            "https://tsp.itinio.com/parks/fall-creek-falls",
            "https://camping.nj.gov/campground/123"
        ]

        for urlString in providerURLs {
            let action = try XCTUnwrap(
                PlaceExternalLinks.reservationAction(url: URL(string: urlString)),
                "Expected a direct reservation action for \(urlString)"
            )
            XCTAssertEqual(action.kind, .reserve)
            XCTAssertEqual(action.title, "Reservation")
        }
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

    func testPlaceProfileActionsExposeEveryAvailableCapability() throws {
        let reservation = try XCTUnwrap(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://www.opentable.com/r/anajak-thai-cuisine-sherman-oaks")
            )
        )

        let actions = PlaceExternalLinks.placeProfileActions(
            placeName: "Anajak Thai",
            latitude: 34.15182,
            longitude: -118.45363,
            websiteURLString: "https://www.anajakthai.com",
            phoneNumber: "+1 (818) 501-4201",
            actionLinksJSON: nil,
            reservationAction: reservation
        )

        XCTAssertEqual(actions.map(\.kind), [.directions, .website, .call, .reserve])
        XCTAssertEqual(actions[0].url.host, "www.google.com")
        XCTAssertEqual(actions[1].url.absoluteString, "https://www.anajakthai.com")
        XCTAssertEqual(actions[2].url.absoluteString, "tel:+18185014201")
        XCTAssertEqual(actions[3].url.host, "www.opentable.com")
    }

    func testPlaceProfileActionsHideOnlyUnavailableCapabilities() {
        let actions = PlaceExternalLinks.placeProfileActions(
            placeName: "Sparse Place",
            latitude: 34.0,
            longitude: -118.0,
            websiteURLString: nil,
            phoneNumber: "+1 213 555 0100",
            actionLinksJSON: nil,
            reservationAction: nil
        )

        XCTAssertEqual(actions.map(\.kind), [.directions, .call])
    }

    func testPlaceProfileKeepsWebsiteAndReservationWhenTheyShareAURL() throws {
        let sharedURL = try XCTUnwrap(
            URL(string: "https://www.opentable.com/r/anajak-thai-cuisine-sherman-oaks")
        )
        let reservation = try XCTUnwrap(PlaceExternalLinks.reservationAction(url: sharedURL))

        let actions = PlaceExternalLinks.placeProfileActions(
            placeName: "Anajak Thai",
            latitude: nil,
            longitude: nil,
            websiteURLString: sharedURL.absoluteString,
            phoneNumber: nil,
            actionLinksJSON: nil,
            reservationAction: reservation
        )

        XCTAssertEqual(actions.map(\.kind), [.website, .reserve])
        XCTAssertEqual(actions.map(\.url), [sharedURL, sharedURL])
    }

    func testPlaceProfileUsesActionLinkWebsiteWithoutDuplicatingCapability() throws {
        let encodedLinks = try XCTUnwrap(
            String(
                data: JSONEncoder().encode([
                    PlaceActionLink(
                        kind: .website,
                        title: "Fallback site",
                        urlString: "https://fallback.example",
                        source: .backendExtraction,
                        confidence: .exact
                    )
                ]),
                encoding: .utf8
            )
        )

        let fallbackActions = PlaceExternalLinks.placeProfileActions(
            placeName: "Fallback Place",
            latitude: nil,
            longitude: nil,
            websiteURLString: nil,
            phoneNumber: nil,
            actionLinksJSON: encodedLinks
        )
        XCTAssertEqual(fallbackActions.map(\.kind), [.website])
        XCTAssertEqual(fallbackActions.first?.url.absoluteString, "https://fallback.example")

        let preferredActions = PlaceExternalLinks.placeProfileActions(
            placeName: "Fallback Place",
            latitude: nil,
            longitude: nil,
            websiteURLString: "https://official.example",
            phoneNumber: nil,
            actionLinksJSON: encodedLinks
        )
        XCTAssertEqual(preferredActions.map(\.kind), [.website])
        XCTAssertEqual(preferredActions.first?.url.absoluteString, "https://official.example")
    }

    func testAnajakRecoveredWebsiteDiscoversExactOpenTableReservation() async {
        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://www.anajakthai.com",
            placeName: "Anajak Thai",
            locality: "Sherman Oaks",
            region: "CA",
            pageLoader: { request in
                (
                    Data(#"<a href="https://www.opentable.com/r/anajak-thai-cuisine-sherman-oaks">Book table</a>"#.utf8),
                    request.url
                )
            }
        )

        XCTAssertEqual(
            action?.url.absoluteString,
            "https://www.opentable.com/r/anajak-thai-cuisine-sherman-oaks"
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

    func testReservationDiscoveryUsesVerifiedTennesseeFallbackWhenOfficialSiteBlocksRequests() async throws {
        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://tnstateparks.com/parks/fall-creek-falls",
            placeName: "Fall Creek Falls State Park",
            locality: "Spencer",
            region: "TN",
            allowsOfficialReservationPageFallback: true,
            pageLoader: { _ in
                XCTFail("A verified park fallback should not need the blocked official website")
                throw URLError(.badServerResponse)
            }
        )

        XCTAssertEqual(
            action?.url.absoluteString,
            "https://tsp.itinio.com/fall-creek-falls/campsites"
        )
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

    func testNatureDiscoveryUsesTrustedStatePortalRootFromOfficialPark() async throws {
        let html = #"<a href="https://CampWithME.com/">Reserve a campsite</a>"#

        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://www.maine.gov/example-state-park",
            allowsOfficialReservationPageFallback: true,
            pageLoader: { request in
                (Data(html.utf8), request.url)
            }
        )

        XCTAssertEqual(action?.url.absoluteString, "https://CampWithME.com/")
    }

    func testNatureDiscoveryAcceptsTrustedStatePortalAsMapKitWebsite() async throws {
        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://camping.nj.gov/",
            allowsOfficialReservationPageFallback: true,
            pageLoader: { _ in
                XCTFail("A trusted state reservation portal should not need a website request")
                throw URLError(.badURL)
            }
        )

        XCTAssertEqual(action?.url.absoluteString, "https://camping.nj.gov/")
    }

    func testRestaurantDoesNotUseTrustedStatePortalRootAsReservation() async {
        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://camping.nj.gov/",
            pageLoader: { request in
                (Data(), request.url)
            }
        )

        XCTAssertNil(action)
    }

    func testStateReservationSearchPageIsNotAcceptedAsDirectAction() {
        XCTAssertNil(
            PlaceExternalLinks.reservationAction(
                url: URL(string: "https://camping.nj.gov/search?query=Liberty")
            )
        )
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

    func testNatureDiscoveryDoesNotTreatNaturePreserveAsReservationPage() async {
        let html = #"<a href="/parks/adams-homestead-and-nature-preserve">Related park</a>"#

        let action = await PlaceExternalLinks.discoverReservationAction(
            actionLinksJSON: nil,
            websiteURLString: "https://parks.example.gov/custer-state-park",
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
