import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Installs / removes the launchd LaunchAgent that runs Jupiter headless.
///
/// Why launchd, not cron: cron on macOS does not wake from sleep, does not
/// reliably fire after logout, and has no native log plumbing. A user
/// LaunchAgent at ~/Library/LaunchAgents/com.jupiter.watchdog.plist loads at
/// login, survives quitting Jupiter, and wakes every StartInterval seconds.
///
/// The plist points at the live Jupiter executable and runs it with
/// `--watchdog-run`. Nothing runs until the user flips the Watchdog toggle.
enum LaunchAgentInstaller {
    static let label = "com.jupiter.watchdog"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var appExecutable: URL? {
        let exe = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Jupiter")
        return FileManager.default.fileExists(atPath: exe.path) ? exe : nil
    }

    enum InstallError: LocalizedError {
        case noExecutable
        case launchctl(String)

        var errorDescription: String? {
            switch self {
            case .noExecutable: return "Jupiter.app executable not found."
            case .launchctl(let message): return message.isEmpty ? "launchctl failed" : message
            }
        }
    }

    static func install(config: WatchdogConfig) throws {
        guard let exe = appExecutable else { throw InstallError.noExecutable }
        let logPath = NSHomeDirectory() + "/Library/Logs/Jupiter/Watchdog.log"
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe.path, "--watchdog-run"],
            "StartInterval": config.startIntervalSeconds,
            "RunAtLoad": false,
            "KeepAlive": false,
            "ThrottleInterval": 30,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
            "ProcessType": "Background",
        ]
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        // Reload so interval changes take effect without logout.
        try? runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path])
        let out = try runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        if out.contains("error") { WatchdogLog.append("launchctl bootstrap: \(out)") }
    }

    static func uninstall() throws {
        try? runLaunchctl(["bootout", "gui/\(getuid())", label])
        try? runLaunchctl(["unload", plistURL.path]) // legacy fallback
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static var isLoaded: Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        probe.arguments = ["print", "gui/\(getuid())/\(label)"]
        probe.standardOutput = Pipe()
        probe.standardError = Pipe()
        do {
            try probe.run()
            probe.waitUntilExit()
            return probe.terminationStatus == 0
        } catch {
            return false
        }
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw InstallError.launchctl(error.localizedDescription)
        }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 && !args.isEmpty {
            // bootstrap on an already-loaded agent fails benignly — treat as ok
            // when the agent is in fact loaded.
            if args.first == "bootstrap" && isLoaded { return output }
            throw InstallError.launchctl(output.isEmpty ? "exit \(process.terminationStatus)" : output)
        }
        return output
    }

    // Cron fallback (documented only — do not install by default).
    // 0 2 */3 * * /Applications/Jupiter.app/Contents/MacOS/Jupiter --watchdog-run
    static let cronLine = "0 2 */3 * * /Applications/Jupiter.app/Contents/MacOS/Jupiter --watchdog-run"
}
