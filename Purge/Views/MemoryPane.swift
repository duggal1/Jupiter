import SwiftUI

/// Memory page: pressure readout + polite ladder. Same tokens as
/// WatchdogPane so the two settings pages feel like one family.
struct MemoryPane: View {
    @Bindable var viewModel: MemoryViewModel
    @Binding var pane: AppPane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            pageBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Frees RAM without quitting anything. The staircase only returns reclaimable pages — active app memory is never touched.")
                        .font(AppType.body)
                        .foregroundStyle(Tok.text2)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        pressureCard
                        numbersCard
                        ladderCard
                        toggleCard
                        if let message = viewModel.message {
                            Text(message)
                                .font(AppType.caption)
                                .foregroundStyle(Tok.text2)
                        }
                        if let result = viewModel.result {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Available")
                                        .font(AppType.caption)
                                        .foregroundStyle(Tok.text2)
                                    Text("\(MemoryLab.fmt(result.before.availableBytes)) → \(MemoryLab.fmt(result.after.availableBytes))")
                                        .font(AppType.body)
                                        .monospacedDigit()
                                        .foregroundStyle(Tok.text)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Swap used")
                                        .font(AppType.caption)
                                        .foregroundStyle(Tok.text2)
                                    Text("\(MemoryLab.fmt(result.after.swapUsedBytes)) (\(MemoryLab.signedFmt(result.swapDeltaBytes)))")
                                        .font(AppType.body)
                                        .monospacedDigit()
                                        .foregroundStyle(Tok.text)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Purged")
                                        .font(AppType.caption)
                                        .foregroundStyle(Tok.text2)
                                    Text(MemoryLab.fmt(result.purgedBytes))
                                        .font(AppType.body)
                                        .monospacedDigit()
                                        .foregroundStyle(Tok.text)
                                }
                            }
                            .padding(12)
                            .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tok.bg)
        .opacity(1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.phase)
    }

    private var pageBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Memory")
                .font(AppType.pageTitle)
                .tracking(-1.4)
                .foregroundStyle(Tok.text)
            Spacer()
            Text(viewModel.statusLine)
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
                .lineLimit(1)
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

    private var pressureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Pressure")
                    .font(AppType.label)
                    .foregroundStyle(Tok.text)
                if let s = viewModel.snapshot {
                    Text(s.pressure.title)
                        .font(AppType.caption)
                        .foregroundStyle(pressureColor(s.pressure))
                }
                Spacer()
                if let s = viewModel.snapshot {
                    Text("\(MemoryLab.fmt(s.availableBytes)) of \(MemoryLab.fmt(s.totalBytes))")
                        .font(AppType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Tok.text2)
                }
            }
            if let s = viewModel.snapshot {
                TickMeter(fraction: s.availableRatio, width: 480)
                Text(s.pressure.blurb)
                    .font(AppType.caption)
                    .foregroundStyle(Tok.text2)
            } else {
                WaitCells()
                    .frame(height: 20)
            }
        }
        .padding(12)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
    }

    private var numbersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snapshot (vm_stat + swap)")
                .font(AppType.label)
                .foregroundStyle(Tok.text)
            if let s = viewModel.snapshot {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                    GridRow { Text("Available (free+inactive+spec+purge)").font(AppType.caption).foregroundStyle(Tok.text2); Text(MemoryLab.fmt(s.availableBytes)).font(AppType.caption).monospacedDigit().foregroundStyle(Tok.text) }
                    GridRow { Text("Free").font(AppType.caption).foregroundStyle(Tok.text2); Text(MemoryLab.fmt(s.freeBytes)).font(AppType.caption).monospacedDigit().foregroundStyle(Tok.text) }
                    GridRow { Text("Wired + active").font(AppType.caption).foregroundStyle(Tok.text2); Text(MemoryLab.fmt(s.wiredBytes + s.activeBytes)).font(AppType.caption).monospacedDigit().foregroundStyle(Tok.text) }
                    GridRow { Text("Compressor (occupied)").font(AppType.caption).foregroundStyle(Tok.text2); Text(MemoryLab.fmt(s.compressorOccupiedBytes)).font(AppType.caption).monospacedDigit().foregroundStyle(Tok.text) }
                    GridRow { Text("Swap used / total").font(AppType.caption).foregroundStyle(Tok.text2); Text("\(MemoryLab.fmt(s.swapUsedBytes)) / \(MemoryLab.fmt(s.swapTotalBytes))").font(AppType.caption).monospacedDigit().foregroundStyle(Tok.text) }
                }
            } else {
                Text("Reading…").font(AppType.caption).foregroundStyle(Tok.text2)
            }
        }
        .padding(12)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
    }

    private var ladderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Polite staircase — never quits an app")
                .font(AppType.label)
                .foregroundStyle(Tok.text)
            ForEach(MemoryLab.Stage.allCases, id: \.self) { stage in
                HStack(spacing: 8) {
                    if let r = viewModel.stageResults.first(where: { $0.stage == stage }) {
                        if r.ok { PixelCheck(cell: 1).frame(width: 7, height: 5) }
                        else { PixelFailed(cell: 1).frame(width: 5, height: 5) }
                    } else if viewModel.isWorking {
                        WaitCells()
                    } else {
                        PixelStop(cell: 1).frame(width: 7, height: 7)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.rawValue)
                            .font(AppType.body)
                            .foregroundStyle(Tok.text)
                        Text(viewModel.stageResults.first(where: { $0.stage == stage })?.note ?? stage.blurb)
                            .font(AppType.caption)
                            .foregroundStyle(Tok.text2)
                    }
                    Spacer()
                }
                .frame(minHeight: 32)
            }
            Text("What it never does: quit apps, kill processes, swapoff, or touch active/wired heaps.")
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
        }
        .padding(12)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
    }

    private var toggleCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Purge page cache (admin dialog)")
                    .font(AppType.label)
                    .foregroundStyle(Tok.text)
                Text("Off = sync only. On keeps apps running, frees file cache.")
                    .font(AppType.caption)
                    .foregroundStyle(Tok.text2)
            }
            Spacer()
            AppToggle(isOn: Binding(
                get: { viewModel.includePurge },
                set: { viewModel.includePurge = $0 }
            ))
        }
        .padding(12)
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
