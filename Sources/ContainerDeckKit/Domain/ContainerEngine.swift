import Foundation

/// Options for starting the Apple Container system.
public struct SystemStartOptions: Sendable, Equatable {
    /// Passes `--enable-kernel-install` so a missing default kernel is
    /// installed without an interactive prompt. Only set after explicit user
    /// consent; never silently.
    public var installDefaultKernelIfNeeded: Bool

    public init(installDefaultKernelIfNeeded: Bool = false) {
        self.installDefaultKernelIfNeeded = installDefaultKernelIfNeeded
    }
}

/// The integration boundary between the feature layer and Apple Container.
///
/// Implementations: `AppleContainerCLIEngine` (real, via the installed CLI)
/// and `MockContainerEngine` (previews and tests). The CLI integration must
/// remain replaceable without touching the feature layer (spec §4).
///
/// Phase 0 implements the system-lifecycle members for real; resource members
/// throw `ContainerEngineError.featureUnavailable` from the CLI engine until
/// their phase arrives.
public protocol ContainerEngine: Sendable {
    func systemVersion() async throws -> ContainerSystemVersion
    func systemStatus() async throws -> ContainerSystemStatus

    func startSystem(options: SystemStartOptions) async throws
    func stopSystem() async throws

    func listContainers(all: Bool) async throws -> [ContainerSummary]
    func inspectContainer(id: String) async throws -> ContainerDetails
    func containerStatistics() async throws -> [ContainerStatistics]

    // Container lifecycle (Phase 2)

    /// Runs (detached) or creates a container; returns the container ID.
    func launchContainer(_ configuration: ContainerRunConfiguration) async throws -> String
    /// Attached run: streams output until the container's process exits.
    func launchContainerStreaming(
        _ configuration: ContainerRunConfiguration
    ) async throws -> AsyncThrowingStream<CommandOutputEvent, Error>
    func startContainer(id: String) async throws
    func stopContainer(id: String) async throws
    func killContainer(id: String) async throws
    func deleteContainer(id: String, force: Bool) async throws
    /// Removes all stopped containers; returns the CLI's summary output.
    func pruneContainers() async throws -> String
    /// Streams container logs (initial tail, optional follow, or boot log).
    func containerLogs(
        id: String,
        tail: Int?,
        follow: Bool,
        boot: Bool
    ) async throws -> AsyncThrowingStream<CommandOutputEvent, Error>

    func listImages() async throws -> [ImageSummary]
    func inspectImage(reference: String) async throws -> ImageDetails

    // Image workflow (Phase 3)

    /// Pulls an image, streaming plain progress output.
    func pullImage(reference: String, platform: String?) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error>
    func tagImage(source: String, target: String) async throws
    /// Returns the CLI's "Reclaimed …" summary.
    func deleteImage(reference: String) async throws -> String
    /// Removes dangling (or, with all, every unused) image; returns summary.
    func pruneImages(all: Bool) async throws -> String
    func saveImage(reference: String, to path: String, platform: String?) async throws
    /// Returns the loaded image references (CLI output).
    func loadImage(from path: String) async throws -> String
    /// Builds an image, streaming plain progress output.
    func buildImage(_ configuration: BuildConfiguration) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error>

    // Builder lifecycle (Phase 3)

    func startBuilder(cpus: String?, memory: String?) async throws
    func stopBuilder() async throws
    func deleteBuilder(force: Bool) async throws

    // Registry (Phase 3)

    /// Logs in; the password travels via stdin only (spec §25).
    func registryLogin(server: String, username: String, password: Data) async throws
    func registryLogout(server: String) async throws

    func listVolumes() async throws -> [VolumeSummary]
    func inspectVolume(name: String) async throws -> VolumeDetails

    // Volume & network management (Phase 4)

    func createVolume(name: String, size: String?, labels: [KeyValueEntry]) async throws
    func deleteVolume(name: String) async throws
    /// Removes volumes with no container references; returns the CLI summary.
    func pruneVolumes() async throws -> String
    func createNetwork(name: String) async throws
    func deleteNetwork(name: String) async throws

    func listNetworks() async throws -> [NetworkSummary]
    func inspectNetwork(name: String) async throws -> NetworkDetails

    func listMachines() async throws -> [MachineSummary]
    func inspectMachine(name: String) async throws -> MachineDetails

    // Machine management (Phase 5)

    /// Creates (and by default boots) a machine, streaming progress.
    func createMachine(_ configuration: MachineConfiguration) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error>
    func stopMachine(name: String) async throws
    func deleteMachine(name: String) async throws
    /// Applies `key=value` settings (cpus/memory/home-mount); effective after restart.
    func setMachine(name: String, settings: [String]) async throws
    func setDefaultMachine(name: String) async throws
    /// One-shot command; returns combined output. Boots the machine if needed.
    func runMachineCommand(name: String, command: [String]) async throws -> String
    func machineLogs(name: String, tail: Int?, follow: Bool, boot: Bool) async throws
        -> AsyncThrowingStream<CommandOutputEvent, Error>

    func listRegistries() async throws -> [RegistryEntry]
    func builderStatus() async throws -> BuilderStatus

    func diskUsage() async throws -> DiskUsage
    func capabilities() async throws -> EngineCapabilities
}

extension ContainerEngine {
    /// Convenience matching the spec §4 signature.
    public func startSystem() async throws {
        try await startSystem(options: SystemStartOptions())
    }
}
