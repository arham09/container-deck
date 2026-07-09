import Foundation

/// Escalating child-process termination: SIGTERM, then SIGKILL after a grace
/// period. Used for timeouts, task cancellation, and app teardown so that
/// long-running children (log follows, builds) never leak.
enum ProcessTermination {
    static let defaultGracePeriod: Duration = .seconds(2)

    static func terminate(_ child: ChildProcess, gracePeriod: Duration = defaultGracePeriod) async {
        guard child.isRunning else { return }
        child.terminate()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: gracePeriod)
        while child.isRunning, clock.now < deadline {
            // If this task is itself cancelled, skip the grace period and kill now.
            if Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if child.isRunning {
            child.forceKill()
        }
    }
}
