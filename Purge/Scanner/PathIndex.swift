import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Path index — the "database" layer for a filesystem scanner.
///
/// Two jobs, both of which used to be done by accident (slowly, and wrongly):
///
/// 1. **Memoised sizes.** The same path was measured more than once —
///    `~/Library/Caches/Homebrew` as a child of `Library/Caches` *and* as a
///    package-manager path; `~/.docker` whole *and* via `~/.docker/buildx`.
///    Each duplicate was a full recursive walk, and each was added to the
///    total, so the app over-reported what was reclaimable.
///
/// 2. **Ownership ledger.** When two categories claim overlapping bytes the
///    second one must not be counted twice. `claim` returns the owner that
///    already holds the bytes, so the caller can mark the row as
///    "already counted in <category>" instead of double-adding it.
///
/// ## Double hashing
///
/// The index is an open-addressed hash table with **double hashing**: the
/// bucket index comes from `hashA`, and the probe step comes from `hashB`.
/// Two independent 64-bit hashes (FNV-1a and a splitmix-style mixer) over
/// the same path bytes. This is the textbook remedy for the clustering that
/// single-hash linear probing suffers when many keys share a prefix —
/// which is exactly the case here, since every scanned path starts with
/// `/Users/<name>/`.
///
/// `hashA` and `hashB` are not derived from each other, so a collision in
/// one does not imply a collision in the other. The stored key is the path
/// string itself and is compared exactly on probe, so a hash collision can
/// never return the wrong size — it only costs an extra probe.
final class PathIndex: @unchecked Sendable {
    static let shared = PathIndex()

    private struct Slot {
        var path: String
        var size: Int64
        var owner: String?
    }

    private var slots: [Slot?] = []
    private var count = 0
    private let lock = NSLock()

    /// Paths already measured, by exact path.
    private var sizes: [String: Int64] = [:]
    /// path → category that owns its bytes.
    private var owners: [String: String] = [:]

    private init() {
        slots = Array(repeating: nil, count: 64)
    }

    // MARK: - Locking
    //
    // The lock is only ever taken inside these synchronous helpers, so it
    // is never held across an `await` and never taken from an async context
    // directly (Swift 6 forbids both).

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - Hashing

    /// FNV-1a, 64-bit.
    @inline(__always)
    private static func hashA(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// splitmix64 finalizer over a different seed — independent of `hashA`.
    @inline(__always)
    private static func hashB(_ s: String) -> UInt64 {
        var hash: UInt64 = 0x9e3779b97f4a7c15
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0xff51afd7ed558ccd
            hash ^= hash >> 33
        }
        hash ^= hash >> 33
        hash = hash &* 0xff51afd7ed558ccd
        hash ^= hash >> 33
        return hash
    }

    // MARK: - Table

    private func insert(path: String, size: Int64, owner: String?) {
        if count * 4 >= slots.count * 3 { rehash() }

        let mask = slots.count - 1
        // `Int(hash)` traps when the hash exceeds Int.max, so the hash is
        // masked down to the table size *before* the conversion.
        var index = Int(truncatingIfNeeded: PathIndex.hashA(path) & UInt64(mask))
        // Odd step ⇒ coprime with the power-of-two table ⇒ the probe visits
        // every slot. `mask` is always odd (slots.count is a power of two), so
        // `| 1` before masking guarantees the step is odd and non-zero.
        let step = Int(truncatingIfNeeded: (PathIndex.hashB(path) | 1) & UInt64(mask))

        while true {
            if slots[index] == nil {
                slots[index] = Slot(path: path, size: size, owner: owner)
                count += 1
                return
            }
            if slots[index]?.path == path { return }
            index = (index + step) & mask
        }
    }

    private func rehash() {
        let old = slots
        slots = Array(repeating: nil, count: old.count * 2)
        count = 0
        for slot in old {
            guard let slot else { continue }
            insert(path: slot.path, size: slot.size, owner: slot.owner)
        }
    }

    private func lookup(path: String) -> Slot? {
        let mask = slots.count - 1
        var index = Int(truncatingIfNeeded: PathIndex.hashA(path) & UInt64(mask))
        let step = Int(truncatingIfNeeded: (PathIndex.hashB(path) | 1) & UInt64(mask))
        var probes = 0

        while probes <= slots.count {
            guard let slot = slots[index] else { return nil }
            if slot.path == path { return slot }
            index = (index + step) & mask
            probes += 1
        }
        return nil
    }

    // MARK: - Public API

    /// Size of a path, measured once and memoised.
    /// Returns `nil` when the path was already measured by someone else, so
    /// the caller can avoid counting the same bytes twice.
    func measure(path: String) -> (size: Int64, alreadyIndexed: Bool) {
        if let cached = withLock({ sizes[path] }) {
            return (cached, true)
        }

        let size = FastSize.allocatedSize(ofPath: path)

        return withLock {
            // Another thread may have won the race; keep the first result so
            // the number stays stable for the lifetime of the scan.
            if let existing = sizes[path] {
                return (existing, true)
            }
            sizes[path] = size
            insert(path: path, size: size, owner: nil)
            return (size, false)
        }
    }

    /// Claims the bytes at `path` for `owner`.
    /// Returns the owner that already holds them, or `nil` if this caller now
    /// owns them.
    @discardableResult
    func claim(path: String, owner: String) -> String? {
        withLock {
            if let existing = owners[path] {
                return existing == owner ? nil : existing
            }
            owners[path] = owner
            if let slot = lookup(path: path) {
                replace(slot: slot, owner: owner)
            } else {
                insert(path: path, size: 0, owner: owner)
            }
            return nil
        }
    }

    /// Overwrites the stored slot for a path with a new owner.
    private func replace(slot: Slot, owner: String) {
        let mask = slots.count - 1
        var index = Int(truncatingIfNeeded: PathIndex.hashA(slot.path) & UInt64(mask))
        let step = Int(truncatingIfNeeded: (PathIndex.hashB(slot.path) | 1) & UInt64(mask))
        var probes = 0
        while probes <= slots.count {
            guard let current = slots[index] else { return }
            if current.path == slot.path {
                slots[index] = Slot(path: slot.path, size: slot.size, owner: owner)
                return
            }
            index = (index + step) & mask
            probes += 1
        }
    }

    /// Owner of `path`, if any. `nil` when unclaimed or owned by `owner`.
    func owner(of path: String, excluding owner: String) -> String? {
        withLock {
            guard let existing = owners[path], existing != owner else { return nil }
            return existing
        }
    }

    /// Drops every memoised size and owner. Called at the start of a scan so
    /// a rescan reflects the disk as it is now, not as it was.
    func reset() {
        withLock {
            slots = Array(repeating: nil, count: 64)
            count = 0
            sizes.removeAll()
            owners.removeAll()
        }
    }

    /// Diagnostics for the audit.
    var stats: (entries: Int, tableSize: Int) {
        withLock { (count, slots.count) }
    }
}
