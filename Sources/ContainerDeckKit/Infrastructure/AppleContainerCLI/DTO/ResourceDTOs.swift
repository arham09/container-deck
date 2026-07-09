import Foundation

// Raw shapes of Apple Container CLI 1.0.0 JSON output, captured in
// Tests/.../Fixtures/. Every field is optional so missing keys never break
// decoding; unknown extra keys are ignored.

/// `container list --all --format json` entry (fixture: container-list*.json).
struct ContainerEntryDTO: Decodable {
    struct Configuration: Decodable {
        struct ImageRef: Decodable {
            var reference: String?
        }
        struct Resources: Decodable {
            var cpus: Int?
            var memoryInBytes: Int64?
        }
        /// `configuration.publishedPorts[]` entry (schema captured from CLI
        /// 1.0.0 by running `-p 127.0.0.1:8080:80/tcp`, fixture
        /// container-list-ports.json).
        struct PublishedPort: Decodable {
            var hostAddress: String?
            var hostPort: Int?
            var containerPort: Int?
            var proto: String?
        }
        var id: String?
        var creationDate: String?
        var image: ImageRef?
        var platform: PlatformDTO?
        var resources: Resources?
        var publishedPorts: [PublishedPort]?
    }

    struct Status: Decodable {
        struct NetworkAttachment: Decodable {
            var network: String?
            var hostname: String?
            var ipv4Address: String?
        }
        var state: String?
        var startedDate: String?
        var networks: [NetworkAttachment]?
    }

    var id: String?
    var configuration: Configuration?
    var status: Status?
}

struct PlatformDTO: Decodable {
    var architecture: String?
    var os: String?
    var variant: String?
}

/// `container image list --verbose --format json` entry (fixture: image-list.json).
struct ImageEntryDTO: Decodable {
    struct Configuration: Decodable {
        struct Descriptor: Decodable {
            var digest: String?
            var mediaType: String?
            var size: Int64?
        }
        var name: String?
        var creationDate: String?
        var descriptor: Descriptor?
    }

    struct Variant: Decodable {
        var digest: String?
        var size: Int64?
        var platform: PlatformDTO?
    }

    var id: String?
    var configuration: Configuration?
    var variants: [Variant]?
}

/// `container volume list --format json` entry (fixture: volume-list.json).
struct VolumeEntryDTO: Decodable {
    struct Configuration: Decodable {
        var name: String?
        var creationDate: String?
        var driver: String?
        var format: String?
        var labels: [String: String]?
        var sizeInBytes: Int64?
        var source: String?
    }

    var id: String?
    var configuration: Configuration?
}

/// `container machine list --format json` entry (fixture: machine-list.json).
/// `machine inspect` returns a superset (fixture: machine-inspect.json).
struct MachineEntryDTO: Decodable {
    struct ImageRef: Decodable {
        var reference: String?
    }

    var id: String?
    var status: String?
    var cpus: Int?
    var memory: Int64?
    var diskSize: Int64?
    var ipAddress: String?
    var createdDate: String?
    var isDefault: Bool?
    // Inspect-only fields
    var image: ImageRef?
    var homeMount: String?

    enum CodingKeys: String, CodingKey {
        case id, status, cpus, memory, diskSize, ipAddress, createdDate
        case isDefault = "default"
        case image, homeMount
    }
}

/// `container system df --format json` (fixture: system-df.json).
struct DiskUsageDTO: Decodable {
    struct Category: Decodable {
        var active: Int?
        var total: Int?
        var sizeInBytes: Int64?
        var reclaimable: Int64?
    }

    var containers: Category?
    var images: Category?
    var volumes: Category?
}

/// Shared date parsing for CLI timestamps like "2026-07-04T08:54:22Z".
enum CLIDate {
    private static let plain = Date.ISO8601FormatStyle()
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return (try? plain.parse(string)) ?? (try? fractional.parse(string))
    }
}
