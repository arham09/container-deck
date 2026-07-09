import SwiftUI

/// Full-page container detail (Harbor layout): back button, status header with
/// lifecycle actions, and tabs. Only tabs we can honestly populate exist —
/// Logs, Stats (configured limits; live usage is unavailable on CLI 1.0.0),
/// and Inspect. Harbor's embedded Terminal and Files tabs are intentionally
/// omitted (deferred §36); Terminal is an external-launch action instead.
struct ContainerDetailView: View {
    @Environment(AppEnvironment.self) private var env

    let container: ContainerSummary
    let onBack: () -> Void
    let openTerminal: (ContainerSummary) -> Void

    enum Tab: Hashable { case logs, stats, inspect }
    @State private var tab: Tab = .logs
    @State private var detail: ContainerDetails?
    @State private var detailError: String?

    private var busy: Bool {
        env.containerActions.isBusy(container.id) || env.power.state != .running
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                backButton
                headerRow
                tabBar
            }
            .padding(.horizontal, DeckMetrics.sectionPaddingH)
            .padding(.top, 18)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .navigationTitle(container.name)
        .task(id: container.id) { await loadDetail() }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                Text("Containers")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Color.deckTextDim)
        }
        .buttonStyle(.plain)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            StatusDot(color: container.isRunning ? .deckGreen : .deckTextFaint, size: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.deckText)
                Text("\(container.image) · \(container.state.displayName) · \(container.id)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.deckTextFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            headerActions
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: 8) {
            if container.isRunning {
                Button { env.containerActions.stop(container) } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(busy)
                Button { env.containerActions.restart(container) } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .disabled(busy)
            } else {
                Button { env.containerActions.start(container) } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(busy)
            }
            Button { openTerminal(container) } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .disabled(!container.isRunning)
            Menu {
                Button("Kill") { env.containerActions.kill(container) }
                    .disabled(!container.isRunning || busy)
                Button("Copy Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(container.id, forType: .string)
                }
                Divider()
                Button(container.isRunning ? "Force Delete…" : "Delete…", role: .destructive) {
                    env.containerActions.requestDelete(container)
                }
                .disabled(busy)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 40)
        }
        .controlSize(.small)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton(.logs, "Logs")
            tabButton(.stats, "Stats")
            tabButton(.inspect, "Inspect")
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.deckBorder).frame(height: DeckMetrics.hairline)
        }
    }

    private func tabButton(_ value: Tab, _ label: String) -> some View {
        let selected = tab == value
        return Button { tab = value } label: {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.deckText : Color.deckTextDim)
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? env.settings.accent.color : Color.clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .logs:
            ContainerLogsView(container: container, embedded: true)
                .padding(.horizontal, DeckMetrics.sectionPaddingH)
                .padding(.vertical, 16)
        case .stats:
            statsTab
        case .inspect:
            inspectTab
        }
    }

    // Honest stats: configured limits only — no fabricated live usage.
    private var statsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
                    spacing: 14
                ) {
                    DeckStatCard(title: "CPU limit", value: container.cpuLimitText)
                    DeckStatCard(title: "Memory limit", value: container.memoryLimitText)
                }
                Label(
                    "Live CPU, memory, and I/O aren't available — Apple Container 1.0.0's stats command returns no data. Showing configured limits.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.deckTextFaint)
            }
            .padding(.horizontal, DeckMetrics.sectionPaddingH)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var inspectTab: some View {
        if let detail {
            JSONInspectView(
                rawJSON: detail.rawJSON,
                suggestedFileName: "\(container.name)-inspect.json"
            )
            .padding(.horizontal, DeckMetrics.sectionPaddingH)
            .padding(.vertical, 16)
        } else if let detailError {
            ContentUnavailableView {
                Label("Could Not Inspect", systemImage: "exclamationmark.triangle")
            } description: {
                Text(detailError)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadDetail() async {
        detail = nil
        detailError = nil
        do {
            detail = try await env.engine.inspectContainer(id: container.id)
        } catch let error as ContainerEngineError {
            detailError = UserFacingError.make(from: error).explanation
        } catch {
            detailError = error.localizedDescription
        }
    }
}
