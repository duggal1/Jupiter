import Foundation
import SwiftUI

/// One view model for the screen. All scanning/deleting runs off the main
/// actor so the UI never blocks.
@Observable
@MainActor
final class ScanViewModel {
    enum Phase {
        case notScanned
        case scanning
        case results
        case cleaning
        case cleaned
    }

    var phase: Phase = .notScanned
    var categories: [JunkCategory] = []
    var hasFDA: Bool = true
    var scanTask: Task<Void, Never>?
    var cleanTask: Task<Void, Never>?

    /// After a clean: estimated freed for Trash items; actual measured for snapshots.
    var lastFreed: Int64?
    var lastFailed: Int = 0
    var lastFailureNote: String?

    var selectedCategoryKind: CategoryKind?
    var showCleanConfirmation: Bool = false
    /// Downloads stays hidden until the user explicitly opts in,
    /// so the launch scan never surprises with a TCC prompt.
    var includeDownloads: Bool = false

    // Live cleaning stream (MB of GB) — pixel bar + rows drain as it moves.
    var cleanFreed: Int64 = 0
    var cleanTotal: Int64 = 0
    var cleanCurrent: String?
    var cleanDoneCount: Int = 0
    var cleanTotalCount: Int = 0
    var ramFlushed: Bool = false
    var ramNote: String?

    var cleanProgress: Double {
        cleanTotal > 0 ? min(1, Double(cleanFreed) / Double(cleanTotal)) : 0
    }

    var totalJunk: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    var totalSelected: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedItemCount: Int {
        categories.reduce(0) { count, cat in count + cat.items.filter(\.isSelected).count }
    }
    var selectedCategory: JunkCategory? {
        categories.first { $0.kind == selectedCategoryKind }
    }

    var sortedCategories: [JunkCategory] {
        categories.sorted { $0.totalSize > $1.totalSize }
    }

    var failedItems: [JunkItem] {
        categories.flatMap(\.items).filter { $0.error != nil }
    }

    /// Largest remaining item size — tick strips scale against this.
    var maxItemSize: Int64 {
        let sizes = categories.flatMap(\.items).map(\.size)
        return max(sizes.max() ?? 0, 1)
    }

    func scan() {
        scanTask?.cancel()
        phase = .scanning
        lastFreed = nil
        lastFailed = 0
        lastFailureNote = nil
        hasFDA = Scanner.hasFullDiskAccess()
        for category in categories {
            category.items = []
            category.didScan = false
        }
        if categories.isEmpty {
            categories = CategoryKind.allCases.map { JunkCategory(kind: $0) }
        }
        let hasFDA = self.hasFDA
        let includeDownloads = self.includeDownloads
        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.runScan(hasFDA: hasFDA, includeDownloads: includeDownloads)
            if !Task.isCancelled {
                self.phase = .results
                // Select the largest category and open it.
                if let first = self.sortedCategories.first {
                    self.selectedCategoryKind = first.kind
                    first.isExpanded = true
                }
            }
        }
    }

    private func runScan(hasFDA: Bool, includeDownloads: Bool) async {
        // The scanner returns immutable `ScannedItem`s; the observable
        // `JunkItem`s are created here, on the main actor. Nothing mutable
        // crosses an actor boundary.
        let scanned = await Scanner.scanAll(hasFDA: hasFDA, includeDownloads: includeDownloads)
        guard !Task.isCancelled else { return }
        for entry in scanned {
            if let category = categories.first(where: { $0.kind == entry.kind }) {
                category.items = entry.items.map { JunkItem(scanned: $0) }
                category.didScan = true
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        if phase == .scanning {
            phase = categories.contains(where: \.didScan) ? .results : .notScanned
        }
    }

    /// Smart batch: select only Safe (regenerates, loses nothing). Never touches Okay/Risky.
    /// Auto-select never grabs Docker-prune or info-only rows — those need a
    /// running daemon / manual review.
    func selectSafe() {
        for category in categories {
            for item in category.items where item.safety == .safe && !item.isDeleted && item.cleanAction == .trash {
                item.isSelected = true
            }
        }
    }

    /// Smart batch (opt-in): Safe + Okay. Still never touches Risky — Risky needs per-item opt-in.
    /// Still never touches Docker-managed rows; use the per-row toggle for those.
    func selectSafeAndOkay() {
        for category in categories {
            for item in category.items where item.safety != .risky && !item.isDeleted && item.cleanAction == .trash {
                item.isSelected = true
            }
        }
    }

    func selectedSize(for safety: Safety) -> Int64 {
        categories.flatMap(\.items).filter { $0.isSelected && $0.safety == safety }.reduce(0) { $0 + $1.size }
    }

    func selectedCount(for safety: Safety) -> Int {
        categories.flatMap(\.items).filter { $0.isSelected && $0.safety == safety }.count
    }

    func clearSelection() {
        for category in categories {
            for item in category.items {
                item.isSelected = false
            }
        }
    }

    var confirmationTitle: String {
        let count = selectedItemCount
        return "Clean \(count) item\(count == 1 ? "" : "s")?"
    }

    var confirmationMessage: String {
        let formatted = ByteCountFormatter.string(fromByteCount: totalSelected, countStyle: .file)
        let safe = categories.reduce(0) { $0 + $1.safeSelectedSize }
        let safeFormatted = ByteCountFormatter.string(fromByteCount: safe, countStyle: .file)
        let hasDockerPrune = categories.flatMap(\.items).contains { item in
            if case .dockerPrune = item.cleanAction { return item.isSelected }
            return false
        }
        if safe == totalSelected && !hasDockerPrune {
            return "This moves \(formatted) to Trash. Items stay recoverable from Trash."
        }
        if hasDockerPrune {
            return "This cleans \(formatted), including docker prune via the CLI. File items stay recoverable from Trash."
        }
        return "This moves \(formatted), of which \(safeFormatted) is marked Safe. Okay items cost time to rebuild and Risky items delete data. They stay recoverable from Trash."
    }

    /// Auto-clean: Safe + Okay only, never Risky. Skips the dialog.
    /// Disk first, then a lightweight RAM page-cache flush (apps stay running).
    func autoClean() {
        guard phase == .results || phase == .cleaned else { return }
        clearSelection()
        selectSafeAndOkay()
        guard totalSelected > 0 else { return }
        confirmClean(auto: true)
    }

    func confirmClean(auto: Bool = false) {
        let selected = categories.flatMap(\.items).filter(\.isSelected)
        guard !selected.isEmpty else { return }
        showCleanConfirmation = false
        phase = .cleaning
        cleanFreed = 0
        cleanTotal = selected.reduce(0) { $0 + $1.size }
        cleanCurrent = nil
        cleanDoneCount = 0
        cleanTotalCount = selected.count
        ramFlushed = false
        ramNote = nil
        let before = Cleaner.availableBytes(on: URL(fileURLWithPath: "/"))
        // The cleaner works on plain values, so it can leave the main actor.
        let targets = selected.map(\.cleanTarget)
        let involvedSnapshots = selected.contains { $0.snapshotID != nil }
        // Detached so Trash I/O never blocks the UI runloop. The Cleaner
        // returns outcomes; every model mutation happens back on the
        // MainActor in `apply(results:)` — no cross-thread @Observable writes.
        cleanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let (outcome, results) = await Cleaner.clean(items: targets) { [weak self] freed, item in
                guard let self else { return }
                // Already on MainActor (Progress is @MainActor).
                self.cleanFreed = freed
                self.cleanCurrent = item.name
                self.cleanDoneCount += 1
            }
            let after = Cleaner.availableBytes(on: URL(fileURLWithPath: "/"))
            let measured = max(0, after - before)
            let freed = involvedSnapshots ? max(outcome.freed, measured) : outcome.freed
            await MainActor.run {
                if Task.isCancelled { return }
                // Apply every item result on the main actor, in one pass, so
                // the list and the totals update in the same frame the clean
                // reports. Previously the deleted rows were removed from a
                // background thread's write and the UI lagged behind.
                self.apply(results: results)
                self.lastFreed = freed
                self.lastFailed = outcome.failed
                self.lastFailureNote = outcome.failureMessages.first
            }
            if auto, !Task.isCancelled {
                do {
                    try await Cleaner.flushRAM()
                    await MainActor.run {
                        self.ramFlushed = true
                        self.ramNote = "RAM cache flushed."
                    }
                } catch {
                    await MainActor.run {
                        self.ramNote = "RAM flush skipped (\(error.localizedDescription))."
                    }
                }
            }
            await MainActor.run {
                if !Task.isCancelled {
                    self.phase = .cleaned
                }
            }
        }
    }

    /// Applies per-item clean results to the model. MainActor only.
    /// Deleted items leave the list; failed items stay, carrying the error,
    /// so the user can retry exactly what broke.
    private func apply(results: [UUID: Cleaner.ItemOutcome]) {
        guard !results.isEmpty else { return }
        for category in categories {
            var survivors: [JunkItem] = []
            for item in category.items {
                guard let result = results[item.id] else {
                    survivors.append(item)
                    continue
                }
                switch result {
                case .deleted:
                    // Removed from the list — it is gone.
                    continue
                case .failed(let message), .skipped(let message):
                    item.isDeleted = false
                    item.error = message
                    item.isSelected = false
                    survivors.append(item)
                }
            }
            category.items = survivors
        }
    }

    func cancelClean() {
        cleanTask?.cancel()
        if phase == .cleaning { phase = .results }
    }

    func recheckFDA() {
        hasFDA = Scanner.hasFullDiskAccess()
    }

    static let fdaDeepLink = Scanner.fdaURL
}
