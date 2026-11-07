import SwiftUI

/// Clean confirmation: DialogLayer (§6.4) 480 wide, surface, radius 16,
/// padding 24. Header disc + title + caption subtitle. Footer Cancel
/// secondary 32 + confirm primary 32, 8 apart right aligned. Esc cancels.
/// Note: ⌘Return is wired on the primary button.
struct CleanConfirmDialog: View {
    @Bindable var viewModel: ScanViewModel
    @Binding var isPresented: Bool

    var body: some View {
        AppDialogLayer(isPresented: isPresented) {
            VStack(alignment: .leading, spacing: 16) {
                DialogHeader(
                    title: viewModel.confirmationTitle,
                    subtitle: viewModel.confirmationMessage
                )
                HStack(spacing: 8) {
                    PixelCheck(cell: 1)
                        .frame(width: 7, height: 5)
                    Text("\(viewModel.selectedItemCount) selected · \(ByteCountFormatter.string(fromByteCount: viewModel.totalSelected, countStyle: .file))")
                        .font(AppType.body)
                        .monospacedDigit()
                        .foregroundStyle(Tok.text2)
                }
                if viewModel.totalSelected > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        breakdownRow(safety: .safe)
                        breakdownRow(safety: .okay)
                        breakdownRow(safety: .risky)
                        if viewModel.selectedSize(for: .risky) > 0 {
                            Text("Risky items include browser profiles — deleting removes your whole Chrome data: history, logins and personal files. This cannot be undone after Trash is emptied.")
                                .font(AppType.caption)
                                .foregroundStyle(Tok.statusBad)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
                }
                DialogFooter(
                    cancelTitle: "Cancel",
                    confirmTitle: "Move to Trash",
                    confirmDisabled: viewModel.totalSelected == 0
                ) {
                    isPresented = false
                } onConfirm: {
                    isPresented = false
                    viewModel.confirmClean()
                }
            }
        } onDismiss: {
            isPresented = false
        }
        .onExitCommand {
            isPresented = false
        }
    }

    @ViewBuilder
    private func breakdownRow(safety: Safety) -> some View {
        let count = viewModel.selectedCount(for: safety)
        let size = viewModel.selectedSize(for: safety)
        HStack(spacing: 8) {
            SafetyBadge(safety: safety)
            Text(safety.blurb)
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
                .lineLimit(1)
            Spacer()
            Text(count > 0 ? "\(count) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))" : "0")
                .font(AppType.caption)
                .monospacedDigit()
                .foregroundStyle(count > 0 ? Tok.text2 : Tok.text2.opacity(0.5))
        }
    }
}
