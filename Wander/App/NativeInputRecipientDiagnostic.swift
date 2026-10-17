#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import UIKit
import MapKit

/// Opt-in synthetic-fixture observation only. This adds a never-recognizing
/// observer, so its overhead must not be called a performance acceptance run.
@MainActor
enum NativeInputRecipientDiagnostic {
    enum CameraEvent { case changed, finished, parentReturned, fullyRendered }
    enum Stage: String {
        case searchActionEntered, searchSurfaceRequested, searchDestinationAppeared
        case mapSourceEntered, mapSourceSelected, mapSourceReturned
        case liveCameraEnded, liveCameraInitialEnd, liveCameraCenterChanged, liveCameraSpanChanged, liveCameraPositionedByUser
        case liveDrawerCollapsed, liveDrawerHalf, liveDrawerExpanded, liveInitialFrameApplied
    }

    enum EventsSelectionStage: String {
        case setterEntered, eligibilityRejected, selectionApplied
        case selectionChanged, eligibilityChanged, presentationChanged
    }

    static let fixture: String? = {
        let arguments = Set(ProcessInfo.processInfo.arguments)
        let required: Set<String> = ["-WanderNativeRecipientDiagnostic", "-WanderAuthenticatedUITest"]
        let excluded: Set<String> = ["-WanderUseLiveAuth", "-WanderForceSignedOut", "-WanderAuthUITest",
            "-WanderOnboardingUITestSignedOut", "-WanderUseStorefrontFixtures", "-WanderUseEphemeralEmptyFixtures"]
        guard Bundle.main.bundleIdentifier == "com.grayline.wander",
              required.isSubset(of: arguments), excluded.isDisjoint(with: arguments),
              !ReplayFixtureHostPolicy.hasRequest else { return nil }
        if arguments.contains("-WanderEventsInputDiagnostic") {
            let ordered = ProcessInfo.processInfo.arguments
            let exactFlags: Set<String> = ["-WanderNativeRecipientDiagnostic", "-WanderEventsInputDiagnostic",
                "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
                "-WanderInitialTab", "-WanderNotificationAuthorizationDeniedFixture", "-WanderTabAppearanceDiagnostics"]
            let fixtureFlags = ordered.filter { $0.hasPrefix("-Wander") }
            guard Set(fixtureFlags) == exactFlags, fixtureFlags.count == exactFlags.count,
                  let initial = ordered.firstIndex(of: "-WanderInitialTab"),
                  ordered.indices.contains(initial + 1), ordered[initial + 1] == "map" else { return nil }
            return "events-map"
        }
        let live: Set<String> = ["-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
            "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture"]
        if live.isSubset(of: arguments), LivePlanDemoPolicy.isEnabled() { return "live-demo" }
        let ordered = ProcessInfo.processInfo.arguments
        if arguments.contains("-WanderDisableWalkthroughs"),
           let index = ordered.firstIndex(of: "-WanderSenderReview"), ordered.indices.contains(index + 1),
           ordered[index + 1] == "checkIn", SenderNotificationReviewRoute.resolved() == .checkIn {
            return "sender-review"
        }
        return nil
    }()

    static func record(_ stage: Stage) {
        guard fixture != nil else { return }
        NativeRecipientRecorder.shared.record(stage)
    }

    static func liveCameraEnded(initial: Bool, centerChanged: Bool, spanChanged: Bool, userPosition: Bool) {
        guard fixture == "live-demo" else { return }
        var stages: [Stage] = [.liveCameraEnded]
        if initial { stages.append(.liveCameraInitialEnd) }
        if centerChanged { stages.append(.liveCameraCenterChanged) }
        if spanChanged { stages.append(.liveCameraSpanChanged) }
        if userPosition { stages.append(.liveCameraPositionedByUser) }
        NativeRecipientRecorder.shared.record(stages)
    }

    static func camera(_ event: CameraEvent, in map: MKMapView) {
        guard fixture != nil else { return }
        NativeRecipientRecorder.shared.camera(event, in: map)
    }

    static func silentSetterEntered(_ requested: Bool) {
        guard fixture == "sender-review" else { return }
        NativeRecipientRecorder.shared.silentSetterEntered(requested)
    }

    static func silentSetterApplied(stored: Bool?, effective: Bool) {
        guard fixture == "sender-review" else { return }
        NativeRecipientRecorder.shared.silentSetterApplied(stored: stored, effective: effective)
    }

    static func eventsSelection(_ stage: EventsSelectionStage, requested: WanderTab?,
                                current: WanderTab, eligible: Bool, activePresentation: Bool) {
        guard fixture == "events-map" else { return }
        NativeRecipientRecorder.shared.eventsSelection(stage, requested: requested, current: current,
            eligible: eligible, activePresentation: activePresentation)
    }

    static func probePublished() {
        guard fixture != nil else { return }
        NativeRecipientRecorder.shared.probePublished()
    }
}

/// Read only on AX demand: no published SwiftUI state or frame-by-frame UI updates.
@MainActor
struct NativeInputRecipientDiagnosticReadout: UIViewRepresentable {
    func makeUIView(context: Context) -> Readout {
        let view = Readout()
        view.text = "Native input diagnostic"
        view.font = .systemFont(ofSize: 1)
        view.textColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "rec636.nativeInputDiagnostic"
        view.accessibilityLabel = "Native input diagnostic"
        view.accessibilityTraits = .staticText
        return view
    }
    func updateUIView(_ view: Readout, context: Context) {}
    final class Readout: UILabel {
        override var accessibilityValue: String? {
            get { NativeRecipientRecorder.shared.readout() }
            set {}
        }
    }
}

@MainActor
struct NativeInputRecipientDiagnosticInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        anchor.isAccessibilityElement = false
        anchor.changed = { [weak coordinator = context.coordinator] anchor in coordinator?.attach(anchor.window) }
        return anchor
    }
    func updateUIView(_ anchor: Anchor, context: Context) { context.coordinator.attach(anchor.window) }
    static func dismantleUIView(_ anchor: Anchor, coordinator: Coordinator) {
        anchor.changed = nil
        coordinator.attach(nil)
    }

    final class Anchor: UIView {
        var changed: ((Anchor) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); changed?(self) }
        override func layoutSubviews() { super.layoutSubviews(); changed?(self) }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private let observer = NativeRecipientObserver(target: nil, action: nil)
        override init() {
            super.init()
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false
            observer.delegate = self
        }
        func attach(_ next: UIWindow?) {
            guard NativeInputRecipientDiagnostic.fixture != nil, window !== next else { return }
            window?.removeGestureRecognizer(observer)
            window = next
            if let next { next.addGestureRecognizer(observer) }
            NativeRecipientRecorder.shared.installation(next)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

/// It observes hit-tested UITouch.view without hit-testing again, recognizing,
/// preventing another recognizer, or changing another recognizer's properties.
private final class NativeRecipientObserver: UIGestureRecognizer {
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        NativeRecipientRecorder.shared.observe(touches, event: event, phase: "began")
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        NativeRecipientRecorder.shared.observe(touches, event: event, phase: "moved")
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        NativeRecipientRecorder.shared.observe(touches, event: event, phase: "ended")
        if event.allTouches?.allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) != false { state = .failed }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        NativeRecipientRecorder.shared.observe(touches, event: event, phase: "cancelled")
        state = .failed
    }
}

private struct NativeDiagnosticRect: Codable, Sendable {
    let x: Double, y: Double, width: Double, height: Double
    init?(_ rect: CGRect) {
        guard !rect.isNull, !rect.isInfinite,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else { return nil }
        x = Double(rect.minX); y = Double(rect.minY); width = Double(rect.width); height = Double(rect.height)
    }
}
private struct NativeDiagnosticView: Codable, Sendable {
    let type: String
    let frameInWindow: NativeDiagnosticRect?
    let hidden: Bool, alpha: Double, interactionEnabled: Bool
}
private struct NativeDiagnosticRecognizer: Codable, Sendable {
    let type: String, state: Int
    let attachedView: NativeDiagnosticView?
}
private struct NativeDiagnosticMap: Codable, Sendable {
    let ordinal: Int, view: NativeDiagnosticView
    let bounds: NativeDiagnosticRect?
    let touchRecipientIsDescendant: Bool
    let scrollEnabled: Bool, zoomEnabled: Bool, rotateEnabled: Bool, pitchEnabled: Bool
}
private struct NativeDiagnosticControlObservation: Codable, Sendable {
    let stage: String, observedUptime: Double, status: String
    let switchOrdinal: Int?, scrollOrdinal: Int?
    let touchAvailable: Bool, touchGeometryAvailable: Bool
    let normalizedTouchX: Double?, normalizedTouchY: Double?, touchInsideSwitchBounds: Bool?
    let switchAvailable: Bool, scrollAvailable: Bool
    let silentIdentifierMatched: Bool, ancestryTruncated: Bool, identityLimitReached: Bool
    let switchIsOn: Bool?, switchIsEnabled: Bool?, switchIsTracking: Bool?, switchIsTouchInside: Bool?
    let scrollIsTracking: Bool?, scrollIsDragging: Bool?, scrollIsDecelerating: Bool?
    let scrollDelaysContentTouches: Bool?, scrollCanCancelContentTouches: Bool?
}
private struct NativeDiagnosticSample: Codable, Sendable {
    let touchOrdinal: Int, phase: String
    let eventUptime: Double, touchUptime: Double, observedUptime: Double
    let x: Double?, y: Double?
    let recipientAncestry: [NativeDiagnosticView]
    let ancestryTruncated: Bool
    let recognizers: [NativeDiagnosticRecognizer]
    let recognizersTruncated: Bool
    let maps: [NativeDiagnosticMap]
    let mapScanTruncated: Bool
    let nativeControl: NativeDiagnosticControlObservation?
}
private struct NativeDiagnosticRecognizerObservation: Codable, Sendable {
    let touchOrdinal: Int, observedUptime: Double
    let recognizers: [NativeDiagnosticRecognizer]
    let nativeControl: NativeDiagnosticControlObservation?
}
private struct NativeDiagnosticStage: Codable, Sendable { let stage: String, observedUptime: Double }
private struct NativeDiagnosticInstallation: Codable, Sendable {
    let observedUptime: Double, attached: Bool, keyWindow: Bool
    let window: NativeDiagnosticView?, maps: [NativeDiagnosticMap], mapScanTruncated: Bool
}
private struct NativeDiagnosticCamera: Codable, Sendable {
    let ordinal: Int
    var changed = 0, finished = 0, parentReturned = 0, fullyRendered = 0
    var lastChangedUptime: Double?, lastFinishedUptime: Double?
    var lastParentReturnedUptime: Double?, lastFullyRenderedUptime: Double?
}
private struct NativeDiagnosticSilentSetter: Codable, Sendable {
    let ordinal: Int, requested: Bool, enteredUptime: Double
    var stored: Bool?, effective: Bool?, appliedUptime: Double?
}
private struct NativeDiagnosticEventsSelection: Encodable {
    let ordinal: Int, stage: String, observedUptime: Double
    let requested: String?, current: String
    let eligible: Bool, activePresentation: Bool
}
private struct NativeDiagnosticTrace: Codable, Sendable {
    let schema: Int, launchID: String, fixture: String
    let startedUnixSeconds: Double, startedUptime: Double
    var generation = 0
    var droppedSamples = 0, droppedStages = 0, droppedTouches = 0, droppedInstallations = 0, droppedLaterObservations = 0
    var installations: [NativeDiagnosticInstallation] = []
    var stages: [NativeDiagnosticStage] = []
    var samples: [NativeDiagnosticSample] = []
    var laterRecognizerObservations: [NativeDiagnosticRecognizerObservation] = []
    var cameras: [NativeDiagnosticCamera] = []
    var probePublications = 0
    var lastProbePublicationUptime: Double?
    var droppedCameraRecords = 0
}

@MainActor
private final class NativeRecipientRecorder {
    static let shared = NativeRecipientRecorder()
    private var trace = NativeDiagnosticTrace(schema: 2, launchID: UUID().uuidString,
        fixture: NativeInputRecipientDiagnostic.fixture ?? "disabled",
        startedUnixSeconds: Date().timeIntervalSince1970, startedUptime: ProcessInfo.processInfo.systemUptime)
    private var liveCameraEnds = 0
    private var silentSetterCalls = 0, droppedSilentSetterObservations = 0
    private var silentSetterObservations: [NativeDiagnosticSilentSetter] = []
    private var eventsSelectionCalls = 0, droppedEventsSelectionObservations = 0
    private var eventsSelectionObservations: [NativeDiagnosticEventsSelection] = []
    private weak var window: UIWindow?
    private var nextOrdinal = 0
    private var active: [ObjectIdentifier: Int] = [:]
    private var retainedOrdinals: [Int] = []
    private var pendingLater: [(Int, [UIGestureRecognizer], String, NativeControlTarget?)] = []
    private final class WeakControlView {
        weak var view: UIView?
        let ordinal: Int
        init(_ view: UIView, ordinal: Int) { self.view = view; self.ordinal = ordinal }
    }
    private var controlViews: [WeakControlView] = []
    private var nextControlOrdinal = 0
    @MainActor private final class NativeControlTarget {
        weak var control: UISwitch?
        weak var scroll: UIScrollView?
        weak var touch: UITouch?
        let targetStatus: String
        let switchOrdinal: Int?, scrollOrdinal: Int?
        let silentIdentifierMatched: Bool, ancestryTruncated: Bool, identityLimitReached: Bool
        init(control: UISwitch?, scroll: UIScrollView?, touch: UITouch, targetStatus: String,
             switchOrdinal: Int?, scrollOrdinal: Int?, silentIdentifierMatched: Bool, ancestryTruncated: Bool) {
            self.control = control; self.scroll = scroll; self.touch = touch; self.targetStatus = targetStatus
            self.switchOrdinal = switchOrdinal; self.scrollOrdinal = scrollOrdinal
            self.silentIdentifierMatched = silentIdentifierMatched; self.ancestryTruncated = ancestryTruncated
            identityLimitReached = (control != nil && switchOrdinal == nil) || (scroll != nil && scrollOrdinal == nil)
        }
        func observe(stage: String, in window: UIWindow?) -> NativeDiagnosticControlObservation {
            let nativeSwitch = control.flatMap { control -> UISwitch? in
                guard let window, control.window === window else { return nil }; return control
            }
            let nativeScroll = scroll.flatMap { scroll -> UIScrollView? in
                guard let window, scroll.window === window else { return nil }; return scroll
            }
            var normalizedX: Double?, normalizedY: Double?, insideBounds: Bool?
            if let nativeSwitch, let touch {
                let bounds = nativeSwitch.bounds
                let point = touch.location(in: nativeSwitch)
                if !bounds.isEmpty, !bounds.isNull, !bounds.isInfinite,
                   [bounds.minX, bounds.minY, bounds.width, bounds.height, point.x, point.y].allSatisfy(\.isFinite) {
                    let x = Double((point.x - bounds.minX) / bounds.width)
                    let y = Double((point.y - bounds.minY) / bounds.height)
                    if x.isFinite && y.isFinite {
                        normalizedX = x; normalizedY = y; insideBounds = bounds.contains(point)
                    }
                }
            }
            let status = targetStatus != "found" ? targetStatus
                : nativeSwitch == nil ? "switch_window_unavailable"
                : nativeScroll == nil ? "scroll_unavailable" : "available"
            return .init(stage: stage, observedUptime: ProcessInfo.processInfo.systemUptime, status: status,
                switchOrdinal: switchOrdinal, scrollOrdinal: scrollOrdinal,
                touchAvailable: touch != nil, touchGeometryAvailable: normalizedX != nil && normalizedY != nil,
                normalizedTouchX: normalizedX, normalizedTouchY: normalizedY, touchInsideSwitchBounds: insideBounds,
                switchAvailable: nativeSwitch != nil, scrollAvailable: nativeScroll != nil,
                silentIdentifierMatched: silentIdentifierMatched, ancestryTruncated: ancestryTruncated,
                identityLimitReached: identityLimitReached,
                switchIsOn: nativeSwitch?.isOn, switchIsEnabled: nativeSwitch?.isEnabled,
                switchIsTracking: nativeSwitch?.isTracking, switchIsTouchInside: nativeSwitch?.isTouchInside,
                scrollIsTracking: nativeScroll?.isTracking, scrollIsDragging: nativeScroll?.isDragging,
                scrollIsDecelerating: nativeScroll?.isDecelerating,
                scrollDelaysContentTouches: nativeScroll?.delaysContentTouches,
                scrollCanCancelContentTouches: nativeScroll?.canCancelContentTouches)
        }
    }
    private var laterObservationScheduled = false
    private final class WeakMap {
        weak var map: MKMapView?
        let ordinal: Int
        init(_ map: MKMapView, ordinal: Int) { self.map = map; self.ordinal = ordinal }
    }
    private var knownMaps: [WeakMap] = [], cachedMaps: [WeakMap] = []
    private var nextMapOrdinal = 0
    private var mapScanTruncated = false

    func installation(_ window: UIWindow?) {
        self.window = window
        refreshMapInventory(in: window)
        let item = NativeDiagnosticInstallation(observedUptime: ProcessInfo.processInfo.systemUptime,
            attached: window != nil, keyWindow: window?.isKeyWindow ?? false,
            window: window.map(viewRecord), maps: mapRecords(recipient: nil), mapScanTruncated: mapScanTruncated)
        if trace.installations.count == 16 { trace.installations.removeFirst(); trace.droppedInstallations += 1 }
        trace.installations.append(item)
        flush()

    }

    func camera(_ event: NativeInputRecipientDiagnostic.CameraEvent, in map: MKMapView) {
        guard let ordinal = mapOrdinal(map) else { trace.droppedCameraRecords += 1; return }
        if !trace.cameras.contains(where: { $0.ordinal == ordinal }) {
            guard trace.cameras.count < 16 else { trace.droppedCameraRecords += 1; return }
            trace.cameras.append(.init(ordinal: ordinal))
        }
        guard let index = trace.cameras.firstIndex(where: { $0.ordinal == ordinal }) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        switch event {
        case .changed:
            trace.cameras[index].changed += 1; trace.cameras[index].lastChangedUptime = now
        case .finished:
            trace.cameras[index].finished += 1; trace.cameras[index].lastFinishedUptime = now
        case .parentReturned:
            trace.cameras[index].parentReturned += 1; trace.cameras[index].lastParentReturnedUptime = now
        case .fullyRendered:
            trace.cameras[index].fullyRendered += 1; trace.cameras[index].lastFullyRenderedUptime = now
        }
        // Counters stay in memory until the post-decision native AX read.
        // No encoding, file I/O, state publication or map queries on callbacks.
    }

    func probePublished() {
        trace.probePublications += 1
        trace.lastProbePublicationUptime = ProcessInfo.processInfo.systemUptime
    }

    func silentSetterEntered(_ requested: Bool) {
        silentSetterCalls += 1
        if silentSetterObservations.count == 8 {
            silentSetterObservations.removeFirst(); droppedSilentSetterObservations += 1
        }
        silentSetterObservations.append(.init(ordinal: silentSetterCalls,
            requested: requested, enteredUptime: ProcessInfo.processInfo.systemUptime))
    }

    func silentSetterApplied(stored: Bool?, effective: Bool) {
        guard !silentSetterObservations.isEmpty else { return }
        let index = silentSetterObservations.count - 1
        silentSetterObservations[index].stored = stored
        silentSetterObservations[index].effective = effective
        silentSetterObservations[index].appliedUptime = ProcessInfo.processInfo.systemUptime
    }

    func eventsSelection(_ stage: NativeInputRecipientDiagnostic.EventsSelectionStage,
                         requested: WanderTab?, current: WanderTab, eligible: Bool, activePresentation: Bool) {
        eventsSelectionCalls += 1
        // Preserve the earliest selection sequence; later overflow is explicit.
        guard eventsSelectionObservations.count < 32 else {
            droppedEventsSelectionObservations += 1
            return
        }
        eventsSelectionObservations.append(.init(ordinal: eventsSelectionCalls, stage: stage.rawValue,
            observedUptime: ProcessInfo.processInfo.systemUptime, requested: requested?.rawValue,
            current: current.rawValue, eligible: eligible, activePresentation: activePresentation))
    }

    private struct ReadoutSample: Encodable {
        let ordinal: Int, phase: String
        let eventUptime: Double, touchUptime: Double, observedUptime: Double
        let recipientTypes: [Int], recognizers: [[Int]]
        let recipientTruncated: Bool, recognizersTruncated: Bool, mapScanTruncated: Bool
        let mapDescendant: Bool, mapScrollEnabled: Bool?
        let nativeControl: NativeDiagnosticControlObservation?
    }
    private struct ReadoutLater: Encodable {
        let ordinal: Int, observedUptime: Double
        let recognizers: [[Int]], recognizersTruncated: Bool
        let nativeControl: NativeDiagnosticControlObservation?
    }
    private struct Readout: Encodable {
        let schema: Int, fixture: String
        let observedUptime: Double, generation: Int, attached: Bool, keyWindow: Bool
        let types: [String], typeOverflow: Int, typeNameTruncations: Int
        let latestOrdinal: Int?, availableSamples: Int, omittedSamples: Int
        let samples: [ReadoutSample], laterObservations: [ReadoutLater]
        let omittedLaterObservations: Int
        let silentSetterCalls: Int, droppedSilentSetterObservations: Int
        let silentSetterObservations: [NativeDiagnosticSilentSetter]
        let eventsSelectionCalls: Int, droppedEventsSelectionObservations: Int
        let eventsSelectionObservations: [NativeDiagnosticEventsSelection]
        let stages: [NativeDiagnosticStage], liveCameraEndCount: Int
        let droppedSamples: Int, droppedTouches: Int, droppedStages: Int, droppedLaterObservations: Int
    }

    /// One native AX read after the original XCTest decision. The projection is
    /// memory-only and excludes coordinates, frames, labels, values and IDs.
    func readout() -> String {
        var types: [String] = [], typeOverflow = 0, typeNameTruncations = 0
        func typeID(_ name: String) -> Int {
            if name.count > 96 { typeNameTruncations += 1 }
            let bounded = String(name.prefix(96))
            if let index = types.firstIndex(of: bounded) { return index }
            guard types.count < 96 else { typeOverflow += 1; return -1 }
            types.append(bounded); return types.count - 1
        }
        func recognizers(_ items: [NativeDiagnosticRecognizer]) -> [[Int]] {
            items.prefix(12).map { [typeID($0.type), $0.state, $0.attachedView.map { typeID($0.type) } ?? -1] }
        }
        let ordinal = trace.samples.last?.touchOrdinal
        let available = trace.samples.filter { $0.touchOrdinal == ordinal }
        // Preserve both ends explicitly if the complete sequence exceeds64 rows.
        let selected = available.count <= 64 ? available : Array(available.prefix(32)) + Array(available.suffix(32))
        let samples = selected.map { sample in
            let map = sample.maps.first { $0.touchRecipientIsDescendant }
            return ReadoutSample(ordinal: sample.touchOrdinal, phase: sample.phase,
                eventUptime: sample.eventUptime, touchUptime: sample.touchUptime, observedUptime: sample.observedUptime,
                recipientTypes: sample.recipientAncestry.prefix(8).map { typeID($0.type) },
                recognizers: recognizers(sample.recognizers),
                recipientTruncated: sample.ancestryTruncated || sample.recipientAncestry.count > 8,
                recognizersTruncated: sample.recognizersTruncated || sample.recognizers.count > 12,
                mapScanTruncated: sample.mapScanTruncated,
                mapDescendant: map != nil, mapScrollEnabled: map?.scrollEnabled,
                nativeControl: sample.nativeControl)
        }
        let availableLater = trace.laterRecognizerObservations.filter { $0.touchOrdinal == ordinal }
        let later = availableLater.suffix(4).map {
            ReadoutLater(ordinal: $0.touchOrdinal, observedUptime: $0.observedUptime,
                         recognizers: recognizers($0.recognizers), recognizersTruncated: $0.recognizers.count > 12,
                         nativeControl: $0.nativeControl)
        }
        let value = Readout(schema: 3, fixture: trace.fixture,
            observedUptime: ProcessInfo.processInfo.systemUptime, generation: trace.generation,
            attached: window != nil, keyWindow: window?.isKeyWindow ?? false,
            types: types, typeOverflow: typeOverflow, typeNameTruncations: typeNameTruncations, latestOrdinal: ordinal,
            availableSamples: available.count, omittedSamples: available.count - selected.count,
            samples: samples, laterObservations: later, omittedLaterObservations: availableLater.count - later.count,
            silentSetterCalls: silentSetterCalls, droppedSilentSetterObservations: droppedSilentSetterObservations,
            silentSetterObservations: silentSetterObservations,
            eventsSelectionCalls: eventsSelectionCalls,
            droppedEventsSelectionObservations: droppedEventsSelectionObservations,
            eventsSelectionObservations: eventsSelectionObservations,
            stages: trace.stages, liveCameraEndCount: liveCameraEnds,
            droppedSamples: trace.droppedSamples, droppedTouches: trace.droppedTouches,
            droppedStages: trace.droppedStages, droppedLaterObservations: trace.droppedLaterObservations)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value), data.count <= 65_536,
              let result = String(data: data, encoding: .utf8) else {
            return "{\"schema\":3,\"status\":\"Gap\",\"reason\":\"readout_size_or_encoding\"}"
        }
        return result
    }

    func record(_ stage: NativeInputRecipientDiagnostic.Stage) { record([stage]) }

    func record(_ stages: [NativeInputRecipientDiagnostic.Stage]) {
        let now = ProcessInfo.processInfo.systemUptime
        for stage in stages {
            if stage == .liveCameraEnded { liveCameraEnds += 1 }
            if trace.stages.count == 128 { trace.stages.removeFirst(); trace.droppedStages += 1 }
            trace.stages.append(.init(stage: stage.rawValue, observedUptime: now))
        }
        flush()
    }

    func observe(_ touches: Set<UITouch>, event: UIEvent, phase: String) {
        // Refresh weak identities once at touch start, never scan the view tree
        // on a moved event. Frame reads below do not request layout or hit-test.
        if phase == "began" { refreshMapInventory(in: window) }
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if phase == "began" && active[key] == nil {
                guard active.count < 16 else { trace.droppedTouches += 1; continue }
                nextOrdinal += 1
                active[key] = nextOrdinal
                retainedOrdinals.append(nextOrdinal)
                if retainedOrdinals.count > 8 {
                    let removed = retainedOrdinals.removeFirst()
                    let oldCount = trace.samples.count
                    trace.samples.removeAll { $0.touchOrdinal == removed }
                    trace.droppedSamples += oldCount - trace.samples.count
                }
            }
            guard let ordinal = active[key] else { trace.droppedTouches += 1; continue }
            guard retainedOrdinals.contains(ordinal) else {
                trace.droppedSamples += 1
                if phase == "ended" || phase == "cancelled" { active.removeValue(forKey: key) }
                continue
            }
            let recipient = touch.view
            var ancestry: [NativeDiagnosticView] = []
            var ancestor = recipient
            while let current = ancestor, ancestry.count < 16 {
                ancestry.append(viewRecord(current)); ancestor = current.superview
            }
            let involved = touch.gestureRecognizers ?? []
            let observeControl = phase == "began" || phase == "ended" || phase == "cancelled"
            let controlTarget = observeControl ? senderControlTarget(from: touch) : nil
            let point = touch.location(in: window)
            let sample = NativeDiagnosticSample(touchOrdinal: ordinal, phase: phase,
                eventUptime: event.timestamp, touchUptime: touch.timestamp,
                observedUptime: ProcessInfo.processInfo.systemUptime,
                x: point.x.isFinite ? Double(point.x) : nil, y: point.y.isFinite ? Double(point.y) : nil,
                recipientAncestry: ancestry, ancestryTruncated: ancestor != nil,
                recognizers: involved.prefix(24).map(recognizerRecord), recognizersTruncated: involved.count > 24,
                maps: mapRecords(recipient: recipient), mapScanTruncated: mapScanTruncated,
                nativeControl: controlTarget?.observe(stage: phase, in: window))
            if trace.samples.count == 512 { trace.samples.removeFirst(); trace.droppedSamples += 1 }
            trace.samples.append(sample)
            if phase == "began" || phase == "ended" || phase == "cancelled" {
                // One later main-actor sample, without waiting or blocking event
                // delivery. It can miss transient recognizer states; no absence
                // here proves that a recognizer never began.
                scheduleLaterObservation(ordinal, recognizers: Array(involved.prefix(24)),
                                         phase: phase, controlTarget: controlTarget)
            }
            if phase == "ended" || phase == "cancelled" { active.removeValue(forKey: key) }
        }
        // No disk I/O or JSON encoding runs on this event path. Native XCTest
        // reads the bounded in-memory projection after its original decision.
        if phase != "moved" { flush() }
    }

    private func scheduleLaterObservation(_ ordinal: Int, recognizers: [UIGestureRecognizer],
                                          phase: String, controlTarget: NativeControlTarget?) {
        if pendingLater.count == 48 { pendingLater.removeFirst(); trace.droppedLaterObservations += 1 }
        pendingLater.append((ordinal, recognizers, phase, controlTarget))
        guard !laterObservationScheduled else { return }
        laterObservationScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let pending = self.pendingLater
            self.pendingLater.removeAll(keepingCapacity: true)
            self.laterObservationScheduled = false
            for (ordinal, recognizers, phase, controlTarget) in pending {
                if self.trace.laterRecognizerObservations.count == 48 {
                    self.trace.laterRecognizerObservations.removeFirst()
                    self.trace.droppedLaterObservations += 1
                }
                self.trace.laterRecognizerObservations.append(.init(touchOrdinal: ordinal,
                    observedUptime: ProcessInfo.processInfo.systemUptime,
                    recognizers: recognizers.map(self.recognizerRecord),
                    nativeControl: controlTarget?.observe(stage: "deferredAfter-" + phase, in: self.window)))
            }
            self.flush()
        }
    }

    // Only the synthetic checkIn fixture reads public native control state.
    // The test binds save.silent before input; a matching UIView identifier is
    // supplementary because SwiftUI's accessibility row may not be a UIView.
    private func senderControlTarget(from touch: UITouch) -> NativeControlTarget? {
        guard trace.fixture == "sender-review" else { return nil }
        let recipient = touch.view
        var ancestor: UIView? = recipient
        var visited = 0, silentIdentifierMatched = false
        var control: UISwitch?, scroll: UIScrollView?
        while let view = ancestor, visited < 16 {
            visited += 1
            silentIdentifierMatched = silentIdentifierMatched || view.accessibilityIdentifier == "save.silent"
            if control == nil { control = view as? UISwitch }
            if control != nil, scroll == nil { scroll = view as? UIScrollView }
            ancestor = view.superview
        }
        let status = recipient == nil ? "recipient_unavailable"
            : control != nil ? "found" : ancestor != nil ? "ancestry_limit_before_switch" : "switch_not_in_ancestry"
        return NativeControlTarget(control: control, scroll: scroll, touch: touch, targetStatus: status,
            switchOrdinal: control.flatMap(controlOrdinal), scrollOrdinal: scroll.flatMap(controlOrdinal),
            silentIdentifierMatched: silentIdentifierMatched, ancestryTruncated: ancestor != nil)
    }
    private func controlOrdinal(_ view: UIView) -> Int? {
        controlViews.removeAll { $0.view == nil }
        if let known = controlViews.first(where: { $0.view === view }) { return known.ordinal }
        guard controlViews.count < 16 else { return nil }
        nextControlOrdinal += 1
        controlViews.append(WeakControlView(view, ordinal: nextControlOrdinal))
        return nextControlOrdinal
    }
    private func flush() { trace.generation += 1 }
    private func viewRecord(_ view: UIView) -> NativeDiagnosticView {
        NativeDiagnosticView(type: String(String(describing: type(of: view)).prefix(192)),
            frameInWindow: window.flatMap { view.window === $0 ? NativeDiagnosticRect(view.convert(view.bounds, to: $0)) : nil },
            hidden: view.isHidden, alpha: Double(view.alpha), interactionEnabled: view.isUserInteractionEnabled)
    }
    private func recognizerRecord(_ recognizer: UIGestureRecognizer) -> NativeDiagnosticRecognizer {
        NativeDiagnosticRecognizer(type: String(String(describing: type(of: recognizer)).prefix(192)), state: recognizer.state.rawValue,
            attachedView: recognizer.view.map(viewRecord))
    }
    private func mapRecords(recipient: UIView?) -> [NativeDiagnosticMap] {
        cachedMaps.compactMap { entry in
            guard let map = entry.map, map.window === window else { return nil }
            return NativeDiagnosticMap(ordinal: entry.ordinal, view: viewRecord(map), bounds: NativeDiagnosticRect(map.bounds),
                touchRecipientIsDescendant: recipient.map { $0 === map || $0.isDescendant(of: map) } ?? false,
                scrollEnabled: map.isScrollEnabled, zoomEnabled: map.isZoomEnabled,
                rotateEnabled: map.isRotateEnabled, pitchEnabled: map.isPitchEnabled)
        }
    }
    private func refreshMapInventory(in window: UIWindow?) {
        cachedMaps.removeAll(keepingCapacity: true)
        knownMaps.removeAll { $0.map == nil }
        mapScanTruncated = false
        guard let window else { return }
        var stack: [UIView] = [window], visited = 0
        while let view = stack.popLast(), visited < 2048 {
            visited += 1
            if let map = view as? MKMapView {
                guard cachedMaps.count < 8 else { mapScanTruncated = true; return }
                guard let ordinal = mapOrdinal(map), let known = knownMaps.first(where: { $0.ordinal == ordinal })
                else { mapScanTruncated = true; return }
                cachedMaps.append(known)
            }
            // Bound both the visited hierarchy and the pending traversal memory.
            let room = max(0, 2048 - visited - stack.count)
            stack.append(contentsOf: view.subviews.prefix(room))
            if view.subviews.count > room { mapScanTruncated = true; return }
        }
        mapScanTruncated = !stack.isEmpty
    }

    private func mapOrdinal(_ map: MKMapView) -> Int? {
        knownMaps.removeAll { $0.map == nil }
        if let known = knownMaps.first(where: { $0.map === map }) { return known.ordinal }
        guard knownMaps.count < 16 else { return nil }
        nextMapOrdinal += 1
        knownMaps.append(WeakMap(map, ordinal: nextMapOrdinal))
        return nextMapOrdinal
    }
}

#endif
