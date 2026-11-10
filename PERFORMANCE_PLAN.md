# Performance Plan — Jupiter (Jupiter/Purge)

Status: **executed**. This document is the plan that was run; `PERFORMANCE_AUDIT.md`
records the measured before/after and what was *not* fixed.

Scope: the initial scan (`Scanner.scanAll`) and the memory ladder. No behaviour
change to *what* is found — only to how fast it is found and how the UI stays
in sync.

---

## 1. Baseline (measured, this machine, 2026-11-10)

Serial per-category, `Scanner.scan(kind:)`:

| Category | Time | Items | Bytes |
|---|---|---|---|
| App Caches | 0.304 s | 29 | 380.6 MB |
| Logs | 0.001 s | 3 | 37 KB |
| Xcode | 0.001 s | 0 | 0 |
| Packages | 1.870 s | 3 | 478.5 MB |
| Downloads | 0.000 s | 0 | 0 |
| Docker | 0.004 s | 1 | 281.2 MB |
| Docker Build | 0.000 s | 0 | 0 |
| Trash | 0.000 s | 0 | 0 |
| Snapshots | 0.059 s | 1 | 0 |
| Orphaned | 3.447 s | 47 | 950 KB |
| **Serial total** | **5.687 s** | | |
| `scanAll` (parallel, 10 categories) | **2.964 s** | | |

Hot-spot isolation (`/tmp/prof.swift`):

| Operation | Time |
|---|---|
| `installedBundleIDs()` — 40 Info.plist reads | 0.039 s |
| `Library/Application Support` children sizes (180 children) | **3.619 s** |
| `Library/Preferences` plist sizes | 0.033 s |
| `scanDevBuilds` BFS + size measurement | **2.000 s** |

## 2. Root causes

1. **Serial fan-out inside categories.** `DiskSize.childrenSizes` awaits one
   subtree at a time. 180 children ⇒ 180 sequential full-tree walks. This is
   the single largest cost (3.6 s of the 3.4 s `Orphaned`).
2. **`FileManager.enumerator` is slow.** Measured 0.307 s vs 0.023 s for a
   `readdir` walk of the same tree — **13×**. It also allocates a `URL` per
   file and re-resolves every path.
3. **`.skipsHiddenFiles` under-counts.** `enumerator(options: [.skipsHiddenFiles])`
   silently drops dot-files, so reported sizes are *smaller than the bytes on
   disk*. On `Library/Application Support` the under-count was **1.47 GB**.
4. **Duplicate work.** `~/Library/Caches/Homebrew` is measured once as a child
   of `Library/Caches` and again as a package-manager path. `~/.docker` is
   measured whole and again via `~/.docker/buildx`. Same bytes, walked twice
   and **counted twice** in the app total.
5. **Cross-thread model mutation.** `Cleaner.clean` writes `item.isDeleted` and
   `item.error` from a detached task; `ScanViewModel` reads them on the main
   actor. `@Observable` notifications therefore fire off the main thread and
   the row removal is racy — the UI does not update immediately after a clean.
6. **Privileged prompt on every purge.** `osascript … with administrator
   privileges` re-prompts for the password on every run, including the
   background watchdog.

## 3. Work items

| # | Change | File | Target |
|---|---|---|---|
| W1 | `readdir`-based allocated-size walker, hidden files included | `Purge/Scanner/FastSize.swift` | 13× on tree walk |
| W2 | Parallel fan-out for children sizes (bounded) | `Purge/Scanner/DiskSize.swift` | 20× on `App Support` |
| W3 | Double-hash path index: memoised sizes + claim ledger | `Purge/Scanner/PathIndex.swift` | no duplicate walk, no double count |
| W4 | Deterministic reconcile pass: unique byte accounting | `Purge/Scanner/Scanner.swift` | totals stop double counting |
| W5 | Cleaner returns outcomes; **all** model mutation on MainActor | `Purge/Scanner/Cleaner.swift`, `ViewModels/ScanViewModel.swift` | UI state immediate |
| W6 | Privileged runner: silent `sudo -n` → one askpass prompt → ticket keepalive | `Purge/Scanner/PrivilegedRunner.swift` | password asked once, not every run |
| W7 | Toggle knob travel clamped to the track (padding fix) | `Purge/UIComponents/AppToggle.swift` | knob never leaves the track |
| W8 | Parallel `installedBundleIDs`, cached per scan | `Purge/Scanner/Scanner.swift` | 0.04 s → 0.01 s |
| W9 | Verification: extend `Tests/Verify.swift`; add `Tests/Bench.swift` | `Tests/` | proof, not vibes |

## 4. Explicitly out of scope

- The app does not have a database. "Indexing" here means the **filesystem
  measurement index** (`PathIndex`): a hash index over paths that memoises
  sizes and tracks byte ownership so the same bytes are never counted twice.
  There is no SQL, no SQLite, no persistent store — and none was added.
- `DESIGN-REPAIR` does not exist in this repository (checked `cleanup/` and
  `workspace/`). The reference actually used is `superflow/DESIGN.md` (§3.5
  Motion, §5 Type, §8.5 Toggle), which `DESIGN_NOTES.md` already points at.
- No notarisation, no privileged helper install, no keychain writes.
