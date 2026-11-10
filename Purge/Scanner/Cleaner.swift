import Foundation

/// Deletes by moving to Trash where possible; snapshots via tmutil.
/// Runs off the MainActor — Trash I/O never blocks the UI.
///
/// ## State ownership
///
/// The Cleaner **never** touches an observable model. It used to set
/// `isDeleted` and `error` on `JunkItem` from a detached task while
/// `ScanViewModel` read them on the main actor. `@Observable` notifications
/// then fired off the main thread and the read-after-write was a race, so
/// the row removal was not reliably observed and the list visibly failed to
/// update right after a clean.
///
/// The Cleaner now works on plain `CleanTarget` values and returns
/// **outcomes**; the view model applies them on the MainActor in one place
/// (`ScanViewModel.apply`).
enum Cleaner {
    struct Outcome {
        var freed: Int64 = 0
        var failed: Int = 0
        var failureMessages: [String] = []
    }

    /// What happened to one item. Returned to the caller so it can update
    /// the model on the main actor.
    enum ItemOutcome: Sendable {
        case deleted(freed: Int64)
        case failed(message: String)
        case skipped(message: String)
    }

    /// Progress tick after each item: (freed total, item name). Called on
    /// the MainActor so the UI streams without touching off-main state.
    typealias Progress = @MainActor @Sendable (Int64, CleanTarget) -> Void

    /// Lightweight RAM flush — purges the file page cache with `purge`.
    /// Needs admin (macOS auth dialog); leaves running apps alone.
    /// Best-effort: throws if the user cancels the prompt.
    /// Implementation lives in MemoryLab so the ladder and auto-clean
    /// share one purge path and one honest before/after measurement.
    ///
    /// `allowPrompt` is `false` for background runs — a launchd job cannot
    /// answer a password dialog.
    static func flushRAM(allowPrompt: Bool = true) async throws {
        try await MemoryLab.purgeCache(allowPrompt: allowPrompt)
    }

    /// Moves each selected item to Trash (or thins a snapshot), streaming
    /// progress off-main. Returns estimated allocated bytes freed for Trash
    /// items; actual APFS thinning for snapshots is left to the caller to
    /// re-measure disk.
    ///
    /// Returns the per-item outcomes so the caller can apply them on the
    /// MainActor.
    @discardableResult
    static func clean(
        items: [CleanTarget],
        onProgress: Progress? = nil
    ) async -> (outcome: Outcome, results: [UUID: ItemOutcome]) {
        resetPruneBatch()
        var outcome = Outcome()
        var results: [UUID: ItemOutcome] = [:]
        // Docker prunes coalesce: one CLI call per kind, not one per row.
        var dockerKinds: [DockerPruneKind: [CleanTarget]] = [:]
        for item in items {
            if case .dockerPrune(let kind) = item.cleanAction {
                dockerKinds[kind, default: []].append(item)
            }
        }
        // Materialise docker prune items so the single-prune path below can run.
        let dockerItems = dockerKinds.flatMap(\.value)
        let fileItems = items.filter {
            if case .dockerPrune = $0.cleanAction { return false }
            return true
        }

        for item in dockerItems {
            if case .dockerPrune(let kind) = item.cleanAction {
                do {
                    try await pruneOnce(kind)
                    outcome.freed += item.size
                    results[item.id] = .deleted(freed: item.size)
                } catch {
                    outcome.failed += 1
                    let message = "\(item.name): \(DockerScanner.pruneLabel(kind)) — \(error.localizedDescription)"
                    results[item.id] = .failed(message: message)
                    outcome.failureMessages.append(message)
                }
                await onProgress?(outcome.freed, item)
            }
        }

        for item in fileItems {
            if Task.isCancelled { break }
            await Task.yield()
            if item.cleanAction == .infoOnly {
                outcome.failed += 1
                let message = "\(item.name): info-only storage — not trashed."
                results[item.id] = .skipped(message: message)
                outcome.failureMessages.append(message)
                await onProgress?(outcome.freed, item)
                continue
            }
            if item.snapshotID != nil {
                // Snapshots: actual freed bytes are measured by the caller
                // via disk-space delta rather than per-item size (tmutil
                // does not report bytes per snapshot).
                do {
                    try await deleteSnapshot(id: item.snapshotID!)
                    outcome.freed += item.size
                    results[item.id] = .deleted(freed: item.size)
                } catch {
                    outcome.failed += 1
                    let message = "\(item.name): \(error.localizedDescription)"
                    results[item.id] = .failed(message: message)
                    outcome.failureMessages.append(message)
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
                results[item.id] = .skipped(message: message)
                outcome.failureMessages.append(message)
                await onProgress?(outcome.freed, item)
                continue
            }
            do {
                // Already gone (moved/emptied between scan and clean) counts as freed.
                if !FileManager.default.fileExists(atPath: url.path) {
                    outcome.freed += item.size
                    results[item.id] = .deleted(freed: item.size)
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
                results[item.id] = .deleted(freed: item.size)
            } catch {
                // Vanished mid-clean (other cleaner, Trash auto-empty) is freed, not failed.
                if !FileManager.default.fileExists(atPath: url.path) {
                    outcome.freed += item.size
                    results[item.id] = .deleted(freed: item.size)
                    await onProgress?(outcome.freed, item)
                    continue
                }
                outcome.failed += 1
                let message = "\(item.name): \(error.localizedDescription)"
                results[item.id] = .failed(message: message)
                outcome.failureMessages.append(message)
            }
            await onProgress?(outcome.freed, item)
        }
        return (outcome, results)
    }

    /// Runs one `docker ... prune -f` per kind per clean batch. Callers
    /// coalesce rows; this helper guards against double-prune races.
    ///
    /// The set is guarded by a lock, but the lock is only ever taken inside
    /// the synchronous helpers below — never held across an `await`, and never
    /// taken from an async context directly (which Swift 6 forbids).
    private static var prunedThisBatch: Set<DockerPruneKind> = []
    private static let pruneLock = NSLock()

    /// Marks a kind as pruned for this batch. Returns true if this call was
    /// the one that performed the prune.
    private static func markPruned(_ kind: DockerPruneKind) -> Bool {
        pruneLock.lock()
        defer { pruneLock.unlock() }
        let already = prunedThisBatch.contains(kind)
        prunedThisBatch.insert(kind)
        return !already
    }

    private static func pruneOnce(_ kind: DockerPruneKind) async throws {
        guard markPruned(kind) else { return }
        try await DockerScanner.prune(kind: kind)
    }

    /// Call at the start of a top-level clean batch to reset the coalescing set.
    static func resetPruneBatch() {
        pruneLock.lock()
        prunedThisBatch = []
        pruneLock.unlock()
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
