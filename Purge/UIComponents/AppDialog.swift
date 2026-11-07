import SwiftUI

/// DialogLayer (§6.4): scrim covers title bar + sidebar. Panel 480 wide,
/// surface, radius 16, padding 24. Header disc + title + caption subtitle.
/// Footer Cancel (secondary 32) + confirm (primary 32), 8 apart right aligned.
/// Opens scale 0.97 + 6 pt rise + fade, closes 120 ms. Esc cancels, ⌘Return confirms.
struct AppDialogLayer<Content: View>: View {
    let isPresented: Bool
    @ViewBuilder let content: () -> Content
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            if isPresented {
                Tok.modalScrim
                    .ignoresSafeArea()
                    .opacity(appeared ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                dialogPanel
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.97)
                    .offset(y: appeared ? 0 : 6)
                    .onAppear {
                        if reduceMotion {
                            appeared = true
                        } else {
                            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)) {
                                appeared = true
                            }
                        }
                    }
                    .onDisappear {
                        appeared = false
                    }
            }
        }
    }

    private var dialogPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .frame(width: 480)
        .padding(24)
        .background(Tok.surface.clipShape(RoundedRectangle(cornerRadius: 16)))
        .contrastStroke(radius: 16)
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
    }
}

/// Dialog header: 7 × 7 pixel disc + title + one-line caption subtitle.
struct DialogHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 8) {
            PixelDisc(cell: 2)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppType.title)
                    .foregroundStyle(Tok.text)
                Text(subtitle)
                    .font(AppType.caption)
                    .foregroundStyle(Tok.text2)
            }
        }
    }
}

/// Dialog footer: Cancel secondary 32 + confirm primary 32, 8 apart right aligned.
struct DialogFooter: View {
    let cancelTitle: String
    let confirmTitle: String
    let confirmDisabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            SecondaryButton(title: cancelTitle, height: .dialog) { onCancel() }
            PrimaryButton(title: confirmTitle, height: .dialog, disabled: confirmDisabled, shortcut: .return) { onConfirm() }
        }
    }
}
