import Foundation
import Observation

/// Owns all resource stores. Refreshes run concurrently and fail
/// independently — one resource's failure never erases another's data.
/// Replaces the Phase 0 mock overview.
@MainActor
@Observable
public final class ResourceCenter {
    public let containers: ResourceStore<ContainerSummary>
    public let images: ResourceStore<ImageSummary>
    public let volumes: ResourceStore<VolumeSummary>
    public let machines: ResourceStore<MachineSummary>
    public let registries: ResourceStore<RegistryEntry>

    public private(set) var disk: DiskUsage?
    public private(set) var builder: BuilderStatus?
    public private(set) var capabilities: EngineCapabilities?
    public private(set) var isStale = false
    public private(set) var lastRefreshed: Date?

    private let engine: any ContainerEngine

    public init(engine: any ContainerEngine) {
        self.engine = engine
        containers = ResourceStore { try await engine.listContainers(all: true) }
        images = ResourceStore { try await engine.listImages() }
        volumes = ResourceStore { try await engine.listVolumes() }
        machines = ResourceStore { try await engine.listMachines() }
        registries = ResourceStore { try await engine.listRegistries() }
    }

    /// Global refresh (⌘R): all stores concurrently, plus disk usage,
    /// builder status, and the capability probe.
    public func refreshAll() async {
        async let containersRefresh: Void = containers.refresh()
        async let imagesRefresh: Void = images.refresh()
        async let volumesRefresh: Void = volumes.refresh()
        async let machinesRefresh: Void = machines.refresh()
        async let registriesRefresh: Void = registries.refresh()
        async let diskFetch = try? engine.diskUsage()
        async let builderFetch = try? engine.builderStatus()
        async let capabilitiesFetch = try? engine.capabilities()

        _ = await (containersRefresh, imagesRefresh, volumesRefresh, machinesRefresh, registriesRefresh)
        if let fetchedDisk = await diskFetch {
            disk = fetchedDisk
        }
        if let fetchedBuilder = await builderFetch {
            builder = fetchedBuilder
        }
        if let fetchedCapabilities = await capabilitiesFetch {
            capabilities = fetchedCapabilities
        }

        if containers.phase == .loaded || images.phase == .loaded {
            isStale = false
            lastRefreshed = Date()
        }
    }

    /// Called when the system stops: keep everything, mark it stale.
    public func markAllStale() {
        containers.markStale()
        images.markStale()
        volumes.markStale()
        machines.markStale()
        registries.markStale()
        if containers.phase == .loaded || images.phase == .loaded {
            isStale = true
        }
    }

    // MARK: Dashboard / sidebar conveniences

    public var runningContainers: [ContainerSummary] { containers.items.filter(\.isRunning) }
    public var stoppedContainers: [ContainerSummary] { containers.items.filter { !$0.isRunning } }
    public var runningMachines: [MachineSummary] { machines.items.filter(\.isRunning) }
    public var stoppedMachines: [MachineSummary] { machines.items.filter { !$0.isRunning } }

    public var hasLoadedResources: Bool {
        containers.phase == .loaded || images.phase == .loaded || machines.phase == .loaded
    }
}
