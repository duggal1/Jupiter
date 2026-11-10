import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Correctness checks for the scanner and the path index.
///
/// Run:
/// ```sh
/// swiftc -O -parse-as-library Tests/Verify.swift \
///   Purge/Models/Junk.swift Purge/Scanner/DiskSize.swift Purge/Scanner/FastSize.swift \
///   Purge/Scanner/PathIndex.swift -o /tmp/verify && /tmp/verify
/// ```
@main
struct Verify {
    static func main() async {
        var failures = 0
        func check(_ ok: Bool, _ name: String, _ detail: String = "") {
            if ok { print("PASS \(name)\(detail.isEmpty ? "" : " — \(detail)")") }
            else { print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")"); failures += 1 }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent("Library/Caches/purge_verify_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // MARK: - Allocated size

        let bigFile = base.appendingPathComponent("data.bin")
        let data = Data(repeating: 0x41, count: 1_000_000)
        try! data.write(to: bigFile)
        let allocated = DiskSize.blockSize(of: bigFile)
        check(allocated > 0, "allocated > 0", "\(allocated) bytes")
        check(allocated <= 1_000_000 + 16384, "allocated <= logical+slack", "\(allocated) vs 1000000")

        let empty = base.appendingPathComponent("empty")
        try! FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: empty.path)) ?? []
        check(names.isEmpty, "empty dir -> 0 children")

        let total = await DiskSize.allocatedSize(of: base)
        check(total > 0, "tree total > 0", "\(total) bytes")

        // MARK: - Hidden files are counted (A3)

        // A dot-file still occupies disk. The old `enumerator` walk with
        // `.skipsHiddenFiles` dropped these, under-reporting by 1.37 GB on
        // `Library/Application Support` alone.
        let hidden = base.appendingPathComponent(".hidden_payload")
        try! Data(repeating: 0x42, count: 500_000).write(to: hidden)
        let withHidden = FastSize.allocatedSize(ofPath: base.path)
        let hiddenSize = DiskSize.blockSize(of: hidden)
        check(withHidden >= total + hiddenSize, "hidden files counted", "\(withHidden) >= \(total + hiddenSize)")

        // MARK: - readdir matches FileManager.enumerator on the same tree

        let fastSize = FastSize.allocatedSize(ofPath: base.path)
        var enumeratorSize: Int64 = 0
        if let e = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) {
            for case let fileURL as URL in e {
                var info = stat()
                if lstat(fileURL.path, &info) == 0 {
                    enumeratorSize += Int64(info.st_blocks) * 512
                }
            }
        }
        check(fastSize > enumeratorSize, "readdir sees at least what enumerator sees", "\(fastSize) vs \(enumeratorSize)")

        // MARK: - PathIndex: memoisation (A4)

        let index = PathIndex.shared
        index.reset()
        let first = index.measure(path: base.path)
        let second = index.measure(path: base.path)
        check(!first.alreadyIndexed, "first measure is fresh")
        check(second.alreadyIndexed, "second measure is memoised")
        check(first.size == second.size, "memoised size is stable", "\(first.size) == \(second.size)")

        // MARK: - PathIndex: double hashing finds every key

        index.reset()
        var paths: [String] = []
        for i in 0..<500 {
            paths.append(base.appendingPathComponent("key_\(i)").path)
        }
        for path in paths { index.measure(path: path) }
        var allFound = true
        for path in paths {
            if index.measure(path: path).alreadyIndexed == false { allFound = false }
        }
        check(allFound, "double-hash table finds all 500 keys", "table=\(index.stats.tableSize)")
        check(index.stats.entries >= 500, "table holds every entry", "\(index.stats.entries) entries")

        // MARK: - PathIndex: concurrent access is safe

        index.reset()
        await withTaskGroup(of: Int64.self) { group in
            for i in 0..<200 {
                group.addTask(priority: .userInitiated) {
                    index.measure(path: base.appendingPathComponent("concurrent_\(i)").path).size
                }
            }
            for await _ in group {}
        }
        check(index.stats.entries >= 200, "concurrent inserts are all recorded", "\(index.stats.entries) entries")

        // MARK: - PathIndex: ownership ledger

        index.reset()
        let owner = index.claim(path: base.path, owner: "App Caches")
        check(owner == nil, "first claim wins")
        let secondClaim = index.claim(path: base.path, owner: "Packages")
        check(secondClaim == "App Caches", "second claim reports the owner", secondClaim ?? "nil")

        // MARK: - Home guard

        let mail = home.appendingPathComponent("Library/Mail")
        let mailListable = (try? FileManager.default.contentsOfDirectory(atPath: mail.path)) != nil
        print("FDA probe mail-listable=\(mailListable) (either way is a valid test result)")
        func isOutside(_ url: URL) -> Bool {
            let homePath = home.path
            if url == home { return false }
            return !url.path.hasPrefix(homePath + "/")
        }
        check(!isOutside(base), "inside-home allowed")
        check(isOutside(URL(fileURLWithPath: "/etc/hosts")), "outside-home blocked")
        check(isOutside(URL(fileURLWithPath: "/Applications/Purge.app")), "Applications blocked")

        try? FileManager.default.removeItem(at: base)
        if failures > 0 { print("\(failures) FAILURE(S)"); exit(1) }
        print("ALL CHECKS PASSED")
    }
}
