import Foundation

/// Append-only watchdog log at ~/Library/Logs/Jupiter/Watchdog.log.
/// launchd also points StandardOutPath here — this helper is for
/// structured lines the app writes itself (start / freed / failed).
enum WatchdogLog {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Jupiter/Watchdog.log")
    }

    static func append(_ line: String) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url)
        }
    }

    /// Last N lines for the pane preview. Empty when no log exists yet.
    /// Reads only the tail chunk so a long-lived log can't stall the pane.
    static func tail(_ count: Int = 20) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? UInt64) ?? 0
        let window: UInt64 = 32 * 1024 // 32KB is plenty for 20 lines
        if size > window {
            try? handle.seek(toOffset: size - window)
        }
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return "" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(count).joined(separator: "\n")
    }
}
