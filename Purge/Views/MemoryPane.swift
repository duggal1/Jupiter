import SwiftUI

/// Memory page: one circular pixel readout, one ladder line, one clean action.
/// No paragraphs. Numbers replace sentences — backend unchanged.
struct MemoryPane: View {
    @Bindable var viewModel: MemoryViewModel
    @Binding var pane: AppPane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            pageBar
            if let snapshot = viewModel.snapshot {
                VStack(spacing: 20) {
                    heroRing(snapshot: snapshot)
                    ladderRow
                    statsRow(snapshot: snapshot)
                    purgeRow
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    WaitCells()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tok.bg)
        .opacity(1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.phase)
    }

    // MARK: - Page bar (52pt, like DetailPane)

    private var pageBar: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Text("Memory")
                    .font(AppType.pageTitle)
                    .tracking(-1.4)
                    .foregroundStyle(Tok.text)
                PixelStop(cell: 1.5)
                    .frame(width: 7.5, height: 7.5)
                    .offset(y: 8)
            }
            Spacer()
            if let snapshot = viewModel.snapshot {
                Circle()
                    .fill(pressureColor(snapshot.pressure))
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(snapshot.pressure.title)
            }
            QuietButton(title: "Back") { pane = .clean }
            QuietButton(title: "Refresh", disabled: viewModel.isWorking) {
                Task { await viewModel.refresh() }
            }
            PrimaryButton(
                title: viewModel.isWorking ? "Cleaning…" : "Clean RAM",
                disabled: viewModel.isWorking
            ) { viewModel.runClean() }
        }
        .frame(height: 52)
        .padding(.horizontal, 32)
    }

    // MARK: - Circular pixel hero

    private func heroRing(snapshot: MemoryLab.Snapshot) -> some View {
        ZStack {
            PixelRing(fraction: snapshot.availableRatio, pressure: snapshot.pressure)
                .frame(width: 220, height: 220)
            VStack(spacing: 2) {
                Text(MemoryLab.fmt(snapshot.availableBytes))
                    .font(AppType.metric)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Motion.drain, value: snapshot.availableBytes)
                Text(MemoryLab.fmt(snapshot.totalBytes))
                    .font(AppType.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text2)
                if let result = viewModel.result {
                    Text(MemoryLab.signedFmt(result.freedAvailableBytes))
                        .font(AppType.label)
                        .monospacedDigit()
                        .foregroundStyle(Tok.accentText)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : Motion.drain, value: result.freedAvailableBytes)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(MemoryLab.fmt(snapshot.availableBytes)) available of \(MemoryLab.fmt(snapshot.totalBytes)). \(snapshot.pressure.title)")
    }

    // MARK: - Ladder (four dots, one tick line)

    private var ladderRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(MemoryLab.Stage.allCases, id: \.self) { stage in
                    VStack(spacing: 4) {
                        ladderDot(for: stage)
                        Text(shortStageName(stage))
                            .font(AppType.caption)
                            .foregroundStyle(Tok.text2)
                    }
                    .frame(width: 72)
                }
            }
            .frame(maxWidth: .infinity)
            TickMeter(fraction: ladderFraction, width: 288)
                .frame(maxWidth: .infinity)
        }
    }

    private var ladderFraction: Double {
        Double(viewModel.stageResults.count) / Double(MemoryLab.Stage.allCases.count)
    }

    private func shortStageName(_ stage: MemoryLab.Stage) -> String {
        switch stage {
        case .observe: return "Observe"
        case .sync: return "Sync"
        case .purge: return "Purge"
        case .settle: return "Settle"
        }
    }

    @ViewBuilder
    private func ladderDot(for stage: MemoryLab.Stage) -> some View {
        Group {
            if let result = viewModel.stageResults.first(where: { $0.stage == stage }) {
                if result.ok {
                    PixelCheck(cell: 1)
                        .frame(width: 7, height: 5)
                } else {
                    PixelFailed(cell: 1)
                        .frame(width: 5, height: 5)
                }
            } else if viewModel.isWorking {
                WaitCells()
            } else {
                PixelStop(cell: 1)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 14, height: 14)
        .animation(reduceMotion ? nil : Motion.drain, value: viewModel.stageResults.count)
    }

    // MARK: - Stats (three numbers, nothing else)

    private func statsRow(snapshot: MemoryLab.Snapshot) -> some View {
        HStack(spacing: 32) {
            statCell(title: "Free", value: MemoryLab.fmt(snapshot.freeBytes))
            statCell(title: "Swap", value: MemoryLab.fmt(snapshot.swapUsedBytes))
            statCell(title: "Purged", value: resultPurgedText)
        }
        .frame(maxWidth: .infinity)
    }

    private var resultPurgedText: String {
        viewModel.result.map { MemoryLab.fmt($0.purgedBytes) } ?? "—"
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppType.title)
                .monospacedDigit()
                .foregroundStyle(Tok.text)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : Motion.drain, value: value)
            Text(title)
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
        }
    }

    // MARK: - Purge toggle (one word)

    private var purgeRow: some View {
        HStack(spacing: 8) {
            Text("Purge")
                .font(AppType.label)
                .foregroundStyle(Tok.text)
            AppToggle(isOn: Binding(
                get: { viewModel.includePurge },
                set: { viewModel.includePurge = $0 }
            ))
        }
        .frame(maxWidth: .infinity)
    }

    private func pressureColor(_ p: MemoryLab.Pressure) -> Color {
        switch p {
        case .green: return Tok.statusOK
        case .yellow: return Tok.accentText
        case .red: return Tok.statusBad
        }
    }
}

/// Circular pixel readout — square cells snapped to the grid around a
/// 220pt circle. Filled blue with a white head, dust dots for empty.
/// Transform + opacity only; snapped to whole pixels like TickMeter.
private struct PixelRing: View {
    let fraction: Double
    let pressure: MemoryLab.Pressure
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ticks = 40
    private let size: CGFloat = 220

    var body: some View {
        let filled = Int((fraction * Double(ticks)).rounded())
        let radius = size / 2 - 14
        let center = size / 2
        ZStack {
            ForEach(0..<ticks, id: \.self) { i in
                let angle = -Double.pi / 2 + Double(i) / Double(ticks) * 2 * Double.pi
                let x = center + radius * CGFloat(cos(angle))
                let y = center + radius * CGFloat(sin(angle))
                if i < filled {
                    let isHead = i == filled - 1 && filled < ticks
                    Rectangle()
                        .fill(isHead ? Tok.text : ringColor)
                        .frame(width: Pixel.snap(4), height: Pixel.snap(4))
                        .position(x: Pixel.snap(x), y: Pixel.snap(y))
                } else {
                    Rectangle()
                        .fill(Tok.controlPressed)
                        .frame(width: Pixel.snap(1), height: Pixel.snap(1))
                        .position(x: Pixel.snap(x), y: Pixel.snap(y))
                }
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : Motion.drain, value: fraction)
        .accessibilityHidden(true)
    }

    private var ringColor: Color {
        switch pressure {
        case .green: return Tok.statusOK
        case .yellow: return Ramp.blue[3]
        case .red: return Tok.statusBad
        }
    }
}
