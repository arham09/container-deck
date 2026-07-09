import Foundation

/// Finds and validates the `container` executable.
///
/// Search order (spec §7): user-configured path → persisted preference →
/// process `PATH` → known install locations → manual selection. Every
/// candidate is validated by actually running
/// `container system version --format json` and decoding the result.
/// No login shell is ever involved.
public actor ContainerBinaryLocator {
    public static let knownLocations = [
        "/usr/local/bin/container",
        "/opt/homebrew/bin/container",
        "/usr/bin/container",
    ]

    private let runner: any CommandRunning
    private let searchPath: String?
    private let knownLocations: [String]
    private var cached: ContainerBinaryLocation?

    public init(
        runner: any CommandRunning,
        searchPath: String? = ProcessInfo.processInfo.environment["PATH"],
        knownLocations: [String] = ContainerBinaryLocator.knownLocations
    ) {
        self.runner = runner
        self.searchPath = searchPath
        self.knownLocations = knownLocations
    }

    /// Resolves the binary, trying candidates in spec order.
    /// - Parameters:
    ///   - userConfiguredPath: explicit path from Settings, if any.
    ///   - persistedPath: last successfully detected path, if any.
    public func locate(
        userConfiguredPath: String?,
        persistedPath: String?
    ) async throws -> ContainerBinaryLocation {
        if let cached { return cached }

        var candidates: [(String, ContainerBinaryLocation.Source)] = []
        if let userConfiguredPath, !userConfiguredPath.isEmpty {
            candidates.append((userConfiguredPath, .userConfigured))
        }
        if let persistedPath, !persistedPath.isEmpty {
            candidates.append((persistedPath, .persistedPreference))
        }
        for directory in (searchPath ?? "").split(separator: ":") {
            candidates.append(("\(directory)/container", .environmentPath))
        }
        for path in knownLocations {
            candidates.append((path, .knownLocation))
        }

        var seen = Set<String>()
        for (path, source) in candidates {
            guard seen.insert(path).inserted else { continue }
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            if let version = await validate(url: url) {
                let location = ContainerBinaryLocation(url: url, source: source, version: version)
                cached = location
                return location
            }
        }
        throw ContainerEngineError.binaryNotFound
    }

    /// Validates a manually selected file (e.g. from an open panel).
    public func adopt(manualSelection url: URL) async throws -> ContainerBinaryLocation {
        guard let version = await validate(url: url) else {
            throw ContainerEngineError.invalidInput(
                "\(url.path) did not respond like the Apple Container CLI."
            )
        }
        let location = ContainerBinaryLocation(url: url, source: .manualSelection, version: version)
        cached = location
        return location
    }

    /// Drops the cache so the next `locate` re-runs discovery.
    public func invalidate() {
        cached = nil
    }

    public var currentLocation: ContainerBinaryLocation? { cached }

    /// Probes a candidate by running `system version --format json`.
    /// Returns nil when the candidate is missing, fails, or emits
    /// unrecognizable output.
    func validate(url: URL) async -> ContainerSystemVersion? {
        let request = CommandRequest(
            executable: url,
            arguments: ["system", "version", "--format", "json"],
            timeout: .seconds(10)
        )
        guard let result = try? await runner.run(request), result.isSuccess else { return nil }
        return try? SystemVersionMapper.map(data: result.standardOutput)
    }
}
