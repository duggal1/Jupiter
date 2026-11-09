import Foundation
import SwiftUI

/// View model for the Watchdog pane. Owns config + launchd status.
/// All UserDefaults writes are synchronous; launchctl runs off MainActor
/// only for status probes (install/uninstall are short blocking calls).
@Observable
@MainActor
final class WatchdogViewModel {
    var config = WatchdogConfig.load()
    var isLoaded = LaunchAgentInstaller.isLoaded
    var message: String?
    var isWorking = false
    var logTail: String = ""

    init() {
        refreshLog()
    }

    var statusLine: String {
        if isWorking { return "Working…" }
        if config.enabled { return "On · every \(config.intervalDays) days" }
        return "Off"
    }

    func refreshLog() {
        logTail = WatchdogLog.tail(20)
    }

    func refreshLoaded() {
        isLoaded = LaunchAgentInstaller.isLoaded
    }

    func setEnabled(_ on: Bool) {
        isWorking = true
        defer { isWorking = false }
        do {
            if on {
                config.enabled = true
                try LaunchAgentInstaller.install(config: config)
            } else {
                config.enabled = false
                try LaunchAgentInstaller.uninstall()
            }
            config.save()
            refreshLoaded()
            message = on
                ? "Watchdog on — runs every \(config.intervalDays) days in the background, even with Jupiter closed."
                : "Watchdog off."
        } catch {
            config.enabled = on ? config.enabled : false
            config.save()
            message = "Failed: \(error.localizedDescription)"
        }
        refreshLog()
    }

    func setInterval(_ days: Int) {
        config.intervalDays = days
        config.save()
        if config.enabled {
            do {
                try LaunchAgentInstaller.install(config: config)
                refreshLoaded()
                message = "Interval updated — next run in \(days) days."
            } catch {
                message = "Failed to update interval: \(error.localizedDescription)"
            }
        }
    }

    func setIncludeTrash(_ on: Bool) {
        config.includeTrash = on
        config.save()
    }

    func setIncludeOkay(_ on: Bool) {
        config.includeOkay = on
        config.save()
    }

    func setIncludeDockerBuilder(_ on: Bool) {
        config.includeDockerBuilderCache = on
        config.save()
    }

    func runNow() {
        guard !isWorking else { return }
        isWorking = true
        message = "Running…"
        Task {
            let freed = await WatchdogRunner.run()
            config = WatchdogConfig.load()
            refreshLoaded()
            refreshLog()
            isWorking = false
            if freed > 0 {
                message = "Ran now — freed \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))."
            } else if let note = config.lastNote {
                message = "Ran now — \(note)"
            } else {
                message = "Ran now — nothing to clean."
            }
        }
    }

    func remove() {
        isWorking = true
        defer { isWorking = false }
        do {
            try LaunchAgentInstaller.uninstall()
            config.enabled = false
            config.save()
            refreshLoaded()
            message = "Removed."
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
        refreshLog()
    }

    func openLog() {
        let url = WatchdogLog.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }
}
