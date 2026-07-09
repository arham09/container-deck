import Foundation
import Observation

/// Composition root: constructs and owns all shared services. Views receive
/// this via the SwiftUI environment and never construct engines themselves
/// (spec §4).
@MainActor
@Observable
public final class AppEnvironment {
    public let engine: any ContainerEngine
    public let settings: UserSettings
    public let operations: OperationStore
    public let power: SystemPowerController
    public let resources: ResourceCenter
    public let containerActions: ContainerLifecycleController
    public let imageActions: ImageActionsController
    public let volumeActions: VolumeActionsController
    public let machineActions: MachineActionsController
    public let metrics: MetricsStore
    public let savedConfigurations: SavedRunConfigurationStore
    public let terminalLauncher: any TerminalLaunching
    public let router: AppRouter
    /// True when running against `MockContainerEngine` (previews, mock mode).
    public let isMockMode: Bool

    public init(
        engine: any ContainerEngine,
        settings: UserSettings,
        operations: OperationStore,
        power: SystemPowerController,
        resources: ResourceCenter,
        isMockMode: Bool
    ) {
        self.engine = engine
        self.settings = settings
        self.operations = operations
        self.power = power
        self.resources = resources
        self.containerActions = ContainerLifecycleController(
            engine: engine,
            operations: operations,
            resources: resources
        )
        self.imageActions = ImageActionsController(
            engine: engine,
            operations: operations,
            resources: resources
        )
        self.volumeActions = VolumeActionsController(
            engine: engine,
            operations: operations,
            resources: resources
        )
        self.machineActions = MachineActionsController(
            engine: engine,
            operations: operations,
            resources: resources
        )
        self.metrics = MetricsStore(engine: engine, settings: settings)
        self.savedConfigurations = SavedRunConfigurationStore(
            fileURL: isMockMode
                ? FileManager.default.temporaryDirectory
                    .appendingPathComponent("containerdeck-preview-configs.json")
                : nil
        )
        self.terminalLauncher = ExternalTerminalLauncher()
        self.router = AppRouter()
        self.isMockMode = isMockMode

        power.onSystemStarted = { [weak resources] in
            Task { await resources?.refreshAll() }
        }
        power.onSystemStopped = { [weak resources] in
            resources?.markAllStale()
        }
    }

    /// Production wiring: real CLI engine behind binary discovery.
    /// Set CONTAINERDECK_USE_MOCK=1 to run the full app against mocks
    /// (useful without Apple Container installed).
    public static func live() -> AppEnvironment {
        if ProcessInfo.processInfo.environment["CONTAINERDECK_USE_MOCK"] == "1" {
            return preview(running: false)
        }

        let runner = CommandRunner()
        let locator = ContainerBinaryLocator(runner: runner)
        let engine = AppleContainerCLIEngine(runner: runner) {
            guard let location = await locator.currentLocation else {
                throw ContainerEngineError.binaryNotFound
            }
            return location.url
        }
        let settings = UserSettings()
        let operations = OperationStore()
        let power = SystemPowerController(
            engine: engine,
            operations: operations,
            settings: settings,
            locator: locator
        )
        let resources = ResourceCenter(engine: engine)
        return AppEnvironment(
            engine: engine,
            settings: settings,
            operations: operations,
            power: power,
            resources: resources,
            isMockMode: false
        )
    }

    /// Mock wiring for previews, tests, and mock mode.
    public static func preview(
        running: Bool = true,
        engine mockEngine: MockContainerEngine? = nil
    ) -> AppEnvironment {
        let engine = mockEngine ?? MockContainerEngine(running: running)
        // Isolated defaults so previews/mock mode never pollute real settings.
        let defaults = UserDefaults(suiteName: "dev.containerdeck.preview") ?? .standard
        defaults.removePersistentDomain(forName: "dev.containerdeck.preview")
        let settings = UserSettings(defaults: defaults)
        let operations = OperationStore()
        let power = SystemPowerController(
            engine: engine,
            operations: operations,
            settings: settings,
            pollInterval: .milliseconds(100)
        )
        let resources = ResourceCenter(engine: engine)
        return AppEnvironment(
            engine: engine,
            settings: settings,
            operations: operations,
            power: power,
            resources: resources,
            isMockMode: true
        )
    }
}
