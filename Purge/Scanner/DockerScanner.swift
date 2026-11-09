import Foundation

/// Docker measurement + cleaning surface.
///
/// Why this exists: the old scan only measured two directories and marked
/// both Risky. Trashing `Docker.raw` while the daemon runs corrupts the VM,
/// and build cache  — the actual developer junk — was invisible.
///
/// Rules (from DESIGN.md honesty + safety):
/// - Builder / buildx cache = **Safe**, cleaned via `docker builder prune`.
/// - Dangling images/containers/networks + unused images = **Okay**, cleaned
///   via `docker image prune` / `docker system prune`.
/// - Volumes + VM disks (Docker Desktop, Colima, OrbStack, Lima, Podman) =
///   **Risky / InfoOnly** — shown with real allocated sizes, never trashed.
///   They must be pruned via `docker volume prune` or Docker Desktop →
///   Troubleshoot → Clean / Prune.
///
/// File paths are measured with `st_blocks × 512` (allocated). Rows from
/// `docker system df` report the reclaimable delta as their size so the
/// tick strips stay honest even for virtual caches with no home-directory
/// file footprint.
enum DockerScanner {
    // MARK: - Binary discovery

    /// First executable `docker` found on this Mac, in priority order.
    /// `nil` when no daemon CLI exists — file caches still scan.
    static func dockerBinary() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/orbstack-docker",
        ].map { URL(fileURLWithPath: $0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var isDockerAvailable: Bool { dockerBinary() != nil }

    // MARK: - Docker Build (builder / buildx)

    /// Safe builder + buildx cache. File sizes are measured; cleaning runs
    /// the CLI prune, never `trashItem` on a live cache dir.
    static func scanDockerBuild() async -> [JunkItem] {
        var items: [JunkItem] = []

        let cacheDirs: [(relative: String, label: String)] = [
            ("Library/Caches/docker-buildx", "Buildx cache"),
            (".docker/buildx", "Buildx"),
            (".docker/builder", "Builder"),
        ]
        for candidate in cacheDirs {
            let url = Scanner.home.appendingPathComponent(candidate.relative)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let size = await DiskSize.allocatedSize(of: url)
            guard size > 0 else { continue }
            items.append(JunkItem(
                name: candidate.label,
                url: url,
                size: size,
                safety: .safe,
                detail: "Build cache — rebuilds on next build",
                cleanAction: .dockerPrune(.builder)
            ))
        }

        // Virtual builder cache reported by the daemon (often much larger
        // than the on-disk stub). Dedupe against the file rows by name.
        if let rows = await systemDF() {
            for row in rows where row.type == "Build Cache" && row.reclaimable > 0 {
                if items.contains(where: { $0.name.localizedCaseInsensitiveContains("build") }) { continue }
                items.append(JunkItem(
                    name: "Build cache (daemon)",
                    size: row.reclaimable,
                    safety: .safe,
                    detail: "\(row.totalText) total · \(row.reclaimableText) reclaimable — docker builder prune",
                    cleanAction: .dockerPrune(.builder)
                ))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    // MARK: - Docker (images, containers, volumes, VM disks)

    /// Daemon rows (Okay / Risky) + VM disk storage (Risky, InfoOnly).
    /// VM disks are sized honestly but are never trashable — the detail
    /// tells the user the safe removal path.
    static func scanDockerData() async -> [JunkItem] {
        var items: [JunkItem] = []

        // Daemon df: images + containers are Okay (rebuild cost), volumes Risky.
        if let rows = await systemDF() {
            for row in rows {
                switch row.type {
                case "Images":
                    if row.reclaimable > 0 {
                        items.append(JunkItem(
                            name: "Unused images",
                            size: row.reclaimable,
                            safety: .okay,
                            detail: "\(row.totalText) total · \(row.reclaimableText) reclaimable — docker image prune -a",
                            cleanAction: .dockerPrune(.images)
                        ))
                    }
                case "Containers":
                    if row.reclaimable > 0 {
                        items.append(JunkItem(
                            name: "Stopped containers",
                            size: row.reclaimable,
                            safety: .okay,
                            detail: "\(row.totalText) total · \(row.reclaimableText) reclaimable — docker system prune",
                            cleanAction: .dockerPrune(.dangling)
                        ))
                    }
                case "Local Volumes":
                    if row.reclaimable > 0 {
                        items.append(JunkItem(
                            name: "Unused volumes",
                            size: row.reclaimable,
                            safety: .risky,
                            detail: "Volumes may hold database data — docker volume prune only after review",
                            cleanAction: .dockerPrune(.system)
                        ))
                    }
                default:
                    break
                }
            }
        }

        // VM / runtime disk storage — InfoOnly. Real numbers, no Trash path.
        let vmCandidates: [(relative: String, label: String, detail: String)] = [
            ("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", "Docker.raw", "Docker Desktop VM disk — clean via Docker Desktop → Troubleshoot → Clean / Prune"),
            ("Library/Containers/com.docker.docker/Data", "Docker data", "Docker Desktop data — clean via Docker Desktop, not Trash"),
            ("Library/Group Containers/group.com.docker", "Docker group", "Docker Desktop group storage"),
            (".colima", "Colima", "Colima runtime — colima delete or docker system prune"),
            (".lima", "Lima", "Lima VMs — lima delete when unused"),
            (".orbstack", "OrbStack", "OrbStack data — clean via OrbStack app"),
            ("Library/Group Containers/HUAUQ4K983.email.orbstack", "OrbStack volumes", "OrbStack volumes"),
            (".podman", "Podman", "Podman data — podman system prune"),
            (".docker", "Docker config", "Docker CLI config + buildx"),
        ]
        for candidate in vmCandidates {
            let url = Scanner.home.appendingPathComponent(candidate.relative)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            // Skip the parent dir if we already measured a child (Docker.raw
            // is inside Docker data) — keep the more specific row only.
            if candidate.label == "Docker data", items.contains(where: { $0.name == "Docker.raw" }) { continue }
            let size = await DiskSize.allocatedSize(of: url)
            guard size > 0 else { continue }
            items.append(JunkItem(
                name: candidate.label,
                url: url,
                size: size,
                safety: .risky,
                detail: candidate.detail,
                cleanAction: .infoOnly
            ))
        }
        return items.sorted { $0.size > $1.size }
    }

    // MARK: - `docker system df`

    struct DFRow {
        let type: String
        let totalText: String
        let reclaimableText: String
        let reclaimable: Int64
    }

    /// `docker system df --format "{{.Type}}|{{.Total}}|{{.Size}}|{{.Reclaimable}}"`
    /// Output: "Images|10|2.5GB|500MB" per line. Returns nil when daemon
    /// is down or CLI is absent — file caches still scan.
    /// Coalesced: scanAll runs Docker + Docker Build in parallel, so the
    /// second caller reuses the in-flight task instead of forking docker twice.
    private static var dfCache: (Date, [DFRow]?) = (.distantPast, nil)
    private static let dfLock = NSLock()

    static func systemDF() async -> [DFRow]? {
        dfLock.lock()
        let cached = dfCache
        dfLock.unlock()
        if Date().timeIntervalSince(cached.0) < 5, let rows = cached.1 { return rows }
        guard let docker = dockerBinary() else { return nil }
        let rows = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = docker
            process.arguments = ["system", "df", "--format", "{{.Type}}|{{.Total}}|{{.Size}}|{{.Reclaimable}}"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil as [DFRow]? }
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return out.split(separator: "\n").compactMap { line -> DFRow? in
                    let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                    guard parts.count >= 4 else { return nil }
                    let type = String(parts[0])
                    let total = String(parts[1])
                    let sizeText = String(parts[2])
                    let reclaimableText = String(parts[3]).trimmingCharacters(in: .whitespaces)
                    return DFRow(type: type, totalText: "\(total) · \(sizeText)", reclaimableText: reclaimableText, reclaimable: parseBytes(reclaimableText))
                }
            } catch {
                return nil
            }
        }.value
        dfLock.lock()
        dfCache = (Date(), rows)
        dfLock.unlock()
        return rows
    }

    /// Best-effort parse of `docker system df` human sizes ("500MB", "2.5GB", "0B").
    static func parseBytes(_ text: String) -> Int64 {
        let t = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !t.isEmpty else { return 0 }
        let units: [(String, Int64)] = [
            ("TB", 1_000_000_000_000), ("GB", 1_000_000_000), ("MB", 1_000_000),
            ("KB", 1_000), ("B", 1),
        ]
        for (suffix, mult) in units where t.hasSuffix(suffix) {
            let num = t.dropLast(suffix.count)
            if let v = Double(num) { return Int64(v * Double(mult)) }
        }
        return 0
    }

    // MARK: - Cleaning (CLI prune)

    enum PruneError: LocalizedError {
        case noDocker
        case daemonDown
        case failed(code: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case .noDocker: return "Docker CLI not found."
            case .daemonDown: return "Docker daemon not running."
            case .failed(_, let message): return message.isEmpty ? "docker prune failed" : message
            }
        }
    }

    /// Runs the matching `docker ... prune -f` subcommand. Throws on failure.
    static func prune(kind: DockerPruneKind) async throws {
        guard let docker = dockerBinary() else { throw PruneError.noDocker }
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = docker
            process.arguments = arguments(for: kind)
            let err = Pipe()
            process.standardError = err
            process.standardOutput = Pipe()
            do {
                try process.run()
            } catch {
                throw PruneError.daemonDown
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if msg.localizedCaseInsensitiveContains("cannot connect") || msg.localizedCaseInsensitiveContains("is the docker daemon running") {
                    throw PruneError.daemonDown
                }
                throw PruneError.failed(code: process.terminationStatus, message: msg)
            }
        }.value
    }

    static func arguments(for kind: DockerPruneKind) -> [String] {
        switch kind {
        case .builder: return ["builder", "prune", "-f"]
        case .dangling: return ["system", "prune", "-f"]
        case .images: return ["image", "prune", "-a", "-f"]
        case .system: return ["system", "prune", "-a", "--volumes", "-f"]
        }
    }

    /// Human verbs for UI + logs.
    static func pruneLabel(_ kind: DockerPruneKind) -> String {
        switch kind {
        case .builder: return "docker builder prune"
        case .dangling: return "docker system prune"
        case .images: return "docker image prune -a"
        case .system: return "docker system prune -a --volumes"
        }
    }
}
