import MapKit
import SwiftUI

final class CircleQuestionMapAnnotation: NSObject, MKAnnotation {
    let question: CircleQuestion
    var coordinate: CLLocationCoordinate2D { question.draft.area?.coordinate ?? .init() }
    var title: String? { question.draft.headline.replacingOccurrences(of: "\n", with: " ") }
    init(_ question: CircleQuestion) { self.question = question }
}

@MainActor final class CircleQuestionMapAnnotationView: MKAnnotationView {
    static let reuseID = "circle-question"
    private let host: UIHostingController<CircleQuestionPin>
    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        host = UIHostingController(rootView: CircleQuestionPin())
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        host.view.backgroundColor = .clear; host.view.frame = bounds
        host.view.isUserInteractionEnabled = false
        addSubview(host.view)
        canShowCallout = false; displayPriority = .required; collisionMode = .rectangle
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { nil }
}
