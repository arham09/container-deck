import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("ContainerArgumentBuilder")
struct ArgumentBuilderTests {
    @Test("Full configuration maps to verified flags in order")
    func fullConfiguration() throws {
        var config = ContainerRunConfiguration()
        config.mode = .run
        config.image = "postgres:17"
        config.name = "db"
        config.commandLine = "postgres -c 'max_connections=100'"
        config.detached = true
        config.removeAfterStop = true
        config.useInit = true
        config.readOnlyRootFilesystem = true
        config.entrypoint = "/entry.sh"
        config.workingDirectory = "/srv"
        config.cpus = "4"
        config.memory = "2G"
        config.shmSize = "64M"
        config.architecture = "arm64"
        config.environment = [KeyValueEntry(key: "POSTGRES_PASSWORD", value: "hunter2")]
        config.labels = [KeyValueEntry(key: "team", value: "payments")]
        config.publishedPorts = [PublishedPortSpec(hostPort: "5432", containerPort: "5432")]
        config.mounts = [MountSpec(source: "/tmp", target: "/data", readOnly: true)]
        config.networks = [NetworkAttachmentSpec(name: "default")]

        let built = try ContainerArgumentBuilder.build(config)
        #expect(built.arguments == [
            "run", "--name", "db", "--detach", "--rm", "--init", "--read-only",
            "--entrypoint", "/entry.sh", "--workdir", "/srv",
            "--cpus", "4", "--memory", "2G", "--shm-size", "64M",
            "--arch", "arm64",
            "--env", "POSTGRES_PASSWORD=hunter2",
            "--label", "team=payments",
            "--publish", "5432:5432/tcp",
            "--mount", "type=bind,source=/tmp,target=/data,readonly",
            "--network", "default",
            "--progress", "plain",
            "postgres:17",
            "postgres", "-c", "max_connections=100",
        ])
        // Env values never appear in the redacted form (spec §8).
        #expect(built.redactedArguments.contains("POSTGRES_PASSWORD=<redacted>"))
        #expect(!built.redactedArguments.joined().contains("hunter2"))
    }

    @Test("Create mode omits --detach")
    func createMode() throws {
        var config = ContainerRunConfiguration()
        config.mode = .create
        config.image = "alpine:latest"
        config.detached = true
        let built = try ContainerArgumentBuilder.build(config)
        #expect(built.arguments.first == "create")
        #expect(!built.arguments.contains("--detach"))
    }

    @Test("Tokenizer honors quotes")
    func tokenizer() {
        #expect(ContainerArgumentBuilder.tokenize("sh -c 'echo a b'") == ["sh", "-c", "echo a b"])
        #expect(ContainerArgumentBuilder.tokenize(#"echo "two words" plain"#) == ["echo", "two words", "plain"])
        #expect(ContainerArgumentBuilder.tokenize("  ") == [])
        #expect(ContainerArgumentBuilder.tokenize("a '' b") == ["a", "", "b"])
    }

    @Test("Invalid input is rejected before any process could spawn")
    func validation() {
        func expectInvalid(_ mutate: (inout ContainerRunConfiguration) -> Void) {
            var config = ContainerRunConfiguration()
            config.image = "alpine:latest"
            mutate(&config)
            #expect(throws: ContainerEngineError.self) {
                _ = try ContainerArgumentBuilder.build(config)
            }
        }
        expectInvalid { $0.image = "" }
        expectInvalid { $0.image = "bad image ref" }
        expectInvalid { $0.name = "has space" }
        expectInvalid { $0.cpus = "-2" }
        expectInvalid { $0.memory = "lots" }
        expectInvalid { $0.workingDirectory = "relative/path" }
        expectInvalid { $0.environment = [KeyValueEntry(key: "1BAD KEY", value: "x")] }
        expectInvalid { $0.publishedPorts = [PublishedPortSpec(hostPort: "99999", containerPort: "80")] }
        expectInvalid { $0.publishedPorts = [PublishedPortSpec(hostIP: "999.1.1.1", hostPort: "80", containerPort: "80")] }
        expectInvalid { $0.mounts = [MountSpec(source: "/nonexistent-cd-path", target: "/d")] }
        expectInvalid { $0.mounts = [MountSpec(source: "/tmp", target: "relative")] }
    }
}

@Suite("Engine container lifecycle")
struct EngineLifecycleTests {
    private func makeEngine(
        _ results: [Result<CommandResult, ContainerEngineError>]
    ) -> (AppleContainerCLIEngine, ScriptedCommandRunner) {
        let runner = ScriptedCommandRunner(results: results)
        let engine = AppleContainerCLIEngine(runner: runner) {
            URL(fileURLWithPath: "/usr/local/bin/container")
        }
        return (engine, runner)
    }

    @Test("Lifecycle commands send verified arguments")
    func lifecycleArguments() async throws {
        let (engine, runner) = makeEngine([
            .success(makeResult()), .success(makeResult()), .success(makeResult()),
            .success(makeResult()), .success(makeResult()),
            .success(makeResult(stdout: "Reclaimed 1 GB in disk space\nid1")),
        ])
        try await engine.startContainer(id: "web")
        try await engine.stopContainer(id: "web")
        try await engine.killContainer(id: "web")
        try await engine.deleteContainer(id: "web", force: false)
        try await engine.deleteContainer(id: "web", force: true)
        let pruneSummary = try await engine.pruneContainers()

        let requests = runner.recordedRequests.map(\.arguments)
        #expect(requests[0] == ["start", "web"])
        #expect(requests[1] == ["stop", "web"])
        #expect(requests[2] == ["kill", "web"])
        #expect(requests[3] == ["delete", "web"])
        #expect(requests[4] == ["delete", "--force", "web"])
        #expect(requests[5] == ["prune"])
        #expect(pruneSummary.contains("Reclaimed"))
    }

    @Test("launchContainer extracts the ID after plain progress output")
    func launchParsesID() async throws {
        let output = """
        [1/6] Fetching image [0s]
        [6/6] Starting container [0s]
        cd-p2
        """
        let (engine, runner) = makeEngine([.success(makeResult(stdout: output))])
        var config = ContainerRunConfiguration()
        config.image = "alpine:latest"
        config.name = "cd-p2"
        let id = try await engine.launchContainer(config)
        #expect(id == "cd-p2")
        let arguments = try #require(runner.recordedRequests.first?.arguments)
        #expect(arguments.contains("--detach"))
        #expect(arguments.contains("--progress"))
        // The request carries a redacted representation for display.
        #expect(runner.recordedRequests.first?.redactedArguments.isEmpty == false)
    }

    @Test("Log streams send verified arguments")
    func logArguments() async throws {
        let (engine, runner) = makeEngine([])
        runner.scriptStream([.stdout("line\n"), .completed(exitCode: 0)])
        _ = try await engine.containerLogs(id: "web", tail: 200, follow: true, boot: false)
        #expect(runner.recordedRequests.first?.arguments == ["logs", "--follow", "-n", "200", "web"])

        runner.scriptStream([.completed(exitCode: 0)])
        _ = try await engine.containerLogs(id: "web", tail: nil, follow: false, boot: true)
        #expect(runner.recordedRequests.last?.arguments == ["logs", "--boot", "web"])
    }

    @Test("IDs are validated before spawning")
    func idValidation() async throws {
        let (engine, runner) = makeEngine([])
        await #expect(throws: ContainerEngineError.self) {
            try await engine.startContainer(id: "bad id")
        }
        #expect(runner.recordedRequests.isEmpty)
    }
}

@MainActor
@Suite("ContainerLifecycleController")
struct LifecycleControllerTests {
    private func makeController(
        engine: MockContainerEngine
    ) -> (ContainerLifecycleController, OperationStore, ResourceCenter) {
        let operations = OperationStore()
        let resources = ResourceCenter(engine: engine)
        let controller = ContainerLifecycleController(
            engine: engine, operations: operations, resources: resources
        )
        return (controller, operations, resources)
    }

    private func waitForIdle(_ controller: ContainerLifecycleController) async {
        _ = await eventually { controller.busyContainers.isEmpty }
    }

    @Test("Stop mutates state, records an operation, and refreshes")
    func stop() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.containers.refresh()
        let running = try #require(resources.containers.items.first(where: { $0.isRunning }))

        controller.stop(running)
        await waitForIdle(controller)
        _ = await eventually { !(resources.containers.items.first { $0.id == running.id }?.isRunning ?? true) }

        #expect(operations.operations.first?.status == .succeeded)
        #expect(operations.operations.first?.redactedCommand == "container stop \(running.id)")
    }

    @Test("Restart stops, verifies, then starts")
    func restart() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.containers.refresh()
        let running = try #require(resources.containers.items.first(where: { $0.isRunning }))

        controller.restart(running)
        await waitForIdle(controller)

        #expect(operations.operations.first?.status == .succeeded)
        let after = try await engine.inspectContainer(id: running.id)
        #expect(after.summary.isRunning)
    }

    @Test("Restart aborts when stop fails — start never runs")
    func restartAbortsOnStopFailure() async throws {
        let engine = MockContainerEngine(running: true)
        await engine.setContainerStopBehavior(.fails)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.containers.refresh()
        let running = try #require(resources.containers.items.first(where: { $0.isRunning }))

        controller.restart(running)
        await waitForIdle(controller)

        if case .failed = operations.operations.first?.status {} else {
            Issue.record("expected failed restart")
        }
        // Still running: stop failed and start was never attempted.
        let after = try await engine.inspectContainer(id: running.id)
        #expect(after.summary.isRunning)
    }

    @Test("Restart aborts when the container still reports running after stop")
    func restartAbortsWhenStopHasNoEffect() async throws {
        let engine = MockContainerEngine(running: true)
        await engine.setContainerStopBehavior(.noEffect)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.containers.refresh()
        let running = try #require(resources.containers.items.first(where: { $0.isRunning }))

        controller.restart(running)
        await waitForIdle(controller)

        if case .failed = operations.operations.first?.status {} else {
            Issue.record("expected failed restart")
        }
        #expect(controller.lastError != nil)
    }

    @Test("Duplicate mutations on the same container are ignored")
    func duplicateGuard() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.containers.refresh()
        let running = try #require(resources.containers.items.first(where: { $0.isRunning }))

        controller.stop(running)
        controller.stop(running)
        controller.stop(running)
        await waitForIdle(controller)

        #expect(operations.operations.count == 1)
    }

    @Test("Deleting a running container requires the explicit force path")
    func deleteRunningNeedsForce() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, _, resources) = makeController(engine: engine)
        await resources.containers.refresh()
        let running = try #require(resources.containers.items.first(where: { $0.isRunning }))

        controller.requestDelete(running)
        #expect(controller.pendingForceDelete)
        controller.confirmDelete()
        await waitForIdle(controller)
        _ = await eventually { !resources.containers.items.contains { $0.id == running.id } }
        #expect(!resources.containers.items.contains { $0.id == running.id })
    }

    @Test("Prune removes stopped containers and records the summary")
    func prune() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.containers.refresh()
        let stoppedCount = resources.containers.items.count { !$0.isRunning }
        #expect(stoppedCount > 0)

        controller.requestPrune()
        #expect(controller.pendingPrune)
        controller.confirmPrune()
        _ = await eventually { operations.operations.first?.status == .succeeded }
        _ = await eventually { !resources.containers.items.contains { !$0.isRunning } }

        #expect(operations.operations.first?.outputExcerpt.contains("Reclaimed") == true)
    }

    @Test("Run form submission launches and refreshes")
    func submitRun() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.containers.refresh()

        var config = ContainerRunConfiguration()
        config.image = "alpine:latest"
        config.name = "new-one"
        controller.submitRunForm(config)
        _ = await eventually { resources.containers.items.contains { $0.id == "new-one" } }

        #expect(operations.operations.first?.status == .succeeded)
        #expect(operations.operations.first?.outputExcerpt.contains("new-one") == true)
    }

    @Test("Invalid run form surfaces the validation error without executing")
    func submitInvalidRun() async {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, _) = makeController(engine: engine)
        var config = ContainerRunConfiguration()
        config.image = "bad image"
        controller.submitRunForm(config)
        #expect(controller.lastError != nil)
        #expect(operations.operations.isEmpty)
    }
}

@MainActor
@Suite("LogSession")
struct LogSessionTests {
    @Test("Chunks split into lines with partial-line carry")
    func lineSplitting() async {
        let engine = MockContainerEngine(running: true)
        let session = LogSession(
            provider: { tail, follow, boot in
                try await engine.containerLogs(id: "a8f3c1d9e2b4", tail: tail, follow: follow, boot: boot)
            },
            bufferLimit: 1000
        )
        session.start(tail: 3, follow: false, boot: false)
        _ = await eventually { !session.isStreaming }
        #expect(session.lines.count == 3)
        #expect(session.lines.first?.text.contains("mock log line") == true)
    }

    @Test("Buffer is bounded")
    func bufferCap() async {
        let engine = MockContainerEngine(running: true)
        let session = LogSession(
            provider: { tail, follow, boot in
                try await engine.containerLogs(id: "a8f3c1d9e2b4", tail: tail, follow: follow, boot: boot)
            },
            bufferLimit: 100
        )
        session.start(tail: 500, follow: false, boot: false)
        _ = await eventually { !session.isStreaming }
        #expect(session.lines.count == 100)
        // Oldest lines were evicted; the newest survived.
        #expect(session.lines.last?.text.contains("500") == true)
    }
}
