import SwiftUI

/// Shell (§7): custom HStack of sidebar and detail on bg. No NavigationSplitView,
/// no system toolbar. Route change = opacity cross-fade only.
struct ShellView: View {
    @State private var viewModel = ScanViewModel()
    @State private var watchdogViewModel = WatchdogViewModel()
    @State private var memoryViewModel = MemoryViewModel()
    @State private var showingCleanDialog = false
    @State private var pane: AppPane = .clean
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarPane(viewModel: viewModel, pane: $pane, watchdogViewModel: watchdogViewModel)
                Tok.bg
                    .frame(width: 1)
                Group {
                    if pane == .watchdog {
                        WatchdogPane(viewModel: watchdogViewModel)
                    } else if pane == .memory {
                        MemoryPane(viewModel: memoryViewModel, pane: $pane)
                    } else {
                        DetailPane(viewModel: viewModel, showingCleanDialog: $showingCleanDialog, pane: $pane)
                    }
                }
                .transition(reduceMotion ? .identity : .opacity)
            }
            .background(Tok.bg)

            // Dialog layer above content.
            if showingCleanDialog {
                CleanConfirmDialog(viewModel: viewModel, isPresented: $showingCleanDialog)
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .background(Tok.bg)
        .focusEffectDisabled()
        .onAppear { viewModel.scan() }
    }
}

/// Top-level pane routing: Clean (scan/detail) vs Watchdog vs Memory.
/// Watchdog lives in the sidebar; Memory opens from the Detail page bar —
/// intentionally not a sidebar row.
enum AppPane: Hashable {
    case clean
    case watchdog
    case memory
}

/// System blur behind the sidebar (the blur exception in §1).
struct SidebarBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
