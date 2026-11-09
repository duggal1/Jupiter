import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Memory Lab — the polite staircase. Never kills, never quits, never
/// `pkill`/`killall`. The only mutating step is `/usr/sbin/purge` (file page
/// cache, admin dialog) after a no-admin `/bin/sync`.
///
/// Why this shape:
/// - `active` / `wired` app heaps are never touched — quitting apps would
///   lose work. Only *reclaimable* pages are returned: `inactive`,
///   `speculative`, `purgeable`, and the file-backed page cache.
/// - `available = free + inactive + speculative + purgeable` is macOS's own
///   definition of what the next allocation can use without swapping.
/// - Honest delta is `availableAfter - availableBefore`, not "pages purged"
///   (purged pages may be reclaimed, then immediately re-filled by the
///   compressor). The ladder reports both and never inflates the number.
/// - Swap is observed, never touched. `swapoff` would stall the machine.
enum MemoryLab {
    // MARK: - Snapshot

    enum Pressure: String, Sendable, CaseIterable {
        case green
        case yellow
        case red

        var title: String {
            switch self {
            case .green: return "Comfortable"
            case .yellow: return "Tight"
            case .red: return "Under pressure"
            }
        }

        var blurb: String {
            switch self {
            case .green: return "Plenty of available memory. No action needed."
            case .yellow: return "Available is low. A purge can help."
            case .red: return "Available is very low and/or swap is heavy. Purge helps; heavy apps still cost RAM."
            }
        }
    }

    struct Snapshot: Sendable {
        let totalBytes: Int64
        let pageSize: Int64
        let freeBytes: Int64
        let activeBytes: Int64
        let inactiveBytes: Int64
        let speculativeBytes: Int64
        let purgeableBytes: Int64
        let wiredBytes: Int64
        let compressorStoredBytes: Int64
        let compressorOccupiedBytes: Int64
        /// Cumulative "Pages purged" * pageSize — delta is the honest purge size.
        let purgedTotalBytes: Int64
        let swapTotalBytes: Int64
        let swapUsedBytes: Int64
        let swapFreeBytes: Int64
        let at: Date

        /// macOS definition: what a new allocation can use without swapping.
        var availableBytes: Int64 {
            freeBytes + inactiveBytes + speculativeBytes + purgeableBytes
        }

        var availableRatio: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(max(0, availableBytes)) / Double(totalBytes)
        }

        var swapRatio: Double {
            guard swapTotalBytes > 0 else { return 0 }
            return Double(max(0, swapUsedBytes)) / Double(swapTotalBytes)
        }

        var pressure: Pressure {
            if availableRatio < 0.10 || swapRatio > 0.80 { return .red }
            if availableRatio < 0.25 || swapRatio > 0.50 { return .yellow }
            return .green
        }
    }

    // MARK: - Observe (read-only, no admin)

    /// One consistent read of vm_stat + sysctl. Runs the two sysctl probes
    /// concurrently — they are independent and each costs one process fork.
    static func observe() async -> Snapshot {
        async let vm = vmStat()
        async let mem = memsize()
        async let swap = swapUsage()
        let v = await vm
        let total = await mem
        let s = await swap
        let page = v.pageSize > 0 ? v.pageSize : 16_384
        func bytes(_ pages: Int64) -> Int64 { pages * page }
        let availableParts = v.free + v.inactive + v.speculative + v.purgeable
        _ = availableParts
        return Snapshot(
            totalBytes: total > 0 ? total : 8_589_934_592,
            pageSize: page,
            freeBytes: bytes(v.free),
            activeBytes: bytes(v.active),
            inactiveBytes: bytes(v.inactive),
            speculativeBytes: bytes(v.speculative),
            purgeableBytes: bytes(v.purgeable),
            wiredBytes: bytes(v.wired),
            compressorStoredBytes: bytes(v.compressorStored),
            compressorOccupiedBytes: bytes(v.compressorOccupied),
            purgedTotalBytes: bytes(v.purged),
            swapTotalBytes: s.total,
            swapUsedBytes: s.used,
            swapFreeBytes: s.free,
            at: Date()
        )
    }

    private struct VMStat {
        var pageSize: Int64 = 16_384
        var free: Int64 = 0
        var active: Int64 = 0
        var inactive: Int64 = 0
        var speculative: Int64 = 0
        var purgeable: Int64 = 0
        var wired: Int64 = 0
        var compressorStored: Int64 = 0
        var compressorOccupied: Int64 = 0
        var purged: Int64 = 0
    }

    private static func vmStat() async -> VMStat {
        await Task.detached(priority: .utility) {
            guard let out = runOutput("/usr/bin/vm_stat", []) else { return VMStat() }
            var v = VMStat()
            for line in out.split(separator: "\n") {
                let s = String(line).lowercased()
                func pages(after label: String) -> Int64? {
                    guard let range = s.range(of: label) else { return nil }
                    let tail = String(s[range.upperBound...])
                    let digits = tail.filter { $0.isNumber }
                    return Int64(digits)
                }
                if s.contains("page size of") {
                    if let r = s.range(of: "of ") {
                        let tail = String(s[r.upperBound...])
                        if let n = Int64(tail.filter({ $0.isNumber })) { v.pageSize = n }
                    }
                } else if s.contains("pages free") { v.free = pages(after: "pages free:") ?? v.free
                } else if s.contains("pages active") && !s.contains("inactive") { v.active = pages(after: "pages active:") ?? v.active
                } else if s.contains("pages inactive") { v.inactive = pages(after: "pages inactive:") ?? v.inactive
                } else if s.contains("pages speculative") { v.speculative = pages(after: "pages speculative:") ?? v.speculative
                } else if s.contains("pages purgeable") { v.purgeable = pages(after: "pages purgeable:") ?? v.purgeable
                } else if s.contains("pages wired") { v.wired = pages(after: "pages wired down:") ?? v.wired
                } else if s.contains("pages stored in compressor") { v.compressorStored = pages(after: "pages stored in compressor:") ?? v.compressorStored
                } else if s.contains("pages occupied by compressor") { v.compressorOccupied = pages(after: "pages occupied by compressor:") ?? v.compressorOccupied
                } else if s.contains("pages purged:") { v.purged = pages(after: "pages purged:") ?? v.purged
                }
            }
            return v
        }.value
    }

    private static func memsize() async -> Int64 {
        await Task.detached(priority: .utility) {
            guard let out = runOutput("/usr/sbin/sysctl", ["hw.memsize"]) else { return 0 }
            // "hw.memsize: 8589934592"
            let digits = out.filter { $0.isNumber }
            return Int64(digits) ?? 0
        }.value
    }

    private struct Swap { var total: Int64 = 0; var used: Int64 = 0; var free: Int64 = 0 }

    private static func swapUsage() async -> Swap {
        await Task.detached(priority: .utility) {
            guard let out = runOutput("/usr/sbin/sysctl", ["vm.swapusage"]) else { return Swap() }
            // "vm.swapusage: total = 4096.00M  used = 3267.06M  free = 828.94M  (encrypted)"
            func megabytes(after key: String) -> Int64 {
                guard let r = out.range(of: key) else { return 0 }
                let tail = String(out[r.upperBound...])
                // take first number, e.g. " 4096.00M"
                var token = ""
                var seenDigit = false
                for ch in tail {
                    if ch.isNumber || ch == "." { token.append(ch); seenDigit = true }
                    else if seenDigit { break }
                }
                guard let v = Double(token) else { return 0 }
                return Int64(v * 1_000_000)
            }
            return Swap(total: megabytes(after: "total ="), used: megabytes(after: "used ="), free: megabytes(after: "free ="))
        }.value
    }

    private static func runOutput(_ exe: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Ladder stages

    enum Stage: String, Sendable, CaseIterable {
        case observe = "Observe"
        case sync = "Sync buffers"
        case purge = "Purge page cache"
        case settle = "Settle & measure"

        var blurb: String {
            switch self {
            case .observe: return "Reads vm_stat + swap. Changes nothing."
            case .sync: return "Flushes dirty buffers to disk. No admin, keeps caches."
            case .purge: return "Returns page-cache pages to the free pool. Needs admin, quits nothing."
            case .settle: return "Waits, then re-reads so compressor noise is not counted as freed."
            }
        }
    }

    struct StageResult: Sendable {
        let stage: Stage
        let note: String
        let ok: Bool
    }

    struct LadderResult: Sendable {
        let before: Snapshot
        let after: Snapshot
        let stages: [StageResult]
        /// Honest gain: availableAfter - availableBefore. Can be small or negative
        /// when the machine is actively allocating — we report it as-is.
        var freedAvailableBytes: Int64 { after.availableBytes - before.availableBytes }
        var purgedBytes: Int64 { max(0, after.purgedTotalBytes - before.purgedTotalBytes) }
        var swapDeltaBytes: Int64 { after.swapUsedBytes - before.swapUsedBytes }
    }

    /// The full polite staircase. `includePurge` gates the only admin step.
    /// `onStage` streams stage completion to the UI (MainActor hops are
    /// done by the caller — this stays off-main).
    static func runLadder(includePurge: Bool, onStage: (@Sendable (StageResult) -> Void)? = nil) async -> LadderResult {
        var stages: [StageResult] = []

        // Stage 0 — observe
        let before = await observe()
        let observeNote = "Available \(fmt(before.availableBytes)) of \(fmt(before.totalBytes)) · \(before.pressure.title)"
        stages.append(StageResult(stage: .observe, note: observeNote, ok: true))
        onStage?(stages[stages.count - 1])

        // Stage 1 — sync (no admin, never destructive)
        let synced = await trimSync()
        stages.append(StageResult(stage: .sync, note: synced ? "Buffers flushed to disk." : "Sync skipped (unavailable).", ok: synced))
        onStage?(stages[stages.count - 1])

        // Stage 2 — purge (admin; skipped when user opted out)
        if includePurge {
            do {
                try await purgeCache()
                stages.append(StageResult(stage: .purge, note: "Page cache purged via admin dialog.", ok: true))
            } catch {
                stages.append(StageResult(stage: .purge, note: "Purge skipped (\(error.localizedDescription)).", ok: false))
            }
            onStage?(stages[stages.count - 1])
        } else {
            stages.append(StageResult(stage: .purge, note: "Purge off — sync-only run.", ok: true))
            onStage?(stages[stages.count - 1])
        }

        // Stage 3 — settle: let the compressor and allocator breathe, then re-observe.
        try? await Task.sleep(nanoseconds: 800_000_000)
        let after = await observe()
        let settleNote = "Available now \(fmt(after.availableBytes)) · swap \(fmt(after.swapUsedBytes)) used"
        stages.append(StageResult(stage: .settle, note: settleNote, ok: true))
        onStage?(stages[stages.count - 1])

        return LadderResult(before: before, after: after, stages: stages)
    }

    /// Stage 1 — flush dirty buffers. `/bin/sync` needs no privilege and
    /// never discards clean cache pages. Returns false if the binary is missing.
    static func trimSync() async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sync")
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    /// Stage 2 — purge the file page cache with the system dialog. This is
    /// the same primitive `Cleaner.flushRAM` uses, housed here so the ladder
    /// owns before/after measurement. Throws if the user cancels.
    static func purgeCache() async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            // osascript prompts once for admin via the system dialog.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"/usr/sbin/purge\" with administrator privileges"]
            let err = Pipe()
            process.standardError = err
            process.standardOutput = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let data = err.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "purge failed"
                throw NSError(domain: "jupiter.MemoryLab", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }
        }.value
    }

    // MARK: - Formatting

    static func fmt(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    static func signedFmt(_ bytes: Int64) -> String {
        if bytes >= 0 { return "+" + fmt(bytes) }
        return "−" + fmt(-bytes)
    }
}
