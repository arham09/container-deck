/// Domain model for `container system status --format json`.
///
/// Verified against Apple Container CLI 1.0.0: the command reports a `status`
/// string (`"running"`, `"unregistered"`, …) and exits non-zero when the
/// system is not running — a non-zero exit with valid JSON is a *state*, not
/// an error.
public struct ContainerSystemStatus: Sendable, Equatable {
    public enum Runtime: Sendable, Equatable {
        case running
        /// Not running; carries the exact status string the CLI reported
        /// (e.g. "unregistered") for diagnostics.
        case stopped(reportedStatus: String)
    }

    public var runtime: Runtime
    public var apiServerVersion: String?
    public var appRoot: String?
    public var installRoot: String?
    /// Raw CLI JSON, preserved for diagnostics and unknown fields.
    public var rawJSON: String

    public init(
        runtime: Runtime,
        apiServerVersion: String? = nil,
        appRoot: String? = nil,
        installRoot: String? = nil,
        rawJSON: String = ""
    ) {
        self.runtime = runtime
        self.apiServerVersion = apiServerVersion
        self.appRoot = appRoot
        self.installRoot = installRoot
        self.rawJSON = rawJSON
    }

    public var isRunning: Bool {
        if case .running = runtime { return true }
        return false
    }
}
