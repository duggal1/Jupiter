import SwiftUI

/// Memory page: circular pixel hero, ladder strip, stat cards. Short words
/// only — visuals carry the meaning. Backend unchanged.
struct MemoryPane: View {
    @Bindable var viewModel: MemoryViewModel
    @Binding var pane: AppPane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            pageBar
            if let snapshot = viewModel.snapshot {
                VStack(spacing: 16) {
                    heroCard(snapshot: snapshot)
                    ladderCard
                    HStack(spacing: 12) {
                        statCard(title: "Free", value: MemoryLab.fmt(snapshot.freeBytes), fraction: snapshot.totalBytes > 0 ? Double(snapshot.freeBytes) / Double(snapshot.totalBytes) : 0)
                        statCard(title: "Swap", value: MemoryLab.fmt(snapshot.swapUsedBytes), fraction: snapshot.swapRatio)
                        statCard(title: "Purged", value: resultPurgedText, fraction: resultPurgedFraction)
                    }
                    purgeCard
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
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

    // MARK: - Hero (surface card + layered pixel rings)

    private func heroCard(snapshot: MemoryLab.Snapshot) -> some View {
        ZStack {
            Tok.surface.clipShape(RoundedRectangle(cornerRadius: 16))
                .contrastStroke(radius: 16)
            VStack(spacing: 12) {
                ZStack {
                    // Outer dust orbit — decoration only, never interactive.
                    OrbitDust(diameter: 248)
                    // Soft inner well behind the numbers.
                    Circle()
                        .fill(Tok.control)
                        .frame(width: 150, height: 150)
                    // Main available ring.
                    PixelRing(fraction: snapshot.availableRatio, pressure: snapshot.pressure)
                        .frame(width: 220, height: 220)
                    // Center numbers.
                    VStack(spacing: 2) {
                        Text(snapshot.pressure.title)
                            .font(AppType.caption)
                            .foregroundStyle(pressureColor(snapshot.pressure))
                        Text(MemoryLab.fmt(snapshot.availableBytes))
                            .font(AppType.metric)
                            .monospacedDigit()
                            .foregroundStyle(Tok.text)
                            .contentTransition(.numericText())
                            .animation(Motion.spring(reduceMotion: reduceMotion), value: snapshot.availableBytes)
                        Text(MemoryLab.fmt(snapshot.totalBytes))
                            .font(AppType.caption)
                            .monospacedDigit()
                            .foregroundStyle(Tok.text2)
                    }
                    // Satellite marks at cardinal points — pixel accent only.
                    PixelDisc(cell: 1)
                        .frame(width: 7, height: 7)
                        .position(x: 320, y: 110)
                        .opacity(0.7)
                    PixelStop(cell: 1)
                        .frame(width: 5, height: 5)
                        .position(x: 24, y: 110)
                        .opacity(0.6)
                }
                .frame(width: 344, height: 248)
                .scaleEffect(viewModel.isWorking ? 1.02 : 1)
                .animation(Motion.spring(reduceMotion: reduceMotion), value: viewModel.isWorking)
                if let result = viewModel.result {
                    HStack(spacing: 6) {
                        PixelCheck(cell: 1)
                            .frame(width: 7, height: 5)
                        Text(MemoryLab.signedFmt(result.freedAvailableBytes))
                            .font(AppType.label)
                            .monospacedDigit()
                            .foregroundStyle(Tok.accentText)
                            .contentTransition(.numericText())
                            .animation(Motion.spring(reduceMotion: reduceMotion), value: result.freedAvailableBytes)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Tok.accentSoft.clipShape(Capsule()))
                    .transition(.opacity.combined(with: .offset(y: 6).combined(with: .scale)))
                }
            }
            .padding(.vertical, 16)
        }
        .animation(reduceMotion ? nil : Motion.springSoft, value: viewModel.result?.freedAvailableBytes)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(MemoryLab.fmt(snapshot.availableBytes)) available of \(MemoryLab.fmt(snapshot.totalBytes)). \(snapshot.pressure.title)")
    }

    // MARK: - Ladder card (dots + tick strip)

    private var ladderCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(MemoryLab.Stage.allCases.enumerated()), id: \.element) { index, stage in
                    VStack(spacing: 4) {
                        ladderDot(for: stage)
                        Text(shortStageName(stage))
                            .font(AppType.caption)
                            .foregroundStyle(Tok.text2)
                    }
                    .frame(width: 72)
                    .scaleEffect(ladderScale(for: stage))
                    .animation(
                        (Motion.spring(reduceMotion: reduceMotion) ?? .default)
                            .delay(Double(index) * 0.04),
                        value: viewModel.stageResults.count
                    )
                }
            }
            .frame(maxWidth: .infinity)
            TickMeter(fraction: ladderFraction, width: 288)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
    }

    private var ladderFraction: Double {
        Double(viewModel.stageResults.count) / Double(MemoryLab.Stage.allCases.count)
    }

    private func ladderScale(for stage: MemoryLab.Stage) -> CGFloat {
        guard reduceMotion == false else { return 1 }
        return viewModel.stageResults.contains(where: { $0.stage == stage }) ? 1 : 0.92
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
        .transition(.opacity.combined(with: .scale))
        .animation(Motion.spring(reduceMotion: reduceMotion), value: viewModel.stageResults.count)
    }

    // MARK: - Stat cards (number + tick strip)

    private var resultPurgedText: String {
        viewModel.result.map { MemoryLab.fmt($0.purgedBytes) } ?? "—"
    }

    private var resultPurgedFraction: Double {
        guard let r = viewModel.result, r.after.totalBytes > 0 else { return 0 }
        return Double(r.purgedBytes) / Double(r.after.totalBytes)
    }

    private func statCard(title: String, value: String, fraction: Double) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(AppType.title)
                .monospacedDigit()
                .foregroundStyle(Tok.text)
                .contentTransition(.numericText())
                .animation(Motion.spring(reduceMotion: reduceMotion), value: value)
            TickMeter(fraction: min(max(fraction, 0), 1), width: 80)
            Text(title)
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
    }

    // MARK: - Purge toggle (one word)

    private var purgeCard: some View {
        HStack(spacing: 8) {
            Text("Purge")
                .font(AppType.label)
                .foregroundStyle(Tok.text)
            Spacer()
            AppToggle(isOn: Binding(
                get: { viewModel.includePurge },
                set: { viewModel.includePurge = $0 }
            ))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
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
/// 220pt circle. Filled with pressure color and a white head, dust for empty.
/// Spring-driven fill; snapped to whole pixels like TickMeter.
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
                    let cell: CGFloat = isHead ? 5 : 4
                    Rectangle()
                        .fill(isHead ? Tok.text : ringColor)
                        .frame(width: Pixel.snap(cell), height: Pixel.snap(cell))
                        .position(x: Pixel.snap(x), y: Pixel.snap(y))
                        .scaleEffect(isHead ? 1.25 : 1)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Rectangle()
                        .fill(Tok.controlPressed)
                        .frame(width: Pixel.snap(1), height: Pixel.snap(1))
                        .position(x: Pixel.snap(x), y: Pixel.snap(y))
                        .opacity(0.9)
                }
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: fraction)
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

/// Outer dust orbit — 28 faint 1pt dots on a wide circle. Pure decoration,
/// purely transform/opacity, no timer.
private struct OrbitDust: View {
    let diameter: CGFloat
    private let count = 28

    var body: some View {
        let radius = diameter / 2 - 6
        let center = diameter / 2
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * Double.pi
                let x = center + radius * CGFloat(cos(angle))
                let y = center + radius * CGFloat(sin(angle))
                Rectangle()
                    .fill(Tok.controlPressed)
                    .frame(width: Pixel.snap(1), height: Pixel.snap(1))
                    .position(x: Pixel.snap(x), y: Pixel.snap(y))
                    .opacity(0.5)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
