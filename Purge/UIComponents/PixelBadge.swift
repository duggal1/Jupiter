import SwiftUI

/// Pixel badges/chips (§3.6): NotchedRect(step: 2), 20 tall, padding 8,
/// 1 pt-cell bitmap + 12 pt text.
enum PixelBadgeKind {
    case active
    case installed
    case failed
    case caution
    case okay
    case risky
}

struct PixelBadge: View {
    let text: String
    let kind: PixelBadgeKind

    var body: some View {
        HStack(spacing: 4) {
            mark
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(fill.clipShape(NotchedRect(step: 2)))
    }

    private var fill: Color {
        switch kind {
        case .active: return Tok.accentSoft
        case .installed, .failed, .caution, .risky: return Tok.control
        case .okay: return Tok.accentSoft
        }
    }

    private var textColor: Color {
        switch kind {
        case .active: return Tok.accentText
        case .installed, .caution: return Tok.text2
        case .failed, .risky: return Tok.statusBad
        case .okay: return Tok.accentText
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch kind {
        case .active:
            PixelDisc(cell: 1)
        case .installed:
            PixelCheck(cell: 1)
        case .failed:
            PixelFailed(cell: 1)
        case .caution:
            PixelExclamation(cell: 1)
        case .okay:
            PixelDisc(cell: 1)
        case .risky:
            PixelExclamation(cell: 1, color: Tok.statusBad)
        }
    }
}

extension PixelBadgeKind {
    init(safety: Safety) {
        switch safety {
        case .safe: self = .installed
        case .okay: self = .okay
        case .risky: self = .risky
        }
    }
}

/// One-line Safe / Okay / Risky badge with honest meaning.
struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        PixelBadge(text: safety.title, kind: PixelBadgeKind(safety: safety))
            .accessibilityLabel("\(safety.title). \(safety.blurb)")
            .accessibilityValue(safety.blurb)
    }
}

/// NoticeRow: 40 pt control fill, radius 12, problem + one or two actions.
/// The notice is the one accent-filled control only while it exists.
struct NoticeRow: View {
    let message: String
    var primaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            PixelExclamation(cell: 1, color: Tok.text2)
                .frame(width: 5, height: 7)
            Text(message)
                .font(AppType.body)
                .foregroundStyle(Tok.text2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer()
            if let title = secondaryTitle, let action = secondaryAction {
                SecondaryButton(title: title, height: .small, action: action)
            }
            if let title = primaryTitle, let action = primaryAction {
                PrimaryButton(title: title, height: .small, action: action)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
        .contrastStroke(radius: 12)
    }
}
