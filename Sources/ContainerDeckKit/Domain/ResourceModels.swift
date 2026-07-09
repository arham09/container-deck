import Foundation

// Domain models for Apple Container resources.
//
// Field choices are driven by schemas verified against CLI 1.0.0
// (see docs/supported-commands.md and Tests/.../Fixtures/). DTOs track the
// CLI; these models stay stable.

public enum ResourceRunState: String, Sendable, Equatable {
    case running
    case stopped
    case starting
    case stopping
    case failed

    public var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// A published port mapping (host → container). Schema verified against CLI
/// 1.0.0's `configuration.publishedPorts` (see ResourceDTOs.PublishedPort).
public struct ContainerPort: Sendable, Equatable {
    public var hostAddress: String?
    public var hostPort: Int
    public var containerPort: Int
    /// "tcp" / "udp" as reported; nil when unspecified.
    public var proto: String?

    public init(hostAddress: String? = nil, hostPort: Int, containerPort: Int, proto: String? = nil) {
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.proto = proto
    }
}

public struct ContainerSummary: Sendable, Equatable, Identifiable {
    /// Container ID (the CLI uses the user-visible name as the ID).
    public var id: String
    public var name: String
    public var image: String
    public var state: ResourceRunState
    /// Live usage — only populated when statistics are available.
    public var cpuPercent: Double?
    public var memoryBytes: Int64?
    /// Configured limits (from configuration.resources).
    public var cpuLimit: Int?
    public var memoryLimitBytes: Int64?
    public var ipAddress: String?
    public var architecture: String?
    public var os: String?
    /// Published host→container port mappings (configuration.publishedPorts).
    public var ports: [ContainerPort]
    public var createdAt: Date?
    public var startedAt: Date?

    public init(
        id: String,
        name: String,
        image: String,
        state: ResourceRunState,
        cpuPercent: Double? = nil,
        memoryBytes: Int64? = nil,
        cpuLimit: Int? = nil,
        memoryLimitBytes: Int64? = nil,
        ipAddress: String? = nil,
        architecture: String? = nil,
        os: String? = nil,
        ports: [ContainerPort] = [],
        createdAt: Date? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.cpuLimit = cpuLimit
        self.memoryLimitBytes = memoryLimitBytes
        self.ipAddress = ipAddress
        self.architecture = architecture
        self.os = os
        self.ports = ports
        self.createdAt = createdAt
        self.startedAt = startedAt
    }

    public var isRunning: Bool { state == .running }
}

public struct ContainerDetails: Sendable, Equatable {
    public var summary: ContainerSummary
    public var rawJSON: String

    public init(summary: ContainerSummary, rawJSON: String = "") {
        self.summary = summary
        self.rawJSON = rawJSON
    }
}

public struct ContainerStatistics: Sendable, Equatable, Identifiable {
    public var id: String
    public var cpuPercent: Double?
    public var memoryBytes: Int64?

    public init(id: String, cpuPercent: Double? = nil, memoryBytes: Int64? = nil) {
        self.id = id
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct ImageSummary: Sendable, Equatable, Identifiable {
    public var id: String
    /// e.g. "docker.io/library/alpine"
    public var repository: String
    public var tag: String
    public var digest: String?
    /// Sum of variant content sizes (compressed, all platforms).
    public var sizeBytes: Int64?
    public var createdAt: Date?
    /// Real platform architectures (attestation variants excluded).
    public var architectures: [String]

    public init(
        id: String,
        repository: String,
        tag: String,
        digest: String? = nil,
        sizeBytes: Int64? = nil,
        createdAt: Date? = nil,
        architectures: [String] = []
    ) {
        self.id = id
        self.repository = repository
        self.tag = tag
        self.digest = digest
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.architectures = architectures
    }

    public var reference: String { "\(repository):\(tag)" }
}

public struct ImageDetails: Sendable, Equatable {
    public var summary: ImageSummary
    public var rawJSON: String

    public init(summary: ImageSummary, rawJSON: String = "") {
        self.summary = summary
        self.rawJSON = rawJSON
    }
}

public struct VolumeSummary: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    /// Provisioned size (sparse maximum), not current usage.
    public var sizeBytes: Int64?
    public var driver: String?
    public var format: String?
    public var sourcePath: String?
    public var labels: [String: String]
    public var createdAt: Date?

    public init(
        name: String,
        sizeBytes: Int64? = nil,
        driver: String? = nil,
        format: String? = nil,
        sourcePath: String? = nil,
        labels: [String: String] = [:],
        createdAt: Date? = nil
    ) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.driver = driver
        self.format = format
        self.sourcePath = sourcePath
        self.labels = labels
        self.createdAt = createdAt
    }
}

public struct VolumeDetails: Sendable, Equatable {
    public var summary: VolumeSummary
    public var rawJSON: String

    public init(summary: VolumeSummary, rawJSON: String = "") {
        self.summary = summary
        self.rawJSON = rawJSON
    }
}

public struct NetworkSummary: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var subnet: String?

    public init(name: String, subnet: String? = nil) {
        self.name = name
        self.subnet = subnet
    }
}

public struct NetworkDetails: Sendable, Equatable {
    public var summary: NetworkSummary
    public var rawJSON: String

    public init(summary: NetworkSummary, rawJSON: String = "") {
        self.summary = summary
        self.rawJSON = rawJSON
    }
}

public struct MachineSummary: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    /// Image reference; the CLI reports it only via inspect, not list.
    public var image: String?
    public var state: ResourceRunState
    public var cpuCount: Int?
    public var memoryBytes: Int64?
    public var diskBytes: Int64?
    public var ipAddress: String?
    public var isDefault: Bool
    public var createdAt: Date?

    public init(
        name: String,
        image: String? = nil,
        state: ResourceRunState,
        cpuCount: Int? = nil,
        memoryBytes: Int64? = nil,
        diskBytes: Int64? = nil,
        ipAddress: String? = nil,
        isDefault: Bool = false,
        createdAt: Date? = nil
    ) {
        self.name = name
        self.image = image
        self.state = state
        self.cpuCount = cpuCount
        self.memoryBytes = memoryBytes
        self.diskBytes = diskBytes
        self.ipAddress = ipAddress
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    public var isRunning: Bool { state == .running }
}

public struct MachineDetails: Sendable, Equatable {
    public var summary: MachineSummary
    public var homeMount: String?
    public var rawJSON: String

    public init(summary: MachineSummary, homeMount: String? = nil, rawJSON: String = "") {
        self.summary = summary
        self.homeMount = homeMount
        self.rawJSON = rawJSON
    }
}

/// One category of `container system df` output (verified schema).
public struct DiskUsageCategory: Sendable, Equatable {
    public var active: Int
    public var total: Int
    public var sizeBytes: Int64
    public var reclaimableBytes: Int64

    public init(active: Int, total: Int, sizeBytes: Int64, reclaimableBytes: Int64) {
        self.active = active
        self.total = total
        self.sizeBytes = sizeBytes
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct DiskUsage: Sendable, Equatable {
    public var containers: DiskUsageCategory
    public var images: DiskUsageCategory
    public var volumes: DiskUsageCategory

    public init(containers: DiskUsageCategory, images: DiskUsageCategory, volumes: DiskUsageCategory) {
        self.containers = containers
        self.images = images
        self.volumes = volumes
    }

    public var totalBytes: Int64 {
        containers.sizeBytes + images.sizeBytes + volumes.sizeBytes
    }

    public var reclaimableBytes: Int64 {
        containers.reclaimableBytes + images.reclaimableBytes + volumes.reclaimableBytes
    }
}

/// Builder state. With CLI 1.0.0 `builder status --format json` returns an
/// empty array when no builder runs; a non-empty response's row schema is
/// not yet verified, so only presence + raw JSON are exposed.
public struct BuilderStatus: Sendable, Equatable {
    public var isRunning: Bool
    public var rawJSON: String

    public init(isRunning: Bool, rawJSON: String) {
        self.isRunning = isRunning
        self.rawJSON = rawJSON
    }
}

/// A registry login entry. Row schema is not yet verified (empty on this
/// installation), so entries carry a best-effort display string + raw JSON.
public struct RegistryEntry: Sendable, Equatable, Identifiable {
    public var id: String { display }
    public var display: String
    public var rawJSON: String

    public init(display: String, rawJSON: String) {
        self.display = display
        self.rawJSON = rawJSON
    }
}
