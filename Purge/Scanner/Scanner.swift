import Foundation

/// Concurrent directory scanner. Never touches anything outside the home
/// directory, except reading the snapshot list via tmutil.
enum Scanner {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: - Full Disk Access

    /// FDA is considered granted when a protected directory can be listed.
    /// One-sentence rationale shown in UI (DESIGN.md): this is the detector.
    static func hasFullDiskAccess() -> Bool {
        let fm = FileManager.default
        let probes = [
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Messages"),
        ]
        for probe in probes {
            if (try? fm.contentsOfDirectory(atPath: probe.path)) != nil {
                return true
            }
        }
        return false
    }

    static let fdaURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    // MARK: - Scan

    /// Scans all categories concurrently. Completion order is arbitrary;
    /// the view model re-sorts by size. Cancellation is cooperative.
    static func scanAll(
        hasFDA: Bool,
        includeDownloads: Bool = false,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async -> [(kind: CategoryKind, items: [ScannedItem])] {
        // Fresh index per scan: sizes must reflect the disk now, and the
        // ownership ledger must start empty so the totals are per-scan.
        PathIndex.shared.reset()

        let scanned = await withTaskGroup(of: (CategoryKind, [ScannedItem]).self) { group in
            for kind in CategoryKind.allCases {
                group.addTask(priority: .userInitiated) {
                    let items = await scan(kind: kind, hasFDA: hasFDA, includeDownloads: includeDownloads, isCancelled: isCancelled)
                    return (kind, items)
                }
            }
            var map: [CategoryKind: [ScannedItem]] = [:]
            for await (kind, items) in group {
                map[kind] = items
            }
            return CategoryKind.allCases.map { (kind: $0, items: map[$0] ?? []) }
        }

        return reconcile(scanned)
    }

    /// Reconciles overlapping categories so the same bytes are never counted
    /// twice (see `PERFORMANCE_AUDIT.md` A4).
    ///
    /// `~/Library/Caches/Homebrew` is found by both App Caches (as a child of
    /// `Library/Caches`) and Packages (as an explicit path). `~/.docker` is
    /// found by both Docker and Docker Build. Each duplicate was a full
    /// recursive walk *and* was added to the app total, so the UI
    /// over-reported what was reclaimable.
    ///
    /// The first category to claim a path keeps the bytes; the later one is
    /// marked "already counted in <category>" and contributes 0 to the total
    /// while still being visible and still cleanable.
    private static func reconcile(
        _ scanned: [(kind: CategoryKind, items: [ScannedItem])]
    ) -> [(kind: CategoryKind, items: [ScannedItem])] {
        // Deterministic order so the same category always wins.
        let order = CategoryKind.allCases
        var claimed: [String: CategoryKind] = [:]
        var result: [(kind: CategoryKind, items: [ScannedItem])] = []

        for kind in order {
            guard let entry = scanned.first(where: { $0.kind == kind }) else {
                result.append((kind: kind, items: []))
                continue
            }
            var rebuilt: [ScannedItem] = []
            for item in entry.items {
                guard let url = item.url else {
                    rebuilt.append(item)
                    continue
                }
                let path = url.standardizedFileURL.path
                if let owner = claimed[path] {
                    // Same bytes, already in the total under another category.
                    // Rebuild the row: `size` and `detail` are immutable.
                    rebuilt.append(ScannedItem(
                        id: item.id,
                        name: item.name,
                        url: item.url,
                        snapshotID: item.snapshotID,
                        size: 0,
                        safety: item.safety,
                        detail: "Already counted in \(owner.rawValue)",
                        cleanAction: item.cleanAction
                    ))
                    continue
                }
                claimed[path] = kind
                rebuilt.append(item)
            }
            result.append((kind: kind, items: rebuilt))
        }
        return result
    }

    static func scan(kind: CategoryKind, hasFDA: Bool, includeDownloads: Bool = false) async -> [ScannedItem] {
        await scan(kind: kind, hasFDA: hasFDA, includeDownloads: includeDownloads, isCancelled: { Task.isCancelled })
    }

    /// Watchdog fast path: only categories that can yield Safe (+ optional
    /// Okay) items. Skips Docker VM traversal, tmutil snapshots, iOS backups,
    /// and Downloads — the expensive + Risky-only work — so a background run
    /// stays cheap. Docker builder is included only when the watchdog opts in.
    static func scanWatchdog(config: WatchdogConfig, hasFDA: Bool) async -> [(kind: CategoryKind, items: [ScannedItem])] {
        let kinds: [CategoryKind] = [
            .appCaches, .logsAndReports, .xcode, .packageManagers, .trash,
        ] + (config.includeOkay ? [.orphaned] : [])
          + (config.includeDockerBuilderCache ? [.dockerBuild] : [])
        return await withTaskGroup(of: (CategoryKind, [ScannedItem]).self) { group in
            for kind in kinds {
                group.addTask(priority: .userInitiated) {
                    let items = await scan(kind: kind, hasFDA: hasFDA, includeDownloads: false, isCancelled: { Task.isCancelled })
                    return (kind, items)
                }
            }
            var map: [CategoryKind: [ScannedItem]] = [:]
            for await (kind, items) in group {
                if Task.isCancelled { break }
                map[kind] = items
            }
            return kinds.map { (kind: $0, items: map[$0] ?? []) }
        }
    }

    private static func scan(kind: CategoryKind, hasFDA: Bool, includeDownloads: Bool, isCancelled: @escaping @Sendable () -> Bool) async -> [ScannedItem] {
        switch kind {
        case .appCaches:
            return await scanAppCaches()
        case .logsAndReports:
            return await scanLogs()
        case .xcode:
            return await scanXcode(isCancelled: isCancelled)
        case .packageManagers:
            return await scanPackageManagers()
        case .downloadsMailBackups:
            return await scanDownloadsMailBackups(hasFDA: hasFDA, includeDownloads: includeDownloads)
        case .docker:
            return await DockerScanner.scanDockerData()
        case .dockerBuild:
            return await DockerScanner.scanDockerBuild()
        case .trash:
            return await scanChildren(at: ".Trash", safety: .safe)
        case .snapshots:
            return await scanSnapshots()
        case .orphaned:
            return await scanOrphaned(isCancelled: isCancelled)
        }
    }

    /// Enumerates immediate children of `relativePath` as items.
    private static func scanChildren(at relativePath: String, safety: Safety) async -> [ScannedItem] {
        let base = home.appendingPathComponent(relativePath)
        let children = await DiskSize.childrenSizes(of: base)
        return children.map {
            ScannedItem(name: $0.name, url: $0.url, size: $0.size, safety: safety)
        }
    }

    private static func scanAppCaches() async -> [ScannedItem] {
        let base = home.appendingPathComponent("Library/Caches")
        let children = await DiskSize.childrenSizes(of: base)
        return children.map { child in
            let safety = cacheSafety(child.name)
            // Browsers: spell out exactly what Risky costs so nobody deletes a profile by accident.
            let detail = safety == .risky ? "Deleting wipes the whole profile — history, logins, session, personal data." : nil
            return ScannedItem(name: child.name, url: child.url, size: child.size, safety: safety, detail: detail)
        }
    }

    /// Browsers keep history, logins and session state alongside cache —
    /// wiping them deletes your whole profile, so they are Risky, not Safe.
    private static func cacheSafety(_ name: String) -> Safety {
        let lower = name.lowercased()
        let riskyMarkers = ["google", "chrome", "brave", "mozilla", "firefox", "opera", "arc", "edge", "safari", "chromium", "electron"]
        return riskyMarkers.contains { lower.contains($0) } ? .risky : .safe
    }

    private static func scanLogs() async -> [ScannedItem] {
        var items: [ScannedItem] = []
        for rel in ["Library/Logs", "Library/Logs/DiagnosticReports"] {
            let base = home.appendingPathComponent(rel)
            let children = await DiskSize.childrenSizes(of: base)
            for child in children {
                // Prefix with parent so duplicates across roots stay distinct.
                let parent = base.deletingLastPathComponent().lastPathComponent
                items.append(ScannedItem(
                    name: parent == "Logs" ? child.name : "DiagnosticReports/\(child.name)",
                    url: child.url, size: child.size, safety: .safe
                ))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func scanXcode(isCancelled: @escaping @Sendable () -> Bool) async -> [ScannedItem] {
        var items: [ScannedItem] = []
        let dev = home.appendingPathComponent("Library/Developer")

        // DerivedData — each project folder, safe (rebuildable).
        let derived = dev.appendingPathComponent("Xcode/DerivedData")
        for child in await DiskSize.childrenSizes(of: derived) {
            items.append(ScannedItem(name: "DerivedData/\(child.name)", url: child.url, size: child.size, safety: .safe))
        }
        // Archives — okay (App Store symbols live here).
        let archives = dev.appendingPathComponent("Xcode/Archives")
        for child in await DiskSize.childrenSizes(of: archives) {
            items.append(ScannedItem(name: "Archives/\(child.name)", url: child.url, size: child.size, safety: .okay, detail: "Symbols for App Store builds"))
        }
        // iOS DeviceSupport — safe (re-downloaded on next build).
        let support = dev.appendingPathComponent("Xcode/iOS DeviceSupport")
        for child in await DiskSize.childrenSizes(of: support) {
            items.append(ScannedItem(name: "DeviceSupport/\(child.name)", url: child.url, size: child.size, safety: .safe))
        }
        // Simulators — okay (device data).
        let sims = dev.appendingPathComponent("CoreSimulator/Devices")
        for child in await DiskSize.childrenSizes(of: sims) {
            if isCancelled() { break }
            items.append(ScannedItem(name: "Simulator/\(child.name)", url: child.url, size: child.size, safety: .okay, detail: "Simulator data"))
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func scanPackageManagers() async -> [ScannedItem] {
        var items: [ScannedItem] = []
        let candidates: [(relative: String, label: String, safety: Safety)] = [
            ("Library/Caches/Homebrew", "Homebrew", .safe),
            (".npm/_cacache", "npm", .safe),
            ("Library/Caches/pip", "pip", .safe),
            (".cargo/registry/cache", "Cargo", .safe),
            (".gradle/caches", "Gradle", .safe),
            ("Library/Caches/Yarn", "Yarn", .safe),
            ("Library/Caches/pnpm", "pnpm", .safe),
            ("Library/Caches/uv", "uv", .safe),
            ("Library/Caches/go-build", "Go build cache", .safe),
            ("go/pkg/mod", "Go modules", .safe),
            ("Library/Caches/CocoaPods", "CocoaPods", .safe),
            ("Library/Caches/org.carthage", "Carthage", .safe),
            ("Library/org.swift.swiftpm", "SwiftPM cache", .safe),
            (".composer/cache", "Composer", .safe),
            (".m2/repository", "Maven", .safe),
            ("Library/pnpm/store", "pnpm store", .safe),
        ]
        // All candidates measured concurrently — 16 sequential tree walks were
        // the bulk of this category's cost.
        let measured = await withTaskGroup(of: (String, URL, Int64, Safety, String).self) { group in
            for candidate in candidates {
                group.addTask(priority: .userInitiated) {
                    let url = home.appendingPathComponent(candidate.relative)
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                        return ("", url, 0, candidate.safety, candidate.relative)
                    }
                    let size = PathIndex.shared.measure(path: url.path).size
                    return (candidate.label, url, size, candidate.safety, candidate.relative)
                }
            }
            var collected: [(String, URL, Int64, Safety, String)] = []
            for await result in group {
                if !result.0.isEmpty {
                    collected.append(result)
                }
            }
            return collected
        }
        for (label, url, size, safety, detail) in measured {
            items.append(ScannedItem(name: label, url: url, size: size, safety: safety, detail: detail))
        }
        // Homebrew: also consult `brew --cache` when available (allocated scan still authoritative).
        if let brewCache = homebrewCachePath() {
            if !items.contains(where: { $0.url?.path == brewCache.path }) {
                let size = PathIndex.shared.measure(path: brewCache.path).size
                items.append(ScannedItem(name: "Homebrew (brew cache)", url: brewCache, size: size, safety: .safe, detail: brewCache.path))
            }
        }
        // Dev project builds: .node_modules, .build, target/, Electron/Tauri outputs.
        // Biggest culprit for engineers (30–40 GB each) — Okay, never Risky, never auto-selected.
        items += await scanDevBuilds()
        return items.sorted { $0.size > $1.size }
    }

    /// Finds rebuildable project folders and badges them Okay (costs a
    /// rebuild, never user data). Generic `build`/`dist`/`out` require a
    /// project marker in the parent — otherwise they could be source.
    /// Debug/test entry point for the dev-build walk.
    static func scanDevBuildsPublic() async -> [ScannedItem] {
        await scanDevBuilds()
    }

    private static func scanDevBuilds() async -> [ScannedItem] {
        // dir name -> (safety, rebuild hint). __pycache__ regenerates instantly.
        let targets: [String: (Safety, String)] = [
            "node_modules": (.okay, "npm install to rebuild"),
            ".next": (.okay, "npm run build to rebuild"),
            ".nuxt": (.okay, "npm run build to rebuild"),
            ".turbo": (.okay, "npm run build to rebuild"),
            ".vite": (.okay, "npm run build to rebuild"),
            ".build": (.okay, "swift build to rebuild"),
            "target": (.okay, "cargo build to rebuild"),
            "Pods": (.okay, "pod install to rebuild"),
            ".gradle": (.okay, "./gradlew build to rebuild"),
            ".swiftpm": (.okay, "swift build to rebuild"),
            ".venv": (.okay, "pip install -r requirements.txt to rebuild"),
            "venv": (.okay, "pip install -r requirements.txt to rebuild"),
            "__pycache__": (.safe, "Regenerates on next run"),
            ".mypy_cache": (.safe, "Regenerates on next run"),
            ".pytest_cache": (.safe, "Regenerates on next run"),
            ".ruff_cache": (.safe, "Regenerates on next run"),
        ]
        // Generic names — only with a project marker in the parent.
        let generic: Set<String> = ["dist", "build", "out", ".output"]
        let markers = ["package.json", "Cargo.toml", "Package.swift", "go.mod",
                       "pom.xml", "build.gradle", "build.gradle.kts", "requirements.txt",
                       "pyproject.toml", "setup.py", "package-lock.json", "pnpm-lock.yaml",
                       "yarn.lock", "Cargo.lock", "go.sum", "poetry.lock"]
        let skip: Set<String> = [".git", ".hg", ".svn", "Library", ".Trash", "Applications",
                                 "Pictures", "Movies", "Music", "__MACOSX"]
        let fm = FileManager.default
        let roots: [URL] = ["Developer", "workspace", "projects", "work", "Code", "dev"].map { home.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }
        var found: [ScannedItem] = []
        // Index cursor instead of `queue.removeFirst()`: popping the front of an
        // Array is O(n), and this walk visits up to 5 000 directories.
        var queue: [(URL, Int)] = roots.map { ($0, 0) }
        var cursor = 0
        var visited = 0
        // Hits are collected first, then measured concurrently — measuring
        // each hit inside the BFS serialised the expensive part.
        var hits: [(URL, Safety, String)] = []

        while cursor < queue.count {
            if Task.isCancelled { break }
            let (dir, depth) = queue[cursor]
            cursor += 1
            guard visited < 5000, depth <= 6 else { continue }
            visited += 1
            // `readdir` gives the name and the type in one pass — no extra
            // `fileExists` stat per child.
            for entry in FastSize.children(ofPath: dir.path) {
                if Task.isCancelled { break }
                let name = entry.name
                if skip.contains(name) { continue }
                guard entry.isDirectory else { continue }
                let url = dir.appendingPathComponent(name)
                if let (safety, hint) = targets[name] {
                    hits.append((url, safety, hint))
                    continue // don't descend into found artifacts
                }
                if generic.contains(name) {
                    if projectHasMarker(in: dir, markers: markers) {
                        hits.append((url, .okay, "Rebuild with the project's build command"))
                    }
                    continue
                }
                queue.append((url, depth + 1))
            }
        }

        let measured = await withTaskGroup(of: (URL, Int64, Safety, String).self) { group in
            for (url, safety, hint) in hits {
                group.addTask(priority: .userInitiated) {
                    (url, PathIndex.shared.measure(path: url.path).size, safety, hint)
                }
            }
            var collected: [(URL, Int64, Safety, String)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        for (url, size, safety, hint) in measured {
            let rel = String(url.path.dropFirst(home.path.count + 1))
            found.append(ScannedItem(name: rel, url: url, size: size, safety: safety, detail: hint))
        }
        return found.sorted { $0.size > $1.size }.prefix(100).map { $0 }
    }

    private static func projectHasMarker(in dir: URL, markers: [String]) -> Bool {
        let fm = FileManager.default
        for marker in markers where fm.fileExists(atPath: dir.appendingPathComponent(marker).path) {
            return true
        }
        // *.xcodeproj / *.xcworkspace in the parent also mark a real project.
        // `readdir` instead of `contentsOfDirectory`: this runs once per
        // generic build folder found, and it only needs the names.
        for entry in FastSize.children(ofPath: dir.path) {
            if entry.name.hasSuffix(".xcodeproj") || entry.name.hasSuffix(".xcworkspace") {
                return true
            }
        }
        return false
    }

    private static func homebrewCachePath() -> URL? {
        // `brew --cache` resolves to a user-writable cache inside home.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        process.arguments = ["--cache"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else { return nil }
            let url = URL(fileURLWithPath: path)
            guard url.path.hasPrefix(home.path) else { return nil }
            return url
        } catch {
            return nil
        }
    }

    private static func scanDownloadsMailBackups(hasFDA: Bool, includeDownloads: Bool) async -> [ScannedItem] {
        var items: [ScannedItem] = []
        // Downloads — opt-in only, so the launch scan never triggers a TCC prompt.
        if includeDownloads {
            let downloads = home.appendingPathComponent("Downloads")
            for child in await DiskSize.childrenSizes(of: downloads) {
                items.append(ScannedItem(name: child.name, url: child.url, size: child.size, safety: .risky, detail: "Downloads — personal files"))
            }
        }
        // iOS device backups — risky (personal data).
        let backups = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        for child in await DiskSize.childrenSizes(of: backups) {
            items.append(ScannedItem(name: "iOS Backup/\(child.name)", url: child.url, size: child.size, safety: .risky, detail: "Device backup"))
        }
        // Mail attachments — risky (personal mail), FDA-gated.
        if hasFDA {
            let mail = home.appendingPathComponent("Library/Mail")
            for child in await DiskSize.childrenSizes(of: mail) {
                items.append(ScannedItem(name: "Mail/\(child.name)", url: child.url, size: child.size, safety: .risky, detail: "Mail"))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Docker file + VM disk layout lives in DockerScanner — kept here as a
    /// thin shim so historical call sites stay stable.
    static func scanDocker() async -> [ScannedItem] {
        await DockerScanner.scanDockerData()
    }

    static func scanDockerBuild() async -> [ScannedItem] {
        await DockerScanner.scanDockerBuild()
    }

    private static func scanSnapshots() async -> [ScannedItem] {
        let ids = await listLocalSnapshots()
        var items: [ScannedItem] = []
        for id in ids {
            // Snapshot size isn't reported on an item line; count as 0 until
            // `tmutil listlocalsnapshots` gives no bytes — report honest 0,
            // detail explains. Sizes for snapshots are measured by APFS
            // thining after deletion (Cleaner reports actual freed).
            items.append(ScannedItem(
                name: snapshotLabel(id),
                url: nil, snapshotID: id,
                size: 0, safety: .risky,
                detail: "Local version history — \(id)"
            ))
        }
        return items
    }

    private static func listLocalSnapshots() async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
            process.arguments = ["listlocalsnapshots", "/"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return [] }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else { return [] }
                return output.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } catch {
                return []
            }
        }.value
    }

    private static func snapshotLabel(_ id: String) -> String {
        // e.g. com.apple.TimeMachine.2026-11-06-120000.local
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let middle = id.replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                           .replacingOccurrences(of: ".local", with: "")
        if let date = formatter.date(from: middle) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return id
    }

    private static func scanOrphaned(isCancelled: @escaping @Sendable () -> Bool) async -> [ScannedItem] {
        let installed = installedBundleIDs()
        var items: [ScannedItem] = []

        let support = home.appendingPathComponent("Library/Application Support")
        // Filter before measuring: 180 children, only the orphaned ones are
        // worth walking.
        let supportChildren = await DiskSize.childrenSizes(of: support) { name in
            looksLikeBundleID(name) && !installed.contains(name)
        }
        for child in supportChildren {
            if isCancelled() { break }
            items.append(ScannedItem(
                name: child.name, url: child.url, size: child.size,
                safety: .okay, detail: "Application Support"
            ))
        }

        let prefs = home.appendingPathComponent("Library/Preferences")
        if let names = try? FileManager.default.contentsOfDirectory(atPath: prefs.path) {
            // Filter before measuring, then measure concurrently.
            let candidates = names.filter { name in
                guard name.hasSuffix(".plist") else { return false }
                let id = String(name.dropLast(".plist".count))
                return looksLikeBundleID(id) && !installed.contains(id)
            }
            let measured = await withTaskGroup(of: (String, URL, Int64).self) { group in
                for name in candidates {
                    group.addTask(priority: .userInitiated) {
                        let url = prefs.appendingPathComponent(name)
                        return (name, url, PathIndex.shared.measure(path: url.path).size)
                    }
                }
                var collected: [(String, URL, Int64)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            for (name, url, size) in measured {
                if isCancelled() { break }
                let id = String(name.dropLast(".plist".count))
                items.append(ScannedItem(
                    name: id, url: url, size: size,
                    safety: .okay, detail: "Preferences"
                ))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func looksLikeBundleID(_ name: String) -> Bool {
        name.contains(".") && !name.contains(" ") && !name.hasPrefix(".")
    }

    /// Bundle IDs of apps in /Applications — read-only, never touched.
    /// The Info.plist reads are independent, so they run concurrently.
    static func installedBundleIDs() -> Set<String> {
        let appsDir = URL(fileURLWithPath: "/Applications")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: appsDir.path) else { return [] }
        let apps = names.filter { $0.hasSuffix(".app") }
        var ids = Set<String>()
        let lock = NSLock()
        // Concurrent plist reads: 40 apps, each an independent file read.
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let infoURL = appsDir.appendingPathComponent(apps[index]).appendingPathComponent("Contents/Info.plist")
            guard let plist = NSDictionary(contentsOf: infoURL),
                  let id = plist["CFBundleIdentifier"] as? String else { return }
            lock.lock()
            ids.insert(id)
            lock.unlock()
        }
        return ids
    }
}

extension ScannedItem {
    static func snapshotPlaceholder(id: String) -> ScannedItem {
        ScannedItem(name: id, url: nil, snapshotID: id, size: 0, safety: .risky, detail: id)
    }
}
