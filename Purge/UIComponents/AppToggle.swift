import SwiftUI
import AppKit

/// Toggle: 40 × 24 track, 20 knob (26 pressed), inset 2, off = controlPressed,
/// on = accent, white knob, snappy 0.22.
struct AppToggle: View {
    @Binding var isOn: Bool
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    var body: some View {
        SwiftUI.Button {
            withAnimation(reduceMotion ? nil : .timingCurve(0.0, 0, 0, 1, duration: 0.22)) {
                isOn.toggle()
            }
            // Haptic on Macs that support it (no-op elsewhere).
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? Tok.accent : (hovering ? Tok.controlHover : Tok.controlPressed))
                    .frame(width: 40, height: 24)
                Circle()
                    .fill(.white)
                    .frame(width: pressed ? 26 : 20, height: pressed ? 26 : 20)
                    .offset(x: isOn ? 18 : 2)
                    .animation(Motion.press(reduceMotion: reduceMotion), value: pressed)
            }
            .frame(width: 40, height: 32)
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Tok.accent, lineWidth: 2)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .animation(Motion.hover(hovering: hovering, reduceMotion: reduceMotion), value: hovering)
        .animation(Motion.press(reduceMotion: reduceMotion), value: pressed)
        .accessibilityLabel(isOn ? "Included" : "Not included")
        .accessibilityValue(isOn ? "On" : "Off")
        .clickable()
    }
}
