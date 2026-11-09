import SwiftUI
import AppKit

@main
struct JupiterApp: App {
    /// launchd runs `Jupiter --watchdog-run` headless every N days.
    /// The UI scene is never built in that mode — the watchdog runner
    /// cleans Safe caches in the background and exits before any window.
    /// Quitting Jupiter does NOT stop it; launchd owns the schedule.
    init() {
        if CommandLine.arguments.contains("--watchdog-run") {
            WatchdogRunner.runAndExit()
        }
    }

    var body: some Scene {
        WindowGroup {
            ShellView()
        }
        // Transparent title bar: traffic lights float, top 52 pt is the page color (§5).
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 620)
    }
}
