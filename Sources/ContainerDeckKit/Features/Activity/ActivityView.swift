import Charts
import SwiftUI

/// Activity view (spec §29): live charts of verifiable metrics over the last
/// five minutes. Sampling runs only while this view is visible and stops on
/// disappear. Per-container CPU/memory charts are capability-gated because
/// CLI 1.0.0's `container stats` returns no usage data.
struct ActivityView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.power.state == .running || !env.metrics.samples.isEmpty {
                content
            } else {
                ContentUnavailableView {
                    Label("Activity", systemImage: "waveform.path.ecg")
                } description: {
                    Text("Turn on Apple Container to start sampling activity.")
                } actions: {
                    Button("Turn On Apple Container") {
                        env.power.requestTurnOn()
                    }
                    .disabled(!env.power.state.canTurnOn)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem {
                Button("Clear", systemImage: "trash") {
                    env.metrics.clear()
                }
                .disabled(env.metrics.samples.isEmpty)
                .help("Clear collected samples")
            }
        }
        .task {
            env.metrics.start()
        }
        .onDisappear {
            env.metrics.stop()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.deckText)

                HStack(spacing: 6) {
                    if env.metrics.isSampling {
                        ProgressView().controlSize(.mini)
                        Text("Sampling every \(Int(env.settings.statisticsIntervalSeconds)) s while this view is visible · last 5 minutes retained")
                    } else {
                        Text("Sampling paused")
                    }
                    Spacer()
                    Text("\(env.metrics.samples.count) samples")
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.deckTextDim)

                chartSection("Running Resources") {
                    Chart(env.metrics.samples) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Count", sample.runningContainers),
                            series: .value("Series", "Containers")
                        )
                        .foregroundStyle(by: .value("Series", "Containers"))
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Count", sample.runningMachines),
                            series: .value("Series", "Machines")
                        )
                        .foregroundStyle(by: .value("Series", "Machines"))
                    }
                    .chartForegroundStyleScale([
                        "Containers": env.settings.accent.color,
                        "Machines": Color.deckGreen,
                    ])
                    .chartYAxisLabel("running")
                } current: {
                    let last = env.metrics.samples.last
                    Text("\(last?.runningContainers ?? 0) containers · \(last?.runningMachines ?? 0) machines")
                }

                chartSection("Disk Usage") {
                    Chart(env.metrics.samples) { sample in
                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Bytes", Double(sample.diskUsedBytes) / 1_000_000_000)
                        )
                        .foregroundStyle(env.settings.accent.color.opacity(0.30))
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Bytes", Double(sample.diskUsedBytes) / 1_000_000_000)
                        )
                        .foregroundStyle(env.settings.accent.color)
                    }
                    .chartYAxisLabel("GB")
                } current: {
                    let last = env.metrics.samples.last
                    Text("\(ResourceFormatters.bytes(last?.diskUsedBytes ?? 0)) used · \(ResourceFormatters.bytes(last?.diskReclaimableBytes ?? 0)) reclaimable")
                }

                // Honest gating for per-container usage (spec §11).
                if case .supportedWithLimitations(let reason) = env.resources.capabilities?.statistics {
                    Label(
                        "Per-container CPU and memory charts are unavailable: \(reason)",
                        systemImage: "info.circle"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Color.deckTextFaint)
                }
            }
            .padding(.horizontal, DeckMetrics.sectionPaddingH)
            .padding(.vertical, DeckMetrics.sectionPaddingV)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chartSection(
        _ title: String,
        @ViewBuilder chart: () -> some View,
        @ViewBuilder current: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.deckText)
                Spacer()
                current()
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Color.deckTextDim)
            }
            chart()
                .frame(height: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deckCard(padded: true)
    }
}

struct ActivityView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityView()
            .environment(AppEnvironment.preview(running: true))
            .frame(width: 900, height: 620)
    }
}
