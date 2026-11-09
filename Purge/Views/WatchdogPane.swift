import SwiftUI

/// Watchdog pane: 52pt page bar + card stack on Tok.bg. Same tokens as
/// DetailPane (AppType, Tok.control cards radius 12, AppToggle).
/// Copy is short and verb-led, per DESIGN.
struct WatchdogPane: View {
    @Bindable var viewModel: WatchdogViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            pageBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Runs in the background every few days, even if Jupiter is closed. Only touches Safe caches — never Risky data.")
                        .font(AppType.body)
                        .foregroundStyle(Tok.text2)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        enabledCard
                        intervalCard
                        ToggleCard(
                            title: "Include Trash",
                            subtitle: "Empty Trash automatically",
                            isOn: Binding(
                                get: { viewModel.config.includeTrash },
                                set: { viewModel.setIncludeTrash($0) }
                            )
                        )
                        ToggleCard(
                            title: "Also clean Okay",
                            subtitle: "Dev builds and orphaned data — costs a rebuild. Off by default.",
                            isOn: Binding(
                                get: { viewModel.config.includeOkay },
                                set: { viewModel.setIncludeOkay($0) }
                            )
                        )
                        ToggleCard(
                            title: "Docker builder cache",
                            subtitle: "Runs docker builder prune. Needs Docker running.",
                            isOn: Binding(
                                get: { viewModel.config.includeDockerBuilderCache },
                                set: { viewModel.setIncludeDockerBuilder($0) }
                            )
                        )
                        if let last = viewModel.config.lastRun {
                            Text("Last: \(last.formatted(date: .abbreviated, time: .shortened)) · Freed \(ByteCountFormatter.string(fromByteCount: viewModel.config.lastFreed, countStyle: .file))")
                                .font(AppType.caption)
                                .foregroundStyle(Tok.text2)
                        }
                        if let next = viewModel.config.nextRun, viewModel.config.enabled {
                            Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                                .font(AppType.caption)
                                .foregroundStyle(Tok.text2)
                        }
                        if let message = viewModel.message {
                            Text(message)
                                .font(AppType.caption)
                                .foregroundStyle(Tok.text2)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                    if !viewModel.logTail.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Log")
                                .font(AppType.label)
                                .foregroundStyle(Tok.text)
                            ScrollView {
                                Text(viewModel.logTail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Tok.text2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 120)
                        }
                        .padding(12)
                        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
                        .padding(.horizontal, 32)
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tok.bg)
        .opacity(1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.config.enabled)
    }

    private var pageBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Watchdog")
                .font(AppType.pageTitle)
                .tracking(-1.4)
                .foregroundStyle(Tok.text)
            Spacer()
            Text(viewModel.statusLine)
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
                .lineLimit(1)
            QuietButton(title: "Open log") { viewModel.openLog() }
            QuietButton(title: "Remove", disabled: viewModel.isWorking) { viewModel.remove() }
            SecondaryButton(title: "Run now", disabled: viewModel.isWorking) { viewModel.runNow() }
        }
        .frame(height: 52)
        .padding(.horizontal, 32)
    }

    private var enabledCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enabled")
                    .font(AppType.label)
                    .foregroundStyle(Tok.text)
                Text(viewModel.isLoaded ? "launchd: loaded (\(LaunchAgentInstaller.label))" : "launchd: not loaded")
                    .font(AppType.caption)
                    .foregroundStyle(Tok.text2)
                if viewModel.config.lastNote != nil, !viewModel.config.enabled {
                    if let note = viewModel.config.lastNote {
                        Text(note)
                            .font(AppType.caption)
                            .foregroundStyle(Tok.text2)
                    }
                }
            }
            Spacer()
            AppToggle(isOn: Binding(
                get: { viewModel.config.enabled },
                set: { viewModel.setEnabled($0) }
            ))
        }
        .padding(12)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
    }

    private var intervalCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Interval")
                    .font(AppType.label)
                    .foregroundStyle(Tok.text)
                Text("How often to allow cleanup")
                    .font(AppType.caption)
                    .foregroundStyle(Tok.text2)
            }
            Spacer()
            Picker(
                "Interval",
                selection: Binding(
                    get: { viewModel.config.intervalDays },
                    set: { viewModel.setInterval($0) }
                )
            ) {
                Text("1 day").tag(1)
                Text("3 days").tag(3)
                Text("7 days").tag(7)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(12)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
    }
}

private struct ToggleCard: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppType.label)
                    .foregroundStyle(Tok.text)
                Text(subtitle)
                    .font(AppType.caption)
                    .foregroundStyle(Tok.text2)
            }
            Spacer()
            AppToggle(isOn: $isOn)
        }
        .padding(12)
        .background(Tok.control.clipShape(RoundedRectangle(cornerRadius: 12)))
    }
}
