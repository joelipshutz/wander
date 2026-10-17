// Injected only into a disposable, hash-checked CI SDK checkout. Not an app source.
#if os(iOS)
import Foundation
import UIKit

enum REC636ReplayStageProbe {
    private static let lock = NSLock()
    private static var attempted = 0
    private static var written = 0
    private static var failed = 0
    private static var capped = 0
    private static var frames: Set<UInt64> = []
    private static let directory: URL? = {
        let args = ProcessInfo.processInfo.arguments
        let flag = "-REC636ReplayStageProbe"
        let indices = args.indices.filter { args[$0] == flag }
        guard indices.count == 1, let index = indices.first,
              args.indices.contains(index + 1),
              !args.contains(where: { $0.hasPrefix(flag + "=") }),
              let uuid = UUID(uuidString: args[index + 1]),
              uuid.uuidString == args[index + 1] else { return nil }
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let value = temporary.appendingPathComponent("REC636-ReplayStage-" + uuid.uuidString, isDirectory: true)
        guard value.deletingLastPathComponent().path == temporary.path,
              !FileManager.default.fileExists(atPath: value.path) else { return nil }
        do { try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false) }
        catch { return nil }
        guard value.resolvingSymlinksInPath().path == value.path else { return nil }
        return value
    }()

    // 1=image returned, 2=serial block entered, 3=toDict returned, 4=beforeSend reached.
    static func record(_ stage: Int, frame: Date, image: UIImage? = nil) {
        guard let directory else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        let frameKey = frame.timeIntervalSince1970.bitPattern
        // Touch/meta $snapshot events have no matching image-stage timestamp.
        if stage == 1 {
            guard frames.count < 32 else { capped += 1; return }
            frames.insert(frameKey)
        }
        else if !frames.contains(frameKey) { return }
        attempted += 1
        guard attempted <= 128 else { capped += 1; return }
        let value: [String: Any] = ["stage": stage, "sequence": attempted,
            "frame": frameKey,
            "uptime": now, "epoch": Date().timeIntervalSince1970,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "image": image != nil, "width": image?.cgImage?.width ?? 0,
            "height": image?.cgImage?.height ?? 0]
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            guard data.count <= 512 else { failed += 1; return }
            try data.write(to: directory.appendingPathComponent(String(format: "%03d.json", attempted)), options: .atomic)
            written += 1
        } catch { failed += 1 }
    }

    // Recorder integrity only; this is not a fifth pipeline stage or a native assertion.
    static func finish() {
        guard let directory else { return }
        lock.lock(); defer { lock.unlock() }
        let value: [String: Any] = ["attempted": attempted, "written": written,
            "failed": failed, "capped": capped, "closed": true,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "uptime": ProcessInfo.processInfo.systemUptime]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("footer.json"), options: .atomic)
        }
    }
}
#endif
