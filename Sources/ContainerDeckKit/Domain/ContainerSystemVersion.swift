/// Domain model for `container system version --format json`.
///
/// Verified against Apple Container CLI 1.0.0: the command emits an array of
/// component entries; the primary entry is the one named "container".
public struct ContainerSystemVersion: Sendable, Equatable {
    public struct Component: Sendable, Equatable {
        public var appName: String?
        public var version: String?
        public var commit: String?
        public var buildType: String?

        public init(appName: String?, version: String?, commit: String?, buildType: String?) {
            self.appName = appName
            self.version = version
            self.commit = commit
            self.buildType = buildType
        }
    }

    /// Primary CLI version string, e.g. "1.0.0".
    public var version: String
    public var commit: String?
    public var buildType: String?
    /// All reported components, in CLI order.
    public var components: [Component]

    public init(version: String, commit: String? = nil, buildType: String? = nil, components: [Component] = []) {
        self.version = version
        self.commit = commit
        self.buildType = buildType
        self.components = components
    }

    public var shortDescription: String {
        var text = version
        if let commit {
            text += " (\(String(commit.prefix(7))))"
        }
        return text
    }
}
