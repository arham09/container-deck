import Foundation

// DTO → domain mapping for Phase 1 resources. Each mapper throws
// `decodingFailed` with the command name so failures are attributable.

enum ResourceMappers {
    static func decode<DTO: Decodable>(
        _ type: DTO.Type,
        from data: Data,
        command: String
    ) throws -> DTO {
        do {
            return try JSONDecoder().decode(DTO.self, from: data)
        } catch {
            throw ContainerEngineError.decodingFailed(
                command: command,
                underlying: String(describing: error)
            )
        }
    }
}

enum ContainerMapper {
    static func summaries(from data: Data, command: String) throws -> [ContainerSummary] {
        let entries = try ResourceMappers.decode([ContainerEntryDTO].self, from: data, command: command)
        return entries.compactMap(summary(from:))
    }

    static func summary(from dto: ContainerEntryDTO) -> ContainerSummary? {
        guard let id = dto.id ?? dto.configuration?.id else { return nil }
        let state: ResourceRunState =
            ResourceRunState(rawValue: dto.status?.state ?? "") ?? .stopped
        // "192.168.64.2/24" → display without the prefix length.
        let ip = dto.status?.networks?.first?.ipv4Address.map { address in
            address.split(separator: "/").first.map(String.init) ?? address
        }
        let ports: [ContainerPort] = (dto.configuration?.publishedPorts ?? []).compactMap { port in
            guard let hostPort = port.hostPort, let containerPort = port.containerPort else { return nil }
            return ContainerPort(
                hostAddress: port.hostAddress,
                hostPort: hostPort,
                containerPort: containerPort,
                proto: port.proto
            )
        }
        return ContainerSummary(
            id: id,
            name: id,
            image: dto.configuration?.image?.reference ?? "unknown",
            state: state,
            cpuLimit: dto.configuration?.resources?.cpus,
            memoryLimitBytes: dto.configuration?.resources?.memoryInBytes,
            ipAddress: ip ?? nil,
            architecture: dto.configuration?.platform?.architecture,
            os: dto.configuration?.platform?.os,
            ports: ports,
            createdAt: CLIDate.parse(dto.configuration?.creationDate),
            startedAt: CLIDate.parse(dto.status?.startedDate)
        )
    }
}

enum ImageMapper {
    static func summaries(from data: Data, command: String) throws -> [ImageSummary] {
        let entries = try ResourceMappers.decode([ImageEntryDTO].self, from: data, command: command)
        return entries.compactMap(summary(from:))
    }

    static func summary(from dto: ImageEntryDTO) -> ImageSummary? {
        guard let name = dto.configuration?.name ?? dto.id else { return nil }
        let (repository, tag) = splitReference(name)
        let variants = dto.variants ?? []
        // Attestation variants report platform os "unknown"; exclude them.
        let architectures = variants
            .compactMap { variant -> String? in
                guard let platform = variant.platform,
                      platform.os != "unknown",
                      let architecture = platform.architecture else { return nil }
                return architecture
            }
        let totalSize = variants.compactMap(\.size).reduce(0, +)
        return ImageSummary(
            id: dto.id ?? name,
            repository: repository,
            tag: tag,
            digest: dto.configuration?.descriptor?.digest,
            sizeBytes: totalSize > 0 ? totalSize : nil,
            createdAt: CLIDate.parse(dto.configuration?.creationDate),
            architectures: Array(Set(architectures)).sorted()
        )
    }

    /// "docker.io/library/alpine:latest" → ("docker.io/library/alpine", "latest").
    /// Digest references and port-suffixed registries keep the last-colon rule
    /// only when the suffix contains no "/".
    static func splitReference(_ reference: String) -> (repository: String, tag: String) {
        guard let colon = reference.lastIndex(of: ":"),
              !reference[reference.index(after: colon)...].contains("/") else {
            return (reference, "latest")
        }
        return (
            String(reference[reference.startIndex..<colon]),
            String(reference[reference.index(after: colon)...])
        )
    }
}

enum VolumeMapper {
    static func summaries(from data: Data, command: String) throws -> [VolumeSummary] {
        let entries = try ResourceMappers.decode([VolumeEntryDTO].self, from: data, command: command)
        return entries.compactMap(summary(from:))
    }

    static func summary(from dto: VolumeEntryDTO) -> VolumeSummary? {
        guard let name = dto.id ?? dto.configuration?.name else { return nil }
        return VolumeSummary(
            name: name,
            sizeBytes: dto.configuration?.sizeInBytes,
            driver: dto.configuration?.driver,
            format: dto.configuration?.format,
            sourcePath: dto.configuration?.source,
            labels: dto.configuration?.labels ?? [:],
            createdAt: CLIDate.parse(dto.configuration?.creationDate)
        )
    }
}

enum MachineMapper {
    static func summaries(from data: Data, command: String) throws -> [MachineSummary] {
        let entries = try ResourceMappers.decode([MachineEntryDTO].self, from: data, command: command)
        return entries.compactMap(summary(from:))
    }

    static func summary(from dto: MachineEntryDTO) -> MachineSummary? {
        guard let id = dto.id else { return nil }
        return MachineSummary(
            name: id,
            image: dto.image?.reference,
            state: ResourceRunState(rawValue: dto.status ?? "") ?? .stopped,
            cpuCount: dto.cpus,
            memoryBytes: dto.memory,
            diskBytes: dto.diskSize,
            ipAddress: dto.ipAddress,
            isDefault: dto.isDefault ?? false,
            createdAt: CLIDate.parse(dto.createdDate)
        )
    }
}

enum DiskUsageMapper {
    static func usage(from data: Data, command: String) throws -> DiskUsage {
        let dto = try ResourceMappers.decode(DiskUsageDTO.self, from: data, command: command)
        return DiskUsage(
            containers: category(dto.containers),
            images: category(dto.images),
            volumes: category(dto.volumes)
        )
    }

    private static func category(_ dto: DiskUsageDTO.Category?) -> DiskUsageCategory {
        DiskUsageCategory(
            active: dto?.active ?? 0,
            total: dto?.total ?? 0,
            sizeBytes: dto?.sizeInBytes ?? 0,
            reclaimableBytes: dto?.reclaimable ?? 0
        )
    }
}

/// Registry rows have no verified schema yet (empty on the verification
/// installation): strings pass through, objects become compact JSON.
enum RegistryMapper {
    static func entries(from data: Data, command: String) throws -> [RegistryEntry] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ContainerEngineError.decodingFailed(
                command: command,
                underlying: "expected a JSON array"
            )
        }
        return array.map { element in
            if let text = element as? String {
                return RegistryEntry(display: text, rawJSON: "\"\(text)\"")
            }
            let raw = (try? JSONSerialization.data(withJSONObject: element))
                .map { String(decoding: $0, as: UTF8.self) } ?? "\(element)"
            let display = (element as? [String: Any])
                .flatMap { $0["registry"] as? String ?? $0["host"] as? String } ?? raw
            return RegistryEntry(display: display, rawJSON: raw)
        }
    }
}
