import Foundation

/// Headless watchdog execution. Runs with no windows — invoked by launchd
/// as `Jupiter --watchdog-run`.
///
/// Safety contract (non-negotiable):
/// - Only Safe (+ optional Okay if user opted in). Risky is never cleaned.
/// - Everything goes to Trash (recoverable), never `removeItem` except
///   inside ~/.Trash where re-trashing is impossible.
/// - Skips snapshots, Docker-managed categories, and VM disks. Docker
///   builder prune is opt-in (daemon may be down during a background run).
/// - Lock file prevents overlapping runs; last run always recorded.
enum WatchdogRunner {
    /// Entry for launchd. Blocks the main thread until the run finishes,
    /// then exits the process. Called from `JupiterApp.init` before any scene.
    static func runAndExit() {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .background) {
            _ = await run()
            semaphore.signal()
        }
        semaphore.wait()
        Foundation.exit(0)
    }

    /// Runs one maintenance pass. Returns bytes freed. Safe to call from the
    /// UI's "Run now" too — it never touches Risky.
    static func run() async -> Int64 {
        var cfg = WatchdogConfig.load()
        let lock = LockFile()
        guard lock.acquire() else {
            WatchdogLog.append("run skipped — another watchdog is active")
            return 0
        }
        defer { lock.release() }

        let start = Date()
        WatchdogLog.append("watchdog start interval=\(cfg.intervalDays)d allowed=\(cfg.allowedSafeties.map(\.title).joined(separator: "+"))")
        defer {
            cfg.lastRun = start
            cfg.save()
        }

        let hasFDA = Scanner.hasFullDiskAccess()
        // Fast path: only Safe-yielding categories. Downloads stays off so a
        // background run never triggers a TCC prompt; Docker VM traversal,
        // snapshots and iOS backups are skipped entirely.
        let cats = await Scanner.scanWatchdog(config: cfg, hasFDA: hasFDA)

        var toClean: [CleanTarget] = []
        for cat in cats {
            for item in cat.items {
                guard cfg.allowedSafeties.contains(item.safety) else { continue }
                if item.snapshotID != nil { continue }
                if item.cleanAction == .infoOnly { continue }
                if cat.kind == .trash && !cfg.includeTrash { continue }
                toClean.append(CleanTarget(scanned: item))
            }
        }

        let estimated = toClean.reduce(0) { $0 + $1.size }
        WatchdogLog.append("found \(toClean.count) items · est \(ByteCountFormatter.string(fromByteCount: estimated, countStyle: .file))")
        guard !toClean.isEmpty else {
            cfg.lastFreed = 0
            cfg.lastFailed = 0
            cfg.lastNote = "Nothing to clean."
            WatchdogLog.append("nothing to clean")
            return 0
        }

        let (outcome, _) = await Cleaner.clean(items: toClean)
        cfg.lastFreed = outcome.freed
        cfg.lastFailed = outcome.failed
        cfg.lastNote = outcome.failureMessages.first ?? (outcome.freed > 0 ? "Freed \(outcome.freed) bytes." : nil)
        WatchdogLog.append("done freed=\(outcome.freed) failed=\(outcome.failed)" + (outcome.failureMessages.isEmpty ? "" : " failures: \(outcome.failureMessages.joined(separator: "; "))"))
        return outcome.freed
    }
}

/// Exclusive lock so two launchd triggers (interval + "Run now") can't
/// double-clean. Uses a file in the user cache — no sandbox needed.
private struct LockFile {
    private var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("jupiter-watchdog.lock")
    }

    func acquire() -> Bool {
        if FileManager.default.fileExists(atPath: url.path) {
            // Stale lock from a crashed run: older than 1h means safe to steal.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let date = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(date) < 3600 {
                return false
            }
            try? FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: "1".data(using: .utf8))
        return true
    }

    func release() {
        try? FileManager.default.removeItem(at: url)
    }
}
