import SwiftUI
import AppKit

/// Shell (§7): custom HStack of sidebar and detail on bg. No NavigationSplitView,
/// no system toolbar. Route change = opacity cross-fade only.
struct ShellView: View {
    @State private var viewModel = ScanViewModel()
    @State private var showingCleanDialog = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarPane(viewModel: viewModel)
                Tok.bg
                    .frame(width: 1)
                DetailPane(viewModel: viewModel, showingCleanDialog: $showingCleanDialog)
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
