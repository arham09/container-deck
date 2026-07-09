import Foundation

/// A validated `container` executable and where it was found.
public struct ContainerBinaryLocation: Sendable, Equatable {
    public enum Source: String, Sendable {
        case userConfigured
        case persistedPreference
        case environmentPath
        case knownLocation
        case manualSelection
    }

    public var url: URL
    public var source: Source
    /// Version reported by `container system version --format json` during validation.
    public var version: ContainerSystemVersion

    public init(url: URL, source: Source, version: ContainerSystemVersion) {
        self.url = url
        self.source = source
        self.version = version
    }
}
