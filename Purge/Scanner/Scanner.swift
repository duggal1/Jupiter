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
    ) async -> [JunkCategory] {
        await withTaskGroup(of: (CategoryKind, [JunkItem]).self) { group in
            for kind in CategoryKind.allCases {
                group.addTask(priority: .userInitiated) {
                    let items = await scan(kind: kind, hasFDA: hasFDA, includeDownloads: includeDownloads, isCancelled: isCancelled)
                    return (kind, items)
                }
            }
            var map: [CategoryKind: [JunkItem]] = [:]
            for await (kind, items) in group {
                map[kind] = items
            }
            return CategoryKind.allCases.map { JunkCategory(kind: $0, items: map[$0] ?? []) }
        }
    }

    static func scan(kind: CategoryKind, hasFDA: Bool, includeDownloads: Bool = false) async -> [JunkItem] {
        await scan(kind: kind, hasFDA: hasFDA, includeDownloads: includeDownloads, isCancelled: { Task.isCancelled })
    }

    private static func scan(kind: CategoryKind, hasFDA: Bool, includeDownloads: Bool, isCancelled: @escaping @Sendable () -> Bool) async -> [JunkItem] {
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
            return await scanDocker()
        case .trash:
            return await scanChildren(at: ".Trash", safety: .safe)
        case .snapshots:
            return await scanSnapshots()
        case .orphaned:
            return await scanOrphaned(isCancelled: isCancelled)
        }
    }

    /// Enumerates immediate children of `relativePath` as items.
    private static func scanChildren(at relativePath: String, safety: Safety) async -> [JunkItem] {
        let base = home.appendingPathComponent(relativePath)
        let children = await DiskSize.childrenSizes(of: base)
        return children.map {
            JunkItem(name: $0.name, url: $0.url, size: $0.size, safety: safety)
        }
    }

    private static func scanAppCaches() async -> [JunkItem] {
        let base = home.appendingPathComponent("Library/Caches")
        let children = await DiskSize.childrenSizes(of: base)
        return children.map { child in
            let safety = cacheSafety(child.name)
            // Browsers: spell out exactly what Risky costs so nobody deletes a profile by accident.
            let detail = safety == .risky ? "Deleting wipes the whole profile — history, logins, session, personal data." : nil
            return JunkItem(name: child.name, url: child.url, size: child.size, safety: safety, detail: detail)
        }
    }

    /// Browsers keep history, logins and session state alongside cache —
    /// wiping them deletes your whole profile, so they are Risky, not Safe.
    private static func cacheSafety(_ name: String) -> Safety {
        let lower = name.lowercased()
        let riskyMarkers = ["google", "chrome", "brave", "mozilla", "firefox", "opera", "arc", "edge", "safari", "chromium", "electron"]
        return riskyMarkers.contains { lower.contains($0) } ? .risky : .safe
    }

    private static func scanLogs() async -> [JunkItem] {
        var items: [JunkItem] = []
        for rel in ["Library/Logs", "Library/Logs/DiagnosticReports"] {
            let base = home.appendingPathComponent(rel)
            let children = await DiskSize.childrenSizes(of: base)
            for child in children {
                // Prefix with parent so duplicates across roots stay distinct.
                let parent = base.deletingLastPathComponent().lastPathComponent
                items.append(JunkItem(
                    name: parent == "Logs" ? child.name : "DiagnosticReports/\(child.name)",
                    url: child.url, size: child.size, safety: .safe
                ))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func scanXcode(isCancelled: @escaping @Sendable () -> Bool) async -> [JunkItem] {
        var items: [JunkItem] = []
        let dev = home.appendingPathComponent("Library/Developer")

        // DerivedData — each project folder, safe (rebuildable).
        let derived = dev.appendingPathComponent("Xcode/DerivedData")
        for child in await DiskSize.childrenSizes(of: derived) {
            items.append(JunkItem(name: "DerivedData/\(child.name)", url: child.url, size: child.size, safety: .safe))
        }
        // Archives — okay (App Store symbols live here).
        let archives = dev.appendingPathComponent("Xcode/Archives")
        for child in await DiskSize.childrenSizes(of: archives) {
            items.append(JunkItem(name: "Archives/\(child.name)", url: child.url, size: child.size, safety: .okay, detail: "Symbols for App Store builds"))
        }
        // iOS DeviceSupport — safe (re-downloaded on next build).
        let support = dev.appendingPathComponent("Xcode/iOS DeviceSupport")
        for child in await DiskSize.childrenSizes(of: support) {
            items.append(JunkItem(name: "DeviceSupport/\(child.name)", url: child.url, size: child.size, safety: .safe))
        }
        // Simulators — okay (device data).
        let sims = dev.appendingPathComponent("CoreSimulator/Devices")
        for child in await DiskSize.childrenSizes(of: sims) {
            if isCancelled() { break }
            items.append(JunkItem(name: "Simulator/\(child.name)", url: child.url, size: child.size, safety: .okay, detail: "Simulator data"))
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func scanPackageManagers() async -> [JunkItem] {
        var items: [JunkItem] = []
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
        for candidate in candidates {
            let url = home.appendingPathComponent(candidate.relative)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let size = await DiskSize.allocatedSize(of: url)
            items.append(JunkItem(name: candidate.label, url: url, size: size, safety: candidate.safety, detail: candidate.relative))
        }
        // Homebrew: also consult `brew --cache` when available (allocated scan still authoritative).
        if let brewCache = homebrewCachePath() {
            if !items.contains(where: { $0.url?.path == brewCache.path }) {
                let size = await DiskSize.allocatedSize(of: brewCache)
                items.append(JunkItem(name: "Homebrew (brew cache)", url: brewCache, size: size, safety: .safe, detail: brewCache.path))
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
    private static func scanDevBuilds() async -> [JunkItem] {
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
        var found: [JunkItem] = []
        var queue: [(URL, Int)] = roots.map { ($0, 0) }
        var visited = 0
        while !queue.isEmpty {
            if Task.isCancelled { break }
            let (dir, depth) = queue.removeFirst()
            guard visited < 5000, depth <= 6 else { continue }
            visited += 1
            guard let children = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in children {
                if Task.isCancelled { break }
                if skip.contains(name) { continue }
                let url = dir.appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
                if let (safety, hint) = targets[name] {
                    let size = await DiskSize.allocatedSize(of: url)
                    let rel = String(url.path.dropFirst(home.path.count + 1))
                    found.append(JunkItem(name: rel, url: url, size: size, safety: safety, detail: hint))
                    continue // don't descend into found artifacts
                }
                if generic.contains(name) {
                    if projectHasMarker(in: dir, markers: markers) {
                        let size = await DiskSize.allocatedSize(of: url)
                        let rel = String(url.path.dropFirst(home.path.count + 1))
                        found.append(JunkItem(name: rel, url: url, size: size, safety: .okay, detail: "Rebuild with the project's build command"))
                    }
                    continue
                }
                queue.append((url, depth + 1))
            }
        }
        return found.sorted { $0.size > $1.size }.prefix(100).map { $0 }
    }

    private static func projectHasMarker(in dir: URL, markers: [String]) -> Bool {
        let fm = FileManager.default
        for marker in markers where fm.fileExists(atPath: dir.appendingPathComponent(marker).path) {
            return true
        }
        // *.xcodeproj / *.xcworkspace in the parent also mark a real project.
        if let children = try? fm.contentsOfDirectory(atPath: dir.path) {
            for name in children where name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") {
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

    private static func scanDownloadsMailBackups(hasFDA: Bool, includeDownloads: Bool) async -> [JunkItem] {
        var items: [JunkItem] = []
        // Downloads — opt-in only, so the launch scan never triggers a TCC prompt.
        if includeDownloads {
            let downloads = home.appendingPathComponent("Downloads")
            for child in await DiskSize.childrenSizes(of: downloads) {
                items.append(JunkItem(name: child.name, url: child.url, size: child.size, safety: .risky, detail: "Downloads — personal files"))
            }
        }
        // iOS device backups — risky (personal data).
        let backups = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        for child in await DiskSize.childrenSizes(of: backups) {
            items.append(JunkItem(name: "iOS Backup/\(child.name)", url: child.url, size: child.size, safety: .risky, detail: "Device backup"))
        }
        // Mail attachments — risky (personal mail), FDA-gated.
        if hasFDA {
            let mail = home.appendingPathComponent("Library/Mail")
            for child in await DiskSize.childrenSizes(of: mail) {
                items.append(JunkItem(name: "Mail/\(child.name)", url: child.url, size: child.size, safety: .risky, detail: "Mail"))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func scanDocker() async -> [JunkItem] {
        var items: [JunkItem] = []
        let candidates: [(relative: String, label: String)] = [
            ("Library/Containers/com.docker.docker/Data", "Docker data"),
            (".docker", "Docker config"),
        ]
        for candidate in candidates {
            let url = home.appendingPathComponent(candidate.relative)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let size = await DiskSize.allocatedSize(of: url)
            items.append(JunkItem(name: candidate.label, url: url, size: size, safety: .risky, detail: candidate.relative))
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func scanSnapshots() async -> [JunkItem] {
        let ids = await listLocalSnapshots()
        var items: [JunkItem] = []
        for id in ids {
            // Snapshot size isn't reported on an item line; count as 0 until
            // `tmutil listlocalsnapshots` gives no bytes — report honest 0,
            // detail explains. Sizes for snapshots are measured by APFS
            // thining after deletion (Cleaner reports actual freed).
            items.append(JunkItem(
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

    private static func scanOrphaned(isCancelled: @escaping @Sendable () -> Bool) async -> [JunkItem] {
        let installed = installedBundleIDs()
        var items: [JunkItem] = []

        let support = home.appendingPathComponent("Library/Application Support")
        for child in await DiskSize.childrenSizes(of: support) {
            if isCancelled() { break }
            guard looksLikeBundleID(child.name) else { continue }
            if installed.contains(child.name) { continue }
            items.append(JunkItem(
                name: child.name, url: child.url, size: child.size,
                safety: .okay, detail: "Application Support"
            ))
        }

        let prefs = home.appendingPathComponent("Library/Preferences")
        if let names = try? FileManager.default.contentsOfDirectory(atPath: prefs.path) {
            for name in names where name.hasSuffix(".plist") {
                if isCancelled() { break }
                let id = String(name.dropLast(".plist".count))
                guard looksLikeBundleID(id), !installed.contains(id) else { continue }
                let url = prefs.appendingPathComponent(name)
                let size = await DiskSize.allocatedSize(of: url)
                items.append(JunkItem(
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
    static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let appsDir = URL(fileURLWithPath: "/Applications")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: appsDir.path) else { return ids }
        for name in names where name.hasSuffix(".app") {
            let infoURL = appsDir.appendingPathComponent(name).appendingPathComponent("Contents/Info.plist")
            if let plist = NSDictionary(contentsOf: infoURL), let id = plist["CFBundleIdentifier"] as? String {
                ids.insert(id)
            }
        }
        return ids
    }
}

extension JunkItem {
    static func snapshotPlaceholder(id: String) -> JunkItem {
        JunkItem(name: id, url: nil, snapshotID: id, size: 0, safety: .risky, detail: id)
    }
}
