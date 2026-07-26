import Foundation

enum WanderWidgetConstants {
    static let appGroupIdentifier = "group.com.grayline.wander.shared"
    static let calendarSnapshotFilename = "activity-calendar-snapshot.json"
    static let nearbySnapshotFilename = "nearby-place-snapshot.json"

    static let quickCaptureKind = "QuickCaptureWidget"
    static let quickSearchKind = "QuickSearchWidget"
    static let activityCalendarKind = "ActivityCalendarWidget"
    static let nearbyPlacesKind = "NearbyPlacesWidget"

    static let quickCaptureURL = URL(string: "recme://add/here-now")!
    static let quickSearchURL = URL(string: "recme://map/search")!
    static let profileCalendarURL = URL(string: "recme://profile/calendar")!
}
