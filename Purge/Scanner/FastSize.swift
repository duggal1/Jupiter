import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Fast allocated-size measurement.
///
/// Why not `FileManager.enumerator`: measured 13x slower than a `readdir`
/// walk on the same tree (0.307s vs 0.023s on `~/Library/Caches`), because
/// it allocates a `URL` per entry and re-resolves every path.
///
/// Why `readdir` and not `FileManager.contentsOfDirectory`: the same
/// allocation-per-entry cost, plus it cannot be combined with `lstat` without
/// a second path round-trip.
///
/// Symlinks are never followed (`lstat`), matching `DiskSize`'s contract:
/// a symlink contributes its own blocks, not its target's.
///
/// Hidden files ARE included. `enumerator(options: [.skipsHiddenFiles])`
/// silently dropped dot-files, under-reporting by 1.37 GB on
/// `Library/Application Support`. The app promises real allocated bytes.
enum FastSize {
    /// Allocated bytes (st_blocks × 512) of a subtree, in one pass.
    /// Symlinks are not followed. Hidden files are counted.
    static func allocatedSize(ofPath path: String) -> Int64 {
        var total: Int64 = 0
        var stack: [String] = [path]

        while let dir = stack.popLast() {
            var handle: UnsafeMutablePointer<DIR>?
            handle = opendir(dir)
            guard let handle else { continue }
            defer { closedir(handle) }

            while let entry = readdir(handle) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) { raw -> String in
                    String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
                }
                if name == "." || name == ".." { continue }

                let child = dir + "/" + name
                var info = stat()
                guard lstat(child, &info) == 0 else { continue }

                let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
                if isDirectory { stack.append(child) }
                total += Int64(info.st_blocks) * 512
            }
        }
        return total
    }

    /// Allocated bytes of a subtree given as a URL.
    static func allocatedSize(of url: URL) -> Int64 {
        allocatedSize(ofPath: url.path)
    }

    /// Immediate children of a directory, with their type, in one `readdir`
    /// pass.
    ///
    /// `FileManager.contentsOfDirectory` + `fileExists(isDirectory:)` costs
    /// two syscalls per entry and allocates a `URL` per entry. `readdir`
    /// gives the name and the file type from the same directory record, so
    /// the dev-build walk stops stat-ing every child it already listed.
    struct Entry {
        let name: String
        let isDirectory: Bool
    }

    /// Children of `path`. Returns an empty array when the directory cannot
    /// be read.
    static func children(ofPath path: String) -> [Entry] {
        var entries: [Entry] = []
        guard let handle = opendir(path) else { return entries }
        defer { closedir(handle) }

        while let entry = readdir(handle) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw -> String in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            if name == "." || name == ".." { continue }
            // `d_type` is available on APFS/HFS+; fall back to a stat when the
            // filesystem does not fill it in. `d_type` is a UInt8 on Darwin.
            let isDirectory: Bool
            switch entry.pointee.d_type {
            case UInt8(DT_DIR):
                isDirectory = true
            case UInt8(DT_REG), UInt8(DT_LNK), UInt8(DT_UNKNOWN):
                var info = stat()
                isDirectory = lstat(path + "/" + name, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
            default:
                isDirectory = false
            }
            entries.append(Entry(name: name, isDirectory: isDirectory))
        }
        return entries
    }
}
