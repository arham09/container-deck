import Foundation
import Observation

/// One time-series sample of verifiable system metrics.
///
/// CLI 1.0.0's `container stats` returns no per-container usage data (see
/// docs/supported-commands.md), so ContainerDeck charts what it can verify:
/// running counts and disk usage. Per-container CPU/memory charts stay
/// capability-gated until a CLI version emits real rows.
public struct MetricsSample: Sendable, Equatable, Identifiable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let runningContainers: Int
    public let runningMachines: Int
    public let diskUsedBytes: Int64
    public let diskReclaimableBytes: Int64
}

/// Samples metrics on the Settings interval while the Activity view is
/// visible (spec §29: no polling when not required, no overlapping requests,
/// bounded in-memory buffer, no metrics persistence).
@MainActor
@Observable
public final class MetricsStore {
    public private(set) var samples: [MetricsSample] = []
    public private(set) var isSampling = false
    public private(set) var lastSampleFailed = false

    private let engine: any ContainerEngine
    private let settings: UserSettings
    /// Last 5 minutes at the fastest (1 s) interval.
    private let capacity = 300
    private var timerTask: Task<Void, Never>?
    private var sampleInFlight = false

    public init(engine: any ContainerEngine, settings: UserSettings) {
        self.engine = engine
        self.settings = settings
    }

    /// Starts sampling; called when the Activity view appears.
    public func start() {
        guard timerTask == nil else { return }
        isSampling = true
        timerTask = Task {
            while !Task.isCancelled {
                await sampleOnce()
                let interval = Duration.seconds(max(1, settings.statisticsIntervalSeconds))
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Stops sampling; called when the Activity view disappears.
    public func stop() {
        timerTask?.cancel()
        timerTask = nil
        isSampling = false
    }

    public func clear() {
        samples = []
    }

    /// One sample; never overlaps a slow previous request (spec §29).
    func sampleOnce() async {
        guard !sampleInFlight else { return }
        sampleInFlight = true
        defer { sampleInFlight = false }

        async let containersFetch = try? engine.listContainers(all: false)
        async let machinesFetch = try? engine.listMachines()
        async let diskFetch = try? engine.diskUsage()
        let (containers, machines, disk) = await (containersFetch, machinesFetch, diskFetch)

        guard containers != nil || machines != nil || disk != nil else {
            lastSampleFailed = true
            return
        }
        lastSampleFailed = false
        samples.append(MetricsSample(
            timestamp: Date(),
            runningContainers: containers?.count { $0.isRunning } ?? 0,
            runningMachines: machines?.count { $0.isRunning } ?? 0,
            diskUsedBytes: disk?.totalBytes ?? 0,
            diskReclaimableBytes: disk?.reclaimableBytes ?? 0
        ))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
