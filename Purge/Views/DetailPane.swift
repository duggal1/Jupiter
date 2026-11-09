import SwiftUI

/// Detail: page bar 52 with serif title + pixel stop, readout subtitle,
/// one primary action (Clean). Rows 44 with AppToggle, badge, size.
/// Hover = control fill. No dividers, no edge accents.
struct DetailPane: View {
    @Bindable var viewModel: ScanViewModel
    @Binding var showingCleanDialog: Bool
    @Binding var pane: AppPane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            pageBar
            if !viewModel.hasFDA {
                NoticeRow(
                    message: "Full Disk Access lets Jupiter see Mail attachments and other protected folders.",
                    primaryTitle: "Open Settings",
                    primaryAction: { NSWorkspace.shared.open(ScanViewModel.fdaDeepLink) }
                )
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
            switch viewModel.phase {
            case .notScanned:
                EmptyState(viewModel: viewModel)
            case .scanning:
                if viewModel.totalJunk > 0 {
                    CompositionGraph(sorted: viewModel.sortedCategories, total: viewModel.totalJunk)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }
                contentList
            case .results, .cleaning, .cleaned:
                if viewModel.phase == .cleaning {
                    CleaningProgress(viewModel: viewModel, reduceMotion: reduceMotion)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
                if viewModel.totalJunk > 0 {
                    CompositionGraph(sorted: viewModel.sortedCategories, total: viewModel.totalJunk)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }
                contentList
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.selectedCategoryKind)
    }

    private var pageBar: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Text(titleText)
                    .font(AppType.pageTitle)
                    .tracking(-1.4)
                    .lineSpacing(0.98)
                    .lineLimit(1)
                    .layoutPriority(2)
                    .foregroundStyle(Tok.text)
                PixelStop(cell: 1.5)
                    .frame(width: 7.5, height: 7.5)
                    .offset(y: 8)
                    .layoutPriority(2)
            }
            Spacer()
            Text(readout)
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
                .lineLimit(1)
            QuietButton(title: scanButtonTitle) {
                viewModel.scan()
            }
            SecondaryButton(
                title: "Memory",
                disabled: viewModel.phase == .cleaning || viewModel.phase == .scanning
            ) {
                pane = .memory
            }
            SecondaryButton(
                title: "Auto-clean",
                disabled: viewModel.phase != .results && viewModel.phase != .cleaned
            ) {
                viewModel.autoClean()
            }
            PrimaryButton(
                title: cleanTitle,
                disabled: viewModel.phase == .cleaned || viewModel.totalSelected == 0 || viewModel.phase == .cleaning || viewModel.phase == .scanning
            ) {
                showingCleanDialog = true
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 32)
    }

    private var titleText: String {
        viewModel.selectedCategory?.kind.rawValue ?? "Jupiter"
    }

    private var readout: String {
        switch viewModel.phase {
        case .notScanned: return "Nothing scanned yet."
        case .scanning:
            let done = viewModel.categories.filter(\.didScan).count
            return "Scanning \(done)/\(viewModel.categories.count) categories."
        case .results:
            return viewModel.totalSelected > 0
                ? "\(viewModel.selectedItemCount) selected · \(ByteCountFormatter.string(fromByteCount: viewModel.totalSelected, countStyle: .file))"
                : "Nothing selected."
        case .cleaning:
            let freed = ByteCountFormatter.string(fromByteCount: viewModel.cleanFreed, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: viewModel.cleanTotal, countStyle: .file)
            let pct = Int((viewModel.cleanProgress * 100).rounded())
            return "Freed \(freed) of \(total) · \(pct)% (\(viewModel.cleanDoneCount)/\(viewModel.cleanTotalCount))"
        case .cleaned:
            if let freed = viewModel.lastFreed {
                let f = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
                return viewModel.lastFailed > 0 ? "Freed \(f). \(viewModel.lastFailed) failed." : "Freed \(f)."
            }
            return "Done."
        }
    }

    private var scanButtonTitle: String {
        viewModel.phase == .notScanned ? "Scan" : "Rescan"
    }

    private var cleanTitle: String {
        if viewModel.phase == .cleaned { return "Cleaned" }
        if viewModel.phase == .cleaning { return "Cleaning…" }
        return viewModel.totalSelected > 0
            ? "Clean \(ByteCountFormatter.string(fromByteCount: viewModel.totalSelected, countStyle: .file))"
            : "Clean"
    }

    private var contentList: some View {
        Group {
            if let category = viewModel.selectedCategory {
                List {
                    sectionHeader(for: category)
                    ForEach(Array(category.items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(item: item, viewModel: viewModel)
                            .id(item.id)
                            .transition(
                                reduceMotion
                                    ? .identity
                                    : .opacity.combined(with: .offset(y: 6))
                            )
                            .animation(
                                reduceMotion
                                    ? nil
                                    : .timingCurve(0.23, 1, 0.32, 1, duration: 0.28)
                                        .delay(Double(min(index, 24)) * 0.035),
                                value: category.items.count
                            )
                    }
                    if category.items.isEmpty {
                        Text(category.didScan ? "Nothing found." : "Scanning…")
                            .font(AppType.body)
                            .foregroundStyle(Tok.text2)
                            .frame(height: 44)
                    }
                    if category.kind.requiresFDA && !viewModel.hasFDA && category.didScan {
                        Text("Mail stays hidden until Full Disk Access is on.")
                            .font(AppType.caption)
                            .foregroundStyle(Tok.text2)
                    }
                    if category.kind == .downloadsMailBackups && !viewModel.includeDownloads {
                        HStack(spacing: 8) {
                            Text("Downloads is hidden until you include it.")
                                .font(AppType.caption)
                                .foregroundStyle(Tok.text2)
                            QuietButton(title: "Include") {
                                viewModel.includeDownloads = true
                                viewModel.scan()
                            }
                        }
                        .frame(height: 32)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Tok.bg)
            } else if viewModel.phase == .scanning {
                VStack(spacing: 12) {
                    Spacer()
                    WaitCells()
                    Text("Scanning…")
                        .font(AppType.body)
                        .foregroundStyle(Tok.text2)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tok.bg)
            } else {
                EmptyState(viewModel: viewModel)
            }
        }
    }

    private func sectionHeader(for category: JunkCategory) -> some View {
        HStack(spacing: 12) {
            TickMeter(fraction: category.selectedSize > 0 ? Double(category.selectedSize) / max(Double(category.totalSize), 1) : 0, width: 180)
            Text(ByteCountFormatter.string(fromByteCount: category.totalSize, countStyle: .file))
                .font(AppType.title)
                .monospacedDigit()
                .foregroundStyle(Tok.text)
            Spacer()
            if category.selectedSize > 0 {
                Text("\(ByteCountFormatter.string(fromByteCount: category.selectedSize, countStyle: .file)) selected")
                    .font(AppType.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.accentText)
            }
        }
        .frame(height: 44)
        .listRowSeparator(.hidden)
        .listRowBackground(Tok.bg)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(footerLine)
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
            Spacer()
            if viewModel.phase == .results {
                QuietButton(title: "Select safe") { viewModel.selectSafe() }
                QuietButton(title: "Safe + Okay") { viewModel.selectSafeAndOkay() }
                QuietButton(title: "Clear") { viewModel.clearSelection() }
            } else if viewModel.phase == .cleaned && viewModel.lastFailed > 0 {
                if let note = viewModel.lastFailureNote {
                    Text(note)
                        .font(AppType.caption)
                        .foregroundStyle(Tok.statusBad)
                        .lineLimit(1)
                }
                QuietButton(title: "Retry") { showingCleanDialog = true }
            }
            if viewModel.phase == .scanning || viewModel.phase == .cleaning {
                WaitCells()
                QuietButton(title: "Cancel") {
                    if viewModel.phase == .scanning { viewModel.cancelScan() }
                    else { viewModel.cancelClean() }
                }
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 32)
    }

    private var footerLine: String {
        switch viewModel.phase {
        case .notScanned: return "Press ⌘R to scan."
        case .scanning: return "Measuring allocated sizes."
        case .results: return "Only Safe items regenerate automatically. Okay costs time. Risky deletes data."
        case .cleaning: return "Cleaning files to Trash and Docker via docker prune — Safe + Okay, never Risky."
        case .cleaned:
            if let freed = viewModel.lastFreed {
                var line = "Freed \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))."
                if let note = viewModel.ramNote {
                    line += " \(note)"
                }
                return line
            }
            return "Done."
        }
    }
}

private struct EmptyState: View {
    let viewModel: ScanViewModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            PixelEmptyStop(cell: 3)
                .frame(width: 33, height: 33)
            Text(viewModel.phase == .notScanned ? "Not scanned yet." : "Select a category.")
                .font(AppType.title)
                .foregroundStyle(Tok.text)
            Text("Press ⌘R to scan.")
                .font(AppType.body)
                .foregroundStyle(Tok.text2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tok.bg)
    }
}

/// Live pixel stream while cleaning: tick bar drains + MB-of-GB text.
/// Transform/opacity only — no timers, no blur. Rows dissolve beneath it.
private struct CleaningProgress: View {
    let viewModel: ScanViewModel
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Cleaning")
                    .font(AppType.label)
                    .foregroundStyle(Tok.text)
                TickMeter(fraction: viewModel.cleanProgress, width: 180)
                Spacer()
                Text(streamText)
                    .font(AppType.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.accentText)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Motion.drain, value: viewModel.cleanFreed)
            }
            if let current = viewModel.cleanCurrent {
                HStack(spacing: 6) {
                    PixelDisc(cell: 1)
                        .frame(width: 5, height: 5)
                    Text(current)
                        .font(AppType.caption)
                        .foregroundStyle(Tok.text2)
                        .lineLimit(1)
                    Text("· \(viewModel.cleanDoneCount)/\(viewModel.cleanTotalCount)")
                        .font(AppType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Tok.text2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
    }

    private var streamText: String {
        let freed = ByteCountFormatter.string(fromByteCount: viewModel.cleanFreed, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: viewModel.cleanTotal, countStyle: .file)
        let pct = Int((viewModel.cleanProgress * 100).rounded())
        return "Freed \(freed) of \(total) · \(pct)%"
    }
}

private struct ItemRow: View {
    let item: JunkItem
    let viewModel: ScanViewModel
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let maxSize: Int64

    init(item: JunkItem, viewModel: ScanViewModel) {
        self.item = item
        self.viewModel = viewModel
        self.maxSize = viewModel.maxItemSize
    }

    /// Info-only rows (Docker.raw, VM disks) are size-only — never selectable.
    private var isSelectable: Bool {
        item.cleanAction != .infoOnly
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelectable {
                AppToggle(isOn: Binding(get: { item.isSelected }, set: { item.isSelected = $0 }))
            } else {
                PixelExclamation(cell: 1, color: Tok.text2)
                    .frame(width: 20)
                    .accessibilityLabel("Info only — not selectable")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(AppType.label)
                    .foregroundStyle(Tok.text)
                    .lineLimit(1)
                if let detail = item.detail {
                    Text(detail)
                        .font(AppType.caption)
                        .foregroundStyle(item.safety.isDestructive ? Tok.statusBad : Tok.text2)
                        .lineLimit(1)
                } else {
                    Text(item.safety.blurb)
                        .font(AppType.caption)
                        .foregroundStyle(Tok.text2)
                        .lineLimit(1)
                }
                if let error = item.error {
                    HStack(alignment: .top, spacing: 4) {
                        PixelFailed(cell: 1)
                            .frame(width: 5, height: 5)
                            .padding(.top, 2)
                        Text(error)
                            .font(AppType.caption)
                            .foregroundStyle(Tok.statusBad)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TickMeter(fraction: Double(item.size) / Double(max(maxSize, 1)), width: 64)
                .frame(width: 64)
            SafetyBadge(safety: item.safety)
            Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                .font(AppType.body)
                .monospacedDigit()
                .foregroundStyle(Tok.text2)
                .frame(width: 72, alignment: .trailing)
        }
        .frame(minHeight: item.error != nil ? 60 : 44)
        .padding(.vertical, item.error != nil ? 6 : 0)
        .contentShape(Rectangle())
        .background(hovering ? Tok.control : .clear, in: RoundedRectangle(cornerRadius: 8))
        .motionPress(pressed: pressed, reduceMotion: reduceMotion)
        .onHover { hovering = $0 }
        .animation(Motion.hover(hovering: hovering, reduceMotion: reduceMotion), value: hovering)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .listRowSeparator(.hidden)
        .listRowBackground(Tok.bg)
        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
    }
}
