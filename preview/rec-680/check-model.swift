import Foundation

@main struct ModelChecks {
    static func main() {
        var rating = PreviewRating()
        precondition(rating.sliderPosition == 3 && rating.value == nil, "Reading the thumb position must not rate a visit")
        rating.beginInteraction()
        precondition(rating.value == 3, "Touching the midpoint deliberately selects 3")
        rating.select(4.5)
        precondition(rating.value == 4.5)
        rating.remove()
        precondition(rating.value == nil && rating.sliderPosition == 3)

        var history = PreviewHistory()
        let original = history.visits[0]
        var edited = original
        edited.note = "A useful memory"
        history.save(edited)
        precondition(history.visits.count == 3)
        precondition(history.visits[0].id == original.id && history.visits[0].time == original.time)
        precondition(history.visits[0].rating.value == nil, "Adding a note must leave an untouched slider unrated")
        precondition(!edited.invitationEligible, "Any meaningful detail ends this invitation")
        var older = history.visits[2]
        older.note = "Changed note"
        history.save(older)
        precondition(history.visits[2].rating.value == 4 && history.visits[2].id == older.id, "Editing preserves a previous explicit rating and ordering")
        older.rating.remove()
        history.save(older)
        precondition(history.visits[2].rating.value == nil)
        var dismissed = original
        dismissed.invitationDismissed = true
        precondition(!dismissed.invitationEligible)
        precondition(!PreviewVisit.wanna.invitationEligible)
        print("PASS: unrated slider, explicit midpoint, half points, clear, exact-visit edits, stable time/order, invitation eligibility")
    }
}
