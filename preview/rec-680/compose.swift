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
    text("Actual Wander app target · proposed changes · synthetic review data", 30, 1057, 16)
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
try board("actual-refinements", "Your revisions, in the actual app.", [
    ("large/quick.png", "Date-only check-in", "Add details, helper text, then Stealth mode."),
    ("large/invitation.png", "A horizontal invitation", "Tap to reopen this exact check-in."),
    ("large/reminders.png", "Inside Push types", "Check-in reminders alongside existing options.")])
try board("actual-capture", "The existing editor, simplified.", [
    ("large/baselineEditor.png", "Current app", "The existing full form, before this proposal."),
    ("large/quick.png", "Quick check-in", "Same place header, privacy control and save action."),
    ("large/details.png", "Expand when you want", "The actual full editor. Untouched means unrated.")])
try board("actual-return", "Return to the exact visit.", [
    ("large/invitation.png", "A contextual invitation", "One dismissible invitation on the existing map."),
    ("large/history.png", "Profile → Activity", "Existing navigation and dated check-in rows."),
    ("large/placeHistory.png", "The place's check-in history", "Add details to one specific visit ticket.")])
try board("actual-details", "The full editor stays available.", [
    ("large/edit.png", "Edit that visit", "Original visit context; no assumed rating."),
    ("large/options.png", "All the existing options", "Friends, lists, photos, tags and more."),
    ("large/reminders.png", "Optional reminder", "Proposed preference in actual Notifications settings.")])
try board("actual-wanna", "Quick now. More detail whenever.", [
    ("large/past.png", "Checking in later", "Choose when the visit happened."),
    ("large/wanna.png", "Quick Wanna", "No rating or visit time to fill in."),
    ("large/wannaDetails.png", "Wanna with details", "Existing notes, lists, plans and optional controls.")])
try board("actual-compact", "Checked on a smaller iPhone too.", [
    ("compact/quick.png", "Compact check-in", "The real app on iPhone 17e."),
    ("compact/details.png", "Full details", "Scrollable fields with the save action visible."),
    ("compact/reminders.png", "Reminder settings", "The same existing Notifications sheet.")])
