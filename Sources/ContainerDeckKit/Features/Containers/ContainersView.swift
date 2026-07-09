import SwiftUI

/// Containers screen (spec §18), Harbor layout: a filterable, card-framed
/// table that opens a full-page tabbed detail. CPU/Memory columns show
/// configured limits — live usage is not reported by `container stats` on the
/// verified CLI, so no live bars are shown anywhere.
struct ContainersView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var openContainerID: ContainerSummary.ID?
    @State private var logsContainer: ContainerSummary?
    @State private var terminalNote: String?

    enum Filter: Hashable { case all, running, stopped }

    private var runningCount: Int { env.resources.containers.items.filter(\.isRunning).count }
    private var stoppedCount: Int { env.resources.containers.items.count - runningCount }

    private var rows: [ContainerSummary] {
        let base = env.resources.containers.items
        let byFilter = base.filter { container in
            switch filter {
            case .all: true
            case .running: container.isRunning
            case .stopped: !container.isRunning
            }
        }
        let filtered = search.isEmpty ? byFilter : byFilter.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.image.localizedCaseInsensitiveContains(search)
        }
        return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if let id = openContainerID, let container = container(id) {
                ContainerDetailView(
                    container: container,
                    onBack: { openContainerID = nil },
                    openTerminal: { openTerminal($0) }
                )
            } else {
                listView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .modifier(ContainerLifecycleDialogs(logsContainer: $logsContainer, terminalNote: $terminalNote))
    }

    private var listView: some View {
        VStack(alignment: .leading, spacing: 14) {
            listHeader
            rowList
                .resourcePhase(
                    env.resources.containers,
                    label: "Containers",
                    symbol: "shippingbox",
                    emptyDescription: "Containers you create appear here."
                )
                .deckCard()
        }
        .padding(.horizontal, DeckMetrics.sectionPaddingH)
        .padding(.vertical, DeckMetrics.sectionPaddingV)
        .searchable(text: $search, placement: .toolbar, prompt: "Name or image")
        .toolbar {
            ToolbarItemGroup {
                Button("Prune", systemImage: "trash.slash") {
                    env.containerActions.requestPrune()
                }
                .disabled(env.power.state != .running
                    || !env.resources.containers.items.contains { !$0.isRunning })
                .help("Remove all stopped containers")
                RefreshToolbarButton()
            }
        }
        .navigationTitle("Containers")
        .task {
            if env.resources.containers.phase == .initial {
                await env.resources.containers.refresh()
            }
        }
    }

    private var listHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Containers")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.deckText)
                Text("\(runningCount) running · \(stoppedCount) stopped")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.deckTextDim)
            }
            Spacer()
            DeckSegmentedControl(
                selection: $filter,
                accent: env.settings.accent.color,
                options: [(.all, "All"), (.running, "Running"), (.stopped, "Stopped")]
            )
            Button {
                env.containerActions.runFormPresented = true
            } label: {
                Label("Run", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(env.power.state != .running)
            .help("Run a new container (⌘N)")
        }
    }

    // Column widths shared by the header and the rows so they line up.
    private enum Col {
        static let lead: CGFloat = 14
        static let ports: CGFloat = 118
        static let cpu: CGFloat = 46
        static let memory: CGFloat = 78
        static let created: CGFloat = 104
    }

    private var rowList: some View {
        VStack(spacing: 0) {
            if !env.resources.containers.items.isEmpty {
                columnHeader
                Rectangle().fill(Color.deckBorder).frame(height: DeckMetrics.hairline)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { container in
                        containerRow(container)
                        Rectangle().fill(Color.deckBorder)
                            .frame(height: DeckMetrics.hairline)
                            .padding(.leading, DeckList.padH)
                    }
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: DeckList.colSpacing) {
            Color.clear.frame(width: Col.lead, height: 1)
            DeckColHeader("Name")
            DeckColHeader("Image")
            DeckColHeader("Ports", width: Col.ports)
            DeckColHeader("CPU", width: Col.cpu, alignment: .trailing)
            DeckColHeader("Memory", width: Col.memory, alignment: .trailing)
            DeckColHeader("Created", width: Col.created)
        }
        .padding(.horizontal, DeckList.padH)
        .frame(height: 34)
    }

    private func containerRow(_ container: ContainerSummary) -> some View {
        let actions = env.containerActions
        let busy = actions.isBusy(container.id) || env.power.state != .running
        return DeckHoverRow(
            onOpen: { openContainerID = container.id }
        ) {
            HStack(spacing: DeckList.colSpacing) {
                StatusDot(
                    color: container.isRunning ? .deckGreen : .deckRed,
                    size: 9, ring: 3
                )
                .frame(width: Col.lead)
                .deckTooltip(container.state.displayName)
                Text(container.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.deckText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .deckColumn()
                    .deckTooltip(container.name)
                Text(container.image)
                    .font(.system(size: 12.5).monospaced())
                    .foregroundStyle(Color.deckTextDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .deckColumn()
                    .deckTooltip(container.image)
                Text(container.portsText)
                    .font(.system(size: 12.5).monospaced())
                    .foregroundStyle(container.ports.isEmpty ? Color.deckTextFaint : Color.deckTextDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .deckColumn(width: Col.ports)
                    .deckTooltip(container.ports.isEmpty ? "" : container.portsText)
                Text(container.cpuLimitText)
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Color.deckTextDim)
                    .deckColumn(width: Col.cpu, alignment: .trailing)
                Text(container.memoryLimitText)
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Color.deckTextDim)
                    .deckColumn(width: Col.memory, alignment: .trailing)
                Text(container.createdText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.deckTextFaint)
                    .lineLimit(1)
                    .deckColumn(width: Col.created)
            }
        } actions: {
            if container.isRunning {
                DeckRowIconButton(systemImage: "stop.fill", help: "Stop", disabled: busy) {
                    actions.stop(container)
                }
            } else {
                DeckRowIconButton(
                    systemImage: "play.fill", help: "Start", tint: .deckGreen, disabled: busy
                ) {
                    actions.start(container)
                }
            }
            DeckRowIconButton(
                systemImage: "trash",
                help: container.isRunning ? "Force Delete" : "Delete",
                tint: .deckRed,
                disabled: actions.isBusy(container.id) || env.power.state != .running
            ) {
                actions.requestDelete(container)
            }
            DeckRowMenu { containerActions(for: container) }
        }
        .contextMenu { containerActions(for: container) }
    }

    private func container(_ id: ContainerSummary.ID) -> ContainerSummary? {
        env.resources.containers.items.first { $0.id == id }
    }

    /// Shared action set for context menus and the detail pane (spec §17:
    /// actions available beyond context menus alone).
    @ViewBuilder
    private func containerActions(for container: ContainerSummary) -> some View {
        let actions = env.containerActions
        let busy = actions.isBusy(container.id) || env.power.state != .running
        if container.isRunning {
            Button("Stop") { actions.stop(container) }
                .disabled(busy)
            Button("Restart") { actions.restart(container) }
                .disabled(busy)
            Button("Kill") { actions.kill(container) }
                .disabled(busy)
        } else {
            Button("Start") { actions.start(container) }
                .disabled(busy)
        }
        Divider()
        Button("Logs…") { logsContainer = container }
        Button("Open Terminal") { openTerminal(container) }
            .disabled(!container.isRunning)
        Button("Inspect") { openContainerID = container.id }
        Button("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(container.id, forType: .string)
        }
        Divider()
        Button(container.isRunning ? "Force Delete…" : "Delete…", role: .destructive) {
            actions.requestDelete(container)
        }
        .disabled(actions.isBusy(container.id) || env.power.state != .running)
    }

    private func openTerminal(_ container: ContainerSummary) {
        let binary = env.power.binaryLocation?.url.path ?? "container"
        let command = "\(binary) exec -it \(container.id) /bin/sh"
        do {
            terminalNote = try env.terminalLauncher.open(
                command: command,
                preference: env.settings.preferredTerminal
            )
        } catch let error as ContainerEngineError {
            env.containerActions.lastError = UserFacingError.make(from: error, context: "opening a terminal")
        } catch {
            env.containerActions.lastError = UserFacingError.make(from: .unexpectedOutput(error.localizedDescription))
        }
    }
}

/// Sheets and confirmations for container lifecycle actions (spec §8:
/// confirm destructive operations; force deletion is explicit and distinct).
private struct ContainerLifecycleDialogs: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Binding var logsContainer: ContainerSummary?
    @Binding var terminalNote: String?

    func body(content: Content) -> some View {
        @Bindable var actions = env.containerActions
        content
            .sheet(item: $logsContainer) { container in
                ContainerLogsView(container: container)
            }
            .sheet(isPresented: $actions.runFormPresented) {
                RunContainerForm()
            }
            .alert(
                actions.pendingForceDelete ? "Force delete container?" : "Delete container?",
                isPresented: Binding(
                    get: { actions.pendingDelete != nil },
                    set: { if !$0 { actions.pendingDelete = nil } }
                ),
                presenting: actions.pendingDelete
            ) { container in
                Button(
                    actions.pendingForceDelete ? "Force Delete" : "Delete",
                    role: .destructive
                ) {
                    actions.confirmDelete()
                }
                Button("Cancel", role: .cancel) {
                    actions.pendingDelete = nil
                }
            } message: { container in
                Text(
                    actions.pendingForceDelete
                        ? "“\(container.name)” is running. Force deleting stops it immediately and removes it. This cannot be undone."
                        : "“\(container.name)” will be permanently removed. This cannot be undone."
                )
            }
            .alert("Remove all stopped containers?", isPresented: $actions.pendingPrune) {
                Button("Prune", role: .destructive) {
                    actions.confirmPrune()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let stopped = env.resources.containers.items.filter { !$0.isRunning }
                Text(
                    """
                    \(stopped.count) stopped container\(stopped.count == 1 ? "" : "s") will be \
                    permanently removed, freeing their disk space. Running containers are not affected.
                    """
                )
            }
            .alert(
                actions.lastError?.title ?? "Error",
                isPresented: Binding(
                    get: { actions.lastError != nil },
                    set: { if !$0 { actions.lastError = nil } }
                ),
                presenting: actions.lastError
            ) { error in
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error.diagnostics, forType: .string)
                }
                Button("OK", role: .cancel) {}
            } message: { error in
                Text("\(error.explanation)\n\n\(error.recommendedAction)")
            }
            .alert(
                "Terminal",
                isPresented: Binding(
                    get: { terminalNote != nil },
                    set: { if !$0 { terminalNote = nil } }
                ),
                presenting: terminalNote
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { note in
                Text(note)
            }
    }
}

extension ContainerSummary {
    var cpuLimitText: String { cpuLimit.map(String.init) ?? "–" }
    var memoryLimitText: String { memoryLimitBytes.map { ResourceFormatters.bytes($0) } ?? "–" }
    var createdText: String {
        createdAt.map { $0.formatted(.relative(presentation: .named)) } ?? "–"
    }

    /// Compact published-port summary, e.g. "8080:80" or "8080:80, 5432:5432/udp".
    var portsText: String {
        guard !ports.isEmpty else { return "–" }
        return ports.map { port in
            let base = "\(port.hostPort):\(port.containerPort)"
            return port.proto?.lowercased() == "udp" ? "\(base)/udp" : base
        }
        .joined(separator: ", ")
    }
}

struct ContainersView_Previews: PreviewProvider {
    static var previews: some View {
        ContainersView()
            .environment(AppEnvironment.preview(running: true))
            .frame(width: 980, height: 620)
    }
}
