import SwiftUI

/// Sidebar 220, rows 32 tall 2 apart, first row at y = 52, icon column 20,
/// one sliding washStrong capsule. Status footer: 20 pt pixel mark + one word.
struct SidebarPane: View {
    @Bindable var viewModel: ScanViewModel
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Solid Tok.bg — behindWindow blur in dark mode lifts toward the
        // desktop (green), breaking the near-black luminance steps. Sharpness
        // wins: one flat surface step, no glass.
        VStack(spacing: 0) {
            reclaimHeader
            categoryRows
            Spacer()
            statusFooter
        }
        .frame(width: 220)
        .frame(height: .infinity)
        .background(Tok.bg)
    }

    private var reclaimHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reclaimTitle)
                .font(AppType.metric)
                .monospacedDigit()
                .foregroundStyle(Tok.text)
                .contentTransition(.numericText())
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28), value: viewModel.totalSelected)
            Text(viewModel.totalJunk > 0
                 ? "\(ByteCountFormatter.string(fromByteCount: viewModel.totalJunk, countStyle: .file)) of junk"
                 : subtitle)
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
            // The pixel move: selected fraction fills the tick track, tip white.
            TickMeter(fraction: meterFraction, width: 180)
        }
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 20)
    }

    private var reclaimTitle: String {
        if viewModel.phase == .cleaned, let freed = viewModel.lastFreed {
            return ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
        }
        if viewModel.totalSelected > 0 {
            return ByteCountFormatter.string(fromByteCount: viewModel.totalSelected, countStyle: .file)
        }
        return viewModel.phase == .notScanned ? "—" : "0 B"
    }

    private var subtitle: String {
        switch viewModel.phase {
        case .notScanned: "Not scanned"
        case .scanning: "Scanning…"
        case .results: "Nothing selected"
        case .cleaning: "Cleaning…"
        case .cleaned: "Done"
        }
    }

    private var meterFraction: Double {
        guard viewModel.totalJunk > 0 else { return 0 }
        return Double(viewModel.totalSelected) / Double(viewModel.totalJunk)
    }

    private var categoryRows: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 2) {
                if viewModel.phase == .scanning {
                    WaitCells()
                        .frame(height: 32)
                }
                ForEach(viewModel.sortedCategories) { category in
                    SidebarRow(
                        category: category,
                        isSelected: viewModel.selectedCategoryKind == category.kind,
                        pill: pill,
                        viewModel: viewModel,
                        reduceMotion: reduceMotion
                    )
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            statusMark
                .frame(width: 20, height: 20)
            Text(statusWord)
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
            Spacer()
        }
        .frame(height: 40)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusMark: some View {
        switch viewModel.phase {
        case .notScanned:
            PixelEmptyStop(cell: 1)
                .frame(width: 11, height: 11)
        case .scanning:
            WaitCells()
        case .results, .cleaning:
            PixelStop(cell: 1)
        case .cleaned:
            PixelCheck(cell: 1)
        }
    }

    private var statusWord: String {
        switch viewModel.phase {
        case .notScanned: "Ready"
        case .scanning: "Scanning"
        case .results: "Ready"
        case .cleaning: "Cleaning"
        case .cleaned: "Done"
        }
    }
}

private struct SidebarRow: View {
    let category: JunkCategory
    let isSelected: Bool
    let pill: Namespace.ID
    let viewModel: ScanViewModel
    let reduceMotion: Bool
    @State private var hovering = false
    @State private var pressed = false

    /// Worst safety present — Risky wins, then Okay, else Safe. Shown as a tiny dot so batch scans read instantly.
    private var worstSafety: Safety? {
        guard category.didScan, !category.items.isEmpty else { return nil }
        if category.items.contains(where: { $0.safety == .risky }) { return .risky }
        if category.items.contains(where: { $0.safety == .okay }) { return .okay }
        return .safe
    }

    private var safetyDot: Color {
        switch worstSafety {
        case .risky: return Tok.statusBad
        case .okay: return Tok.accentText
        case .safe: return Tok.statusOK
        case nil: return .clear
        }
    }

    var body: some View {
        SwiftUI.Button {
            viewModel.selectedCategoryKind = category.kind
            viewModel.categories.first { $0.kind == category.kind }?.isExpanded = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.kind.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Tok.text2)
                    .frame(width: 20, height: 20)
                Text(category.kind.rawValue)
                    .font(AppType.label)
                    .foregroundStyle(Tok.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let worstSafety {
                    Circle()
                        .fill(safetyDot)
                        .frame(width: 6, height: 6)
                        .opacity(hovering || isSelected ? 1 : 0.7)
                        .accessibilityLabel("\(worstSafety.title). \(worstSafety.blurb)")
                }
                Text(sizeLabel)
                    .font(AppType.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text2)
            }
            .frame(height: 32)
            .padding(.horizontal, 8)
            .background {
                if isSelected {
                    (hovering ? Tok.control : Tok.washStrong)
                        .clipShape(Capsule())
                        .matchedGeometryEffect(id: "sidebar", in: pill)
                } else if hovering {
                    Tok.control
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .motionPress(pressed: pressed, reduceMotion: reduceMotion)
        .onHover { hovering = $0 }
        .animation(Motion.hover(hovering: hovering, reduceMotion: reduceMotion), value: hovering)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .clickable()
    }

    private var sizeLabel: String {
        if viewModel.phase == .scanning && !category.didScan { return "—" }
        return ByteCountFormatter.string(fromByteCount: category.totalSize, countStyle: .file)
    }
}
