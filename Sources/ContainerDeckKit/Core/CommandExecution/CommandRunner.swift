import Foundation
import Synchronization

/// Executes child processes with structured concurrency.
///
/// Guarantees:
/// - Binaries are executed directly; no shell is ever involved.
/// - stdin is always closed (after optional write) so prompts cannot hang.
/// - Timeouts and task cancellation terminate the child (SIGTERM → SIGKILL).
/// - All waiting and pipe reads happen off the main actor.
public actor CommandRunner: CommandRunning {
    public init() {}

    public func run(_ request: CommandRequest) async throws -> CommandResult {
        let child = ChildProcess(request: request)
        let startedAt = Date()
        try Self.launch(child, request: request)

        // Watchdog terminates the child on timeout; the flag records why.
        // Created unconditionally (no-op without a timeout) so it can be a
        // `let` capturable by concurrent closures under region isolation.
        let timedOut = Mutex(false)
        let requestTimeout = request.timeout
        let watchdog = Task {
            guard let requestTimeout else { return }
            try? await Task.sleep(for: requestTimeout)
            guard !Task.isCancelled else { return }
            timedOut.withLock { $0 = true }
            await ProcessTermination.terminate(child)
        }
        defer { watchdog.cancel() }

        async let stdoutData = child.collectedStandardOutput()
        async let stderrData = child.collectedStandardError()

        let exitCode = await withTaskCancellationHandler {
            await child.waitForExit()
        } onCancel: {
            // Unstructured task is required: onCancel is synchronous. It only
            // terminates the child, which in turn completes waitForExit().
            Task { await ProcessTermination.terminate(child) }
        }

        let standardOutput = await stdoutData
        let standardError = await stderrData

        if timedOut.withLock({ $0 }) {
            throw ContainerEngineError.commandTimedOut
        }
        if Task.isCancelled {
            throw ContainerEngineError.commandCancelled
        }

        return CommandResult(
            exitCode: exitCode,
            standardOutput: standardOutput,
            standardError: standardError,
            startedAt: startedAt,
            endedAt: Date()
        )
    }

    public nonisolated func stream(_ request: CommandRequest) -> AsyncThrowingStream<CommandOutputEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<CommandOutputEvent, Error>.makeStream()
        let pump = Task {
            await self.pump(request: request, continuation: continuation)
        }
        continuation.onTermination = { reason in
            if case .cancelled = reason {
                // Consumer walked away: cancelling the pump terminates the child.
                pump.cancel()
            }
        }
        return stream
    }

    private func pump(
        request: CommandRequest,
        continuation: AsyncThrowingStream<CommandOutputEvent, Error>.Continuation
    ) async {
        let child = ChildProcess(request: request)
        do {
            try Self.launch(child, request: request)
        } catch {
            continuation.finish(throwing: error)
            return
        }

        let timedOut = Mutex(false)
        let requestTimeout = request.timeout
        let watchdog = Task {
            guard let requestTimeout else { return }
            try? await Task.sleep(for: requestTimeout)
            guard !Task.isCancelled else { return }
            timedOut.withLock { $0 = true }
            await ProcessTermination.terminate(child)
        }
        defer { watchdog.cancel() }

        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    var decoder = IncrementalUTF8Decoder()
                    for await chunk in child.standardOutputChunks() {
                        let text = decoder.decode(chunk)
                        if !text.isEmpty { continuation.yield(.stdout(text)) }
                    }
                    let rest = decoder.flush()
                    if !rest.isEmpty { continuation.yield(.stdout(rest)) }
                }
                group.addTask {
                    var decoder = IncrementalUTF8Decoder()
                    for await chunk in child.standardErrorChunks() {
                        let text = decoder.decode(chunk)
                        if !text.isEmpty { continuation.yield(.stderr(text)) }
                    }
                    let rest = decoder.flush()
                    if !rest.isEmpty { continuation.yield(.stderr(rest)) }
                }
            }
        } onCancel: {
            // Unstructured task is required: onCancel is synchronous. It only
            // terminates the child, which unblocks the pipe reads above.
            Task { await ProcessTermination.terminate(child) }
        }

        let exitCode = await child.waitForExit()

        if timedOut.withLock({ $0 }) {
            continuation.finish(throwing: ContainerEngineError.commandTimedOut)
        } else if Task.isCancelled {
            continuation.finish(throwing: ContainerEngineError.commandCancelled)
        } else {
            continuation.yield(.completed(exitCode: exitCode))
            continuation.finish()
        }
    }

    private static func launch(_ child: ChildProcess, request: CommandRequest) throws {
        do {
            try child.launch(standardInput: request.standardInput)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            throw ContainerEngineError.binaryNotFound
        } catch let error as ContainerEngineError {
            throw error
        } catch {
            throw ContainerEngineError.commandFailed(
                executable: request.executable.path,
                arguments: request.redactedArguments,
                exitCode: -1,
                stderr: "Failed to launch: \(error.localizedDescription)"
            )
        }
    }
}
