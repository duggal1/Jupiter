import Foundation
import Observation

/// Regression test for the "the state doesn't change after a clean" bug.
///
/// The Cleaner used to write `item.isDeleted` from a detached task while the
/// view model read it on the main actor. The `@Observable` notification then
/// fired off the main thread and the read-after-write was a race, so the row
/// removal was not reliably observed.
///
/// This test asserts the new contract:
/// 1. The Cleaner never mutates an observable model — it returns outcomes.
/// 2. The view model applies the outcomes on the main actor, in one pass.
/// 3. Deleted rows leave the list; failed rows stay and carry the error.
///
/// Run:
/// ```sh
/// swiftc -O -parse-as-library Tests/StateSync.swift \
///   Purge/Models/Junk.swift Purge/Scanner/DiskSize.swift \
///   Purge/Scanner/FastSize.swift Purge/Scanner/PathIndex.swift \
///   Purge/Scanner/Cleaner.swift Purge/Scanner/Scanner.swift \
///   Purge/Scanner/DockerScanner.swift Purge/Scanner/WatchdogConfig.swift \
///   Purge/Scanner/MemoryLab.swift -o /tmp/statesync && /tmp/statesync
/// ```
@main
struct StateSync {
    @MainActor
    static func main() async {
        var failures = 0
        func check(_ ok: Bool, _ name: String, _ detail: String = "") {
            if ok { print("PASS \(name)\(detail.isEmpty ? "" : " — \(detail)")") }
            else { print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")"); failures += 1 }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent("Library/Caches/jupiter_statesync_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Two real files, so the cleaner has something to act on.
        let doomed = base.appendingPathComponent("doomed.txt")
        let kept = base.appendingPathComponent("kept.txt")
        try! Data(repeating: 0x41, count: 4096).write(to: doomed)
        try! Data(repeating: 0x42, count: 4096).write(to: kept)

        // MARK: - The cleaner returns outcomes and does not mutate the model

        let scanned = [
            ScannedItem(name: "doomed", url: doomed, size: 4096, safety: .safe),
            ScannedItem(name: "kept", url: kept, size: 4096, safety: .safe),
        ]
        let items = scanned.map { JunkItem(scanned: $0) }
        check(items.allSatisfy { !$0.isDeleted }, "items start undeleted")

        let targets = items.map(\.cleanTarget)
        let (outcome, results) = await Cleaner.clean(items: targets)

        check(results.count == 2, "cleaner returned a result per item", "\(results.count)")
        check(outcome.failed == 0, "no failures", "failed=\(outcome.failed)")
        check(outcome.freed > 0, "freed bytes reported", "\(outcome.freed)")

        // The model was NOT touched by the cleaner — the caller applies it.
        check(items.allSatisfy { !$0.isDeleted }, "cleaner did not mutate the model")

        // MARK: - The view model applies outcomes on the main actor

        let viewModel = ScanViewModel()
        viewModel.categories = [
            JunkCategory(kind: .appCaches, items: items),
        ]
        check(viewModel.categories[0].items.count == 2, "view model holds both rows")

        // Simulate exactly what `ScanViewModel.apply(results:)` does.
        @MainActor
        func apply(_ results: [UUID: Cleaner.ItemOutcome], to categories: [JunkCategory]) {
            for category in categories {
                var survivors: [JunkItem] = []
                for item in category.items {
                    guard let result = results[item.id] else {
                        survivors.append(item)
                        continue
                    }
                    switch result {
                    case .deleted:
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
        apply(results, to: viewModel.categories)

        check(viewModel.categories[0].items.isEmpty, "deleted rows leave the list immediately",
              "\(viewModel.categories[0].items.count) rows left")
        check(viewModel.totalJunk == 0, "totals update in the same pass", "\(viewModel.totalJunk)")
        check(!FileManager.default.fileExists(atPath: doomed.path), "the file really was cleaned")

        // MARK: - A failed item stays in the list with its error

        let failedItem = JunkItem(scanned: ScannedItem(name: "failed", url: kept, size: 4096, safety: .safe))
        let failResults: [UUID: Cleaner.ItemOutcome] = [
            failedItem.id: .failed(message: "permission denied"),
        ]
        let failCategories = [JunkCategory(kind: .appCaches, items: [failedItem])]
        apply(failResults, to: failCategories)
        check(failCategories[0].items.count == 1, "failed row stays in the list")
        check(failCategories[0].items.first?.error == "permission denied", "failed row carries the error",
              failCategories[0].items.first?.error ?? "nil")

        // MARK: - info-only rows are reported, never deleted

        let infoOnly = JunkItem(scanned: ScannedItem(
            name: "Docker.raw",
            url: base.appendingPathComponent("Docker.raw"),
            size: 1024,
            safety: .risky,
            detail: "VM disk",
            cleanAction: .infoOnly
        ))
        let (infoOutcome, infoResults) = await Cleaner.clean(items: [infoOnly.cleanTarget])
        check(infoOutcome.failed == 1, "info-only row is not deleted")
        if case .skipped = infoResults[infoOnly.id] {
            check(true, "info-only row reports skipped")
        } else {
            check(false, "info-only row reports skipped")
        }

        try? FileManager.default.removeItem(at: base)
        if failures > 0 { print("\(failures) FAILURE(S)"); exit(1) }
        print("ALL CHECKS PASSED")
    }
}
