/// How well the installed Apple Container version supports a feature.
public enum FeatureSupport: Sendable, Equatable {
    case supported
    case supportedWithLimitations(String)
    case unavailable(String)
    case experimental(String)

    public var isUsable: Bool {
        switch self {
        case .supported, .supportedWithLimitations, .experimental: true
        case .unavailable: false
        }
    }
}

/// Capability report used to gate UI. Built from the installed CLI version
/// and verified behavior — features are never simulated (spec §11).
public struct EngineCapabilities: Sendable {
    public var cliVersion: String?
    public var systemLifecycle: FeatureSupport
    public var resourceListing: FeatureSupport
    /// Live per-container usage (`container stats`).
    public var statistics: FeatureSupport
    /// The `container network` subcommand (requires the network plugin).
    public var networks: FeatureSupport
    public var containerLifecycle: FeatureSupport
    public var logs: FeatureSupport
    public var builds: FeatureSupport
    public var machines: FeatureSupport

    public init(
        cliVersion: String?,
        systemLifecycle: FeatureSupport,
        resourceListing: FeatureSupport,
        statistics: FeatureSupport,
        networks: FeatureSupport,
        containerLifecycle: FeatureSupport,
        logs: FeatureSupport,
        builds: FeatureSupport,
        machines: FeatureSupport
    ) {
        self.cliVersion = cliVersion
        self.systemLifecycle = systemLifecycle
        self.resourceListing = resourceListing
        self.statistics = statistics
        self.networks = networks
        self.containerLifecycle = containerLifecycle
        self.logs = logs
        self.builds = builds
        self.machines = machines
    }

    /// Baseline: system power supported, everything else gated until its
    /// phase (callers override what they can actually verify).
    public static func phase0(cliVersion: String?) -> EngineCapabilities {
        EngineCapabilities(
            cliVersion: cliVersion,
            systemLifecycle: .supported,
            resourceListing: .unavailable("Resource browsing arrives in Phase 1."),
            statistics: .unavailable("Statistics arrive with resource browsing."),
            networks: .unavailable("Network support has not been probed."),
            containerLifecycle: .unavailable("Container lifecycle arrives in Phase 2."),
            logs: .unavailable("Logs arrive in Phase 2."),
            builds: .unavailable("Builds arrive in Phase 3."),
            machines: .unavailable("Machine management arrives in Phase 5.")
        )
    }
}
