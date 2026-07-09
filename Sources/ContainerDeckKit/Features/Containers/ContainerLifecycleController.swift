import Foundation
import Observation

/// Owns container lifecycle mutations (spec §19): per-container duplicate
/// prevention, confirmations for destructive actions, operation-panel
/// records with redacted commands, and refresh after every mutation.
@MainActor
@Observable
public final class ContainerLifecycleController {
    private let engine: any ContainerEngine
    private let operations: OperationStore
    private let resources: ResourceCenter

    /// Container IDs with an in-flight mutation (duplicate guard, spec §9).
    public private(set) var busyContainers: Set<String> = []
    public var lastError: UserFacingError?

    // Confirmation state (bound to dialogs)
    public var pendingDelete: ContainerSummary?
    public var pendingForceDelete = false
    public var pendingPrune = false
    /// Run form presentation; `prefillImage` seeds the form's image field
    /// (used by "Run" on an image row).
    public var runFormPresented = false
    public var prefillImage: String?

    public init(engine: any ContainerEngine, operations: OperationStore, resources: ResourceCenter) {
        self.engine = engine
        self.operations = operations
        self.resources = resources
    }

    public func isBusy(_ id: String) -> Bool {
        busyContainers.contains(id)
    }

    // MARK: - Simple lifecycle actions

    public func start(_ container: ContainerSummary) {
        mutate(container.id, title: "Starting \(container.name)", command: "container start \(container.id)") { engine in
            try await engine.startContainer(id: container.id)
        }
    }

    public func stop(_ container: ContainerSummary) {
        mutate(container.id, title: "Stopping \(container.name)", command: "container stop \(container.id)") { engine in
            try await engine.stopContainer(id: container.id)
        }
    }

    public func kill(_ container: ContainerSummary) {
        mutate(container.id, title: "Killing \(container.name)", command: "container kill \(container.id)") { engine in
            try await engine.killContainer(id: container.id)
        }
    }

    /// Restart = stop, verify stopped, then start — one user-visible
    /// operation with distinct phases; start never runs if stop fails
    /// (spec §19).
    public func restart(_ container: ContainerSummary) {
        guard !isBusy(container.id) else { return }
        busyContainers.insert(container.id)
        let operationID = operations.begin(
            title: "Restarting \(container.name)",
            kind: .other,
            redactedCommand: "container stop \(container.id) && container start \(container.id)",
            phase: "Stopping"
        )
        Task {
            defer { busyContainers.remove(container.id) }
            do {
                try await engine.stopContainer(id: container.id)
                operations.updatePhase(operationID, phase: "Verifying the container stopped")
                let details = try await engine.inspectContainer(id: container.id)
                guard !details.summary.isRunning else {
                    throw ContainerEngineError.unexpectedOutput(
                        "The stop command completed, but \(container.name) still reports running."
                    )
                }
                operations.updatePhase(operationID, phase: "Starting")
                try await engine.startContainer(id: container.id)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "restarting \(container.name)")
            }
            await refreshAfterMutation()
        }
    }

    // MARK: - Deletion (confirmed, force distinct — spec §8)

    public func requestDelete(_ container: ContainerSummary) {
        pendingForceDelete = container.isRunning
        pendingDelete = container
    }

    public func confirmDelete() {
        guard let container = pendingDelete else { return }
        let force = pendingForceDelete
        pendingDelete = nil
        pendingForceDelete = false
        let command = "container delete \(force ? "--force " : "")\(container.id)"
        mutate(container.id, title: "Deleting \(container.name)", command: command) { engine in
            try await engine.deleteContainer(id: container.id, force: force)
        }
    }

    public func requestPrune() {
        pendingPrune = true
    }

    public func confirmPrune() {
        pendingPrune = false
        let operationID = operations.begin(
            title: "Pruning stopped containers",
            kind: .other,
            redactedCommand: "container prune"
        )
        Task {
            do {
                let summary = try await engine.pruneContainers()
                operations.appendOutput(operationID, text: summary)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "pruning containers")
            }
            await refreshAfterMutation()
        }
    }

    // MARK: - Run / create

    public func submitRunForm(_ configuration: ContainerRunConfiguration) {
        // Validate before doing anything; surface the error in the form.
        let built: ContainerArgumentBuilder.BuiltCommand
        do {
            built = try ContainerArgumentBuilder.build(configuration)
        } catch let error as ContainerEngineError {
            lastError = UserFacingError.make(from: error)
            return
        } catch {
            lastError = UserFacingError.make(from: .unexpectedOutput(error.localizedDescription))
            return
        }
        runFormPresented = false
        let title = configuration.mode == .run
            ? "Running \(configuration.image)"
            : "Creating container from \(configuration.image)"
        let command = "container " + built.redactedArguments.joined(separator: " ")
        let operationID = operations.begin(title: title, kind: .other, redactedCommand: command)

        if configuration.mode == .run, !configuration.detached {
            streamAttachedRun(configuration, operationID: operationID)
            return
        }
        Task {
            do {
                let id = try await engine.launchContainer(configuration)
                operations.appendOutput(operationID, text: "Container ID: \(id)\n")
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "launching the container")
            }
            await refreshAfterMutation()
        }
    }

    /// Attached run: the container's output streams into the operation record.
    private func streamAttachedRun(_ configuration: ContainerRunConfiguration, operationID: UUID) {
        Task {
            do {
                let stream = try await engine.launchContainerStreaming(configuration)
                operations.updatePhase(operationID, phase: "Attached — output below")
                // First list refresh so the new container appears while attached.
                Task { await self.refreshAfterMutation() }
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
                report(error, operation: operationID, action: "running the container")
            }
            await refreshAfterMutation()
        }
    }

    // MARK: - Helpers

    private func mutate(
        _ id: String,
        title: String,
        command: String,
        _ body: @escaping @Sendable (any ContainerEngine) async throws -> Void
    ) {
        guard !isBusy(id) else { return }
        busyContainers.insert(id)
        let operationID = operations.begin(title: title, kind: .other, redactedCommand: command)
        let engine = engine
        Task {
            defer { busyContainers.remove(id) }
            do {
                try await body(engine)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: title.lowercased())
            }
            await refreshAfterMutation()
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

    private func refreshAfterMutation() async {
        await resources.containers.refresh()
    }
}
