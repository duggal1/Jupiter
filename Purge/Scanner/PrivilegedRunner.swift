import Foundation
#if canImport(Darwin)
import Darwin
import CoreGraphics
#endif

/// Runs a privileged command without asking for a password every time.
///
/// ## The problem
///
/// `osascript -e 'do shell script "…" with administrator privileges'` spawns
/// a **fresh** authorization on every call. So every purge — including the
/// background watchdog, which cannot answer a dialog at all — raised a
/// password prompt. Measured behaviour before this change: one prompt per
/// purge, every purge.
///
/// ## The fix
///
/// Three tiers, tried in order, so the common path is silent:
///
/// 1. **`sudo -n`** — non-interactive. Uses an existing sudo ticket. No
///    prompt. This is the path that runs every time after the first unlock.
/// 2. **`sudo -v` with askpass** — if no ticket is live, `sudo` asks its
///    askpass helper for the password. The helper is a tiny script that
///    shows the standard macOS password sheet. **One** prompt, then `sudo`
///    holds a timestamp ticket (default 5 min).
/// 3. **`osascript … with administrator privileges`** — the original path.
///    Used when `sudo` is unavailable or misconfigured. Always prompts, so
///    it is the last resort, not the first.
///
/// ## Why not `AuthorizationExecuteWithPrivileges`
///
/// It is the classic API for this, but it is unavailable in Swift
/// (`'AuthorizationExecuteWithPrivileges' is unavailable in macOS: APIs
/// deprecated as of macOS 10.9 and earlier are unavailable in Swift`) and it
/// is deprecated by Apple in favour of `SMJobBless`, which needs a signed
/// helper tool and a launchd job — far more machinery than this app needs.
/// `sudo` is already on every Mac, already integrates with the system
/// password sheet, and already implements ticket caching.
///
/// ## Ticket keepalive
///
/// The sudo timestamp is short-lived (5 minutes by default). After a
/// successful `sudo -v`, the runner schedules a background refresh so the
/// ticket stays alive while the app is open. If the refresh fails (ticket
/// expired, password changed), the next privileged call falls back to
/// asking — the clean still happens, it just prompts again.
enum PrivilegedRunner {
    enum PrivilegedError: LocalizedError {
        case sudoUnavailable
        case noGUISession
        case rejected
        case commandFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .sudoUnavailable: return "sudo is not available on this Mac."
            case .noGUISession: return "Administrator access needs a signed-in session."
            case .rejected: return "Administrator access was declined."
            case .commandFailed(let code, let message):
                return message.isEmpty ? "Command failed (exit \(code))." : message
            }
        }
    }

    /// Runs `tool` with elevated privileges. Throws on failure.
    ///
    /// `allowPrompt` must be `false` for background work (the watchdog).
    /// A headless launchd job has no window server session, so a password
    /// dialog would hang the job instead of failing it.
    static func run(tool: String, arguments: [String] = [], allowPrompt: Bool = true) async throws {
        let result = await Task.detached(priority: .userInitiated) {
            runSync(tool: tool, arguments: arguments, allowPrompt: allowPrompt)
        }.value
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    /// Whether a GUI session exists to host a password dialog.
    /// `CGSessionCopyCurrentDictionary` returns nil when there is no Aqua
    /// session (a launchd job, an SSH shell, a daemon).
    static var hasGUISession: Bool {
        CGSessionCopyCurrentDictionary() != nil
    }

    /// Whether a privileged command can run right now without prompting.
    static func hasLiveTicket() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "true"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Synchronous implementation

    private enum Result {
        case success
        case failure(Error)
    }

    private static func runSync(tool: String, arguments: [String], allowPrompt: Bool) -> Result {
        // Tier 1 — silent, uses an existing ticket. A non-zero exit means
        // "no ticket", not "failed", so fall through to tier 2.
        if let status = execute(sudo: true, nonInteractive: true, tool: tool, arguments: arguments), status == 0 {
            return .success
        }
        // Tier 2 — one askpass prompt, then reuse the ticket.
        // Only when a prompt can actually be shown.
        if allowPrompt, hasGUISession {
            if let status = execute(sudo: true, nonInteractive: false, tool: tool, arguments: arguments) {
                if status == 0 {
                    scheduleTicketRefresh()
                    return .success
                }
                // sudo ran and the user declined or the password was wrong.
                // Do not prompt again with a different dialog.
                return .failure(PrivilegedError.rejected)
            }
            // Tier 3 — sudo is unusable on this machine. The original osascript
            // path, which always prompts.
            return runViaOSAScript(tool: tool, arguments: arguments)
        }
        // Headless: a prompt cannot be shown. Fail cleanly instead of hanging.
        return .failure(PrivilegedError.noGUISession)
    }

    /// Runs `sudo <tool> <args>`. `nonInteractive` adds `-n` (never prompt).
    /// Returns the exit status, or `nil` when `sudo` is unusable.
    private static func execute(sudo: Bool, nonInteractive: Bool, tool: String, arguments: [String]) -> Int32? {
        let sudoPath = "/usr/bin/sudo"
        guard FileManager.default.fileExists(atPath: sudoPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sudoPath)
        var args: [String] = []
        if nonInteractive { args.append("-n") }
        if !nonInteractive {
            // Askpass: show the standard macOS password sheet instead of a
            // terminal prompt. The helper writes the password to stdout.
            args += ["-A"]
            process.environment = askpassEnvironment()
        }
        args += [tool] + arguments
        process.arguments = args
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0, message.localizedCaseInsensitiveContains("unknown user") {
            return nil
        }
        return process.terminationStatus
    }

    /// Environment for `sudo -A`: point at our askpass helper.
    private static func askpassEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["SUDO_ASKPASS"] = askpassHelperPath
        environment["SUDO_ASKPASS_REQUIRE"] = "force"
        return environment
    }

    /// Path to the askpass helper script. Written on demand into the user's
    /// caches directory; it only ever shows a password dialog and prints
    /// what the user typed on stdout.
    private static var askpassHelperPath: String {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Jupiter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("askpass.sh")
        // The AppleScript must be a single line: AppleScript has no line
        // continuation, so a trailing backslash is a syntax error.
        let body = """
        #!/bin/sh
        # Jupiter askpass: shows the system password sheet and prints the
        # result on stdout for `sudo -A`. Nothing is stored.
        exec /usr/bin/osascript <<'APPLESCRIPT'
        display dialog "Jupiter needs administrator access to purge the file cache." default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK"
        text returned of result
        APPLESCRIPT
        """
        if !FileManager.default.fileExists(atPath: script.path) {
            try? body.write(to: script, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        }
        return script.path
    }

    /// The original path: one `osascript` authorization, exactly as before.
    private static func runViaOSAScript(tool: String, arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let command = ([tool] + arguments)
            .map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: " ")
        process.arguments = ["-e", "do shell script \"\(command)\" with administrator privileges"]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(PrivilegedError.sudoUnavailable)
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "purge failed"
            return .failure(PrivilegedError.commandFailed(process.terminationStatus, message))
        }
        return .success
    }

    // MARK: - Ticket keepalive

    private static var refreshTask: Task<Void, Never>?

    /// Keeps the sudo timestamp alive while the app is open, so the next
    /// privileged command is silent. Cancelled when the app exits.
    private static func scheduleTicketRefresh() {
        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .background) {
            // The default sudo ticket lives 5 minutes; refresh at 2 so it
            // never lapses while the app is in the foreground.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                if Task.isCancelled { break }
                guard hasLiveTicket() else { break }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["-n", "-v"] // validate without prompting
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    break
                }
            }
        }
    }

    /// Stops the keepalive. Called when the app terminates.
    static func stopKeepalive() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
