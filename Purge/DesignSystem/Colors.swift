import SwiftUI
import AppKit

/// Design tokens — exact values from DESIGN.md §1 (sRGB, dynamic).
/// No hex outside this file.
enum Tok {
    // Surfaces
    static let bg = Color.dynamic(light: 0xF4F4F4, dark: 0x0A0A0A)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x171717)
    static let well = Color.dynamic(light: 0xEDEDED, dark: 0x0F0F0F)
    static let control = Color.dynamic(light: 0xEBEBEB, dark: 0x1F1F1F)
    static let controlHover = Color.dynamic(light: 0xE3E3E3, dark: 0x262626)
    static let controlPressed = Color.dynamic(light: 0xDADADA, dark: 0x2E2E2E)
    static let field = Color.dynamic(light: 0xEAEAEA, dark: 0x101010)
    static let fieldHover = Color.dynamic(light: 0xE3E3E3, dark: 0x151515)
    static let island = Color(hex: 0x000000)

    // Text — two levels only
    static let text = Color.dynamic(light: 0x0A0A0A, dark: 0xFAFAFA)
    static let text2 = Color.dynamic(light: 0x666666, dark: 0xA3A3A3)
    static let textAction = Color.dynamic(light: 0x2E2E2E, dark: 0xE5E5E5)

    // Accent — Blue 600, the only brand color
    static let accent = Color(hex: 0x2563EB)
    static let accentHover = Color.dynamic(light: 0x1D4ED8, dark: 0x3B82F6)
    static let accentPressed = Color(hex: 0x1D4ED8)
    static let accentText = Color.dynamic(light: 0x2563EB, dark: 0x60A5FA)
    static let accentSoft = Color.dynamic(light: (0xDBEAFE, 1), dark: (0x2563EB, 0.17))
    static let accentFill = Color.dynamic(light: (0xDBEAFE, 1), dark: (0x2563EB, 0.50))
    static let onAccent = Color.white

    // Status / diff
    static let statusOK = Color.dynamic(light: 0x16A34A, dark: 0x4ADE80)
    static let statusBad = Color.dynamic(light: 0xDC2626, dark: 0xF87171)
    static let diffStrong = Color.dynamic(light: 0x93C5FD, dark: 0x1D4ED8)
    static let diffSoft = Color.dynamic(light: 0xDBEAFE, dark: 0x1E3A8A)
    static let diffInk = Color.dynamic(light: 0x0A0A0A, dark: 0xFFFFFF)

    // Washes / scrims
    static let wash = Color.dynamic(light: (0x000000, 0.05), dark: (0xFFFFFF, 0.07))
    static let washStrong = Color.dynamic(light: (0x000000, 0.09), dark: (0xFFFFFF, 0.12))
    static let modalScrim = Color.dynamic(light: (0x000000, 0.28), dark: (0x000000, 0.55))
    static let scrim = Color(hex: 0x000000).opacity(0.18)
}

/// Graph categories only — the app chrome stays Blue 600 (§1.3).
/// The four composition colors: blue, fuchsia, orange, violet.
enum GraphPalette {
    static let categories: [Color] = [
        Color(hex: 0x2563EB), // blue
        Color(hex: 0xD946EF), // fuchsia
        Color(hex: 0xF97316), // orange
        Color(hex: 0x8B5CF6), // violet
    ]

    static func color(forRank rank: Int) -> Color {
        categories[rank % categories.count]
    }
}

enum Ramp {
    static let blue: [Color] = [
        Color.dynamic(light: 0xE9E9E9, dark: 0x171717),
        Color.dynamic(light: 0xDBEAFE, dark: 0x172554),
        Color.dynamic(light: 0x93C5FD, dark: 0x1E3A8A),
        Color(hex: 0x2563EB),
        Color.dynamic(light: 0x1E3A8A, dark: 0x60A5FA),
    ]
    static let heat: [Color] = [
        Color.dynamic(light: 0xDBEAFE, dark: 0x1E3A8A),
        Color.dynamic(light: 0x93C5FD, dark: 0x1D4ED8),
        Color(hex: 0x2563EB),
        Color.dynamic(light: 0x1D4ED8, dark: 0x60A5FA),
    ]
}

extension Color {
    static func hex(_ value: Int) -> Color {
        Color(nsColor: nsColorFromHex(value, alpha: 1))
    }

    init(hex: Int) {
        self.init(nsColor: Color.nsColorFromHex(hex, alpha: 1))
    }

    static func dynamic(light: (Int, Double), dark: (Int, Double)) -> Color {
        Color(nsColor: dynamicNSColor(light: light, dark: dark))
    }

    static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: dynamicNSColor(light: (light, 1), dark: (dark, 1)))
    }

    static func dynamicNSColor(light: (Int, Double), dark: (Int, Double)) -> NSColor {
        let lightColor = nsColorFromHex(light.0, alpha: light.1)
        let darkColor = nsColorFromHex(dark.0, alpha: dark.1)
        return NSColor(name: nil) { appearance in
            let isDark = appearance.name == NSAppearance.Name.darkAqua
            return isDark ? darkColor : lightColor
        }
    }

    static func nsColorFromHex(_ value: Int, alpha: Double) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

extension View {
    /// Increase Contrast adds a 1 pt Color.primary @ 35% stroke. The only stroke in the app.
    func contrastStroke(radius: CGFloat = 16) -> some View {
        overlay {
            if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.primary.opacity(0.35), lineWidth: 1)
            }
        }
    }
}
