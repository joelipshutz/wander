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
        case onboardingNextCircleEntered, onboardingNextRecentEntered, onboardingNextOtherEntered
        case onboardingArrivingRequested, onboardingCircleRequested, onboardingCenteringRequested
        case onboardingRecentRequested, onboardingReturningRequested, onboardingFinishedRequested
        case onboardingArrivingTaskEntered, onboardingCircleTaskEntered, onboardingCenteringTaskEntered
        case onboardingRecentTaskEntered, onboardingReturningTaskEntered, onboardingFinishedTaskEntered
        case onboardingSceneInactive, onboardingCenteringScrollRequested
        case onboardingCenteringTargetReady, onboardingCenteringTargetUnavailable
    }

    static let fixture: String? = {
        let arguments = Set(ProcessInfo.processInfo.arguments)
        let required: Set<String> = ["-WanderNativeRecipientDiagnostic", "-WanderAuthenticatedUITest"]
        let excluded: Set<String> = ["-WanderUseLiveAuth", "-WanderForceSignedOut", "-WanderAuthUITest",
            "-WanderOnboardingUITestSignedOut", "-WanderUseStorefrontFixtures", "-WanderUseEphemeralEmptyFixtures"]
        guard Bundle.main.bundleIdentifier == "com.grayline.wander",
              required.isSubset(of: arguments), excluded.isDisjoint(with: arguments),
              !ReplayFixtureHostPolicy.hasRequest else { return nil }
        if arguments.contains("-WanderOnboardingNextDiagnostic") {
            let onboarding: Set<String> = [
                "-WanderNativeRecipientDiagnostic", "-WanderOnboardingNextDiagnostic",
                "-WanderAuthenticatedUITest", "-WanderMapCapture", "-WanderUseDemoFixtures",
                "-WanderEnableWalkthroughs", "-WanderResetWalkthroughs",
                "-WanderHoldWalkthroughStep", "-WanderNUXFeedFixture"
            ]
            // One synthetic case only. Additional app flags, including other
            // fixture/auth/live modes, cannot fall through to another admission.
            guard Set(arguments.filter { $0.hasPrefix("-Wander") }) == onboarding else { return nil }
            return "onboarding-map-overview"
        }
        if LivePlanDemoPolicy.isEnabled(), arguments.contains("-WanderNUXFeedFixture") { return "live-demo" }
        let performance: Set<String> = ["-WanderMapCapture", "-WanderUsePerformanceFixtures"]
        if performance.isSubset(of: arguments), !arguments.contains("-WanderUseDemoFixtures") {
            return "map-performance"
        }
        return nil
    }()

    static func record(_ stage: Stage) {
        guard fixture != nil else { return }
        NativeRecipientRecorder.shared.record(stage)
    }

    static func onboarding(_ stage: Stage) {
        guard fixture == "onboarding-map-overview" else { return }
        NativeRecipientRecorder.shared.record(stage)
    }

    static func camera(_ event: CameraEvent, in map: MKMapView) {
        guard fixture != nil else { return }
        NativeRecipientRecorder.shared.camera(event, in: map)
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
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "rec636.nativeInputDiagnostic"
        view.accessibilityLabel = "Native input diagnostic"
        view.accessibilityTraits = .staticText
        return view
    }
    func updateUIView(_ view: Readout, context: Context) {}
    final class Readout: UIView {
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
}
private struct NativeDiagnosticRecognizerObservation: Codable, Sendable {
    let touchOrdinal: Int, observedUptime: Double
    let recognizers: [NativeDiagnosticRecognizer]
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
private struct NativeDiagnosticLiveness: Codable, Sendable {
    let observedUptime: Double, attached: Bool, keyWindow: Bool
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
    var liveness: [NativeDiagnosticLiveness] = []
    var droppedCameraRecords = 0
}

@MainActor
private final class NativeRecipientRecorder {
    static let shared = NativeRecipientRecorder()
    private var trace = NativeDiagnosticTrace(schema: 2, launchID: UUID().uuidString,
        fixture: NativeInputRecipientDiagnostic.fixture ?? "disabled",
        startedUnixSeconds: Date().timeIntervalSince1970, startedUptime: ProcessInfo.processInfo.systemUptime)
    private let writer = NativeDiagnosticWriter()
    private weak var window: UIWindow?
    private var nextOrdinal = 0
    private var active: [ObjectIdentifier: Int] = [:]
    private var retainedOrdinals: [Int] = []
    private var pendingLater: [(Int, [UIGestureRecognizer])] = []
    private var laterObservationScheduled = false
    private final class WeakMap {
        weak var map: MKMapView?
        let ordinal: Int
        init(_ map: MKMapView, ordinal: Int) { self.map = map; self.ordinal = ordinal }
    }
    private var knownMaps: [WeakMap] = [], cachedMaps: [WeakMap] = []
    private var nextMapOrdinal = 0
    private var mapScanTruncated = false
    private var livenessStarted = false

    func installation(_ window: UIWindow?) {
        self.window = window
        refreshMapInventory(in: window)
        let item = NativeDiagnosticInstallation(observedUptime: ProcessInfo.processInfo.systemUptime,
            attached: window != nil, keyWindow: window?.isKeyWindow ?? false,
            window: window.map(viewRecord), maps: mapRecords(recipient: nil), mapScanTruncated: mapScanTruncated)
        if trace.installations.count == 16 { trace.installations.removeFirst(); trace.droppedInstallations += 1 }
        trace.installations.append(item)
        flush()
        if window != nil, !livenessStarted {
            livenessStarted = true
            // A bounded liveness record distinguishes a live observer with no
            // delivered touches from an old or detached trace. Diagnostic only.
            // After 180 ticks, touch/stage writes continue; later silence alone
            // cannot establish that the observer or main thread stopped.
            Task { @MainActor [weak self] in
                for _ in 0..<180 {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self else { return }
                    self.trace.liveness.append(.init(
                        observedUptime: ProcessInfo.processInfo.systemUptime,
                        attached: self.window != nil, keyWindow: self.window?.isKeyWindow ?? false))
                    self.flush()
                }
            }
        }
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
        // The liveness/sequence-boundary writer persists these scalar counters.
        // No encoding, file I/O, state publication or map queries on callbacks.
    }

    func probePublished() {
        trace.probePublications += 1
        trace.lastProbePublicationUptime = ProcessInfo.processInfo.systemUptime
    }

    private struct Readout: Encodable {
        let schema: Int, launchID: String, fixture: String
        let observedUptime: Double, generation: Int, attached: Bool, keyWindow: Bool
        let lastLiveness: NativeDiagnosticLiveness?
        let samples: Int, began: Int, moved: Int, ended: Int, cancelled: Int
        let droppedSamples: Int, droppedTouches: Int, droppedCameraRecords: Int
        let cameras: [NativeDiagnosticCamera]
        let probePublications: Int, lastProbePublicationUptime: Double?
    }

    func readout() -> String {
        let value = Readout(schema: trace.schema, launchID: trace.launchID, fixture: trace.fixture,
            observedUptime: ProcessInfo.processInfo.systemUptime, generation: trace.generation,
            attached: window != nil, keyWindow: window?.isKeyWindow ?? false,
            lastLiveness: trace.liveness.last, samples: trace.samples.count,
            began: trace.samples.filter { $0.phase == "began" }.count,
            moved: trace.samples.filter { $0.phase == "moved" }.count,
            ended: trace.samples.filter { $0.phase == "ended" }.count,
            cancelled: trace.samples.filter { $0.phase == "cancelled" }.count,
            droppedSamples: trace.droppedSamples, droppedTouches: trace.droppedTouches,
            droppedCameraRecords: trace.droppedCameraRecords, cameras: trace.cameras,
            probePublications: trace.probePublications, lastProbePublicationUptime: trace.lastProbePublicationUptime)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value), data.count <= 16_384,
              let result = String(data: data, encoding: .utf8) else { return "diagnostic-readout-unavailable" }
        return result
    }

    func record(_ stage: NativeInputRecipientDiagnostic.Stage) {
        if trace.stages.count == 128 { trace.stages.removeFirst(); trace.droppedStages += 1 }
        trace.stages.append(.init(stage: stage.rawValue, observedUptime: ProcessInfo.processInfo.systemUptime))
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
            let point = touch.location(in: window)
            let sample = NativeDiagnosticSample(touchOrdinal: ordinal, phase: phase,
                eventUptime: event.timestamp, touchUptime: touch.timestamp,
                observedUptime: ProcessInfo.processInfo.systemUptime,
                x: point.x.isFinite ? Double(point.x) : nil, y: point.y.isFinite ? Double(point.y) : nil,
                recipientAncestry: ancestry, ancestryTruncated: ancestor != nil,
                recognizers: involved.prefix(24).map(recognizerRecord), recognizersTruncated: involved.count > 24,
                maps: mapRecords(recipient: recipient), mapScanTruncated: mapScanTruncated)
            if trace.samples.count == 512 { trace.samples.removeFirst(); trace.droppedSamples += 1 }
            trace.samples.append(sample)
            if phase == "began" || phase == "ended" || phase == "cancelled" {
                // One later main-actor sample, without waiting or blocking event
                // delivery. It can miss transient recognizer states; no absence
                // here proves that a recognizer never began.
                scheduleLaterObservation(ordinal, recognizers: Array(involved.prefix(24)))
            }
            if phase == "ended" || phase == "cancelled" { active.removeValue(forKey: key) }
        }
        // Persist on sequence boundaries, not each move. No disk I/O or JSON
        // encoding runs on this event path; the writer coalesces pending traces.
        if phase != "moved" { flush() }
    }

    private func scheduleLaterObservation(_ ordinal: Int, recognizers: [UIGestureRecognizer]) {
        if pendingLater.count == 48 { pendingLater.removeFirst(); trace.droppedLaterObservations += 1 }
        pendingLater.append((ordinal, recognizers))
        guard !laterObservationScheduled else { return }
        laterObservationScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let pending = self.pendingLater
            self.pendingLater.removeAll(keepingCapacity: true)
            self.laterObservationScheduled = false
            for (ordinal, recognizers) in pending {
                if self.trace.laterRecognizerObservations.count == 48 {
                    self.trace.laterRecognizerObservations.removeFirst()
                    self.trace.droppedLaterObservations += 1
                }
                self.trace.laterRecognizerObservations.append(.init(touchOrdinal: ordinal,
                    observedUptime: ProcessInfo.processInfo.systemUptime,
                    recognizers: recognizers.map(self.recognizerRecord)))
            }
            self.flush()
        }
    }

    private func flush() { trace.generation += 1; writer.submit(trace) }
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

/// Only immutable, Sendable value snapshots cross this boundary. The lock owns
/// pending/writing and the serial utility queue owns encoding and file I/O.
private final class NativeDiagnosticWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "rec636.native-recipient-diagnostic", qos: .utility)
    private var pending: NativeDiagnosticTrace?
    private var writing = false
    private var writeFailures = 0
    private struct Stored: Codable { let trace: NativeDiagnosticTrace; let priorWriteFailures: Int }
    func submit(_ trace: NativeDiagnosticTrace) {
        lock.lock()
        pending = trace
        let shouldStart = !writing
        writing = true
        lock.unlock()
        if shouldStart { queue.async { [self] in drain() } }
    }
    private func drain() {
        while true {
            lock.lock()
            guard let next = pending else { writing = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            do {
                let url = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true).appendingPathComponent("rec636-native-pan-diagnostic.json")
                let data = try JSONEncoder().encode(Stored(trace: next, priorWriteFailures: writeFailures))
                try data.write(to: url, options: .atomic)
            } catch {
                // A missing/stale file or nonzero subsequent counter is an
                // observation gap; never change the test/app outcome to hide it.
                writeFailures += 1
            }
        }
    }
}
#endif
