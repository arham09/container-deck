import Foundation
import Observation

/// Loading state for one resource area. Previously loaded items stay visible
/// during refreshes and failures (spec §9); a stopped system marks data stale
/// instead of erasing it (spec §12).
public enum ResourceLoadPhase: Equatable, Sendable {
    case initial
    case loaded
    /// Apple Container is stopped and nothing was loaded yet.
    case needsSystem
    /// The feature is capability-gated on this installation.
    case unavailable(String)
    case failed(String)
}

@MainActor
@Observable
public final class ResourceStore<Item: Identifiable & Sendable & Equatable> {
    public private(set) var items: [Item] = []
    public private(set) var phase: ResourceLoadPhase = .initial
    public private(set) var isStale = false
    public private(set) var isRefreshing = false
    public private(set) var lastRefreshed: Date?

    private let fetch: @Sendable () async throws -> [Item]
    private var refreshTask: Task<Void, Never>?

    public init(fetch: @escaping @Sendable () async throws -> [Item]) {
        self.fetch = fetch
    }

    /// Refreshes, cancelling any stale in-flight refresh.
    public func refresh() async {
        refreshTask?.cancel()
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
    }

    public func markStale() {
        if phase == .loaded {
            isStale = true
        }
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fetched = try await fetch()
            guard !Task.isCancelled else { return }
            items = fetched
            phase = .loaded
            isStale = false
            lastRefreshed = Date()
        } catch let error as ContainerEngineError {
            guard !Task.isCancelled else { return }
            switch error {
            case .serviceNotRunning:
                // Keep old data, mark stale; only show needsSystem when
                // there is nothing to keep.
                if phase == .loaded {
                    isStale = true
                } else {
                    phase = .needsSystem
                }
            case .featureUnavailable(let reason):
                phase = .unavailable(reason)
            case .commandCancelled:
                break
            default:
                // One failed refresh never erases loaded data.
                if phase != .loaded {
                    phase = .failed(UserFacingError.make(from: error).title)
                }
            }
        } catch {
            if !Task.isCancelled, phase != .loaded {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
