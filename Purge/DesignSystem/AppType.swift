import SwiftUI
import AppKit

/// Type roles from DESIGN.md §4. Weights 350/500 only — nothing above Medium.
enum AppType {
    static let caption: Font = .system(size: 12, weight: .regular)
    static let body: Font = .system(size: 13, weight: .regular)
    static let label: Font = .system(size: 13, weight: .medium)
    static let reading: Font = .system(size: 15, weight: .regular)
    static let title: Font = .system(size: 15, weight: .medium)
    static let metric: Font = .system(size: 28, weight: .medium)

    /// Page titles: serif italic 28, tracking −1.4. Never below 28.
    static let pageTitle: Font = .system(size: 28, weight: .medium, design: .serif).italic()
}

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

/// Hand cursor via clickable().
extension View {
    func clickable() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
