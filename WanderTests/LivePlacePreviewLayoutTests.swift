import SwiftUI
import UIKit
import XCTest
@testable import Wander

@MainActor
final class LivePlacePreviewLayoutTests: XCTestCase {
    func testHeaderKeepsPhoneWidthWithPanoramicPortraitAndMissingImages() {
        let images: [UIImage?] = [nil, image(width: 2_400, height: 120),
            image(width: 120, height: 2_400), image(width: 600, height: 600)]
        for width: CGFloat in [288, 343, 398] {
            for image in images {
                let host = UIHostingController(rootView: header(image: image).environment(\.dynamicTypeSize, .large))
                let size = host.sizeThatFits(in: CGSize(width: width, height: 1_000))
                XCTAssertEqual(size.width, width, accuracy: 0.5,
                    "Image aspect ratio cannot widen the layout that positions title and controls")
                XCTAssertEqual(size.height, 196, accuracy: 0.5)
            }
        }
    }

    func testAccessibilityHeaderStaysBoundedWithLongTitleAndWidePhoto() {
        let host = UIHostingController(rootView: header(image: image(width: 2_400, height: 120),
            name: "Coffee House and Neighborhood Gathering Place")
            .environment(\.dynamicTypeSize, .accessibility3))
        let size = host.sizeThatFits(in: CGSize(width: 288, height: 1_000))
        XCTAssertEqual(size.width, 288, accuracy: 0.5)
        XCTAssertEqual(size.height, 236, accuracy: 0.5)
    }

    private func header(image: UIImage?, name: String = "Coffee House") -> LivePlacePreviewHeader {
        LivePlacePreviewHeader(name: name, image: image, onOpen: {}, onAdd: {},
            onShare: {}, onAddToList: {}, onClose: {})
    }

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
