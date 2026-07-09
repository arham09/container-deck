import Foundation
import Testing
@testable import ContainerDeckKit

/// Opt-in end-to-end verification of the real start/stop workflow through
/// `SystemPowerController` against the installed CLI.
///
/// This MUTATES system state (starts and stops Apple Container), so it only
/// runs with CONTAINERDECK_REAL_LIFECYCLE=1 and only when the system is
/// found stopped; it stops the system again afterwards.
///
///     CONTAINERDECK_REAL_LIFECYCLE=1 scripts/test.sh --filter RealLifecycle
/// Opt-in end-to-end container workflow against the real CLI: system start →
/// run → logs → stop → delete → prune → system stop. Requires a configured
/// kernel and the alpine:latest image (pulled if missing is NOT done here —
/// the test skips instead of mutating more than necessary).
///
///     CONTAINERDECK_REAL_CONTAINERS=1 scripts/test.sh --filter RealContainer
@Suite("Real container lifecycle (opt-in, mutates state)", .serialized)
struct RealContainerLifecycleTests {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["CONTAINERDECK_REAL_CONTAINERS"] == "1"
            && FileManager.default.isExecutableFile(atPath: "/usr/local/bin/container")
    }

    @Test("Run, logs, stop, delete, prune through the production engine", .enabled(if: enabled))
    @MainActor
    func fullContainerCycle() async throws {
        let engine = AppleContainerCLIEngine(runner: CommandRunner()) {
            URL(fileURLWithPath: "/usr/local/bin/container")
        }
        let initial = try await engine.systemStatus()
        try #require(!initial.isRunning, "requires a stopped system")

        try await engine.startSystem(options: SystemStartOptions())
        // Poll until running (kernel is configured, so no prompt).
        var running = false
        for _ in 0..<30 {
            if let status = try? await engine.systemStatus(), status.isRunning {
                running = true
                break
            }
            try await Task.sleep(for: .seconds(1))
        }
        try #require(running, "system did not reach running")

        do {
            var config = ContainerRunConfiguration()
            config.image = "alpine:latest"
            config.name = "cd-e2e"
            config.commandLine = "sh -c 'echo hello-e2e; sleep 120'"
            let id = try await engine.launchContainer(config)
            #expect(id == "cd-e2e")

            let listed = try await engine.listContainers(all: true)
            #expect(listed.contains { $0.id == "cd-e2e" && $0.isRunning })

            try await Task.sleep(for: .seconds(2))
            let stream = try await engine.containerLogs(id: id, tail: 50, follow: false, boot: false)
            var logText = ""
            for try await event in stream {
                if case .stdout(let text) = event { logText += text }
            }
            #expect(logText.contains("hello-e2e"))

            try await engine.stopContainer(id: id)
            let afterStop = try await engine.inspectContainer(id: id)
            #expect(!afterStop.summary.isRunning)

            try await engine.deleteContainer(id: id, force: false)
            // With nothing left to prune the CLI prints nothing; success is
            // the command completing (verified behavior).
            _ = try await engine.pruneContainers()
        } catch {
            // Best-effort cleanup before failing the test.
            try? await engine.deleteContainer(id: "cd-e2e", force: true)
            try? await engine.stopSystem()
            throw error
        }

        try await engine.stopSystem()
        let final = try await engine.systemStatus()
        #expect(!final.isRunning)
    }
}

/// Opt-in real image workflow: pull (streaming) → tag → delete tag → prune.
///
///     CONTAINERDECK_REAL_IMAGES=1 scripts/test.sh --filter RealImage
@Suite("Real image workflow (opt-in, mutates state)", .serialized)
struct RealImageWorkflowTests {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["CONTAINERDECK_REAL_IMAGES"] == "1"
            && FileManager.default.isExecutableFile(atPath: "/usr/local/bin/container")
    }

    @Test("Pull, tag, delete, prune through the production engine", .enabled(if: enabled))
    @MainActor
    func imageWorkflow() async throws {
        let engine = AppleContainerCLIEngine(runner: CommandRunner()) {
            URL(fileURLWithPath: "/usr/local/bin/container")
        }
        let initial = try await engine.systemStatus()
        try #require(!initial.isRunning, "requires a stopped system")
        try await engine.startSystem(options: SystemStartOptions())
        var running = false
        for _ in 0..<30 {
            if let status = try? await engine.systemStatus(), status.isRunning {
                running = true
                break
            }
            try await Task.sleep(for: .seconds(1))
        }
        try #require(running)

        do {
            // Pull streams plain progress and completes with exit 0.
            let stream = try await engine.pullImage(reference: "alpine:latest", platform: nil)
            var sawOutput = false
            var exitCode: Int32?
            for try await event in stream {
                switch event {
                case .stdout, .stderr: sawOutput = true
                case .completed(let code): exitCode = code
                }
            }
            #expect(sawOutput)
            #expect(exitCode == 0)

            try await engine.tagImage(source: "alpine:latest", target: "cd-real-tag:1")
            let listed = try await engine.listImages()
            #expect(listed.contains { $0.reference.contains("cd-real-tag") })

            let summary = try await engine.deleteImage(reference: "cd-real-tag:1")
            #expect(summary.contains("Reclaimed"))
            _ = try await engine.pruneImages(all: false)
        } catch {
            _ = try? await engine.deleteImage(reference: "cd-real-tag:1")
            try? await engine.stopSystem()
            throw error
        }

        try await engine.stopSystem()
        let final = try await engine.systemStatus()
        #expect(!final.isRunning)
    }
}

@Suite("Real CLI lifecycle (opt-in, mutates system state)", .serialized)
struct RealLifecycleIntegrationTests {
    static let binaryPath = "/usr/local/bin/container"
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["CONTAINERDECK_REAL_LIFECYCLE"] == "1"
            && FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    @Test("Full power cycle: start, verify, stop, verify", .enabled(if: enabled))
    @MainActor
    func fullPowerCycle() async throws {
        let runner = CommandRunner()
        let engine = AppleContainerCLIEngine(runner: runner) {
            URL(fileURLWithPath: Self.binaryPath)
        }
        let settings = makeTestSettings()
        settings.confirmBeforeStopping = false
        let controller = SystemPowerController(
            engine: engine,
            operations: OperationStore(),
            settings: settings,
            pollInterval: .seconds(1),
            startVerificationTimeout: .seconds(90),
            stopVerificationTimeout: .seconds(45)
        )

        // Refuse to disturb a system the user is running.
        let initial = try await engine.systemStatus()
        try #require(!initial.isRunning, "requires a stopped system; found it running")

        await controller.refreshStatus()
        #expect(controller.state == .stopped)

        // Turn On through the exact production code path.
        controller.requestTurnOn()
        #expect(controller.state == .starting)
        await controller.waitForLifecycleCompletion()

        if controller.kernelInstallPrompt {
            // Machine has no default kernel: the app must surface the
            // decision (never a silent download) and resync to the real
            // state — observed with CLI 1.0.0, the apiserver may still be up.
            let resynced = try await engine.systemStatus()
            #expect(controller.state == (resynced.isRunning ? .running : .stopped))
        } else {
            #expect(controller.state == .running)
        }

        // Turn Off (only if it is actually up) and verify.
        if controller.state == .running {
            controller.requestTurnOff()
            let stopped = await eventually(timeout: .seconds(60), poll: .milliseconds(200)) {
                controller.state == .stopped
            }
            #expect(stopped)
        }

        // Restore: never leave the system running after the test.
        if let final = try? await engine.systemStatus(), final.isRunning {
            try? await engine.stopSystem()
        }
        let restored = try await engine.systemStatus()
        #expect(!restored.isRunning)
    }
}
