import SwiftUI
import Observation

/// Machine mutations (spec §28): create (streaming), stop, delete, settings
/// with an explicit pending-restart state (never a silent restart), default
/// selection, one-shot commands, and logs.
@MainActor
@Observable
public final class MachineActionsController {
    private let engine: any ContainerEngine
    private let operations: OperationStore
    private let resources: ResourceCenter

    public var lastError: UserFacingError?
    public var createSheetPresented = false
    public var runCommandTarget: MachineSummary?
    public var settingsTarget: MachineSummary?
    public var pendingDelete: MachineSummary?
    /// Machines whose settings changed and need a restart to take effect.
    public private(set) var pendingRestart: Set<String> = []
    public private(set) var busyMachines: Set<String> = []

    public init(engine: any ContainerEngine, operations: OperationStore, resources: ResourceCenter) {
        self.engine = engine
        self.operations = operations
        self.resources = resources
    }

    public func isBusy(_ name: String) -> Bool { busyMachines.contains(name) }

    public func create(_ configuration: MachineConfiguration) {
        createSheetPresented = false
        let operationID = operations.begin(
            title: "Creating machine \(configuration.name.isEmpty ? configuration.image : configuration.name)",
            kind: .other,
            redactedCommand: "container machine create --name \(configuration.name) \(configuration.image)"
        )
        Task {
            do {
                let stream = try await engine.createMachine(configuration)
                for try await event in stream {
                    switch event {
                    case .stdout(let text), .stderr(let text):
                        operations.appendOutput(operationID, text: text)
                    case .completed(let code):
                        operations.finish(
                            operationID,
                            status: code == 0 ? .succeeded : .failed("Exited with code \(code)")
                        )
                    }
                }
            } catch {
                report(error, operation: operationID, action: "creating the machine")
            }
            await resources.machines.refresh()
        }
    }

    public func stop(_ machine: MachineSummary) {
        mutate(machine.name, title: "Stopping \(machine.name)",
               command: "container machine stop \(machine.name)") { engine in
            try await engine.stopMachine(name: machine.name)
        }
    }

    /// Boots via `machine run` (no dedicated start verb in CLI 1.0.0).
    public func boot(_ machine: MachineSummary) {
        mutate(machine.name, title: "Booting \(machine.name)",
               command: "container machine run --name \(machine.name) /bin/true") { engine in
            _ = try await engine.runMachineCommand(name: machine.name, command: ["/bin/true"])
        }
        pendingRestart.remove(machine.name)
    }

    /// Explicit restart after settings changes: stop → verify → boot.
    public func restart(_ machine: MachineSummary) {
        guard !isBusy(machine.name) else { return }
        busyMachines.insert(machine.name)
        let operationID = operations.begin(
            title: "Restarting \(machine.name)",
            kind: .other,
            redactedCommand: "container machine stop \(machine.name) && container machine run --name \(machine.name)",
            phase: "Stopping"
        )
        Task {
            defer { busyMachines.remove(machine.name) }
            do {
                try await engine.stopMachine(name: machine.name)
                operations.updatePhase(operationID, phase: "Booting")
                _ = try await engine.runMachineCommand(name: machine.name, command: ["/bin/true"])
                operations.finish(operationID, status: .succeeded)
                pendingRestart.remove(machine.name)
            } catch {
                report(error, operation: operationID, action: "restarting \(machine.name)")
            }
            await resources.machines.refresh()
        }
    }

    public func confirmDelete() {
        guard let machine = pendingDelete else { return }
        pendingDelete = nil
        mutate(machine.name, title: "Deleting \(machine.name)",
               command: "container machine delete \(machine.name)") { engine in
            try await engine.deleteMachine(name: machine.name)
        }
        pendingRestart.remove(machine.name)
    }

    /// Applies settings; marks the machine as pending restart (spec §28:
    /// changes take effect after restart, never restarted silently).
    public func applySettings(_ machine: MachineSummary, settings: [String]) {
        settingsTarget = nil
        guard !settings.isEmpty else { return }
        let operationID = operations.begin(
            title: "Updating settings of \(machine.name)",
            kind: .other,
            redactedCommand: "container machine set --name \(machine.name) " + settings.joined(separator: " ")
        )
        Task {
            do {
                try await engine.setMachine(name: machine.name, settings: settings)
                operations.finish(operationID, status: .succeeded)
                pendingRestart.insert(machine.name)
            } catch {
                report(error, operation: operationID, action: "updating machine settings")
            }
            await resources.machines.refresh()
        }
    }

    public func setDefault(_ machine: MachineSummary) {
        mutate(machine.name, title: "Setting \(machine.name) as default",
               command: "container machine set-default \(machine.name)") { engine in
            try await engine.setDefaultMachine(name: machine.name)
        }
    }

    public func runCommand(_ machine: MachineSummary, command: String) {
        runCommandTarget = nil
        let tokens = ContainerArgumentBuilder.tokenize(command)
        guard !tokens.isEmpty else { return }
        let operationID = operations.begin(
            title: "Running command in \(machine.name)",
            kind: .other,
            redactedCommand: "container machine run --name \(machine.name) " + command
        )
        Task {
            do {
                let output = try await engine.runMachineCommand(name: machine.name, command: tokens)
                operations.appendOutput(operationID, text: output)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "running the command")
            }
            await resources.machines.refresh()
        }
    }

    private func mutate(
        _ name: String,
        title: String,
        command: String,
        _ body: @escaping @Sendable (any ContainerEngine) async throws -> Void
    ) {
        guard !isBusy(name) else { return }
        busyMachines.insert(name)
        let operationID = operations.begin(title: title, kind: .other, redactedCommand: command)
        let engine = engine
        Task {
            defer { busyMachines.remove(name) }
            do {
                try await body(engine)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: title.lowercased())
            }
            await resources.machines.refresh()
        }
    }

    private func report(_ error: Error, operation: UUID, action: String) {
        let facing: UserFacingError
        if let engineError = error as? ContainerEngineError {
            facing = UserFacingError.make(from: engineError, context: action)
        } else {
            facing = UserFacingError.make(from: .unexpectedOutput(error.localizedDescription), context: action)
        }
        lastError = facing
        operations.finish(operation, status: .failed(facing.title))
    }
}

/// Create Machine sheet (spec §28) with verified flags.
struct CreateMachineSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = MachineConfiguration()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Image", text: $configuration.image, prompt: Text("ubuntu:24.04"))
                    TextField("Name", text: $configuration.name, prompt: Text("Optional"))
                    TextField("CPUs", text: $configuration.cpus, prompt: Text("Optional"))
                    TextField("Memory", text: $configuration.memory, prompt: Text("Optional, e.g. 8G (default: half of system)"))
                    Picker("Home directory", selection: $configuration.homeMount) {
                        ForEach(MachineConfiguration.HomeMount.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
                Section("Advanced") {
                    TextField("Platform", text: $configuration.platform, prompt: Text("Optional, e.g. linux/arm64"))
                    Toggle("Set as default machine", isOn: $configuration.setAsDefault)
                    Toggle("Create without booting", isOn: $configuration.createWithoutBooting)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    env.machineActions.create(configuration)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(configuration.image.trimmingCharacters(in: .whitespaces).isEmpty
                    || env.power.state != .running)
            }
            .padding(12)
        }
        .frame(minWidth: 480, minHeight: 380)
    }
}

/// One-shot command sheet (spec §28: no embedded PTY).
struct MachineRunCommandSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let machine: MachineSummary
    @State private var command = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Run Command in \(machine.name)")
                .font(.headline)
            TextField("Command", text: $command, prompt: Text("uname -a"))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            Text("Runs once without a TTY; output appears in the operation panel. The machine boots if it is not running. For an interactive shell use Open Terminal.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Run") {
                    env.machineActions.runCommand(machine, command: command)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}

/// Machine settings sheet: cpus / memory / home-mount via `machine set`,
/// with the pending-restart contract made explicit.
struct MachineSettingsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let machine: MachineSummary
    @State private var cpus = ""
    @State private var memory = ""
    @State private var homeMount: MachineConfiguration.HomeMount?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings for \(machine.name)")
                .font(.headline)
            Form {
                TextField("CPUs", text: $cpus, prompt: Text(machine.cpuCount.map(String.init) ?? "unchanged"))
                TextField("Memory", text: $memory, prompt: Text("unchanged, e.g. 8G"))
                Picker("Home directory", selection: $homeMount) {
                    Text("Unchanged").tag(MachineConfiguration.HomeMount?.none)
                    ForEach(MachineConfiguration.HomeMount.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(MachineConfiguration.HomeMount?.some(mode))
                    }
                }
            }
            Text("Changes take effect after the machine restarts. ContainerDeck never restarts it silently — use Restart when you are ready.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    var settings: [String] = []
                    if !cpus.trimmingCharacters(in: .whitespaces).isEmpty {
                        settings.append("cpus=\(cpus.trimmingCharacters(in: .whitespaces))")
                    }
                    if !memory.trimmingCharacters(in: .whitespaces).isEmpty {
                        settings.append("memory=\(memory.trimmingCharacters(in: .whitespaces))")
                    }
                    if let homeMount {
                        settings.append("home-mount=\(homeMount.rawValue)")
                    }
                    env.machineActions.applySettings(machine, settings: settings)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}

/// Machine log viewer sharing the container log session.
struct MachineLogsView: View {
    @Environment(AppEnvironment.self) private var env
    let machine: MachineSummary

    var body: some View {
        ContainerLogsView(container: ContainerSummary(
            id: machine.name,
            name: machine.name,
            image: machine.image ?? "machine",
            state: machine.state
        ), logSource: .machine)
    }
}

/// Dialogs for machine actions.
struct MachineActionDialogs: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Binding var logsMachine: MachineSummary?

    func body(content: Content) -> some View {
        @Bindable var actions = env.machineActions
        content
            .sheet(isPresented: $actions.createSheetPresented) { CreateMachineSheet() }
            .sheet(item: $actions.runCommandTarget) { machine in
                MachineRunCommandSheet(machine: machine)
            }
            .sheet(item: $actions.settingsTarget) { machine in
                MachineSettingsSheet(machine: machine)
            }
            .sheet(item: $logsMachine) { machine in
                MachineLogsView(machine: machine)
            }
            .alert(
                "Delete machine?",
                isPresented: Binding(
                    get: { actions.pendingDelete != nil },
                    set: { if !$0 { actions.pendingDelete = nil } }
                ),
                presenting: actions.pendingDelete
            ) { _ in
                Button("Delete", role: .destructive) { actions.confirmDelete() }
                Button("Cancel", role: .cancel) { actions.pendingDelete = nil }
            } message: { machine in
                Text("“\(machine.name)” and its disk will be permanently deleted. This cannot be undone.")
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
    }
}
