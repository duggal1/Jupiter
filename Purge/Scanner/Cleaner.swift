import Foundation

/// Deletes by moving to Trash where possible; snapshots via tmutil.
/// Runs off the MainActor — Trash I/O never blocks the UI.
enum Cleaner {
    struct Outcome {
        var freed: Int64 = 0
        var failed: Int = 0
        var failureMessages: [String] = []
    }

    /// Progress tick after each item: (freed total, item). Called on the
    /// MainActor so the UI streams without touching off-main state.
    typealias Progress = @MainActor @Sendable (Int64, JunkItem) -> Void

    /// Lightweight RAM flush — purges the file page cache with `purge`.
    /// Needs admin (macOS auth dialog); leaves running apps alone.
    /// Best-effort: throws if the user cancels the prompt.
    static func flushRAM() async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            // osascript prompts once for admin via the system dialog.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"purge\" with administrator privileges"]
            let err = Pipe()
            process.standardError = err
            process.standardOutput = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let data = err.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "purge failed"
                throw NSError(domain: "jupiter.Cleaner", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }
        }.value
    }

    static func clean(items: [JunkItem]) async -> Outcome {
        await clean(items: items, onProgress: nil)
    }

    /// Moves each selected item to Trash (or thins a snapshot), streaming
    /// progress off-main. Returns estimated allocated bytes freed for Trash
    /// items; actual APFS thinning for snapshots is left to the caller to
    /// re-measure disk.
    static func clean(items: [JunkItem], onProgress: Progress?) async -> Outcome {
        var outcome = Outcome()
        for item in items {
            if Task.isCancelled { break }
            await Task.yield()
            if item.snapshotID != nil {
                // Snapshots: actual freed bytes are measured by the caller
                // via disk-space delta rather than per-item size (tmutil
                // does not report bytes per snapshot).
                do {
                    try await deleteSnapshot(id: item.snapshotID!)
                    item.isDeleted = true
                } catch {
                    outcome.failed += 1
                    item.error = error.localizedDescription
                    outcome.failureMessages.append("\(item.name): \(error.localizedDescription)")
                }
                await onProgress?(outcome.freed, item)
                continue
            }
            guard let url = item.url else {
                await onProgress?(outcome.freed, item)
                continue
            }
            // Refuse anything outside home (except snapshots handled above).
            guard url.path.hasPrefix(Scanner.home.path) || url == Scanner.home else {
                outcome.failed += 1
                let message = "\(item.name): outside home directory, skipped"
                item.error = message
                outcome.failureMessages.append(message)
                await onProgress?(outcome.freed, item)
                continue
            }
            do {
                // Already gone (moved/emptied between scan and clean) counts as freed.
                if !FileManager.default.fileExists(atPath: url.path) {
                    outcome.freed += item.size
                    item.isDeleted = true
                    await onProgress?(outcome.freed, item)
                    continue
                }
                // Files already in ~/.Trash can't be re-trashed — remove permanently.
                if url.path.contains("/.Trash/") {
                    try FileManager.default.removeItem(at: url)
                } else {
                    _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
                outcome.freed += item.size
                item.isDeleted = true
            } catch {
                // Vanished mid-clean (other cleaner, Trash auto-empty) is freed, not failed.
                if !FileManager.default.fileExists(atPath: url.path) {
                    outcome.freed += item.size
                    item.isDeleted = true
                    await onProgress?(outcome.freed, item)
                    continue
                }
                outcome.failed += 1
                item.error = error.localizedDescription
                outcome.failureMessages.append("\(item.name): \(error.localizedDescription)")
            }
            await onProgress?(outcome.freed, item)
        }
        return outcome
    }

    private static func deleteSnapshot(id: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
            process.arguments = ["deletelocalsnapshots", id]
            let pipe = Pipe()
            process.standardOutput = pipe
            let errPipe = Pipe()
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "tmutil failed"
                    throw NSError(domain: "jupiter.Cleaner", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
                }
            } catch let error as NSError where error.domain == "jupiter.Cleaner" {
                throw error
            } catch {
                throw error
            }
        }.value
    }

    /// Available bytes on the boot volume — used to measure actual freed space
    /// for snapshots, where per-item sizes are unavailable.
    static func availableBytes(on url: URL = URL(fileURLWithPath: "/")) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
