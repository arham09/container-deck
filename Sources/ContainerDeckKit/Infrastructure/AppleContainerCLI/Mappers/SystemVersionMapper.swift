import Foundation

/// Maps the version DTO array to the stable domain model.
enum SystemVersionMapper {
    static func map(data: Data) throws -> ContainerSystemVersion {
        let entries: [SystemVersionEntryDTO]
        do {
            entries = try JSONDecoder().decode([SystemVersionEntryDTO].self, from: data)
        } catch {
            throw ContainerEngineError.decodingFailed(
                command: "container system version --format json",
                underlying: String(describing: error)
            )
        }

        // The primary entry is the CLI itself; fall back to the first entry.
        let primary = entries.first(where: { $0.appName == "container" }) ?? entries.first
        guard let primary, let version = primary.version, !version.isEmpty else {
            throw ContainerEngineError.unexpectedOutput(
                "system version returned no recognizable version entry"
            )
        }

        return ContainerSystemVersion(
            version: version,
            commit: primary.commit,
            buildType: primary.buildType,
            components: entries.map {
                ContainerSystemVersion.Component(
                    appName: $0.appName,
                    version: $0.version,
                    commit: $0.commit,
                    buildType: $0.buildType
                )
            }
        )
    }
}
