import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Allocated-size arithmetic (st_blocks × 512), symlinks never followed.
enum DiskSize {
    /// Allocated size of a single directory subtree. Returns 0 on error.
    /// `isCancellationRequested` is polled so large scans stay responsive.
    static func allocatedSize(of url: URL, isCancellationRequested: @escaping @Sendable () -> Bool = { false }) async -> Int64 {
        await Task.detached(priority: .userInitiated) {
            size(of: url, isCancellationRequested: isCancellationRequested)
        }.value
    }

    private static func size(of url: URL, isCancellationRequested: @Sendable () -> Bool) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return blockSize(of: url)
        }
        for case let fileURL as URL in enumerator {
            if isCancellationRequested() { break }
            total += blockSize(of: fileURL)
        }
        return total
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
    static func childrenSizes(of url: URL) async -> [(name: String, url: URL, size: Int64)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { return [] }
        var results: [(name: String, url: URL, size: Int64)] = []
        for name in names {
            let child = url.appendingPathComponent(name, isDirectory: true)
            let size = await allocatedSize(of: child)
            results.append((name, child, size))
        }
        return results.sorted(by: { $0.size > $1.size })
    }
}
