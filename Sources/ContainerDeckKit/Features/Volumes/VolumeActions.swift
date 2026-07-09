import SwiftUI
import Observation

/// Volume mutations (spec §26): create, confirmed delete, confirmed prune.
/// The CLI has no force-delete for volumes; deleting an in-use volume fails
/// with the CLI's own error, which is surfaced verbatim.
@MainActor
@Observable
public final class VolumeActionsController {
    private let engine: any ContainerEngine
    private let operations: OperationStore
    private let resources: ResourceCenter

    public var lastError: UserFacingError?
    public var createSheetPresented = false
    public var pendingDelete: VolumeSummary?
    public var pendingPrune = false

    public init(engine: any ContainerEngine, operations: OperationStore, resources: ResourceCenter) {
        self.engine = engine
        self.operations = operations
        self.resources = resources
    }

    public func create(name: String, size: String, labels: [KeyValueEntry]) {
        createSheetPresented = false
        let sizeValue = size.trimmingCharacters(in: .whitespaces)
        let command = "container volume create "
            + (sizeValue.isEmpty ? "" : "-s \(sizeValue) ") + name
        let operationID = operations.begin(
            title: "Creating volume \(name)", kind: .other, redactedCommand: command
        )
        Task {
            do {
                try await engine.createVolume(
                    name: name, size: sizeValue.isEmpty ? nil : sizeValue, labels: labels
                )
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "creating the volume")
            }
            await resources.volumes.refresh()
        }
    }

    public func confirmDelete() {
        guard let volume = pendingDelete else { return }
        pendingDelete = nil
        let operationID = operations.begin(
            title: "Deleting volume \(volume.name)",
            kind: .other,
            redactedCommand: "container volume delete \(volume.name)"
        )
        Task {
            do {
                try await engine.deleteVolume(name: volume.name)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "deleting the volume")
            }
            await resources.volumes.refresh()
        }
    }

    public func confirmPrune() {
        pendingPrune = false
        let operationID = operations.begin(
            title: "Pruning unreferenced volumes",
            kind: .other,
            redactedCommand: "container volume prune"
        )
        Task {
            do {
                let summary = try await engine.pruneVolumes()
                operations.appendOutput(operationID, text: summary)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "pruning volumes")
            }
            await resources.volumes.refresh()
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

/// Create Volume sheet (verified flags: `-s <size>`, `--label k=v`).
struct CreateVolumeSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var size = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Volume")
                .font(.headline)
            Form {
                TextField("Name", text: $name, prompt: Text("app-data"))
                TextField("Size", text: $size, prompt: Text("Optional, e.g. 10G (default 512G sparse)"))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    env.volumeActions.create(
                        name: name.trimmingCharacters(in: .whitespaces),
                        size: size,
                        labels: []
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                    || env.power.state != .running)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

/// Sheets and confirmations for volume actions (spec §26: warn that data
/// deletion is permanent; prune explains its scope).
struct VolumeActionDialogs: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        @Bindable var actions = env.volumeActions
        content
            .sheet(isPresented: $actions.createSheetPresented) { CreateVolumeSheet() }
            .alert(
                "Delete volume?",
                isPresented: Binding(
                    get: { actions.pendingDelete != nil },
                    set: { if !$0 { actions.pendingDelete = nil } }
                ),
                presenting: actions.pendingDelete
            ) { _ in
                Button("Delete", role: .destructive) { actions.confirmDelete() }
                Button("Cancel", role: .cancel) { actions.pendingDelete = nil }
            } message: { volume in
                Text("All data in “\(volume.name)” will be permanently deleted. This cannot be undone. Apple Container refuses to delete volumes that are attached to containers.")
            }
            .alert("Prune volumes?", isPresented: $actions.pendingPrune) {
                Button("Prune", role: .destructive) { actions.confirmPrune() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Volumes with no container references will be permanently deleted, including their data. The operation reports how much space was reclaimed.")
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
