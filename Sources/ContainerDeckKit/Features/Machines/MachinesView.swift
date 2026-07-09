import SwiftUI

/// Linux machines list (spec §28 read-only subset). Create/stop/set arrive
/// in Phase 5. The CLI reports the image reference only via inspect.
struct MachinesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var search = ""
    @State private var detail: MachineDetails?
    @State private var detailError: String?
    @State private var logsMachine: MachineSummary?

    private var rows: [MachineSummary] {
        let base = env.resources.machines.items
        let filtered = search.isEmpty ? base : base.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
        return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            rowList
                .resourcePhase(
                    env.resources.machines,
                    label: "Machines",
                    symbol: "desktopcomputer",
                    emptyDescription: "Linux machines appear here."
                )
                .deckCard()
        }
        .padding(.horizontal, DeckMetrics.sectionPaddingH)
        .padding(.vertical, DeckMetrics.sectionPaddingV)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .searchable(text: $search, placement: .toolbar, prompt: "Name")
        .inspector(isPresented: detailPresented) {
            detailView
                .inspectorColumnWidth(min: 320, ideal: 380)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Create Machine", systemImage: "plus") {
                    env.machineActions.createSheetPresented = true
                }
                .disabled(env.power.state != .running)
                RefreshToolbarButton()
            }
        }
        .modifier(MachineActionDialogs(logsMachine: $logsMachine))
        .navigationTitle("Machines")
        .task {
            if env.resources.machines.phase == .initial {
                await env.resources.machines.refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Machines")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.deckText)
            Text("\(env.resources.machines.items.count) machines")
                .font(.system(size: 13))
                .foregroundStyle(Color.deckTextDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Column widths shared by the header and the rows so they line up.
    private enum Col {
        static let lead: CGFloat = 10
        static let status: CGFloat = 88
        static let cpu: CGFloat = 44
        static let memory: CGFloat = 74
        static let disk: CGFloat = 74
        static let created: CGFloat = 104
    }

    private var rowList: some View {
        VStack(spacing: 0) {
            if !env.resources.machines.items.isEmpty {
                columnHeader
                Rectangle().fill(Color.deckBorder).frame(height: DeckMetrics.hairline)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { machine in
                        machineRow(machine)
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
            DeckColHeader("Status", width: Col.status)
            DeckColHeader("CPU", width: Col.cpu, alignment: .trailing)
            DeckColHeader("Memory", width: Col.memory, alignment: .trailing)
            DeckColHeader("Disk", width: Col.disk, alignment: .trailing)
            DeckColHeader("Created", width: Col.created)
        }
        .padding(.horizontal, DeckList.padH)
        .frame(height: 34)
    }

    private func machineRow(_ machine: MachineSummary) -> some View {
        let actions = env.machineActions
        let busy = actions.isBusy(machine.name) || env.power.state != .running
        return DeckHoverRow(
            onOpen: { openDetail(name: machine.name) }
        ) {
            HStack(spacing: DeckList.colSpacing) {
                StatusDot(
                    color: machine.isRunning ? .deckGreen : .deckTextFaint,
                    size: 8, ring: 2
                )
                .frame(width: Col.lead)
                HStack(spacing: 5) {
                    Text(machine.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.deckText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if machine.isDefault {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.deckYellow)
                            .help("Default machine")
                    }
                }
                .deckColumn()
                .deckTooltip(machine.name)
                Text(machine.state.displayName)
                    .font(.system(size: 12.5))
                    .foregroundStyle(machine.isRunning ? Color.deckGreen : Color.deckTextDim)
                    .deckColumn(width: Col.status)
                Text(machine.cpuText)
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Color.deckTextDim)
                    .deckColumn(width: Col.cpu, alignment: .trailing)
                Text(machine.memoryText)
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Color.deckTextDim)
                    .deckColumn(width: Col.memory, alignment: .trailing)
                Text(machine.diskText)
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Color.deckTextDim)
                    .deckColumn(width: Col.disk, alignment: .trailing)
                Text(machine.createdText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.deckTextFaint)
                    .lineLimit(1)
                    .deckColumn(width: Col.created)
            }
        } actions: {
            if machine.isRunning {
                DeckRowIconButton(systemImage: "stop.fill", help: "Stop", disabled: busy) {
                    actions.stop(machine)
                }
            } else {
                DeckRowIconButton(
                    systemImage: "play.fill", help: "Boot", tint: .deckGreen, disabled: busy
                ) {
                    actions.boot(machine)
                }
            }
            DeckRowIconButton(systemImage: "trash", help: "Delete…", tint: .deckRed, disabled: busy) {
                actions.pendingDelete = machine
            }
            DeckRowMenu { machineActions(for: machine) }
        }
        .contextMenu { machineActions(for: machine) }
    }

    /// Shared action set for context menu and detail pane.
    @ViewBuilder
    private func machineActions(for machine: MachineSummary) -> some View {
        let actions = env.machineActions
        let busy = actions.isBusy(machine.name) || env.power.state != .running
        if machine.isRunning {
            Button("Stop") { actions.stop(machine) }
                .disabled(busy)
        } else {
            Button("Boot") { actions.boot(machine) }
                .disabled(busy)
        }
        if actions.pendingRestart.contains(machine.name) {
            Button("Restart (settings pending)") { actions.restart(machine) }
                .disabled(busy)
        }
        Divider()
        Button("Run Command…") { actions.runCommandTarget = machine }
            .disabled(env.power.state != .running)
        Button("Open Terminal") { openTerminal(machine) }
        Button("Logs…") { logsMachine = machine }
        Button("Settings…") { actions.settingsTarget = machine }
            .disabled(env.power.state != .running)
        Divider()
        Button("Set as Default") { actions.setDefault(machine) }
            .disabled(machine.isDefault || busy)
        Button("Inspect") { openDetail(name: machine.name) }
        Button("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(machine.name, forType: .string)
        }
        Divider()
        Button("Delete…", role: .destructive) { actions.pendingDelete = machine }
            .disabled(busy)
    }

    private func openTerminal(_ machine: MachineSummary) {
        let binary = env.power.binaryLocation?.url.path ?? "container"
        let command = "\(binary) machine run --name \(machine.name)"
        do {
            _ = try env.terminalLauncher.open(
                command: command,
                preference: env.settings.preferredTerminal
            )
        } catch let error as ContainerEngineError {
            env.machineActions.lastError = UserFacingError.make(from: error, context: "opening a terminal")
        } catch {
            env.machineActions.lastError = UserFacingError.make(from: .unexpectedOutput(error.localizedDescription))
        }
    }

    private var detailPresented: Binding<Bool> {
        Binding(
            get: { detail != nil || detailError != nil },
            set: { presented in
                if !presented {
                    detail = nil
                    detailError = nil
                }
            }
        )
    }

    private func openDetail(name: String) {
        detail = nil
        detailError = nil
        Task {
            do {
                detail = try await env.engine.inspectMachine(name: name)
            } catch let error as ContainerEngineError {
                detailError = UserFacingError.make(from: error).explanation
            } catch {
                detailError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        StatusDot(color: detail.summary.isRunning ? .deckGreen : .deckTextFaint)
                        Text(detail.summary.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.deckText)
                        if detail.summary.isDefault {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.deckYellow)
                                .help("Default machine")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if let image = detail.summary.image {
                            LabeledContent("Image", value: image)
                        }
                        LabeledContent("Status", value: detail.summary.state.displayName)
                        LabeledContent("CPUs", value: detail.summary.cpuText)
                        LabeledContent("Memory", value: detail.summary.memoryText)
                        LabeledContent("Disk", value: detail.summary.diskText)
                        LabeledContent("IP address", value: detail.summary.ipText)
                        if let homeMount = detail.homeMount {
                            LabeledContent("Home mount", value: homeMount)
                        }
                        LabeledContent("Created", value: detail.summary.createdText)
                    }
                    .font(.callout)
                    Divider()
                    Text("Inspect")
                        .font(.headline)
                    JSONInspectView(
                        rawJSON: detail.rawJSON,
                        suggestedFileName: "\(detail.summary.name)-inspect.json"
                    )
                    .frame(minHeight: 300)
                }
                .padding(14)
            }
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
}

extension MachineSummary {
    var cpuText: String { cpuCount.map(String.init) ?? "–" }
    var memoryText: String { memoryBytes.map { ResourceFormatters.bytes($0) } ?? "–" }
    var diskText: String { diskBytes.map { ResourceFormatters.bytes($0) } ?? "–" }
    var ipText: String { ipAddress ?? "–" }
    var createdText: String {
        createdAt.map { $0.formatted(.relative(presentation: .named)) } ?? "–"
    }
}

struct MachinesView_Previews: PreviewProvider {
    static var previews: some View {
        MachinesView()
            .environment(AppEnvironment.preview(running: true))
            .frame(width: 980, height: 620)
    }
}
