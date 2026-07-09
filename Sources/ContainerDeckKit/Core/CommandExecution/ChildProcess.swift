import Foundation
import Synchronization

/// Wraps `Foundation.Process` for use from Swift concurrency.
///
/// `@unchecked Sendable` justification: `Process` and `Pipe` are not `Sendable`,
/// but every operation used here is thread-safe in practice (`run`,
/// `terminate`, `processIdentifier`, `isRunning`, pipe file handles), all
/// configuration happens in `init`/`launch` before the instance crosses an
/// isolation boundary, and the exit code is published through a lock-protected
/// latch. Each instance backs exactly one `run` or `stream` call.
final class ChildProcess: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe = Pipe()
    private let exitLatch = ExitLatch()

    init(request: CommandRequest) {
        process.executableURL = request.executable
        process.arguments = request.arguments
        if !request.environmentOverrides.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in request.environmentOverrides {
                environment[key] = value
            }
            process.environment = environment
        }
        if let workingDirectory = request.workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        // Registered before launch so the exit can never be missed.
        let latch = exitLatch
        process.terminationHandler = { process in
            latch.fulfill(process.terminationStatus)
        }
    }

    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }
    var hasExited: Bool { exitLatch.value != nil }

    /// Launches the child and writes/closes stdin. stdin is always closed so
    /// the child can never block the app waiting for interactive input.
    func launch(standardInput: Data?) throws {
        try process.run()
        let writeHandle = stdinPipe.fileHandleForWriting
        if let standardInput, !standardInput.isEmpty {
            // Written off-calling-thread: a filled pipe buffer must not stall the caller.
            DispatchQueue.global(qos: .utility).async {
                try? writeHandle.write(contentsOf: standardInput)
                try? writeHandle.close()
            }
        } else {
            try? writeHandle.close()
        }
    }

    /// Suspends until the child exits. Not cancellation-responsive by design:
    /// callers cancel by terminating the child, which completes this wait.
    func waitForExit() async -> Int32 {
        await exitLatch.wait()
    }

    /// Sends SIGTERM.
    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    /// Sends SIGKILL.
    func forceKill() {
        let pid = process.processIdentifier
        guard pid > 0, process.isRunning else { return }
        kill(pid, SIGKILL)
    }

    /// Collects stdout to EOF.
    func collectedStandardOutput() async -> Data {
        await Self.drain(stdoutPipe.fileHandleForReading)
    }

    /// Collects stderr to EOF.
    func collectedStandardError() async -> Data {
        await Self.drain(stderrPipe.fileHandleForReading)
    }

    /// Streams raw stdout chunks as they arrive.
    func standardOutputChunks() -> AsyncStream<Data> {
        Self.chunks(stdoutPipe.fileHandleForReading)
    }

    /// Streams raw stderr chunks as they arrive.
    func standardErrorChunks() -> AsyncStream<Data> {
        Self.chunks(stderrPipe.fileHandleForReading)
    }

    private static func drain(_ handle: FileHandle) async -> Data {
        var collected = Data()
        for await chunk in chunks(handle) {
            collected.append(chunk)
        }
        return collected
    }

    private static func chunks(_ handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }
}

/// One-shot exit-code latch supporting fulfillment before or after waiters arrive.
private final class ExitLatch: @unchecked Sendable {
    private let state = Mutex<State>(State())

    private struct State {
        var code: Int32?
        var waiters: [CheckedContinuation<Int32, Never>] = []
    }

    var value: Int32? {
        state.withLock { $0.code }
    }

    func fulfill(_ code: Int32) {
        let waiters: [CheckedContinuation<Int32, Never>] = state.withLock { state in
            guard state.code == nil else { return [] }
            state.code = code
            let waiting = state.waiters
            state.waiters = []
            return waiting
        }
        for waiter in waiters {
            waiter.resume(returning: code)
        }
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            let immediate: Int32? = state.withLock { state in
                if let code = state.code { return code }
                state.waiters.append(continuation)
                return nil
            }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }
}
