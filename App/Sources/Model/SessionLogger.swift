import Foundation

/// Writes a timestamped ride log to the app's Documents directory so a real
/// ride can be analysed afterwards (fetch via `devicectl device copy` or the
/// Files app). Records connection events, the measured BLE rate, foreground
/// / background transitions, island updates, and alerts, so we can see how
/// the Live Activity actually behaved in the pocket.
///
/// Thread-safe: all file work happens on a private serial queue, and the
/// timestamp is formatted there too, so it can be called from any thread
/// (the BLE main queue, the @MainActor store) without contention.
final class SessionLogger {
    static let shared = SessionLogger()

    private let io = DispatchQueue(label: "com.varioradar.sessionlog", qos: .utility)
    private var handle: FileHandle?
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func start() {
        io.async {
            let name = "ride-\(Int(Date().timeIntervalSince1970)).log"
            let url = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            self.handle = try? FileHandle(forWritingTo: url)
        }
        log("=== session start ===")
    }

    func log(_ message: String) {
        let now = Date()
        io.async {
            guard let handle = self.handle else { return }
            let line = "\(self.formatter.string(from: now))\t\(message)\n"
            handle.write(Data(line.utf8))
        }
    }

    func stop() {
        log("=== session stop ===")
        io.async {
            try? self.handle?.close()
            self.handle = nil
        }
    }
}
