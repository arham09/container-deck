import Foundation

/// User input for `container run` / `container create` (spec §20).
/// Field values are kept as entered; `ContainerArgumentBuilder` validates and
/// converts them into an argument array — never a shell string.
public struct ContainerRunConfiguration: Sendable, Equatable, Codable {
    public enum Mode: String, Sendable, CaseIterable, Codable {
        case run
        case create

        public var displayName: String {
            switch self {
            case .run: "Run"
            case .create: "Create only"
            }
        }
    }

    public var mode: Mode = .run
    public var image = ""
    public var name = ""
    /// Init-process arguments, tokenized with quote support.
    public var commandLine = ""

    // Runtime options
    public var detached = true
    public var removeAfterStop = false
    public var useInit = false
    public var readOnlyRootFilesystem = false
    public var entrypoint = ""
    public var workingDirectory = ""

    // Resources
    public var cpus = ""
    public var memory = ""
    public var shmSize = ""

    // Platform
    public var architecture = ""
    public var os = ""
    public var platform = ""

    // Collections
    public var environment: [KeyValueEntry] = []
    public var environmentFile = ""
    public var labels: [KeyValueEntry] = []
    public var publishedPorts: [PublishedPortSpec] = []
    public var mounts: [MountSpec] = []
    public var networks: [NetworkAttachmentSpec] = []

    public init() {}
}

public struct KeyValueEntry: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

public struct PublishedPortSpec: Sendable, Equatable, Identifiable, Codable {
    public enum PortProtocol: String, Sendable, CaseIterable, Codable {
        case tcp
        case udp
    }

    public var id: UUID
    public var hostIP: String
    public var hostPort: String
    public var containerPort: String
    public var portProtocol: PortProtocol

    public init(
        id: UUID = UUID(),
        hostIP: String = "",
        hostPort: String = "",
        containerPort: String = "",
        portProtocol: PortProtocol = .tcp
    ) {
        self.id = id
        self.hostIP = hostIP
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.portProtocol = portProtocol
    }
}

public struct MountSpec: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var source: String
    public var target: String
    public var readOnly: Bool

    public init(id: UUID = UUID(), source: String = "", target: String = "", readOnly: Bool = false) {
        self.id = id
        self.source = source
        self.target = target
        self.readOnly = readOnly
    }
}

public struct NetworkAttachmentSpec: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }
}
