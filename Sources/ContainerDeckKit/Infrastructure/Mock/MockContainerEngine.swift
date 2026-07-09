import Foundation

/// Scriptable in-memory engine for previews and tests.
///
/// System transitions are modeled honestly: `startSystem`/`stopSystem`
/// return like the CLI would, and the *status* — observed by polling —
/// determines the outcome, exactly like the real integration. This lets
/// tests cover "command succeeded but the state never changed".
public actor MockContainerEngine: ContainerEngine {
    public enum StartBehavior: Sendable {
        /// Status flips to running after `becomesRunningAfter` elapses.
        case success(becomesRunningAfter: Duration)
        /// Command returns success but status never reaches running.
        case succeedsButStaysStopped
        case fails(message: String)
        case requiresKernelInstall
    }

    public enum StopBehavior: Sendable {
        /// Status flips to stopped after `becomesStoppedAfter` elapses.
        case success(becomesStoppedAfter: Duration)
        /// Command returns success but status stays running.
        case succeedsButStaysRunning
        case fails(message: String)
    }

    private var running: Bool
    private var transitionDeadline: (target: Bool, at: ContinuousClock.Instant)?
    private let clock = ContinuousClock()

    public var startBehavior: StartBehavior
    public var stopBehavior: StopBehavior

    public var containers: [ContainerSummary]
    public var machines: [MachineSummary]
    public var images: [ImageSummary]
    public var volumes: [VolumeSummary]
    public var networks: [NetworkSummary]
    public var disk: DiskUsage

    public init(
        running: Bool = false,
        startBehavior: StartBehavior = .success(becomesRunningAfter: .milliseconds(400)),
        stopBehavior: StopBehavior = .success(becomesStoppedAfter: .milliseconds(300)),
        containers: [ContainerSummary] = MockData.containers,
        machines: [MachineSummary] = MockData.machines,
        images: [ImageSummary] = MockData.images,
        volumes: [VolumeSummary] = MockData.volumes,
        networks: [NetworkSummary] = MockData.networks,
        disk: DiskUsage = MockData.diskUsage
    ) {
        self.running = running
        self.startBehavior = startBehavior
        self.stopBehavior = stopBehavior
        self.containers = containers
        self.machines = machines
        self.images = images
        self.volumes = volumes
        self.networks = networks
        self.disk = disk
    }

    public func setStartBehavior(_ behavior: StartBehavior) {
        startBehavior = behavior
    }

    public func setStopBehavior(_ behavior: StopBehavior) {
        stopBehavior = behavior
    }

    public func setRunning(_ value: Bool) {
        running = value
        transitionDeadline = nil
    }

    // MARK: - System lifecycle

    public func systemVersion() async throws -> ContainerSystemVersion {
        MockData.version
    }

    public func systemStatus() async throws -> ContainerSystemStatus {
        applyPendingTransition()
        return ContainerSystemStatus(
            runtime: running ? .running : .stopped(reportedStatus: "unregistered"),
            apiServerVersion: running ? "container-apiserver version 1.0.0 (mock)" : nil,
            rawJSON: running ? #"{"status":"running"}"# : #"{"status":"unregistered"}"#
        )
    }

    public func startSystem(options: SystemStartOptions) async throws {
        switch startBehavior {
        case .success(let becomesRunningAfter):
            transitionDeadline = (target: true, at: clock.now.advanced(by: becomesRunningAfter))
        case .succeedsButStaysStopped:
            break
        case .fails(let message):
            throw ContainerEngineError.commandFailed(
                executable: "container",
                arguments: ["system", "start"],
                exitCode: 1,
                stderr: message
            )
        case .requiresKernelInstall:
            if options.installDefaultKernelIfNeeded {
                transitionDeadline = (target: true, at: clock.now.advanced(by: .milliseconds(400)))
            } else {
                throw ContainerEngineError.kernelInstallationRequired(
                    "Apple Container reported that no default kernel is configured."
                )
            }
        }
    }

    public func stopSystem() async throws {
        switch stopBehavior {
        case .success(let becomesStoppedAfter):
            transitionDeadline = (target: false, at: clock.now.advanced(by: becomesStoppedAfter))
        case .succeedsButStaysRunning:
            break
        case .fails(let message):
            throw ContainerEngineError.commandFailed(
                executable: "container",
                arguments: ["system", "stop"],
                exitCode: 1,
                stderr: message
            )
        }
    }

    public func capabilities() async throws -> EngineCapabilities {
        var capabilities = EngineCapabilities.phase0(cliVersion: MockData.version.version)
        capabilities.resourceListing = .supported
        capabilities.statistics = .supported
        capabilities.networks = .supported
        return capabilities
    }

    private func applyPendingTransition() {
        guard let pending = transitionDeadline, clock.now >= pending.at else { return }
        running = pending.target
        transitionDeadline = nil
    }

    // MARK: - Resources

    public func listContainers(all: Bool) async throws -> [ContainerSummary] {
        all ? containers : containers.filter(\.isRunning)
    }

    public func inspectContainer(id: String) async throws -> ContainerDetails {
        guard let summary = containers.first(where: { $0.id == id }) else {
            throw ContainerEngineError.unexpectedOutput("No container with ID \(id)")
        }
        return ContainerDetails(summary: summary, rawJSON: #"{"mock":true}"#)
    }

    public func containerStatistics() async throws -> [ContainerStatistics] {
        containers.filter(\.isRunning).map {
            ContainerStatistics(id: $0.id, cpuPercent: $0.cpuPercent, memoryBytes: $0.memoryBytes)
        }
    }

    public func listImages() async throws -> [ImageSummary] {
        images
    }

    public func inspectImage(reference: String) async throws -> ImageDetails {
        guard let summary = images.first(where: { $0.reference == reference }) else {
            throw ContainerEngineError.unexpectedOutput("No image \(reference)")
        }
        return ImageDetails(summary: summary, rawJSON: #"{"mock":true}"#)
    }

    public func listVolumes() async throws -> [VolumeSummary] {
        volumes
    }

    public func inspectVolume(name: String) async throws -> VolumeDetails {
        guard let summary = volumes.first(where: { $0.name == name }) else {
            throw ContainerEngineError.unexpectedOutput("No volume \(name)")
        }
        return VolumeDetails(summary: summary, rawJSON: #"{"mock":true}"#)
    }

    public func listNetworks() async throws -> [NetworkSummary] {
        networks
    }

    public func inspectNetwork(name: String) async throws -> NetworkDetails {
        guard let summary = networks.first(where: { $0.name == name }) else {
            throw ContainerEngineError.unexpectedOutput("No network \(name)")
        }
        return NetworkDetails(summary: summary, rawJSON: #"{"mock":true}"#)
    }

    public func listMachines() async throws -> [MachineSummary] {
        machines
    }

    public func inspectMachine(name: String) async throws -> MachineDetails {
        guard let summary = machines.first(where: { $0.name == name }) else {
            throw ContainerEngineError.unexpectedOutput("No machine \(name)")
        }
        return MachineDetails(summary: summary, rawJSON: #"{"mock":true}"#)
    }

    public func diskUsage() async throws -> DiskUsage {
        disk
    }

    // MARK: - Container lifecycle (Phase 2)

    public func launchContainer(_ configuration: ContainerRunConfiguration) async throws -> String {
        let built = try ContainerArgumentBuilder.build(configuration)
        _ = built  // validation happens exactly like the real engine
        let id = configuration.name.isEmpty ? "mock-\(containers.count + 1)" : configuration.name
        containers.append(ContainerSummary(
            id: id,
            name: id,
            image: configuration.image,
            state: configuration.mode == .run ? .running : .stopped,
            cpuLimit: Int(configuration.cpus),
            ipAddress: configuration.mode == .run ? "192.168.64.99" : nil,
            createdAt: Date()
        ))
        return id
    }

    public func launchContainerStreaming(
        _ configuration: ContainerRunConfiguration
    ) async throws -> AsyncThrowingStream<CommandOutputEvent, Error> {
        _ = try ContainerArgumentBuilder.build(configuration)
        let (stream, continuation) = AsyncThrowingStream<CommandOutputEvent, Error>.makeStream()
        continuation.yield(.stdout("mock container output line 1\n"))
        continuation.yield(.stdout("mock container output line 2\n"))
        continuation.yield(.completed(exitCode: 0))
        continuation.finish()
        return stream
    }

    public func startContainer(id: String) async throws {
        try mutateContainer(id: id, to: .running)
    }

    /// Scripted container-stop failures for restart-sequence tests.
    public enum ContainerStopBehavior: Sendable {
        case normal
        case fails
        /// Command "succeeds" but the container stays running.
        case noEffect
    }

    public var containerStopBehavior: ContainerStopBehavior = .normal

    public func setContainerStopBehavior(_ behavior: ContainerStopBehavior) {
        containerStopBehavior = behavior
    }

    public func stopContainer(id: String) async throws {
        switch containerStopBehavior {
        case .normal:
            try mutateContainer(id: id, to: .stopped)
        case .fails:
            throw ContainerEngineError.commandFailed(
                executable: "container", arguments: ["stop", id], exitCode: 1, stderr: "mock stop failure"
            )
        case .noEffect:
            guard containers.contains(where: { $0.id == id }) else {
                throw ContainerEngineError.unexpectedOutput("No container with ID \(id)")
            }
        }
    }

    public func killContainer(id: String) async throws {
        try mutateContainer(id: id, to: .stopped)
    }

    public func deleteContainer(id: String, force: Bool) async throws {
        guard let index = containers.firstIndex(where: { $0.id == id }) else {
            throw ContainerEngineError.unexpectedOutput("No container with ID \(id)")
        }
        // Mirrors the verified CLI behavior: running containers need force.
        if containers[index].isRunning, !force {
            throw ContainerEngineError.commandFailed(
                executable: "container",
                arguments: ["delete", id],
                exitCode: 1,
                stderr: "container \(id) is running and can not be deleted"
            )
        }
        containers.remove(at: index)
    }

    public func pruneContainers() async throws -> String {
        let stopped = containers.filter { !$0.isRunning }
        containers.removeAll { !$0.isRunning }
        return "Reclaimed 1.2 GB in disk space\n" + stopped.map(\.id).joined(separator: "\n")
    }

    public func containerLogs(
        id: String,
        tail: Int?,
        follow: Bool,
        boot: Bool
    ) async throws -> AsyncThrowingStream<CommandOutputEvent, Error> {
        guard containers.contains(where: { $0.id == id }) else {
            throw ContainerEngineError.unexpectedOutput("No container with ID \(id)")
        }
        let (stream, continuation) = AsyncThrowingStream<CommandOutputEvent, Error>.makeStream()
        let lineCount = tail ?? 20
        for line in 1...max(1, lineCount) {
            continuation.yield(.stdout("\(boot ? "[boot] " : "")mock log line \(line)\n"))
        }
        if !follow {
            continuation.yield(.completed(exitCode: 0))
            continuation.finish()
        }
        // Follow mode: leave the stream open like a real `logs --follow`.
        return stream
    }

    private func mutateContainer(id: String, to state: ResourceRunState) throws {
        guard let index = containers.firstIndex(where: { $0.id == id }) else {
            throw ContainerEngineError.unexpectedOutput("No container with ID \(id)")
        }
        containers[index].state = state
        containers[index].ipAddress = state == .running ? "192.168.64.99" : nil
    }

    // MARK: - Machine management (Phase 5)

    public func createMachine(_ configuration: MachineConfiguration) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error> {
        try InputValidator.validateImageReference(configuration.image)
        let name = configuration.name.isEmpty ? "machine-\(machines.count + 1)" : configuration.name
        machines.append(MachineSummary(
            name: name,
            image: configuration.image,
            state: configuration.createWithoutBooting ? .stopped : .running,
            cpuCount: Int(configuration.cpus) ?? 4,
            memoryBytes: 8_000_000_000,
            ipAddress: configuration.createWithoutBooting ? nil : "192.168.64.50",
            isDefault: configuration.setAsDefault,
            createdAt: Date()
        ))
        let (stream, continuation) = AsyncThrowingStream<CommandOutputEvent, Error>.makeStream()
        continuation.yield(.stdout("[1/3] Fetching image\n"))
        continuation.yield(.stdout(name + "\n"))
        continuation.yield(.completed(exitCode: 0))
        continuation.finish()
        return stream
    }

    public func stopMachine(name: String) async throws {
        guard let index = machines.firstIndex(where: { $0.name == name }) else {
            throw ContainerEngineError.unexpectedOutput("No machine \(name)")
        }
        machines[index].state = .stopped
        machines[index].ipAddress = nil
    }

    public func deleteMachine(name: String) async throws {
        let before = machines.count
        machines.removeAll { $0.name == name }
        guard machines.count < before else {
            throw ContainerEngineError.unexpectedOutput("No machine \(name)")
        }
    }

    public func setMachine(name: String, settings: [String]) async throws {
        guard machines.contains(where: { $0.name == name }) else {
            throw ContainerEngineError.unexpectedOutput("No machine \(name)")
        }
        for setting in settings where setting.hasPrefix("cpus=") {
            if let index = machines.firstIndex(where: { $0.name == name }) {
                machines[index].cpuCount = Int(setting.dropFirst(5))
            }
        }
    }

    public func setDefaultMachine(name: String) async throws {
        for index in machines.indices {
            machines[index].isDefault = machines[index].name == name
        }
    }

    public func runMachineCommand(name: String, command: [String]) async throws -> String {
        guard machines.contains(where: { $0.name == name }) else {
            throw ContainerEngineError.unexpectedOutput("No machine \(name)")
        }
        return "mock output of: " + command.joined(separator: " ")
    }

    public func machineLogs(name: String, tail: Int?, follow: Bool, boot: Bool) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error> {
        guard machines.contains(where: { $0.name == name }) else {
            throw ContainerEngineError.unexpectedOutput("No machine \(name)")
        }
        let (stream, continuation) = AsyncThrowingStream<CommandOutputEvent, Error>.makeStream()
        for line in 1...(tail ?? 10) {
            continuation.yield(.stdout("\(boot ? "[boot] " : "")machine log \(line)\n"))
        }
        if !follow {
            continuation.yield(.completed(exitCode: 0))
            continuation.finish()
        }
        return stream
    }

    // MARK: - Volume & network management (Phase 4)

    public func createVolume(name: String, size: String?, labels: [KeyValueEntry]) async throws {
        try InputValidator.validateResourceName(name)
        volumes.append(VolumeSummary(
            name: name,
            sizeBytes: 549_755_813_888,
            driver: "local",
            format: "ext4",
            createdAt: Date()
        ))
    }

    public func deleteVolume(name: String) async throws {
        let before = volumes.count
        volumes.removeAll { $0.name == name }
        guard volumes.count < before else {
            throw ContainerEngineError.unexpectedOutput("No volume \(name)")
        }
    }

    public func pruneVolumes() async throws -> String {
        "Reclaimed Zero KB in disk space"
    }

    public func createNetwork(name: String) async throws {
        networks.append(NetworkSummary(name: name, subnet: "192.168.66.0/24"))
    }

    public func deleteNetwork(name: String) async throws {
        networks.removeAll { $0.name == name }
    }

    public func listRegistries() async throws -> [RegistryEntry] {
        registries
    }

    public func builderStatus() async throws -> BuilderStatus {
        builder
    }

    // MARK: - Image workflow (Phase 3)

    public var registries: [RegistryEntry] = MockData.registries
    public var builder = MockData.builderStatus
    public private(set) var lastLoginPassword: Data?

    public func pullImage(reference: String, platform: String?) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error> {
        try InputValidator.validateImageReference(reference)
        let (repository, tag) = ImageMapper.splitReference(reference)
        images.append(ImageSummary(
            id: "sha256:mock-\(images.count)",
            repository: repository,
            tag: tag,
            sizeBytes: 42_000_000,
            createdAt: Date(),
            architectures: ["arm64"]
        ))
        let (stream, continuation) = AsyncThrowingStream<CommandOutputEvent, Error>.makeStream()
        continuation.yield(.stdout("[1/2] Fetching image\n"))
        continuation.yield(.stdout("[2/2] Unpacking image 100%\n"))
        continuation.yield(.completed(exitCode: 0))
        continuation.finish()
        return stream
    }

    public func tagImage(source: String, target: String) async throws {
        guard let existing = images.first(where: { $0.reference.hasSuffix(source) }) else {
            throw ContainerEngineError.unexpectedOutput("No image \(source)")
        }
        let (repository, tag) = ImageMapper.splitReference(target)
        var copy = existing
        copy.repository = repository
        copy.tag = tag
        images.append(copy)
    }

    public func deleteImage(reference: String) async throws -> String {
        let before = images.count
        images.removeAll { $0.reference.hasSuffix(reference) }
        guard images.count < before else {
            throw ContainerEngineError.unexpectedOutput("No image \(reference)")
        }
        return "Reclaimed 42 MB in disk space\n\(reference)"
    }

    public func pruneImages(all: Bool) async throws -> String {
        "Reclaimed Zero KB in disk space"
    }

    public func saveImage(reference: String, to path: String, platform: String?) async throws {
        guard images.contains(where: { $0.reference.hasSuffix(reference) }) else {
            throw ContainerEngineError.unexpectedOutput("No image \(reference)")
        }
        try Data("mock-archive".utf8).write(to: URL(fileURLWithPath: path))
    }

    public func loadImage(from path: String) async throws -> String {
        "docker.io/library/loaded:latest"
    }

    public func buildImage(_ configuration: BuildConfiguration) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error> {
        _ = try BuildArgumentBuilder.build(configuration)
        let (repository, tag) = ImageMapper.splitReference(configuration.tag)
        images.append(ImageSummary(
            id: "sha256:built-\(images.count)",
            repository: repository,
            tag: tag,
            sizeBytes: 99_000_000,
            createdAt: Date(),
            architectures: ["arm64"]
        ))
        let (stream, continuation) = AsyncThrowingStream<CommandOutputEvent, Error>.makeStream()
        continuation.yield(.stdout("#1 building with mock builder\n"))
        continuation.yield(.stdout("#2 exporting image\n"))
        continuation.yield(.completed(exitCode: 0))
        continuation.finish()
        return stream
    }

    // MARK: - Builder lifecycle (Phase 3)

    public func startBuilder(cpus: String?, memory: String?) async throws {
        builder = BuilderStatus(isRunning: true, rawJSON: #"[{"id":"buildkit","status":"running"}]"#)
    }

    public func stopBuilder() async throws {
        builder = BuilderStatus(isRunning: false, rawJSON: "[]")
    }

    public func deleteBuilder(force: Bool) async throws {
        builder = BuilderStatus(isRunning: false, rawJSON: "[]")
    }

    // MARK: - Registry (Phase 3)

    public func registryLogin(server: String, username: String, password: Data) async throws {
        guard !password.isEmpty else {
            throw ContainerEngineError.invalidInput("Password must not be empty.")
        }
        lastLoginPassword = password
        registries.append(RegistryEntry(display: server, rawJSON: "\"\(server)\""))
    }

    public func registryLogout(server: String) async throws {
        registries.removeAll { $0.display == server }
    }
}
