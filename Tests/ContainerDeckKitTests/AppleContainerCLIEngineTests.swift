import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("AppleContainerCLIEngine")
struct AppleContainerCLIEngineTests {
    private func makeEngine(
        _ results: [Result<CommandResult, ContainerEngineError>]
    ) -> (AppleContainerCLIEngine, ScriptedCommandRunner) {
        let runner = ScriptedCommandRunner(results: results)
        let engine = AppleContainerCLIEngine(runner: runner) {
            URL(fileURLWithPath: "/usr/local/bin/container")
        }
        return (engine, runner)
    }

    @Test("systemStatus sends the verified arguments")
    func statusArguments() async throws {
        let stopped = try fixtureData("system-status-stopped")
        let (engine, runner) = makeEngine([
            .success(makeResult(exitCode: 1, stdout: String(decoding: stopped, as: UTF8.self)))
        ])
        _ = try await engine.systemStatus()
        #expect(runner.recordedRequests.first?.arguments == ["system", "status", "--format", "json"])
    }

    @Test("Status exit 1 with valid JSON means stopped, not an error")
    func statusExitOneIsStopped() async throws {
        let stopped = try fixtureData("system-status-stopped")
        let (engine, _) = makeEngine([
            .success(makeResult(exitCode: 1, stdout: String(decoding: stopped, as: UTF8.self)))
        ])
        let status = try await engine.systemStatus()
        #expect(!status.isRunning)
    }

    @Test("Status exit 1 with garbage output is commandFailed")
    func statusExitOneGarbage() async throws {
        let (engine, _) = makeEngine([
            .success(makeResult(exitCode: 1, stdout: "apiserver is not running", stderr: "boom"))
        ])
        do {
            _ = try await engine.systemStatus()
            Issue.record("expected commandFailed")
        } catch let error as ContainerEngineError {
            guard case .commandFailed(_, _, let exitCode, let stderr) = error else {
                Issue.record("expected commandFailed, got \(error)")
                return
            }
            #expect(exitCode == 1)
            #expect(stderr == "boom")
        }
    }

    @Test("Status exit 0 with garbage output is decodingFailed")
    func statusExitZeroGarbage() async throws {
        let (engine, _) = makeEngine([
            .success(makeResult(exitCode: 0, stdout: "surprise"))
        ])
        do {
            _ = try await engine.systemStatus()
            Issue.record("expected decodingFailed")
        } catch let error as ContainerEngineError {
            guard case .decodingFailed = error else {
                Issue.record("expected decodingFailed, got \(error)")
                return
            }
        }
    }

    @Test("systemVersion decodes the fixture")
    func version() async throws {
        let fixture = try fixtureData("system-version")
        let (engine, runner) = makeEngine([
            .success(makeResult(stdout: String(decoding: fixture, as: UTF8.self)))
        ])
        let version = try await engine.systemVersion()
        #expect(version.version == "1.0.0")
        #expect(runner.recordedRequests.first?.arguments == ["system", "version", "--format", "json"])
    }

    @Test("Start failure mentioning the kernel prompt becomes kernelInstallationRequired")
    func startKernelPrompt() async throws {
        // Reproduces the observed CLI 1.0.0 behavior under a closed stdin.
        let output = """
        Launching container-apiserver...
        Verifying machine API server is running...
        No default kernel configured.
        Install the recommended default kernel from [https://example.invalid]? [Y/n]:
        """
        let (engine, _) = makeEngine([
            .success(makeResult(exitCode: 1, stdout: output, stderr: "Error: failed to read user input"))
        ])
        await #expect(throws: ContainerEngineError.kernelInstallationRequired(
            "Apple Container reported that no default kernel is configured."
        )) {
            try await engine.startSystem(options: SystemStartOptions())
        }
    }

    @Test("Kernel-install option adds the verified flag")
    func startKernelInstallFlag() async throws {
        let (engine, runner) = makeEngine([.success(makeResult())])
        try await engine.startSystem(
            options: SystemStartOptions(installDefaultKernelIfNeeded: true)
        )
        #expect(runner.recordedRequests.first?.arguments == ["system", "start", "--enable-kernel-install"])
    }

    @Test("Plain start failure is commandFailed")
    func startFailure() async throws {
        let (engine, _) = makeEngine([
            .success(makeResult(exitCode: 1, stderr: "something broke"))
        ])
        do {
            try await engine.startSystem(options: SystemStartOptions())
            Issue.record("expected commandFailed")
        } catch let error as ContainerEngineError {
            guard case .commandFailed = error else {
                Issue.record("expected commandFailed, got \(error)")
                return
            }
        }
    }

    @Test("Stop sends the verified arguments and succeeds on exit 0")
    func stop() async throws {
        let (engine, runner) = makeEngine([.success(makeResult())])
        try await engine.stopSystem()
        #expect(runner.recordedRequests.first?.arguments == ["system", "stop"])
    }

    @Test("Phase 1+ resource methods are capability-gated, not simulated")
    func resourcesUnavailable() async throws {
        let (engine, _) = makeEngine([])
        await #expect(throws: ContainerEngineError.self) {
            _ = try await engine.listContainers(all: true)
        }
        await #expect(throws: ContainerEngineError.self) {
            _ = try await engine.diskUsage()
        }
    }
}
