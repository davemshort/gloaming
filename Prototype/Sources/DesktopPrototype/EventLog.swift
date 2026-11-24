import Foundation

/// Appends timestamped lines to ~/Library/Logs/DesktopPrototype/events.log and stdout,
/// so manual test runs (Spaces, sleep/wake, displays) leave evidence behind.
@MainActor
final class EventLog {
    static let shared = EventLog()

    let url: URL
    private let handle: FileHandle?
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DesktopPrototype", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("events.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        handle?.write(Data(line.utf8))
    }
}
