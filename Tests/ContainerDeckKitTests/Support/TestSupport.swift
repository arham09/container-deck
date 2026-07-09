import Foundation
import Synchronization
@testable import ContainerDeckKit

/// Loads a committed fixture captured from the real CLI.
func fixtureData(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Fixtures"
    ) else {
        throw NSError(
            domain: "TestSupport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name).json"]
        )
    }
    return try Data(contentsOf: url)
}

/// Returns scripted results in order and records every request.
final class ScriptedCommandRunner: CommandRunning, @unchecked Sendable {
    private struct State {
        var results: [Result<CommandResult, ContainerEngineError>]
        var requests: [CommandRequest] = []
    }

    private let state: Mutex<State>

    init(results: [Result<CommandResult, ContainerEngineError>]) {
        self.state = Mutex(State(results: results))
    }

    var recordedRequests: [CommandRequest] {
        state.withLock { $0.requests }
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let next: Result<CommandResult, ContainerEngineError> = state.withLock { state in
            state.requests.append(request)
            guard !state.results.isEmpty else {
                return .failure(.unexpectedOutput("ScriptedCommandRunner exhausted"))
            }
            return state.results.removeFirst()
        }
        return try next.get()
    }

    /// Events replayed by the next stream() call; set before invoking.
    private let scriptedStreamEvents = Mutex<[CommandOutputEvent]>([])

    func scriptStream(_ events: [CommandOutputEvent]) {
        scriptedStreamEvents.withLock { $0 = events }
    }

    func stream(_ request: CommandRequest) -> AsyncThrowingStream<CommandOutputEvent, Error> {
        state.withLock { $0.requests.append(request) }
        let events = scriptedStreamEvents.withLock { $0 }
        return AsyncThrowingStream { continuation in
            if events.isEmpty {
                continuation.finish(throwing: ContainerEngineError.unexpectedOutput("stream not scripted"))
                return
            }
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

func makeResult(
    exitCode: Int32 = 0,
    stdout: String = "",
    stderr: String = ""
) -> CommandResult {
    CommandResult(
        exitCode: exitCode,
        standardOutput: Data(stdout.utf8),
        standardError: Data(stderr.utf8),
        startedAt: Date(),
        endedAt: Date()
    )
}

/// Isolated UserDefaults per test so settings never leak between tests.
@MainActor
func makeTestSettings() -> UserSettings {
    let suite = "containerdeck-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return UserSettings(defaults: defaults)
}

/// Polls until `condition` is true or the timeout elapses.
func eventually(
    timeout: Duration = .seconds(2),
    poll: Duration = .milliseconds(10),
    _ condition: @MainActor @escaping () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await MainActor.run(body: condition) { return true }
        try? await Task.sleep(for: poll)
    }
    return await MainActor.run(body: condition)
}
