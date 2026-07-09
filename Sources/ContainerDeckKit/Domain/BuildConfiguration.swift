import Foundation

/// User input for `container build` (spec §23). Flags verified against CLI
/// 1.0.0: single `-t` tag, `-f` Dockerfile path, `--build-arg`, `--label`,
/// `--no-cache`, `--target`, `--cpus`, `--memory`, `--platform`, `--pull`,
/// `--secret id=<key>[,env=|,src=]`, `--progress plain`.
public struct BuildConfiguration: Sendable, Equatable {
    /// Build context directory (absolute path).
    public var contextDirectory = ""
    /// Dockerfile path; empty = the CLI default (Dockerfile in context).
    public var dockerfilePath = ""
    /// Image tag; empty would make the CLI generate a UUID name, so the UI
    /// requires one.
    public var tag = ""
    public var target = ""
    public var noCache = false
    public var pullBaseImage = false
    public var cpus = ""
    public var memory = ""
    public var platform = ""
    public var buildArguments: [KeyValueEntry] = []
    public var labels: [KeyValueEntry] = []
    /// Build secrets as raw `id=<key>[,env=ENV|,src=/path]` specs.
    public var secrets: [String] = []

    public init() {}
}

/// One persisted build record (spec §23: history survives restart).
public struct BuildRecord: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var tag: String
    public var contextDirectory: String
    /// Redacted command — build-arg values and secrets are masked.
    public var redactedCommand: String
    public var startedAt: Date
    public var duration: TimeInterval
    public var succeeded: Bool

    public init(
        id: UUID = UUID(),
        tag: String,
        contextDirectory: String,
        redactedCommand: String,
        startedAt: Date,
        duration: TimeInterval,
        succeeded: Bool
    ) {
        self.id = id
        self.tag = tag
        self.contextDirectory = contextDirectory
        self.redactedCommand = redactedCommand
        self.startedAt = startedAt
        self.duration = duration
        self.succeeded = succeeded
    }
}

/// User input for `container machine create` (spec §28). Flags verified
/// against CLI 1.0.0: -n/--name, --cpus, --memory, --home-mount (ro|rw|none),
/// --set-default, --no-boot, --platform, image argument.
public struct MachineConfiguration: Sendable, Equatable {
    public enum HomeMount: String, Sendable, CaseIterable {
        case rw, ro, none
        public var displayName: String {
            switch self {
            case .rw: "Read and write"
            case .ro: "Read-only"
            case .none: "Not mounted"
            }
        }
    }

    public var image = ""
    public var name = ""
    public var cpus = ""
    public var memory = ""
    public var homeMount: HomeMount = .rw
    public var setAsDefault = false
    public var createWithoutBooting = false
    public var platform = ""

    public init() {}
}
