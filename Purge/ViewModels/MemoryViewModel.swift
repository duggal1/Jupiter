import Foundation
import SwiftUI

/// View model for the Memory page. Observes (read-only) on load, runs the
/// polite ladder on demand, streams stage results as they land.
@Observable
@MainActor
final class MemoryViewModel {
    enum Phase: Equatable {
        case idle
        case running
        case done
    }

    private static let purgeDefaultsKey = "jupiter.memory.includePurge"

    var snapshot: MemoryLab.Snapshot?
    var result: MemoryLab.LadderResult?
    var phase: Phase = .idle
    var stageResults: [MemoryLab.StageResult] = []
    var includePurge: Bool {
        didSet { UserDefaults.standard.set(includePurge, forKey: Self.purgeDefaultsKey) }
    }
    var message: String?

    init() {
        self.includePurge = UserDefaults.standard.object(forKey: Self.purgeDefaultsKey) as? Bool ?? true
        Task { await refresh() }
    }

    /// Current pressure line for the page bar.
    var statusLine: String {
        guard let s = snapshot else { return "—" }
        return "\(MemoryLab.fmt(s.availableBytes)) available · \(s.pressure.title)"
    }

    var isWorking: Bool { phase == .running }

    /// Read-only observe. No admin, safe to call any time.
    func refresh() async {
        snapshot = await MemoryLab.observe()
    }

    /// Runs the staircase. Purge needs admin; cancel the dialog and we
    /// still report the sync-only delta honestly.
    func runClean() {
        guard phase != .running else { return }
        phase = .running
        stageResults = []
        result = nil
        message = nil
        Task {
            let includePurge = self.includePurge
            // The ladder reports stages from a background context; the stage
            // list is rebuilt from the result below, so the callback only
            // needs to note that the run started.
            let ladder = await MemoryLab.runLadder(includePurge: includePurge)
            snapshot = ladder.after
            result = ladder
            stageResults = ladder.stages
            phase = .done
            let freed = ladder.freedAvailableBytes
            if let purge = ladder.stages.first(where: { $0.stage == .purge }), !purge.ok {
                message = "Purge skipped. Available changed \(MemoryLab.signedFmt(freed))."
            } else if freed > 0 {
                message = "Freed \(MemoryLab.fmt(freed)) available · purged \(MemoryLab.fmt(ladder.purgedBytes))."
            } else if freed < -50_000_000 {
                message = "Available dropped \(MemoryLab.fmt(-freed)) while settling. Purged \(MemoryLab.fmt(ladder.purgedBytes))."
            } else {
                message = "Memory already tight-or-better. Purged \(MemoryLab.fmt(ladder.purgedBytes))."
            }
        }
    }
}
