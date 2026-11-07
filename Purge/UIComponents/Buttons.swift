import SwiftUI
import AppKit

/// Flat capsule buttons (DESIGN.md §6.1). Height 24/28, 32 in dialogs.
/// No edge, no shadow. Hover easeOut 0.10/0.22, press scale 0.98 (0.92 for ≤28).
private struct CapsuleButton<Label: View>: View {
    let height: CGFloat
    let normalFill: Color
    let hoverFill: Color
    let pressedFill: Color
    let labelColor: (Bool) -> Color
    let disabled: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.Button(action: action) {
            label()
                .frame(height: height)
                .padding(.horizontal, height <= 24 ? 10 : 12)
                .background(
                    (pressed ? pressedFill : (hovering ? hoverFill : normalFill))
                        .clipShape(Capsule())
                )
                .foregroundStyle(labelColor(disabled))
                .scaleEffect(reduceMotion ? 1 : (pressed ? (height <= 28 ? 0.92 : 0.98) : 1))
                .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: hovering ? 0.10 : 0.22), value: hovering)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .clickable()
    }
}

enum AppButtonHeight {
    case small
    case regular
    case dialog
    var value: CGFloat {
        switch self {
        case .small: return 24
        case .regular: return 28
        case .dialog: return 32
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var height: AppButtonHeight = .regular
    var disabled = false
    var shortcut: KeyboardShortcut?
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Disabled primary renders as a quiet control (control fill, text2).
        SwiftUI.Button(action: action) {
            Text(title)
                .font(AppType.label)
                .frame(height: height.value)
                .padding(.horizontal, height.value <= 24 ? 10 : 12)
                .background(
                    fill
                        .clipShape(Capsule())
                )
                .foregroundStyle(disabled ? Tok.text2 : Tok.onAccent)
                .scaleEffect(reduceMotion ? 1 : (pressed ? 0.98 : 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(Motion.hover(hovering: hovering, reduceMotion: reduceMotion), value: hovering)
        .animation(Motion.press(reduceMotion: reduceMotion), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .ifPresent(shortcut)
        .clickable()
    }

    private var fill: Color {
        if disabled { return Tok.control }
        if pressed { return Tok.accentPressed }
        if hovering { return Tok.accentHover }
        return Tok.accent
    }
}

struct SecondaryButton: View {
    let title: String
    var height: AppButtonHeight = .regular
    var disabled = false
    var shortcut: KeyboardShortcut?
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.Button(action: action) {
            Text(title)
                .font(AppType.label)
                .frame(height: height.value)
                .padding(.horizontal, height.value <= 24 ? 10 : 12)
                .background(
                    fill
                        .clipShape(Capsule())
                )
                .foregroundStyle(Tok.text)
                .motionPress(pressed: pressed, compact: height.value <= 24, reduceMotion: reduceMotion)
                .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(Motion.hover(hovering: hovering, reduceMotion: reduceMotion), value: hovering)
        .animation(Motion.press(reduceMotion: reduceMotion), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .ifPresent(shortcut)
        .clickable()
    }

    private var fill: Color {
        if pressed { return Tok.controlPressed }
        if hovering { return Tok.controlHover }
        return Tok.control
    }
}

struct QuietButton: View {
    let title: String
    var disabled = false
    var shortcut: KeyboardShortcut?
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.Button(action: action) {
            Text(title)
                .font(AppType.label)
                .frame(height: 28)
                .padding(.horizontal, 8)
                .background((hovering ? Tok.wash : .clear).clipShape(Capsule()))
                .foregroundStyle(hovering ? Tok.text : Tok.text2)
                .motionPress(pressed: pressed, compact: true, reduceMotion: reduceMotion)
                .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(Motion.hover(hovering: hovering, reduceMotion: reduceMotion), value: hovering)
        .animation(Motion.press(reduceMotion: reduceMotion), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .ifPresent(shortcut)
        .clickable()
    }
}

struct LinkButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.Button(action: action) {
            Text(title)
                .font(AppType.body)
                .foregroundStyle(hovering ? Tok.text : Tok.textAction)
                .motionPress(pressed: pressed, compact: true, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover(hovering: hovering, reduceMotion: reduceMotion), value: hovering)
        .animation(Motion.press(reduceMotion: reduceMotion), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .clickable()
    }
}

extension View {
    @ViewBuilder
    fileprivate func ifPresent(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut {
            keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            self
        }
    }
}

struct KeyboardShortcut {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    static let commandR = KeyboardShortcut(key: "r", modifiers: .command)
    static let delete = KeyboardShortcut(key: .delete, modifiers: .command)
    static let `return` = KeyboardShortcut(key: .return, modifiers: .command)
}


