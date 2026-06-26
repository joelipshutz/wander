import XCTest
@testable import Wander

final class LinkPlaceParserTests: XCTestCase {
    private let parser = LinkPlaceParser()

    func testParsesGoogleMapsPlacePath() {
        let input = parser.manualInput(
            from: LinkPlaceInput(rawValue: "https://www.google.com/maps/place/Larchmont+Noodles/@34.073,-118.323,17z")
        )

        XCTAssertEqual(input, ManualPlaceInput(name: "Larchmont Noodles", areaHint: nil, category: nil))
    }

    func testParsesExpandedGoogleMapsShortLinkDestination() {
        let input = parser.manualInput(
            from: LinkPlaceInput(rawValue: "https://maps.google.com/maps?q=Tahoe+Waterman's+Landing,+5166+N+Lake+Blvd,+Carnelian+Bay,+CA+96140&ftid=0x8099634d085665a5:0x9db0380829c24219")
        )

        XCTAssertEqual(
            input,
            ManualPlaceInput(name: "Tahoe Waterman's Landing, 5166 N Lake Blvd, Carnelian Bay, CA 96140", areaHint: nil, category: nil)
        )
    }

    func testParsesAppleMapsQuery() {
        let input = parser.manualInput(
            from: LinkPlaceInput(rawValue: "https://maps.apple.com/?q=Maru%20Coffee&ll=34.0407,-118.2354")
        )

        XCTAssertEqual(input, ManualPlaceInput(name: "Maru Coffee", areaHint: "34.0407,-118.2354", category: nil))
    }

    func testParsesExpandedMapsAppleShortLinkDestination() {
        let input = parser.manualInput(
            from: LinkPlaceInput(rawValue: "https://maps.apple.com/place?address=2327%20Main%20St,%20Santa%20Monica,%20CA%20%2090405,%20United%20States&coordinate=34.004387,-118.485816&name=Urth%20Caff%C3%A9&place-id=I1BEA961C41ECB5A7&map=explore")
        )

        XCTAssertEqual(input, ManualPlaceInput(name: "Urth Café", areaHint: "34.004387,-118.485816", category: nil))
    }

    func testRecognizesMapsAppleShortLink() {
        XCTAssertTrue(parser.isShortMapLink(LinkPlaceInput(rawValue: "https://maps.apple/p/hDU04tUWpbVsMn")))
    }

    func testParsesAppleMapsAddressParameter() {
        let input = parser.manualInput(
            from: LinkPlaceInput(rawValue: "https://maps.apple.com/place?address=Urth%20Caffe,%20451%20S%20Hewitt%20St,%20Los%20Angeles,%20CA%2090013")
        )

        XCTAssertEqual(input, ManualPlaceInput(name: "Urth Caffe, 451 S Hewitt St, Los Angeles, CA 90013", areaHint: nil, category: nil))
    }

    func testParsesAppleMapsPlacePathAndCoordinateHint() {
        let input = parser.manualInput(
            from: LinkPlaceInput(rawValue: "https://maps.apple.com/place/Lake%20Shrine?coordinate=34.0483,-118.4634")
        )

        XCTAssertEqual(input, ManualPlaceInput(name: "Lake Shrine", areaHint: "34.0483,-118.4634", category: nil))
    }

    func testParsesInstagramLocationSlug() {
        let input = parser.manualInput(
            from: LinkPlaceInput(rawValue: "https://www.instagram.com/explore/locations/123456789/larchmont-noodles/")
        )

        XCTAssertEqual(input, ManualPlaceInput(name: "larchmont noodles", areaHint: nil, category: nil))
    }

    func testParsesInstagramBusinessProfileSlug() {
        let input = parser.manualInput(
            from: LinkPlaceInput(rawValue: "https://www.instagram.com/ronan_la")
        )

        XCTAssertEqual(input, ManualPlaceInput(name: "ronan la", areaHint: nil, category: nil))
    }

    func testDoesNotTreatInstagramPostAsPlaceName() {
        let input = parser.manualInput(
            from: LinkPlaceInput(rawValue: "https://www.instagram.com/p/C1234567890/")
        )

        XCTAssertNil(input)
    }

    func testRejectsOpaqueShortLinkWithoutPlaceHint() {
        let input = parser.manualInput(from: LinkPlaceInput(rawValue: "https://maps.app.goo.gl/abc123"))

        XCTAssertNil(input)
        XCTAssertTrue(parser.isShortMapLink(LinkPlaceInput(rawValue: "https://maps.app.goo.gl/abc123")))
    }

    func testTreatsPlainTextAsManualHint() {
        let input = parser.manualInput(from: LinkPlaceInput(rawValue: "Courage Bagels near Virgil"))

        XCTAssertEqual(input, ManualPlaceInput(name: "Courage Bagels near Virgil", areaHint: nil, category: nil))
    }

    func testShortLinkCopyIsSpecific() {
        XCTAssertEqual(
            PlaceResolutionError.shortLinkNeedsExtraction.localizedDescription,
            "Short map links need extraction. Save this as a draft for now or add it manually."
        )
    }
}
