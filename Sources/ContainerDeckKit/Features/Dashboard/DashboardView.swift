import SwiftUI

/// Compact control center (spec §16), styled to the Harbor design: a page
/// header, honest stat cards, and the running-resources table.
/// Live per-container CPU/memory are intentionally NOT shown — the CLI's
/// `stats` returns no data — so those areas carry an honest note, never bars.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.power.state == .unavailable {
                OnboardingView()
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .navigationTitle("Dashboard")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if env.resources.isStale {
                    staleBanner
                }
                if env.resources.hasLoadedResources {
                    statCards
                }
                runningResources
            }
            .padding(.horizontal, DeckMetrics.sectionPaddingH)
            .padding(.vertical, DeckMetrics.sectionPaddingV)
            .frame(maxWidth: 1040, alignment: .leading)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Dashboard")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.deckText)
                HStack(spacing: 6) {
                    Text("System overview")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.deckTextDim)
                    Text("·").foregroundStyle(Color.deckTextFaint)
                    SystemStateBadge(state: env.power.state)
                }
            }
            Spacer()
            headerActions
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        switch env.power.state {
        case .running:
            HStack(spacing: 8) {
                Button("Run Container") {
                    env.router.selection = .containers
                    env.containerActions.runFormPresented = true
                }
                .buttonStyle(.borderedProminent)
                Button("Pull Image") {
                    env.router.selection = .images
                    env.imageActions.pullSheetPresented = true
                }
                Button("Turn Off") {
                    env.power.requestTurnOff()
                }
            }
        case .stopped:
            Button("Turn On Apple Container") {
                env.power.requestTurnOn()
            }
            .buttonStyle(.borderedProminent)
        case .starting, .stopping:
            Button("Cancel") {
                env.power.cancelLifecycleOperation()
            }
        case .failed:
            HStack(spacing: 8) {
                Button("Retry") {
                    env.power.requestTurnOn()
                }
                .buttonStyle(.borderedProminent)
                Button("View Details") {
                    env.power.showLastFailureDetails()
                }
            }
        case .unknown, .unavailable:
            EmptyView()
        }
    }

    private var staleBanner: some View {
        Label(
            "Showing last known data. Turn on Apple Container to refresh.",
            systemImage: "clock.badge.exclamationmark"
        )
        .font(.system(size: 12.5))
        .foregroundStyle(Color.deckOrange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DeckMetrics.controlRadius)
                .fill(Color.deckOrange.opacity(0.12))
        )
    }

    // MARK: Stat cards

    private var statCards: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
            spacing: 14
        ) {
            DeckStatCard(
                title: "Containers",
                value: "\(env.resources.runningContainers.count)",
                valueSuffix: " / \(env.resources.containers.items.count)",
                fillHeight: true
            ) {
                HStack(spacing: 5) {
                    StatusDot(color: .deckGreen, size: 7, ring: 2)
                    Text("running")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.deckGreen)
                }
            }
            DeckStatCard(title: "Images", value: "\(env.resources.images.items.count)", fillHeight: true)
            DeckStatCard(title: "Volumes", value: "\(env.resources.volumes.items.count)", fillHeight: true)
            if let disk = env.resources.disk {
                DeckStatCard(
                    title: "Disk",
                    value: ResourceFormatters.bytes(disk.totalBytes),
                    fillHeight: true
                ) {
                    Text("\(ResourceFormatters.bytes(disk.reclaimableBytes)) reclaimable")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.deckTextFaint)
                }
            } else {
                DeckStatCard(title: "Disk", value: "–", fillHeight: true)
            }
        }
    }

    // MARK: Running resources

    private struct RunningRow: Identifiable {
        let id: String
        let name: String
        let type: String
        let cpu: String
        let memory: String
        let status: String
    }

    private var runningRows: [RunningRow] {
        let containerRows = env.resources.runningContainers.map { container in
            RunningRow(
                id: "container-\(container.id)",
                name: container.name,
                type: "Container",
                cpu: container.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "–",
                memory: container.memoryBytes.map { ResourceFormatters.bytes($0) } ?? "–",
                status: container.state.displayName
            )
        }
        let machineRows = env.resources.runningMachines.map { machine in
            RunningRow(
                id: "machine-\(machine.id)",
                name: machine.name,
                type: "Machine",
                cpu: "–",
                memory: machine.memoryBytes.flatMap { $0 > 0 ? ResourceFormatters.bytes($0) : nil } ?? "–",
                status: machine.state.displayName
            )
        }
        return containerRows + machineRows
    }

    @ViewBuilder
    private var runningResources: some View {
        if env.resources.hasLoadedResources, !runningRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle("Running")
                Table(runningRows) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Type", value: \.type)
                        .width(max: 90)
                    TableColumn("CPU", value: \.cpu)
                        .width(max: 70)
                    TableColumn("Memory", value: \.memory)
                        .width(max: 90)
                    TableColumn("Status", value: \.status)
                        .width(max: 90)
                }
                .frame(height: CGFloat(runningRows.count) * 28 + 32)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                gatedMetricsNote
            }
            .deckCard(padded: true)
        } else if case .unavailable(let reason) = env.resources.containers.phase {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle("Resources")
                Label(reason, systemImage: "info.circle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.deckTextDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .deckCard(padded: true)
        }
    }

    /// Honest replacement for Harbor's "CPU/Memory by container" panels.
    private var gatedMetricsNote: some View {
        Label(
            "Live per-container CPU and memory aren't available — Apple Container 1.0.0's stats command returns no data.",
            systemImage: "info.circle"
        )
        .font(.system(size: 11.5))
        .foregroundStyle(Color.deckTextFaint)
        .padding(.top, 2)
    }

    private func cardTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.deckText)
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
            .environment(AppEnvironment.preview(running: true))
            .frame(width: 1000, height: 700)
            .previewDisplayName("Running")

        DashboardView()
            .environment(AppEnvironment.preview(running: false))
            .frame(width: 1000, height: 700)
            .previewDisplayName("Stopped")
    }
}
