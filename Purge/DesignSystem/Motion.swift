import SwiftUI

/// Lag-free motion: transform + opacity only, no shadow/blur/layout churn.
/// Short durations keep perceived latency ~0 while staying smooth.
enum Motion {
    /// Hover-in feels instant, hover-out relaxes.
    static func hover(hovering: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: hovering ? 0.10 : 0.22)
    }

    /// Click settle: 0.14s ease-out scale back to 1.
    static func press(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    }

    static func pressScale(pressed: Bool, compact: Bool = false) -> CGFloat {
        pressed ? (compact ? 0.94 : 0.97) : 1
    }

    static let insert = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)
    static let drain = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)
}

extension View {
    /// Composited press scale (GPU-only, no layout pass).
    func motionPress(pressed: Bool, compact: Bool = false, reduceMotion: Bool) -> some View {
        scaleEffect(reduceMotion ? 1 : Motion.pressScale(pressed: pressed, compact: compact))
            .animation(Motion.press(reduceMotion: reduceMotion), value: pressed)
    }
}
