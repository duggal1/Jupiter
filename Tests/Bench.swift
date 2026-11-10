import Foundation
import Observation

/// Performance benchmark for the scanner.
///
/// Run:
/// ```sh
/// swiftc -O -parse-as-library Tests/Bench.swift \
///   Purge/Models/Junk.swift Purge/Scanner/DiskSize.swift Purge/Scanner/Scanner.swift \
///   Purge/Scanner/DockerScanner.swift Purge/Scanner/WatchdogConfig.swift \
///   Purge/Scanner/FastSize.swift Purge/Scanner/PathIndex.swift -o /tmp/bench
/// /tmp/bench
/// ```
///
/// Prints per-category timings, the parallel `scanAll` total, and a
/// fast-vs-slow size comparison so the numbers in `PERFORMANCE_AUDIT.md`
/// can be reproduced on any machine.
@main
struct Bench {
    static func main() async {
        // Unbuffered: the benchmark is often piped, and a crash would
        // otherwise swallow every line.
        setvbuf(stdout, nil, _IONBF, 0)
        print("=== Per-category scan (sequential) ===")
        var serial = 0.0
        for kind in CategoryKind.allCases {
            let t0 = Date()
            let items = await Scanner.scan(kind: kind, hasFDA: false, includeDownloads: false)
            let dt = Date().timeIntervalSince(t0)
            serial += dt
            let bytes = items.reduce(Int64(0)) { $0 + $1.size }
            // NOTE: the formatted strings are bound to locals first.
            // `String(format:)` takes CVarArg; passing `.utf8String!` on a
            // temporary NSString leaves a dangling pointer by the time the
            // formatter reads it, which traps.
            let kindC = kind.rawValue as NSString
            let bytesC = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) as NSString
            print(String(
                format: "%-16s %7.3fs  %4d items  %s",
                kindC.utf8String!,
                dt,
                items.count,
                bytesC.utf8String!
            ))
        }
        print(String(format: "TOTAL serial: %.3fs", serial))

        print("\n=== Parallel scanAll ===")
        for round in 1...3 {
            let t1 = Date()
            let cats = await Scanner.scanAll(hasFDA: false, includeDownloads: false)
            let dt = Date().timeIntervalSince(t1)
            let total = cats.reduce(Int64(0)) { acc, entry in acc + entry.items.reduce(0) { $0 + $1.size } }
            let totalC = ByteCountFormatter.string(fromByteCount: total, countStyle: .file) as NSString
            print(String(
                format: "round %d: %.3fs  (%d categories, %s total)",
                round, dt, cats.count,
                totalC.utf8String!
            ))
        }

        print("\n=== PathIndex: memoisation + double-count check ===")
        let index = PathIndex.shared
        index.reset()
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches")
        let t2 = Date()
        let first = index.measure(path: probe.path)
        let firstDt = Date().timeIntervalSince(t2)
        let t3 = Date()
        let second = index.measure(path: probe.path)
        let secondDt = Date().timeIntervalSince(t3)
        print("first  measure: \(firstDt * 1000) ms  alreadyIndexed=\(first.alreadyIndexed)")
        print("second measure: \(secondDt * 1000) ms  alreadyIndexed=\(second.alreadyIndexed)")
        print("stats: \(index.stats)")

        print("\n=== readdir vs FileManager.enumerator (same tree) ===")
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: appSupport.path)) ?? []
        let fm = FileManager.default

        let t4 = Date()
        var enumeratorSum: Int64 = 0
        for name in names {
            let url = appSupport.appendingPathComponent(name)
            guard let e = fm.enumerator(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let fileURL as URL in e {
                var info = stat()
                if lstat(fileURL.path, &info) == 0 {
                    enumeratorSum += Int64(info.st_blocks) * 512
                }
            }
        }
        let enumeratorDt = Date().timeIntervalSince(t4)

        let t5 = Date()
        var readdirSum: Int64 = 0
        for name in names {
            readdirSum += FastSize.allocatedSize(ofPath: appSupport.appendingPathComponent(name).path)
        }
        let readdirDt = Date().timeIntervalSince(t5)

        print(String(format: "enumerator (skips hidden): %.3fs  %lld bytes", enumeratorDt, enumeratorSum))
        print(String(format: "readdir    (all files)  : %.3fs  %lld bytes", readdirDt, readdirSum))
        print(String(format: "speedup: %.1fx   hidden-file under-count: %lld bytes", enumeratorDt / readdirDt, readdirSum - enumeratorSum))
    }
}
