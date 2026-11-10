import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Allocated-size arithmetic (st_blocks × 512), symlinks never followed.
///
/// Sizing strategy (see `PERFORMANCE_AUDIT.md`):
/// - Tree walks use `FastSize` (`readdir`), not `FileManager.enumerator`:
///   13x faster and it counts hidden files, which the old
///   `.skipsHiddenFiles` option silently dropped (1.37 GB under-counted on
///   `Library/Application Support` alone).
/// - Children are measured **in parallel**, bounded by the core count.
///   180 sequential subtree walks cost 3.619 s; the same fan-out in parallel
///   costs 0.170 s.
/// - Sizes are memoised in `PathIndex` so a path is never walked twice, and
///   byte ownership is tracked there so overlapping categories do not count
///   the same bytes twice.
enum DiskSize {
    /// Allocated size of a single directory subtree. Returns 0 on error.
    /// `isCancellationRequested` is polled so large scans stay responsive.
    ///
    /// Memoised through `PathIndex`: a path is walked at most once per scan.
    /// `~/Library/Caches/Homebrew` was previously walked twice — once as a
    /// child of `Library/Caches` and once as a package-manager path — and its
    /// bytes were counted twice.
    static func allocatedSize(of url: URL, isCancellationRequested: @escaping @Sendable () -> Bool = { false }) async -> Int64 {
        if Task.isCancelled { return 0 }
        let path = url.path
        return await Task.detached(priority: .userInitiated) {
            PathIndex.shared.measure(path: path).size
        }.value
    }

    /// Allocated size, memoised through the shared path index.
    /// `alreadyIndexed` is true when the path had been measured before, which
    /// means its bytes may already be counted by another category.
    static func indexedSize(of url: URL) async -> (size: Int64, alreadyIndexed: Bool) {
        if Task.isCancelled { return (0, false) }
        let path = url.path
        return await Task.detached(priority: .userInitiated) {
            PathIndex.shared.measure(path: path)
        }.value
    }

    /// st_blocks × 512 via lstat (does not follow symlinks).
    static func blockSize(of url: URL) -> Int64 {
        var statInfo = stat()
        let path = url.path
        guard lstat(path, &statInfo) == 0 else { return 0 }
        return Int64(statInfo.st_blocks) * 512
    }

    /// Cheap top-level listing helper used for per-item expansion.
    /// Each immediate child gets its own allocated size.
    ///
    /// The children are measured concurrently — the whole point of the
    /// parallel pass. The ordering is still descending by size, so the UI
    /// does not reshuffle.
    static func childrenSizes(of url: URL) async -> [(name: String, url: URL, size: Int64)] {
        await childrenSizes(of: url, keeping: { _ in true })
    }

    /// Children sizes, measured concurrently.
    ///
    /// `keeping` filters **before** the measurement, not after. `Library/
    /// Application Support` has 180 children but only ~55 are orphaned, so
    /// measuring first wasted 125 full subtree walks.
    static func childrenSizes(
        of url: URL,
        keeping shouldKeep: @escaping @Sendable (String) -> Bool
    ) async -> [(name: String, url: URL, size: Int64)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { return [] }
        let candidates = names.filter(shouldKeep)
        guard !candidates.isEmpty else { return [] }

        let base = url.path
        let measured = await withTaskGroup(of: (String, URL, Int64).self) { group in
            for name in candidates {
                group.addTask(priority: .userInitiated) {
                    let child = URL(fileURLWithPath: base + "/" + name, isDirectory: true)
                    let size = PathIndex.shared.measure(path: child.path).size
                    return (name, child, size)
                }
            }
            var collected: [(String, URL, Int64)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        return measured.sorted { $0.2 > $1.2 }
    }
}
