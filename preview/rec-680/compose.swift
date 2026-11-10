import AppKit

// Composite genuine simulator images without altering their UI pixels.
let args = CommandLine.arguments
precondition(args.count == 3, "Usage: swift compose.swift <capture-root> <board-output>")
let captureRoot = args[1]
let outputRoot = args[2]
try FileManager.default.createDirectory(atPath: outputRoot, withIntermediateDirectories: true)
func board(_ name: String, _ title: String, _ screens: [(String,String,String)]) throws {
    let width: CGFloat = 1440, height: CGFloat = 1130
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor(calibratedRed: 0.953, green: 0.933, blue: 0.90, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0,y: 0,width: width,height: height)).fill()
    func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ bold: Bool = false) {
        (value as NSString).draw(at: NSPoint(x:x,y:y), withAttributes: [.font: bold ? NSFont.boldSystemFont(ofSize:size) : NSFont.systemFont(ofSize:size), .foregroundColor:NSColor(calibratedWhite:0.1,alpha:1)])
    }
    text("ASTIR  /  " + title, 30, 1084, 27, true)
    text("Native SwiftUI simulator captures · design proposal · fictional data", 30, 1057, 16)
    for (i, screen) in screens.enumerated() {
        let x = CGFloat(i) * 470 + 30
        guard let source = NSImage(contentsOfFile: captureRoot + "/" + screen.0) else { fatalError("Missing screenshot: " + screen.0) }
        let h: CGFloat = 930, w = h * source.size.width / source.size.height
        source.draw(in:NSRect(x:x+(440-w)/2,y:98,width:w,height:h))
        text(screen.1,x,57,21,true)
        text(screen.2,x,30,14)
    }
    image.unlockFocus()
    let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
    try rep.representation(using:.jpeg,properties:[.compressionFactor:0.86])!.write(to:URL(fileURLWithPath:outputRoot+"/"+name+".jpg"))
}
try board("return-and-history", "Easy to find, whenever you're ready.", [
    ("large/invitation.png", "01  A contextual invitation", "Private, dismissible, and tied to one visit."),
    ("large/profile.png", "02  A permanent home", "Profile → Your check-ins."),
    ("large/history.png", "03  Choose the exact visit", "Each visit keeps its own date and details.")])
try board("specific-visit", "One place. Different memories.", [
    ("large/place.png", "04  On the place profile", "Your visits are always within reach."),
    ("large/visits.png", "05  All your visits here", "Today's unrated visit stays separate."),
    ("large/visit.png", "06  This specific check-in", "Add any detail, whenever you like.")])
try board("edit-and-rating", "Untouched means unrated.", [
    ("large/edit.png", "07  No assumed rating", "A neutral slider and an explicit Not rated."),
    ("large/rated.png", "08  Deliberate input", "Half-point scores; Remove rating restores nil."),
    ("large/updated.png", "09  The original visit, updated", "Same date and time. No duplicate check-in.")])
try board("reminders", "A gentle push, with a direct destination.", [
    ("large/notification.png", "10  Push concept", "SwiftUI preview; no notification was sent."),
    ("large/reminders.png", "11  User control", "Optional reminders and proposed timing."),
    ("large/push-edit.png", "12  Open the referenced visit", "Ready to edit, still unrated until input.")])
try board("quick-capture-proposal", "Capture now. Add details whenever.", [
    ("large/quick.png", "13  Quick check-in", "Place, time, audience. Save."),
    ("large/later.png", "14  A visit from earlier", "Change the visit time before saving."),
    ("large/details.png", "15  Add details right away", "The same draft expands when you want it.")])
try board("other-capture-paths", "Keep the full suite of optional details.", [
    ("large/options.png", "16  Everything still available", "Photos, friends, lists, tags, questions & privacy."),
    ("large/saved.png", "17  Saved means finished", "Add details without another required step."),
    ("large/wanna.png", "18  Quick Wanna", "No visit date or rating required.")])
try board("wanna-return", "Room for plans, now or later.", [
    ("large/wannas.png", "19  Your Wanna", "A permanent route from Profile."),
    ("large/wanna-detail.png", "20  A saved place", "Keep a memory of why you wanted to go."),
    ("large/wanna-edit.png", "21  Optional plans & details", "Notes, people, lists, tags and a planned date.")])
try board("adaptive-capture", "Designed to scroll, without hiding Save.", [
    ("compact/invitation.png", "Compact · invitation", "The map stays visible around one invitation."),
    ("compact/edit.png", "Compact · edit visit", "The original visit stays identifiable."),
    ("compact/edit-large-text.png", "Larger text · edit visit", "Content scrolls; the action remains reachable.")])
try board("adaptive-return", "Light, Dark, and smaller iPhones.", [
    ("large/invitation-dark.png", "Dark · contextual invitation", "Adaptive ink and paper, same interaction."),
    ("large/history-dark.png", "Dark · visit history", "Ratings and unrated visits stay distinct."),
    ("compact/reminders.png", "Compact · reminder settings", "A preference, not another capture step.")])
