import Foundation

/// Watchdog preferences + run history. Stored in UserDefaults as JSON so the
/// headless launchd run and the SwiftUI pane share one source of truth.
struct WatchdogConfig: Codable, Sendable, Equatable {
    var enabled = false
    /// 1, 3, or 7 days. Default 3 (72h) per request.
    var intervalDays = 3
    var includeTrash = true
    /// Watchdog is Safe-only by default. This opt-in also allows Okay
    /// (dev builds, orphaned support dirs). Risky is NEVER allowed.
    var includeOkay = false
    /// Docker builder cache prune needs a running daemon. Off by default
    /// for the background job — turn on only if Docker runs on schedule.
    var includeDockerBuilderCache = false

    var lastRun: Date?
    var lastFreed: Int64 = 0
    var lastNote: String?
    var lastFailed: Int = 0

    static let defaultsKey = "jupiter.watchdog.config.v1"

    static func load() -> WatchdogConfig {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let cfg = try? JSONDecoder().decode(WatchdogConfig.self, from: data) else {
            return WatchdogConfig()
        }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    static func store(_ cfg: WatchdogConfig) {
        cfg.save()
    }

    var nextRun: Date? {
        guard let lastRun else { return nil }
        return lastRun.addingTimeInterval(TimeInterval(intervalDays * 24 * 60 * 60))
    }

    var startIntervalSeconds: Int { intervalDays * 24 * 60 * 60 }

    /// Allowed safeties for any background clean. Risky is structurally
    /// excluded — there is no toggle that enables it.
    var allowedSafeties: Set<Safety> {
        includeOkay ? [.safe, .okay] : [.safe]
    }
}
