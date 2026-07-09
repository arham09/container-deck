import Foundation
import Observation

/// Owns image, build, builder, and registry mutations (Phase 3):
/// confirmations, streaming pull/build output into the operation panel,
/// persisted build history, and refresh after every mutation.
@MainActor
@Observable
public final class ImageActionsController {
    private let engine: any ContainerEngine
    private let operations: OperationStore
    private let resources: ResourceCenter
    public let buildHistory: BuildHistoryStore

    public var lastError: UserFacingError?
    public var pullSheetPresented = false
    public var buildSheetPresented = false
    public var loginSheetPresented = false
    public var tagTarget: ImageSummary?
    public var pendingDelete: ImageSummary?
    public var pendingPrune = false
    public var pendingLogout: RegistryEntry?
    /// True while a builder mutation is in flight.
    public private(set) var builderBusy = false

    public init(engine: any ContainerEngine, operations: OperationStore, resources: ResourceCenter) {
        self.engine = engine
        self.operations = operations
        self.resources = resources
        self.buildHistory = BuildHistoryStore()
    }

    // MARK: - Pull

    public func pull(reference: String, platform: String) {
        pullSheetPresented = false
        let platformValue = platform.trimmingCharacters(in: .whitespaces)
        let command = "container image pull --progress plain "
            + (platformValue.isEmpty ? "" : "--platform \(platformValue) ") + reference
        let operationID = operations.begin(
            title: "Pulling \(reference)", kind: .other, redactedCommand: command
        )
        Task {
            do {
                let stream = try await engine.pullImage(
                    reference: reference,
                    platform: platformValue.isEmpty ? nil : platformValue
                )
                try await consume(stream, operationID: operationID)
            } catch {
                report(error, operation: operationID, action: "pulling \(reference)")
            }
            await refreshImages()
        }
    }

    // MARK: - Tag / delete / prune / save / load

    public func tag(source: ImageSummary, target: String) {
        tagTarget = nil
        let operationID = operations.begin(
            title: "Tagging \(source.reference) → \(target)",
            kind: .other,
            redactedCommand: "container image tag \(source.reference) \(target)"
        )
        Task {
            do {
                try await engine.tagImage(source: source.reference, target: target)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "tagging the image")
            }
            await refreshImages()
        }
    }

    public func confirmDelete() {
        guard let image = pendingDelete else { return }
        pendingDelete = nil
        let operationID = operations.begin(
            title: "Deleting \(image.reference)",
            kind: .other,
            redactedCommand: "container image delete \(image.reference)"
        )
        Task {
            do {
                let summary = try await engine.deleteImage(reference: image.reference)
                operations.appendOutput(operationID, text: summary)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "deleting the image")
            }
            await refreshImages()
        }
    }

    public func confirmPrune() {
        pendingPrune = false
        let operationID = operations.begin(
            title: "Pruning unused images",
            kind: .other,
            redactedCommand: "container image prune"
        )
        Task {
            do {
                let summary = try await engine.pruneImages(all: false)
                operations.appendOutput(operationID, text: summary)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "pruning images")
            }
            await refreshImages()
        }
    }

    public func save(image: ImageSummary, to path: String) {
        let operationID = operations.begin(
            title: "Saving \(image.reference)",
            kind: .other,
            redactedCommand: "container image save --output \(path) \(image.reference)"
        )
        Task {
            do {
                try await engine.saveImage(reference: image.reference, to: path, platform: nil)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "saving the image")
            }
        }
    }

    public func load(from path: String) {
        let operationID = operations.begin(
            title: "Loading images from \((path as NSString).lastPathComponent)",
            kind: .other,
            redactedCommand: "container image load --input \(path)"
        )
        Task {
            do {
                let loaded = try await engine.loadImage(from: path)
                operations.appendOutput(operationID, text: loaded)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "loading the archive")
            }
            await refreshImages()
        }
    }

    // MARK: - Build

    public func build(_ configuration: BuildConfiguration) {
        let built: ContainerArgumentBuilder.BuiltCommand
        do {
            built = try BuildArgumentBuilder.build(configuration)
        } catch let error as ContainerEngineError {
            lastError = UserFacingError.make(from: error)
            return
        } catch {
            lastError = UserFacingError.make(from: .unexpectedOutput(error.localizedDescription))
            return
        }
        buildSheetPresented = false
        let command = "container " + built.redactedArguments.joined(separator: " ")
        let operationID = operations.begin(
            title: "Building \(configuration.tag)", kind: .other, redactedCommand: command
        )
        let startedAt = Date()
        Task {
            var succeeded = false
            do {
                let stream = try await engine.buildImage(configuration)
                try await consume(stream, operationID: operationID)
                succeeded = true
            } catch {
                report(error, operation: operationID, action: "building \(configuration.tag)")
            }
            buildHistory.append(BuildRecord(
                tag: configuration.tag,
                contextDirectory: configuration.contextDirectory,
                redactedCommand: command,
                startedAt: startedAt,
                duration: Date().timeIntervalSince(startedAt),
                succeeded: succeeded
            ))
            await refreshImages()
            await resources.refreshAll()
        }
    }

    // MARK: - Builder

    public func startBuilder() {
        builderMutation(title: "Starting builder", command: "container builder start") { engine in
            try await engine.startBuilder(cpus: nil, memory: nil)
        }
    }

    public func stopBuilder() {
        builderMutation(title: "Stopping builder", command: "container builder stop") { engine in
            try await engine.stopBuilder()
        }
    }

    public func deleteBuilder() {
        builderMutation(title: "Deleting builder", command: "container builder delete") { engine in
            try await engine.deleteBuilder(force: false)
        }
    }

    private func builderMutation(
        title: String,
        command: String,
        _ body: @escaping @Sendable (any ContainerEngine) async throws -> Void
    ) {
        guard !builderBusy else { return }
        builderBusy = true
        let operationID = operations.begin(title: title, kind: .other, redactedCommand: command)
        let engine = engine
        Task {
            defer { builderBusy = false }
            do {
                try await body(engine)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: title.lowercased())
            }
            await resources.refreshAll()
        }
    }

    // MARK: - Registry

    /// Password goes to the engine as data destined for stdin; it is never
    /// stored, logged, or placed in any argument (spec §25).
    public func login(server: String, username: String, password: String) {
        loginSheetPresented = false
        let operationID = operations.begin(
            title: "Logging in to \(server)",
            kind: .other,
            redactedCommand: "container registry login --username \(username) --password-stdin \(server)"
        )
        Task {
            do {
                try await engine.registryLogin(
                    server: server, username: username, password: Data(password.utf8)
                )
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "logging in to \(server)")
            }
            await resources.registries.refresh()
        }
    }

    public func confirmLogout() {
        guard let entry = pendingLogout else { return }
        pendingLogout = nil
        let operationID = operations.begin(
            title: "Logging out of \(entry.display)",
            kind: .other,
            redactedCommand: "container registry logout \(entry.display)"
        )
        Task {
            do {
                try await engine.registryLogout(server: entry.display)
                operations.finish(operationID, status: .succeeded)
            } catch {
                report(error, operation: operationID, action: "logging out")
            }
            await resources.registries.refresh()
        }
    }

    // MARK: - Helpers

    private func consume(
        _ stream: AsyncThrowingStream<CommandOutputEvent, Error>,
        operationID: UUID
    ) async throws {
        for try await event in stream {
            switch event {
            case .stdout(let text), .stderr(let text):
                operations.appendOutput(operationID, text: text)
            case .completed(let code):
                if code == 0 {
                    operations.finish(operationID, status: .succeeded)
                } else {
                    operations.finish(operationID, status: .failed("Exited with code \(code)"))
                    throw ContainerEngineError.commandFailed(
                        executable: "container", arguments: [], exitCode: code, stderr: ""
                    )
                }
            }
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

    private func refreshImages() async {
        await resources.images.refresh()
    }
}

/// JSON-file-backed build history (spec §23: survives restart). Records
/// contain only redacted commands — never build-arg values or secrets.
@MainActor
@Observable
public final class BuildHistoryStore {
    public private(set) var records: [BuildRecord] = []
    private let fileURL: URL
    private let capacity = 100

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ContainerDeck/build-history.json")
        load()
    }

    public func append(_ record: BuildRecord) {
        records.insert(record, at: 0)
        if records.count > capacity {
            records.removeLast(records.count - capacity)
        }
        persist()
    }

    public func clear() {
        records = []
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BuildRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL)
        }
    }
}
