import Foundation

/// Appends every raw radar notification to a capture file in the app's
/// Documents directory (one line: ISO-8601 timestamp, a tab, hex bytes).
///
/// This exists because the RCT716's multi-target frame layout has never
/// been observed in the wild; the first real rides double as protocol
/// capture sessions. Files are visible in the Files app (and via
/// `devicectl device copy`) and become parser test fixtures.
final class RawFrameRecorder {
    private var handle: FileHandle?
    private let formatter = ISO8601DateFormatter()
    // All file I/O happens here, off the BLE/main queue, so recording never
    // competes with the main thread that drives the UI and Live Activity.
    private let queue = DispatchQueue(label: "com.varioradar.capture", qos: .utility)

    init() {
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let name = "capture-\(Int(Date().timeIntervalSince1970)).log"
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func record(_ data: Data, parseFailed: Bool = false) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let marker = parseFailed ? "\tPARSE_FAILED" : ""
        let line = "\(formatter.string(from: Date()))\t\(hex)\(marker)\n"
        queue.async { [weak self] in
            self?.handle?.write(Data(line.utf8))
        }
    }

    deinit {
        let handle = self.handle
        queue.async { try? handle?.close() }
    }
}
