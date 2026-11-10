import SwiftUI
import AppKit

/// Toggle: 40 × 24 track, 20 knob (26 pressed), inset 2, off = controlPressed,
/// on = accent, white knob, snappy 0.22.
///
/// ## Knob travel
///
/// The knob grows when pressed (20 → 26). The travel offset has to follow
/// that growth, or the knob leaves the track: with a fixed offset of 18 the
/// pressed knob spans 18…44 inside a 40 pt track — 4 pt outside, and 1 pt
/// above and below vertically.
///
/// The knob is therefore positioned by its **leading edge relative to the
/// track**, and the offset is derived from the knob's current diameter:
/// `travel = trackWidth - knobDiameter - inset` on the "on" side. The outer
/// inset is then exactly 2 pt at every size, pressed or not.
struct AppToggle: View {
    @Binding var isOn: Bool
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    // MARK: - Geometry

    private static let trackWidth: CGFloat = 40
    private static let trackHeight: CGFloat = 24
    private static let knobIdle: CGFloat = 20
    private static let knobPressed: CGFloat = 26
    private static let inset: CGFloat = 2
    /// Vertical room for the pressed knob so it never crops the track.
    private static let hitHeight: CGFloat = 32

    private var knobDiameter: CGFloat {
        pressed ? Self.knobPressed : Self.knobIdle
    }

    /// Leading edge of the knob inside the track.
    /// Off: flush to the inset. On: flush to the opposite inset.
    private var knobOffset: CGFloat {
        isOn
            ? Self.trackWidth - knobDiameter - Self.inset
            : Self.inset
    }

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
                    .frame(width: Self.trackWidth, height: Self.trackHeight)
                Circle()
                    .fill(.white)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .offset(x: knobOffset)
                    .animation(Motion.press(reduceMotion: reduceMotion), value: pressed)
                    .animation(
                        reduceMotion ? nil : .timingCurve(0.0, 0, 0, 1, duration: 0.22),
                        value: isOn
                    )
            }
            .frame(width: Self.trackWidth, height: Self.hitHeight)
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
