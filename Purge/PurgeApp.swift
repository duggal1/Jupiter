import SwiftUI

@main
struct JupiterApp: App {
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
