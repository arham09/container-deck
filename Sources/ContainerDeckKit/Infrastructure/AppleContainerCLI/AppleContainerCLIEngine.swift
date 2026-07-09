import Foundation

/// Real engine backed by the installed `container` CLI.
///
/// All commands and JSON schemas verified against CLI 1.0.0 —
/// see docs/supported-commands.md and Tests/.../Fixtures/.
public final class AppleContainerCLIEngine: ContainerEngine, Sendable {
    private let runner: any CommandRunning
    private let executableURL: @Sendable () async throws -> URL

    /// Marker the CLI prints when the system services are not running.
    private static let serviceDownMarker = "Ensure container system service has been started"
    /// Marker printed when a CLI plugin (e.g. container-network) is missing.
    private static let pluginMissingMarker = "not found"

    public init(
        runner: any CommandRunning,
        executableURL: @escaping @Sendable () async throws -> URL
    ) {
        self.runner = runner
        self.executableURL = executableURL
    }

    // MARK: - System lifecycle

    public func systemVersion() async throws -> ContainerSystemVersion {
        let result = try await run(
            arguments: ["system", "version", "--format", "json"],
            timeout: .seconds(15)
        )
        guard result.isSuccess else {
            throw failure(result, arguments: ["system", "version", "--format", "json"])
        }
        return try SystemVersionMapper.map(data: result.standardOutput)
    }

    public func systemStatus() async throws -> ContainerSystemStatus {
        let arguments = ["system", "status", "--format", "json"]
        let result = try await run(arguments: arguments, timeout: .seconds(15))
        // Verified with CLI 1.0.0: status exits 1 when the system is stopped
        // but still prints valid JSON. Valid JSON wins over the exit code.
        do {
            return try SystemStatusMapper.map(data: result.standardOutput)
        } catch {
            if !result.isSuccess {
                throw failure(result, arguments: arguments)
            }
            throw error
        }
    }

    public func startSystem(options: SystemStartOptions) async throws {
        var arguments = ["system", "start"]
        if options.installDefaultKernelIfNeeded {
            arguments.append("--enable-kernel-install")
        }
        // Kernel download can be slow; allow a generous window when installing.
        let timeout: Duration = options.installDefaultKernelIfNeeded ? .seconds(600) : .seconds(120)
        let result = try await run(arguments: arguments, timeout: timeout)

        if !result.isSuccess {
            let combinedOutput = result.standardOutputText + "\n" + result.standardErrorText
            // Verified with CLI 1.0.0: without a configured default kernel,
            // start prompts interactively; under our closed stdin it fails
            // while the apiserver may still come up. Surface a typed error
            // so the UI can ask the user for an explicit install decision.
            if combinedOutput.contains("No default kernel configured") {
                throw ContainerEngineError.kernelInstallationRequired(
                    "Apple Container reported that no default kernel is configured."
                )
            }
            throw failure(result, arguments: arguments)
        }
        // Exit code 0 is not proof the system is ready (spec §12); the caller
        // verifies by polling systemStatus().
    }

    public func stopSystem() async throws {
        let arguments = ["system", "stop"]
        let result = try await run(arguments: arguments, timeout: .seconds(60))
        guard result.isSuccess else {
            throw failure(result, arguments: arguments)
        }
    }

    public func capabilities() async throws -> EngineCapabilities {
        let version = try? await systemVersion()
        var capabilities = EngineCapabilities.phase0(cliVersion: version?.version)
        capabilities.resourceListing = .supported
        // Verified with CLI 1.0.0: `container stats` returned an empty array
        // even for running containers, so live usage is not shown.
        capabilities.statistics = .supportedWithLimitations(
            "container stats returned no per-container data with the installed CLI."
        )
        // The `container network` subcommand requires the container-network
        // plugin, which may not be installed. Probe it honestly.
        do {
            _ = try await listNetworks()
            capabilities.networks = .supported
        } catch let error as ContainerEngineError {
            switch error {
            case .featureUnavailable(let reason):
                capabilities.networks = .unavailable(reason)
            case .serviceNotRunning:
                capabilities.networks = .supportedWithLimitations(
                    "Availability is checked while Apple Container is running."
                )
            default:
                capabilities.networks = .unavailable("The network plugin probe failed.")
            }
        }
        return capabilities
    }

    // MARK: - Containers

    public func listContainers(all: Bool) async throws -> [ContainerSummary] {
        var arguments = ["list"]
        if all { arguments.append("--all") }
        arguments += ["--format", "json"]
        let data = try await runExpectingJSON(arguments: arguments)
        return try ContainerMapper.summaries(from: data, command: "container list")
    }

    public func inspectContainer(id: String) async throws -> ContainerDetails {
        try InputValidator.validateResourceName(id)
        let data = try await runExpectingJSON(arguments: ["inspect", id])
        let entries = try ResourceMappers.decode(
            [ContainerEntryDTO].self, from: data, command: "container inspect"
        )
        guard let first = entries.first, let summary = ContainerMapper.summary(from: first) else {
            throw ContainerEngineError.unexpectedOutput("inspect returned no entry for \(id)")
        }
        return ContainerDetails(summary: summary, rawJSON: String(decoding: data, as: UTF8.self))
    }

    public func containerStatistics() async throws -> [ContainerStatistics] {
        // Verified with CLI 1.0.0: returns [] even with running containers.
        // Decoded tolerantly; row schema integration waits until a CLI
        // version actually emits rows (Activity arrives in Phase 6 anyway).
        let data = try await runExpectingJSON(
            arguments: ["stats", "--no-stream", "--format", "json"]
        )
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ContainerEngineError.decodingFailed(
                command: "container stats",
                underlying: "expected a JSON array"
            )
        }
        if !array.isEmpty {
            // Schema not yet verified — report honestly rather than guess.
            throw ContainerEngineError.featureUnavailable(
                "The installed CLI returned statistics in a format ContainerDeck has not verified yet."
            )
        }
        return []
    }

    // MARK: - Container lifecycle (Phase 2)

    public func launchContainer(_ configuration: ContainerRunConfiguration) async throws -> String {
        var configuration = configuration
        configuration.detached = true
        let built = try ContainerArgumentBuilder.build(configuration)
        // Image pulls can be part of a first run; allow a generous window.
        let executable = try await executableURL()
        let request = CommandRequest(
            executable: executable,
            arguments: built.arguments,
            timeout: .seconds(600),
            redactedArguments: built.redactedArguments
        )
        let result = try await runner.run(request)
        guard result.isSuccess else {
            throw try mappedListFailure(result, arguments: built.redactedArguments)
        }
        // Verified with CLI 1.0.0: the container ID is the last non-empty
        // stdout line after the plain progress output.
        let id = result.standardOutputText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && !$0.hasPrefix("[") }
        guard let id else {
            throw ContainerEngineError.unexpectedOutput("run/create did not report a container ID")
        }
        return id
    }

    public func launchContainerStreaming(
        _ configuration: ContainerRunConfiguration
    ) async throws -> AsyncThrowingStream<CommandOutputEvent, Error> {
        var configuration = configuration
        configuration.detached = false
        let built = try ContainerArgumentBuilder.build(configuration)
        let executable = try await executableURL()
        let request = CommandRequest(
            executable: executable,
            arguments: built.arguments,
            redactedArguments: built.redactedArguments
        )
        return runner.stream(request)
    }

    public func startContainer(id: String) async throws {
        try InputValidator.validateResourceName(id)
        _ = try await runExpectingJSON(arguments: ["start", id], timeout: .seconds(120))
    }

    public func stopContainer(id: String) async throws {
        try InputValidator.validateResourceName(id)
        _ = try await runExpectingJSON(arguments: ["stop", id], timeout: .seconds(60))
    }

    public func killContainer(id: String) async throws {
        try InputValidator.validateResourceName(id)
        _ = try await runExpectingJSON(arguments: ["kill", id], timeout: .seconds(30))
    }

    public func deleteContainer(id: String, force: Bool) async throws {
        try InputValidator.validateResourceName(id)
        var arguments = ["delete"]
        if force { arguments.append("--force") }
        arguments.append(id)
        _ = try await runExpectingJSON(arguments: arguments, timeout: .seconds(60))
    }

    public func pruneContainers() async throws -> String {
        return try await runForSummary(arguments: ["prune"], timeout: .seconds(120))
    }

    public func containerLogs(
        id: String,
        tail: Int?,
        follow: Bool,
        boot: Bool
    ) async throws -> AsyncThrowingStream<CommandOutputEvent, Error> {
        try InputValidator.validateResourceName(id)
        var arguments = ["logs"]
        if boot { arguments.append("--boot") }
        if follow { arguments.append("--follow") }
        if let tail {
            guard tail > 0 else {
                throw ContainerEngineError.invalidInput("Log tail must be positive.")
            }
            arguments.append(contentsOf: ["-n", String(tail)])
        }
        arguments.append(id)
        let executable = try await executableURL()
        return runner.stream(CommandRequest(executable: executable, arguments: arguments))
    }

    // MARK: - Images

    public func listImages() async throws -> [ImageSummary] {
        let data = try await runExpectingJSON(
            arguments: ["image", "list", "--verbose", "--format", "json"]
        )
        return try ImageMapper.summaries(from: data, command: "container image list")
    }

    public func inspectImage(reference: String) async throws -> ImageDetails {
        let data = try await runExpectingJSON(arguments: ["image", "inspect", reference])
        let entries = try ResourceMappers.decode(
            [ImageEntryDTO].self, from: data, command: "container image inspect"
        )
        guard let first = entries.first, let summary = ImageMapper.summary(from: first) else {
            throw ContainerEngineError.unexpectedOutput("inspect returned no entry for \(reference)")
        }
        return ImageDetails(summary: summary, rawJSON: String(decoding: data, as: UTF8.self))
    }

    // MARK: - Image workflow (Phase 3)

    public func pullImage(reference: String, platform: String?) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error> {
        try InputValidator.validateImageReference(reference)
        var arguments = ["image", "pull", "--progress", "plain"]
        if let platform, !platform.isEmpty {
            arguments.append(contentsOf: ["--platform", platform])
        }
        arguments.append(reference)
        let executable = try await executableURL()
        return runner.stream(CommandRequest(executable: executable, arguments: arguments))
    }

    public func tagImage(source: String, target: String) async throws {
        try InputValidator.validateImageReference(source)
        try InputValidator.validateImageReference(target)
        _ = try await runExpectingJSON(arguments: ["image", "tag", source, target])
    }

    public func deleteImage(reference: String) async throws -> String {
        try InputValidator.validateImageReference(reference)
        return try await runForSummary(
            arguments: ["image", "delete", reference], timeout: .seconds(120)
        )
    }

    public func pruneImages(all: Bool) async throws -> String {
        var arguments = ["image", "prune"]
        if all { arguments.append("--all") }
        return try await runForSummary(arguments: arguments, timeout: .seconds(300))
    }

    public func saveImage(reference: String, to path: String, platform: String?) async throws {
        try InputValidator.validateImageReference(reference)
        guard path.hasPrefix("/") else {
            throw ContainerEngineError.invalidInput("Save path must be absolute.")
        }
        var arguments = ["image", "save", "--output", path]
        if let platform, !platform.isEmpty {
            arguments.append(contentsOf: ["--platform", platform])
        }
        arguments.append(reference)
        _ = try await runExpectingJSON(arguments: arguments, timeout: .seconds(600))
    }

    public func loadImage(from path: String) async throws -> String {
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else {
            throw ContainerEngineError.invalidInput("No archive exists at \(path).")
        }
        let data = try await runExpectingJSON(
            arguments: ["image", "load", "--input", path], timeout: .seconds(600)
        )
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func buildImage(_ configuration: BuildConfiguration) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error> {
        let built = try BuildArgumentBuilder.build(configuration)
        let executable = try await executableURL()
        return runner.stream(CommandRequest(
            executable: executable,
            arguments: built.arguments,
            redactedArguments: built.redactedArguments
        ))
    }

    // MARK: - Builder lifecycle (Phase 3)

    public func startBuilder(cpus: String?, memory: String?) async throws {
        var arguments = ["builder", "start"]
        if let cpus, !cpus.isEmpty {
            try InputValidator.validateCPUCount(cpus)
            arguments.append(contentsOf: ["--cpus", cpus])
        }
        if let memory, !memory.isEmpty {
            try InputValidator.validateMemoryString(memory)
            arguments.append(contentsOf: ["--memory", memory])
        }
        // First start may pull the BuildKit image.
        _ = try await runExpectingJSON(arguments: arguments, timeout: .seconds(600))
    }

    public func stopBuilder() async throws {
        _ = try await runExpectingJSON(arguments: ["builder", "stop"], timeout: .seconds(60))
    }

    public func deleteBuilder(force: Bool) async throws {
        var arguments = ["builder", "delete"]
        if force { arguments.append("--force") }
        _ = try await runExpectingJSON(arguments: arguments, timeout: .seconds(60))
    }

    // MARK: - Registry (Phase 3)

    public func registryLogin(server: String, username: String, password: Data) async throws {
        guard !server.isEmpty, !server.contains(" ") else {
            throw ContainerEngineError.invalidInput("Registry server must not contain spaces.")
        }
        guard !username.isEmpty else {
            throw ContainerEngineError.invalidInput("Username must not be empty.")
        }
        guard !password.isEmpty else {
            throw ContainerEngineError.invalidInput("Password must not be empty.")
        }
        // Password over stdin only — never in arguments (verified:
        // --password-stdin exists in CLI 1.0.0). Never logged or persisted.
        let arguments = ["registry", "login", "--username", username, "--password-stdin", server]
        let executable = try await executableURL()
        let request = CommandRequest(
            executable: executable,
            arguments: arguments,
            standardInput: password,
            timeout: .seconds(60)
        )
        let result = try await runner.run(request)
        guard result.isSuccess else {
            throw try mappedListFailure(result, arguments: arguments)
        }
    }

    public func registryLogout(server: String) async throws {
        guard !server.isEmpty, !server.contains(" ") else {
            throw ContainerEngineError.invalidInput("Registry server must not contain spaces.")
        }
        _ = try await runExpectingJSON(arguments: ["registry", "logout", server])
    }

    // MARK: - Volumes

    public func listVolumes() async throws -> [VolumeSummary] {
        let data = try await runExpectingJSON(arguments: ["volume", "list", "--format", "json"])
        return try VolumeMapper.summaries(from: data, command: "container volume list")
    }

    public func inspectVolume(name: String) async throws -> VolumeDetails {
        try InputValidator.validateResourceName(name)
        let data = try await runExpectingJSON(arguments: ["volume", "inspect", name])
        let entries = try ResourceMappers.decode(
            [VolumeEntryDTO].self, from: data, command: "container volume inspect"
        )
        guard let first = entries.first, let summary = VolumeMapper.summary(from: first) else {
            throw ContainerEngineError.unexpectedOutput("inspect returned no entry for \(name)")
        }
        return VolumeDetails(summary: summary, rawJSON: String(decoding: data, as: UTF8.self))
    }

    // MARK: - Volume management (Phase 4)

    public func createVolume(name: String, size: String?, labels: [KeyValueEntry]) async throws {
        try InputValidator.validateResourceName(name)
        var arguments = ["volume", "create"]
        if let size, !size.isEmpty {
            try InputValidator.validateMemoryString(size)
            arguments.append(contentsOf: ["-s", size])
        }
        for label in labels where !label.key.isEmpty {
            try InputValidator.validateEnvironmentKey(label.key)
            arguments.append(contentsOf: ["--label", "\(label.key)=\(label.value)"])
        }
        arguments.append(name)
        _ = try await runExpectingJSON(arguments: arguments, timeout: .seconds(120))
    }

    public func deleteVolume(name: String) async throws {
        try InputValidator.validateResourceName(name)
        _ = try await runExpectingJSON(arguments: ["volume", "delete", name], timeout: .seconds(60))
    }

    public func pruneVolumes() async throws -> String {
        try await runForSummary(arguments: ["volume", "prune"], timeout: .seconds(120))
    }

    /// Network mutations are capability-gated: the container-network plugin
    /// is not installed on the verification machine, so create/delete flag
    /// formats could not be verified (spec §5: never guess).
    public func createNetwork(name: String) async throws {
        throw ContainerEngineError.featureUnavailable(
            "Network management requires macOS 26 or later."
        )
    }

    public func deleteNetwork(name: String) async throws {
        throw ContainerEngineError.featureUnavailable(
            "Network management requires macOS 26 or later."
        )
    }

    // MARK: - Networks

    public func listNetworks() async throws -> [NetworkSummary] {
        // Verified on the reference installation: the `network` subcommand
        // requires the container-network plugin, which is not part of the
        // standard install. Schema is therefore unverified; the command is
        // capability-gated until a plugin-equipped installation is available.
        let arguments = ["network", "list", "--format", "json"]
        let result = try await run(arguments: arguments, timeout: .seconds(15))
        if !result.isSuccess {
            let output = result.standardOutputText + result.standardErrorText
            if output.contains("Plugin"), output.contains(Self.pluginMissingMarker) {
                // Verified against apple/container docs: custom networks
                // require macOS 26+; the macOS 15 installer ships no
                // container-network plugin.
                throw ContainerEngineError.featureUnavailable(
                    "Network management requires macOS 26 or later. Apple Container on macOS 15 supports only the built-in default network, which your containers already use."
                )
            }
            throw try mappedListFailure(result, arguments: arguments)
        }
        throw ContainerEngineError.featureUnavailable(
            "Network listing is available but its format has not been verified with this CLI version yet."
        )
    }

    public func inspectNetwork(name: String) async throws -> NetworkDetails {
        throw ContainerEngineError.featureUnavailable(
            "Network management requires macOS 26 or later."
        )
    }

    // MARK: - Machines

    public func listMachines() async throws -> [MachineSummary] {
        let data = try await runExpectingJSON(arguments: ["machine", "list", "--format", "json"])
        return try MachineMapper.summaries(from: data, command: "container machine list")
    }

    public func inspectMachine(name: String) async throws -> MachineDetails {
        try InputValidator.validateResourceName(name)
        let data = try await runExpectingJSON(arguments: ["machine", "inspect", name])
        let entries = try ResourceMappers.decode(
            [MachineEntryDTO].self, from: data, command: "container machine inspect"
        )
        guard let first = entries.first, let summary = MachineMapper.summary(from: first) else {
            throw ContainerEngineError.unexpectedOutput("inspect returned no entry for \(name)")
        }
        return MachineDetails(
            summary: summary,
            homeMount: first.homeMount,
            rawJSON: String(decoding: data, as: UTF8.self)
        )
    }

    // MARK: - Machine management (Phase 5)

    public func createMachine(_ configuration: MachineConfiguration) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error> {
        try InputValidator.validateImageReference(configuration.image)
        var arguments = ["machine", "create", "--progress", "plain"]
        let name = configuration.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            try InputValidator.validateResourceName(name)
            arguments.append(contentsOf: ["--name", name])
        }
        let cpus = configuration.cpus.trimmingCharacters(in: .whitespaces)
        if !cpus.isEmpty {
            try InputValidator.validateCPUCount(cpus)
            arguments.append(contentsOf: ["--cpus", cpus])
        }
        let memory = configuration.memory.trimmingCharacters(in: .whitespaces)
        if !memory.isEmpty {
            try InputValidator.validateMemoryString(memory)
            arguments.append(contentsOf: ["--memory", memory])
        }
        arguments.append(contentsOf: ["--home-mount", configuration.homeMount.rawValue])
        if configuration.setAsDefault { arguments.append("--set-default") }
        if configuration.createWithoutBooting { arguments.append("--no-boot") }
        let platform = configuration.platform.trimmingCharacters(in: .whitespaces)
        if !platform.isEmpty {
            arguments.append(contentsOf: ["--platform", platform])
        }
        arguments.append(configuration.image)
        let executable = try await executableURL()
        return runner.stream(CommandRequest(executable: executable, arguments: arguments))
    }

    public func stopMachine(name: String) async throws {
        try InputValidator.validateResourceName(name)
        _ = try await runExpectingJSON(arguments: ["machine", "stop", name], timeout: .seconds(120))
    }

    public func deleteMachine(name: String) async throws {
        try InputValidator.validateResourceName(name)
        _ = try await runExpectingJSON(arguments: ["machine", "delete", name], timeout: .seconds(120))
    }

    public func setMachine(name: String, settings: [String]) async throws {
        try InputValidator.validateResourceName(name)
        // Verified keys: cpus=<n>, memory=<size>, home-mount=<ro|rw|none>.
        for setting in settings {
            let parts = setting.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  ["cpus", "memory", "home-mount"].contains(String(parts[0])) else {
                throw ContainerEngineError.invalidInput(
                    "Settings must be cpus=<n>, memory=<size>, or home-mount=<ro|rw|none>."
                )
            }
        }
        _ = try await runExpectingJSON(
            arguments: ["machine", "set", "--name", name] + settings, timeout: .seconds(60)
        )
    }

    public func setDefaultMachine(name: String) async throws {
        try InputValidator.validateResourceName(name)
        _ = try await runExpectingJSON(arguments: ["machine", "set-default", name])
    }

    public func runMachineCommand(name: String, command: [String]) async throws -> String {
        try InputValidator.validateResourceName(name)
        guard !command.isEmpty else {
            throw ContainerEngineError.invalidInput("Command must not be empty.")
        }
        // One-shot, no TTY (spec §28: no embedded PTY). Boots if necessary.
        return try await runForSummary(
            arguments: ["machine", "run", "--name", name] + command,
            timeout: .seconds(300)
        )
    }

    public func machineLogs(name: String, tail: Int?, follow: Bool, boot: Bool) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error> {
        try InputValidator.validateResourceName(name)
        var arguments = ["machine", "logs"]
        if boot { arguments.append("--boot") }
        if follow { arguments.append("--follow") }
        if let tail {
            guard tail > 0 else {
                throw ContainerEngineError.invalidInput("Log tail must be positive.")
            }
            arguments.append(contentsOf: ["-n", String(tail)])
        }
        arguments.append(name)
        let executable = try await executableURL()
        return runner.stream(CommandRequest(executable: executable, arguments: arguments))
    }

    // MARK: - Registries & builder

    public func listRegistries() async throws -> [RegistryEntry] {
        let data = try await runExpectingJSON(arguments: ["registry", "list", "--format", "json"])
        return try RegistryMapper.entries(from: data, command: "container registry list")
    }

    public func builderStatus() async throws -> BuilderStatus {
        let data = try await runExpectingJSON(arguments: ["builder", "status", "--format", "json"])
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ContainerEngineError.decodingFailed(
                command: "container builder status",
                underlying: "expected a JSON array"
            )
        }
        return BuilderStatus(
            isRunning: !array.isEmpty,
            rawJSON: String(decoding: data, as: UTF8.self)
        )
    }

    // MARK: - Disk usage

    public func diskUsage() async throws -> DiskUsage {
        let data = try await runExpectingJSON(arguments: ["system", "df", "--format", "json"])
        return try DiskUsageMapper.usage(from: data, command: "container system df")
    }

    // MARK: - Helpers

    private func run(arguments: [String], timeout: Duration) async throws -> CommandResult {
        let executable = try await executableURL()
        let request = CommandRequest(
            executable: executable,
            arguments: arguments,
            timeout: timeout
        )
        return try await runner.run(request)
    }

    /// Runs a read command, mapping the verified "system not started" error
    /// text to `serviceNotRunning` and returning stdout on success.
    private func runExpectingJSON(
        arguments: [String],
        timeout: Duration = .seconds(30)
    ) async throws -> Data {
        let result = try await run(arguments: arguments, timeout: timeout)
        guard result.isSuccess else {
            throw try mappedListFailure(result, arguments: arguments)
        }
        return result.standardOutput
    }

    private func mappedListFailure(
        _ result: CommandResult,
        arguments: [String]
    ) throws -> ContainerEngineError {
        let output = result.standardOutputText + result.standardErrorText
        if output.contains(Self.serviceDownMarker) {
            return .serviceNotRunning
        }
        return failure(result, arguments: arguments)
    }


    /// Runs a command whose human-readable summary may arrive on stdout or
    /// stderr (verified: image delete prints "Reclaimed …" on stderr).
    private func runForSummary(arguments: [String], timeout: Duration) async throws -> String {
        let result = try await run(arguments: arguments, timeout: timeout)
        guard result.isSuccess else {
            throw try mappedListFailure(result, arguments: arguments)
        }
        return (result.standardErrorText + "\n" + result.standardOutputText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func failure(_ result: CommandResult, arguments: [String]) -> ContainerEngineError {
        .commandFailed(
            executable: "container",
            arguments: arguments,
            exitCode: result.exitCode,
            stderr: String((result.standardErrorText.isEmpty
                ? result.standardOutputText
                : result.standardErrorText).prefix(4000))
        )
    }
}
