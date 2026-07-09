import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("CommandRunner")
struct CommandRunnerTests {
    let runner = CommandRunner()

    @Test("Successful command collects stdout and exit code")
    func success() async throws {
        let result = try await runner.run(
            CommandRequest(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"])
        )
        #expect(result.exitCode == 0)
        #expect(result.isSuccess)
        #expect(result.standardOutputText == "hello\n")
        #expect(result.standardErrorText.isEmpty)
        #expect(result.duration >= 0)
    }

    @Test("Non-zero exit is reported, not thrown")
    func failureExitCode() async throws {
        let result = try await runner.run(
            CommandRequest(executable: URL(fileURLWithPath: "/usr/bin/false"))
        )
        #expect(result.exitCode == 1)
        #expect(!result.isSuccess)
    }

    @Test("stdout and stderr are kept separate")
    func outputSeparation() async throws {
        // /bin/sh is acceptable in tests as a fixture generator; production
        // code never launches a shell.
        let result = try await runner.run(
            CommandRequest(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo out; echo err 1>&2"]
            )
        )
        #expect(result.standardOutputText == "out\n")
        #expect(result.standardErrorText == "err\n")
    }

    @Test("stdin data is delivered and stdin is closed afterwards")
    func stdinDelivery() async throws {
        let result = try await runner.run(
            CommandRequest(
                executable: URL(fileURLWithPath: "/bin/cat"),
                standardInput: Data("piped-input".utf8)
            )
        )
        #expect(result.exitCode == 0)
        #expect(result.standardOutputText == "piped-input")
    }

    @Test("stdin is closed even without input, so prompts cannot hang")
    func stdinClosedByDefault() async throws {
        // cat exits immediately on EOF; without a closed stdin this would
        // hit the timeout instead.
        let result = try await runner.run(
            CommandRequest(
                executable: URL(fileURLWithPath: "/bin/cat"),
                timeout: .seconds(5)
            )
        )
        #expect(result.exitCode == 0)
        #expect(result.standardOutputText.isEmpty)
    }

    @Test("Timeout terminates the child and throws commandTimedOut")
    func timeout() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ContainerEngineError.commandTimedOut) {
            _ = try await runner.run(
                CommandRequest(
                    executable: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["30"],
                    timeout: .milliseconds(200)
                )
            )
        }
        // Termination must not wait for the child's natural 30 s exit.
        #expect(clock.now - start < .seconds(10))
    }

    @Test("Cancellation terminates the child and throws commandCancelled")
    func cancellation() async throws {
        let runner = self.runner
        let task = Task {
            try await runner.run(
                CommandRequest(
                    executable: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["30"]
                )
            )
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()

        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ContainerEngineError.commandCancelled) {
            _ = try await task.value
        }
        #expect(clock.now - start < .seconds(10))
    }

    @Test("Missing executable throws binaryNotFound")
    func missingBinary() async throws {
        await #expect(throws: ContainerEngineError.binaryNotFound) {
            _ = try await runner.run(
                CommandRequest(executable: URL(fileURLWithPath: "/nonexistent/tool"))
            )
        }
    }

    @Test("Streaming delivers stdout, stderr, and completion")
    func streaming() async throws {
        let stream = runner.stream(
            CommandRequest(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf out; printf err 1>&2; exit 3"]
            )
        )
        var stdout = ""
        var stderr = ""
        var exitCode: Int32?
        for try await event in stream {
            switch event {
            case .stdout(let text): stdout += text
            case .stderr(let text): stderr += text
            case .completed(let code): exitCode = code
            }
        }
        #expect(stdout == "out")
        #expect(stderr == "err")
        #expect(exitCode == 3)
    }

    @Test("Stream timeout throws commandTimedOut")
    func streamTimeout() async throws {
        let stream = runner.stream(
            CommandRequest(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                timeout: .milliseconds(200)
            )
        )
        await #expect(throws: ContainerEngineError.commandTimedOut) {
            for try await _ in stream {}
        }
    }
}
