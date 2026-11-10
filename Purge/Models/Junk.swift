import Foundation

/// One removable thing with a real allocated size.
/// - safe: regenerates automatically, loses nothing.
/// - okay: okay with limits — deletes, but costs time (re-pull, re-index) or convenience.
/// - risky: deleting wipes user data (history, logins, files, versions) — review before touching.
enum Safety: Sendable {
    case safe
    case okay
    case risky

    var title: String {
        switch self {
        case .safe: return "Safe"
        case .okay: return "Okay"
        case .risky: return "Risky"
        }
    }

    /// Short honest explainer shown next to the badge / in dialogs.
    var blurb: String {
        switch self {
        case .safe: return "Regenerates automatically. Loses nothing."
        case .okay: return "Okay with limits — deletes, but costs time or convenience."
        case .risky: return "Risky — deleting wipes personal data (history, logins, files)."
        }
    }

    var isDestructive: Bool { self == .risky }
}

/// How an item is actually removed. Most items are trashed (recoverable).
/// Docker daemon caches are pruned via the `docker` CLI — never by trashing VM storage.
enum DockerPruneKind: String, Sendable {
    case builder
    case dangling
    case images
    case system
}

enum CleanAction: Sendable, Equatable {
    /// Move to Trash (recoverable). Default for every file item.
    case trash
    /// Run a `docker ... prune` subcommand instead of touching the filesystem.
    case dockerPrune(DockerPruneKind)
    /// Size-only row. Never deleted by Cleaner — shown for awareness.
    case infoOnly
}

/// An immutable scan result.
///
/// The scanner runs off the main actor and produces these; they carry no
/// mutable state, so they cross actor boundaries safely. The UI turns them
/// into `JunkItem`s on the main actor, and only the UI mutates them.
struct ScannedItem: Sendable, Identifiable {
    let id: UUID
    let name: String
    /// nil for Time Machine snapshots (deleted via tmutil) and docker prune rows.
    let url: URL?
    /// Time Machine snapshot ID when `url == nil`.
    let snapshotID: String?
    /// Allocated bytes (st_blocks × 512), never logical size.
    let size: Int64
    let safety: Safety
    let detail: String?
    let cleanAction: CleanAction

    init(
        id: UUID = UUID(),
        name: String,
        url: URL? = nil,
        snapshotID: String? = nil,
        size: Int64,
        safety: Safety,
        detail: String? = nil,
        cleanAction: CleanAction = .trash
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.snapshotID = snapshotID
        self.size = size
        self.safety = safety
        self.detail = detail
        self.cleanAction = cleanAction
    }
}

/// The minimum a cleaner needs to act on an item.
///
/// The cleaner never touches the observable model — it works on these plain
/// values and reports outcomes, so no model state is ever written off the
/// main actor.
struct CleanTarget: Sendable {
    let id: UUID
    let name: String
    let url: URL?
    let snapshotID: String?
    let size: Int64
    let cleanAction: CleanAction

    init(
        id: UUID,
        name: String,
        url: URL?,
        snapshotID: String?,
        size: Int64,
        cleanAction: CleanAction
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.snapshotID = snapshotID
        self.size = size
        self.cleanAction = cleanAction
    }

    init(item: JunkItem) {
        self.init(
            id: item.id,
            name: item.name,
            url: item.url,
            snapshotID: item.snapshotID,
            size: item.size,
            cleanAction: item.cleanAction
        )
    }

    init(scanned: ScannedItem) {
        self.init(
            id: scanned.id,
            name: scanned.name,
            url: scanned.url,
            snapshotID: scanned.snapshotID,
            size: scanned.size,
            cleanAction: scanned.cleanAction
        )
    }
}

/// One removable thing with a real allocated size.
///
/// ## Actor isolation
///
/// `JunkItem` is `@Observable` **and** carries mutable state, so it cannot
/// be `Sendable` — the compiler is right, and it is why the clean used to
/// lose updates: `Cleaner` wrote `isDeleted` from a detached task while the
/// view model read it on the main actor.
///
/// The model is now **main-actor bound**. The scanner produces immutable
/// `ScannedItem`s off the main actor and hands them over once; after that
/// every mutation happens on the main actor, in one place
/// (`ScanViewModel.apply`).
///
/// `Identifiable` is satisfied by the non-isolated `id` property, so the
/// conformance does not cross the isolation boundary.
@Observable
@MainActor
final class JunkItem: Identifiable {
    let id: UUID
    let name: String
    /// nil for Time Machine snapshots (deleted via tmutil) and docker prune rows.
    let url: URL?
    /// Time Machine snapshot ID when `url == nil`.
    let snapshotID: String?
    /// Allocated bytes (st_blocks × 512), never logical size.
    let size: Int64
    let safety: Safety
    let detail: String?
    let cleanAction: CleanAction
    var isSelected: Bool = false
    var isDeleted: Bool = false
    var error: String?

    init(scanned: ScannedItem) {
        self.id = scanned.id
        self.name = scanned.name
        self.url = scanned.url
        self.snapshotID = scanned.snapshotID
        self.size = scanned.size
        self.safety = scanned.safety
        self.detail = scanned.detail
        self.cleanAction = scanned.cleanAction
    }

    /// Non-Trash rows (docker prune, info-only) are never selected by Auto-clean.
    var isAutoCleanable: Bool {
        cleanAction == .trash && safety != .risky
    }

    /// The plain value a cleaner acts on.
    var cleanTarget: CleanTarget { CleanTarget(item: self) }
}

enum CategoryKind: String, Sendable, CaseIterable {
    case appCaches = "App Caches"
    case logsAndReports = "Logs"
    case xcode = "Xcode"
    case packageManagers = "Packages"
    case downloadsMailBackups = "Downloads"
    case docker = "Docker"
    case dockerBuild = "Docker Build"
    case trash = "Trash"
    case snapshots = "Snapshots"
    case orphaned = "Orphaned"

    var symbol: String {
        switch self {
        case .appCaches: "shippingbox"
        case .logsAndReports: "list.bullet.rectangle"
        case .xcode: "hammer"
        case .packageManagers: "terminal"
        case .downloadsMailBackups: "tray.and.arrow.down"
        case .docker: "container"
        case .dockerBuild: "shippingbox.fill"
        case .trash: "trash"
        case .snapshots: "clock.arrow.circlepath"
        case .orphaned: "questionmark.folder.fill"
        }
    }

    /// Whether this category needs Full Disk Access to enumerate.
    var requiresFDA: Bool {
        self == .downloadsMailBackups
    }

    /// Categories with daemon-managed storage — never trashed in place.
    var isDockerManaged: Bool {
        self == .docker || self == .dockerBuild
    }
}

@Observable
@MainActor
final class JunkCategory: Identifiable {
    /// The category itself is the identity. `kind` is immutable, so the
    /// `Identifiable` conformance does not cross the isolation boundary.
    nonisolated let kind: CategoryKind
    var items: [JunkItem]
    var isExpanded: Bool = false
    var didScan: Bool = false
    var scanError: String?

    init(kind: CategoryKind, items: [JunkItem] = []) {
        self.kind = kind
        self.items = items
    }

    nonisolated var id: CategoryKind { kind }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var safeSelectedSize: Int64 {
        items.filter { $0.isSelected && $0.safety == .safe }.reduce(0) { $0 + $1.size }
    }
}
