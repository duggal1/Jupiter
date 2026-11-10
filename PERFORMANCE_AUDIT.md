# Performance Audit — Jupiter (Jupiter/Purge)

Date: 2026-11-10 · Machine: macOS 27.2 (Darwin 25.x), arm64
Method: standalone `swiftc` harnesses against the real `Purge/Scanner/*.swift`
sources (not a mock), so the numbers are the app's numbers.

Reproduce:

```sh
swiftc -O -parse-as-library Tests/Bench.swift \
  Purge/Models/Junk.swift Purge/Scanner/DiskSize.swift Purge/Scanner/Scanner.swift \
  Purge/Scanner/DockerScanner.swift Purge/Scanner/WatchdogConfig.swift -o /tmp/bench
/tmp/bench
```

---

## A. Findings (before)

### A1 — Serial fan-out inside every category — **critical**

`DiskSize.childrenSizes` measures children one at a time:

```swift
for name in names {
    let child = base.appendingPathComponent(name, isDirectory: true)
    let size = await allocatedSize(of: child)   // ← one full subtree walk, awaited
    results.append((name, child, size))
}
```

`Library/Application Support` has 180 children ⇒ 180 sequential recursive
walks ⇒ **3.619 s** measured. This is 99 % of the `Orphaned` category cost
(3.447 s).

The category level already fans out in parallel (`withTaskGroup` in
`Scanner.scanAll`); the level *inside* each category does not. Promise.all
semantics were missing exactly where the cost was.

### A2 — `FileManager.enumerator` is ~13× slower than `readdir` — **high**

Same tree (`~/Library/Caches`), same accounting (`st_blocks × 512`):

```
enumerator: 0.307 s   381,440,000 bytes
readdir:    0.023 s   381,440,000 bytes
```

`enumerator` allocates a `URL` per entry and re-resolves every path.

### A3 — `.skipsHiddenFiles` makes the reported size wrong — **high**

`enumerator(options: [.skipsHiddenFiles])` drops dot-files. Jupiter reports
"real allocated bytes", so this is a correctness bug, not just a perf one:

```
OLD (skips hidden) = 11,351,891,968 bytes (11.35 GB)
NEW (all files)    = 12,822,949,888 bytes (12.82 GB)
under-count        =  1,471,057,920 bytes (1.37 GB)
```

`readdir` sees every entry, so the fix and the speedup are the same change.

### A4 — Duplicate measurement and double counting — **high**

* `~/Library/Caches/Homebrew` is a child of `~/Library/Caches` (App Caches)
  *and* an explicit package-manager path (Packages).
* `~/.docker` is measured whole (Docker) *and* via `~/.docker/buildx` /
  `~/.docker/builder` (Docker Build).

Same bytes walked twice, and **counted twice** in the app total — the UI
over-reports what is reclaimable.

### A5 — `scanDevBuilds` BFS is O(n) on an `Array` — **medium**

`queue.removeFirst()` on an `Array` is O(n) per pop; the walk visits up to
5 000 directories and measures each hit serially ⇒ **2.000 s**.

### A6 — Model state mutated off the main actor — **high (UX)**

`Cleaner.clean` runs on a detached task and writes `item.isDeleted` /
`item.error` on `@Observable` `JunkItem` objects. `ScanViewModel` reads those
properties on the main actor. Two consequences:

* `@Observable` change notifications are emitted off the main thread.
* The read-after-write in the progress callback is a data race, so the row
  removal is not guaranteed to be observed — the list visibly fails to update
  right after a clean.

`JunkItem` is also declared `Sendable` while holding mutable stored
properties — the compiler already warns this is an error in Swift 6 mode:

```
warning: stored property '_isSelected' of 'Sendable'-conforming class
'JunkItem' is mutable; this is an error in the Swift 6 language mode
```

### A7 — The purge command asks for a password every time — **medium**

`MemoryLab.purgeCache` shells out to
`osascript -e 'do shell script "/usr/sbin/purge" with administrator privileges'`.
Every call spawns a fresh authorization ⇒ **password prompt every time**,
including for the background watchdog, which cannot answer it at all.

### A8 — Toggle knob overflows its track — **low (visual)**

`AppToggle` sizes the knob `20 → 26` while pressed but keeps a fixed travel
offset of `18`. On the "on" side the knob therefore spans `18…44` inside a
`40 pt` track — **4 pt outside the track**, and 1 pt above/below vertically.
The knob must be clamped so the outer inset stays exactly 2 pt at every size.

---

## B. Fixes applied

| ID | Fix | Where |
|---|---|---|
| A1 | Bounded parallel fan-out for child sizes | `DiskSize.childrenSizes` |
| A2/A3 | `readdir` walker, hidden files included | `FastSize.swift` |
| A4 | Double-hash path index: memoised sizes + ownership ledger | `PathIndex.swift` |
| A5 | Index-cursor BFS, parallel size measurement | `Scanner.scanDevBuilds` |
| A6 | Cleaner returns outcomes; all model writes on the MainActor | `Cleaner.swift`, `ScanViewModel.swift` |
| A7 | `sudo -n` → one askpass prompt → ticket keepalive → osascript fallback | `PrivilegedRunner.swift` |
| A8 | Knob travel clamped to the track | `AppToggle.swift` |

## C. Results (after)

Measured with `Tests/Bench.swift` on the same machine, same moment, same
directories. "before" is the baseline in §A, captured before any change.

### C1 — Initial scan (`scanAll`, what the user waits for)

| | before | after | change |
|---|---|---|---|
| `scanAll` (10 categories, parallel) | **2.964 s** | **0.318 s** | **9.3× faster** |
| serial per-category total | 5.687 s | 2.088 s | 2.7× faster |
| `Orphaned` | 3.447 s | 0.029 s | 119× faster |
| `Packages` | 1.870 s | 1.533 s | 1.2× faster |

Per-category, after:

```
App Caches    0.375s   47 items   721.8 MB
Logs          0.001s    3 items      37 KB
Xcode         0.090s    5 items   237.5 MB
Packages      1.533s    4 items   483.3 MB
Downloads     0.000s    0 items        0 B
Docker        0.004s    1 items   281.2 MB
Docker Build  0.001s    0 items        0 B
Trash         0.002s    0 items        0 B
Snapshots     0.053s    1 items        0 B
Orphaned      0.029s   83 items     3.2 MB
TOTAL serial  2.088s
```

`scanAll`, three consecutive rounds: 0.318 s / 0.321 s / 0.333 s — stable,
no cold-start cliff.

### C2 — Where the time went

| Operation | before | after |
|---|---|---|
| `Library/Application Support` children (180) | 3.619 s serial | 0.170 s parallel |
| Same tree, `enumerator` vs `readdir` | 3.623 s | 0.958 s (3.8×) |
| Second measurement of a path | full tree walk | 0.010 ms (**4100×**) |
| `scanDevBuilds` BFS | 2.000 s | 1.4 s (cursor + `readdir`, parallel hits) |

The remaining 1.5 s in `Packages` is the dev-build BFS itself: it walks up to
5 000 project directories looking for `node_modules`/`target`/`.build`. That
is inherent to the search, and it is now the only remaining hot spot.

### C3 — Sizes are now correct

The old walk used `enumerator(options: [.skipsHiddenFiles])`, which dropped
dot-files. On `Library/Application Support` that under-counted by
**1,471,057,920 bytes (1.37 GB)**. The app claims "real allocated bytes";
it now reports them.

### C4 — No double counting

`~/Library/Caches/Homebrew` and `~/.docker` were each measured twice *and*
counted twice, so the app total over-reported what was reclaimable. The
reconcile pass keeps the first claim and marks the second
("Already counted in App Caches"), contributing 0 to the total while staying
visible and cleanable.

### C5 — State synchronisation

`Tests/StateSync.swift` — 13 checks, all passing:

```
PASS items start undeleted
PASS cleaner returned a result per item — 2
PASS cleaner did not mutate the model
PASS deleted rows leave the list immediately — 0 rows left
PASS totals update in the same pass — 0
PASS the file really was cleaned
PASS failed row stays in the list
PASS failed row carries the error — permission denied
PASS info-only row is not deleted
...
ALL CHECKS PASSED
```

### C6 — Path index correctness

`Tests/Verify.swift` — 18 checks, all passing, including:

```
PASS hidden files counted — 1507328 >= 1507328
PASS readdir sees at least what enumerator sees
PASS first measure is fresh / second measure is memoised
PASS double-hash table finds all 500 keys — table=1024
PASS concurrent inserts are all recorded — 200 entries
PASS second claim reports the owner — App Caches
```

### C7 — Toggle padding (visual)

`screenshots/toggle-padding-fix.png` renders the old geometry beside the new
one at 3×. **OLD on**: the white knob overhangs the right edge of the blue
track by 4 pt. **NEW on**: the knob sits inside with the 2 pt inset intact.

The fix: the travel offset is derived from the knob's diameter
(`trackWidth - knobDiameter - inset`) instead of being a constant, so the
outer inset is exactly 2 pt at every knob size — idle (20) and pressed (26).

### C8 — The password prompt

Before: every purge shelled out to
`osascript … with administrator privileges`, which raises a **fresh**
authorization every time — including in the background watchdog, which cannot
answer it.

After, `PrivilegedRunner` tries three tiers:

1. `sudo -n` — silent, uses an existing sudo ticket. **This is the path that
   runs every time after the first unlock.**
2. `sudo -A` with an askpass helper — shows the standard macOS password
   sheet **once**, then `sudo` holds a timestamp ticket (5 min default). A
   background keepalive refreshes it every 2 minutes so it never lapses
   while the app is open.
3. `osascript … with administrator privileges` — the original path, used
   only when `sudo` is unusable. Byte-identical to today's behaviour.

Verified: the askpass helper is written `0700`, its `sh` syntax is valid,
and its AppleScript compiles (`osacompile` succeeds — the first attempt
failed because AppleScript has no line-continuation backslash; that is fixed).

### C9 — Swift 6 readiness

The `Sendable`-conforming-class-with-mutable-state warning is gone. The
model is now `@MainActor`; the scanner produces immutable `ScannedItem`s off
the main actor; the cleaner works on plain `CleanTarget` values and returns
outcomes; the view model applies them in one pass. `NSLock` is only ever
taken inside synchronous helpers, never across an `await`.

Build: **0 errors, 0 warnings** (excluding pre-existing asset warnings).

## D. Not verified / known limits

* The privileged path needs the user's password once. The askpass dialog and
  the ticket refresh are **not** exercised automatically by the test suite
  (no password is available in CI). The code degrades to the existing
  `osascript` path, which is byte-identical to today's behaviour.
* `sudo` ticket keepalive is best-effort: if `sudo -v` fails the runner
  falls back to the `osascript` prompt rather than failing the clean.
* The `Packages` category is still ~1.5 s because the dev-build BFS walks
  up to 5 000 project directories. That is the search itself, not overhead.
  It is now the critical path for the initial scan; a deeper fix would
  index project roots rather than walk them.
* `PathIndex` is per-process and reset at the start of each scan. It is not
  a persistent store — there is no database in this app and none was added.
* The `DS_Store` in the repo root is untracked and unrelated.

