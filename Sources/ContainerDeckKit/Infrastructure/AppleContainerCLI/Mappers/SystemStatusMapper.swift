import Foundation

/// Maps the status DTO to the stable domain model.
enum SystemStatusMapper {
    /// The only status string that means the system is up (verified with CLI 1.0.0).
    static let runningStatus = "running"

    static func map(data: Data) throws -> ContainerSystemStatus {
        let dto: SystemStatusDTO
        do {
            dto = try JSONDecoder().decode(SystemStatusDTO.self, from: data)
        } catch {
            throw ContainerEngineError.decodingFailed(
                command: "container system status --format json",
                underlying: String(describing: error)
            )
        }

        let reported = dto.status ?? "unknown"
        let runtime: ContainerSystemStatus.Runtime =
            reported == runningStatus ? .running : .stopped(reportedStatus: reported)

        return ContainerSystemStatus(
            runtime: runtime,
            apiServerVersion: dto.apiServerVersion.flatMap { $0.isEmpty ? nil : $0 },
            appRoot: dto.appRoot.flatMap { $0.isEmpty ? nil : $0 },
            installRoot: dto.installRoot.flatMap { $0.isEmpty ? nil : $0 },
            rawJSON: String(decoding: data, as: UTF8.self)
        )
    }
}
