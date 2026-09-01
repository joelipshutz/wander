import Foundation
import XCTest
@testable import Wander

final class CalendarReservationTests: XCTestCase {
    private let startAt = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testReservationPromptDraftUsesReservationStartInsteadOfTapTime() throws {
        let reservationStart = Date(timeIntervalSince1970: 1_750_000_000)
        let tapTime = reservationStart.addingTimeInterval(24 * 60 * 60)
        let candidate = PlaceCandidate(
            id: "calendar-elephante",
            name: "Elephante",
            category: "Restaurant",
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            latitude: 34.0195,
            longitude: -118.4912,
            confidence: 1
        )
        let context = MapPlaceSaveContext.calendarReservation(
            candidate,
            reservationID: "90000000-0000-0000-0000-000000000001",
            visitedAt: reservationStart,
            defaultVisibility: .followers
        )

        let draft = try XCTUnwrap(PlaceSaveDraft.addFlow(
            ownerUserID: "user-calendar-test",
            context: context,
            now: tapTime
        ))

        XCTAssertEqual(context.initialVisitedAt, reservationStart)
        XCTAssertEqual(draft.form.visitedAt, reservationStart)
        XCTAssertNotEqual(draft.form.visitedAt, tapTime)
    }

    func testDetectsProviderReservationWithoutPersistingRawEventIdentity() throws {
        let event = snapshot(
            identifier: "private-calendar-event-id",
            title: "Elephante - Reservation",
            location: "1332 2nd St, Santa Monica, CA",
            notes: "Manage at https://resy.com/cities/la/venues/elephante"
        )

        let reservation = try XCTUnwrap(CalendarReservationDetector.detect(event))

        XCTAssertEqual(reservation.placeQuery, "Elephante")
        XCTAssertEqual(reservation.localityHint, "Santa Monica")
        XCTAssertEqual(reservation.occurrenceKey.count, 64)
        XCTAssertFalse(reservation.occurrenceKey.contains(event.stableIdentifier))
        XCTAssertEqual(reservation.startAt, startAt)
        XCTAssertEqual(reservation.timeZoneIdentifier, "America/Los_Angeles")
    }

    func testDetectsHumanAuthoredDinnerTitle() throws {
        let reservation = try XCTUnwrap(CalendarReservationDetector.detect(snapshot(
            title: "Dinner at Bavel",
            location: "Los Angeles, CA"
        )))

        XCTAssertEqual(reservation.placeQuery, "Bavel")
        XCTAssertEqual(reservation.localityHint, "Los Angeles")
    }

    func testOccurrenceKeyIsStableForSameEventOccurrence() throws {
        let first = try XCTUnwrap(CalendarReservationDetector.detect(snapshot(
            identifier: "stable-id",
            title: "Lunch at Kismet"
        )))
        let second = try XCTUnwrap(CalendarReservationDetector.detect(snapshot(
            identifier: "stable-id",
            title: "Lunch at Kismet"
        )))

        XCTAssertEqual(first.occurrenceKey, second.occurrenceKey)
    }

    func testRejectsUnrelatedAllDayCancelledAndInvalidEvents() {
        XCTAssertNil(CalendarReservationDetector.detect(snapshot(title: "Team meeting")))
        XCTAssertNil(CalendarReservationDetector.detect(snapshot(title: "Dinner at Kismet", isAllDay: true)))
        XCTAssertNil(CalendarReservationDetector.detect(snapshot(title: "Dinner at Kismet", isCancelled: true)))
        XCTAssertNil(CalendarReservationDetector.detect(snapshot(
            title: "Dinner at Kismet",
            endAt: startAt
        )))
    }

    private func snapshot(
        identifier: String = "event-id",
        title: String,
        location: String? = nil,
        notes: String? = nil,
        urlString: String? = nil,
        endAt: Date? = nil,
        isAllDay: Bool = false,
        isCancelled: Bool = false
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            stableIdentifier: identifier,
            title: title,
            location: location,
            notes: notes,
            urlString: urlString,
            startAt: startAt,
            endAt: endAt ?? startAt.addingTimeInterval(90 * 60),
            timeZoneIdentifier: "America/Los_Angeles",
            isAllDay: isAllDay,
            isCancelled: isCancelled
        )
    }
}
