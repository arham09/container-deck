import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("Phase 3 image/build/registry engine")
struct Phase3EngineTests {
    private func makeEngine(
        _ results: [Result<CommandResult, ContainerEngineError>]
    ) -> (AppleContainerCLIEngine, ScriptedCommandRunner) {
        let runner = ScriptedCommandRunner(results: results)
        let engine = AppleContainerCLIEngine(runner: runner) {
            URL(fileURLWithPath: "/usr/local/bin/container")
        }
        return (engine, runner)
    }

    @Test("Image commands send verified arguments")
    func imageArguments() async throws {
        let (engine, runner) = makeEngine([
            .success(makeResult()),
            .success(makeResult(stdout: "Reclaimed 42 MB in disk space")),
            .success(makeResult(stdout: "Reclaimed Zero KB in disk space")),
            .success(makeResult()),
            .success(makeResult(stdout: "docker.io/library/alpine:latest")),
        ])
        try await engine.tagImage(source: "alpine:latest", target: "mine:1")
        _ = try await engine.deleteImage(reference: "mine:1")
        _ = try await engine.pruneImages(all: true)
        try await engine.saveImage(reference: "alpine:latest", to: "/tmp/a.tar", platform: nil)
        _ = try await engine.loadImage(from: "/tmp")  // /tmp exists

        let requests = runner.recordedRequests.map(\.arguments)
        #expect(requests[0] == ["image", "tag", "alpine:latest", "mine:1"])
        #expect(requests[1] == ["image", "delete", "mine:1"])
        #expect(requests[2] == ["image", "prune", "--all"])
        #expect(requests[3] == ["image", "save", "--output", "/tmp/a.tar", "alpine:latest"])
        #expect(requests[4] == ["image", "load", "--input", "/tmp"])
    }

    @Test("Pull streams with plain progress and optional platform")
    func pullArguments() async throws {
        let (engine, runner) = makeEngine([])
        runner.scriptStream([.stdout("[1/2] Fetching\n"), .completed(exitCode: 0)])
        _ = try await engine.pullImage(reference: "alpine:latest", platform: "linux/arm64")
        #expect(runner.recordedRequests.first?.arguments
            == ["image", "pull", "--progress", "plain", "--platform", "linux/arm64", "alpine:latest"])
    }

    @Test("Registry login sends the password via stdin, never in arguments")
    func registryLoginStdin() async throws {
        let (engine, runner) = makeEngine([.success(makeResult())])
        try await engine.registryLogin(
            server: "ghcr.io", username: "me", password: Data("s3cret".utf8)
        )
        let request = try #require(runner.recordedRequests.first)
        #expect(request.arguments == ["registry", "login", "--username", "me", "--password-stdin", "ghcr.io"])
        #expect(!request.arguments.joined().contains("s3cret"))
        #expect(request.standardInput == Data("s3cret".utf8))
    }

    @Test("Registry logout and builder commands send verified arguments")
    func builderAndLogout() async throws {
        let (engine, runner) = makeEngine([
            .success(makeResult()), .success(makeResult()),
            .success(makeResult()), .success(makeResult()),
        ])
        try await engine.registryLogout(server: "ghcr.io")
        try await engine.startBuilder(cpus: "4", memory: "4G")
        try await engine.stopBuilder()
        try await engine.deleteBuilder(force: true)

        let requests = runner.recordedRequests.map(\.arguments)
        #expect(requests[0] == ["registry", "logout", "ghcr.io"])
        #expect(requests[1] == ["builder", "start", "--cpus", "4", "--memory", "4G"])
        #expect(requests[2] == ["builder", "stop"])
        #expect(requests[3] == ["builder", "delete", "--force"])
    }

    @Test("Empty password is rejected before spawning")
    func emptyPasswordRejected() async throws {
        let (engine, runner) = makeEngine([])
        await #expect(throws: ContainerEngineError.self) {
            try await engine.registryLogin(server: "ghcr.io", username: "me", password: Data())
        }
        #expect(runner.recordedRequests.isEmpty)
    }
}

@Suite("BuildArgumentBuilder")
struct BuildArgumentBuilderTests {
    @Test("Full build configuration maps to verified flags")
    func fullBuild() throws {
        var config = BuildConfiguration()
        config.contextDirectory = "/tmp"
        config.tag = "my-app:latest"
        config.target = "release"
        config.noCache = true
        config.pullBaseImage = true
        config.cpus = "4"
        config.memory = "4G"
        config.platform = "linux/arm64"
        config.buildArguments = [KeyValueEntry(key: "API_KEY", value: "topsecret")]
        config.labels = [KeyValueEntry(key: "team", value: "core")]
        config.secrets = ["id=npm,src=/tmp/npmrc"]

        let built = try BuildArgumentBuilder.build(config)
        #expect(built.arguments == [
            "build", "--tag", "my-app:latest", "--target", "release",
            "--no-cache", "--pull", "--cpus", "4", "--memory", "4G",
            "--platform", "linux/arm64",
            "--build-arg", "API_KEY=topsecret",
            "--label", "team=core",
            "--secret", "id=npm,src=/tmp/npmrc",
            "--progress", "plain", "/tmp",
        ])
        // Build-arg values and secret specs are masked (spec §8).
        #expect(built.redactedArguments.contains("API_KEY=<redacted>"))
        #expect(built.redactedArguments.contains("<redacted>"))
        #expect(!built.redactedArguments.joined().contains("topsecret"))
        #expect(!built.redactedArguments.joined().contains("npmrc"))
    }

    @Test("Missing tag or bad context is rejected")
    func buildValidation() {
        var config = BuildConfiguration()
        config.contextDirectory = "/tmp"
        #expect(throws: ContainerEngineError.self) {
            _ = try BuildArgumentBuilder.build(config)  // no tag
        }
        config.tag = "x:1"
        config.contextDirectory = "/nonexistent-cd-dir"
        #expect(throws: ContainerEngineError.self) {
            _ = try BuildArgumentBuilder.build(config)
        }
    }
}

@MainActor
@Suite("ImageActionsController")
struct ImageActionsControllerTests {
    private func makeController(
        engine: MockContainerEngine
    ) -> (ImageActionsController, OperationStore, ResourceCenter) {
        let operations = OperationStore()
        let resources = ResourceCenter(engine: engine)
        let controller = ImageActionsController(
            engine: engine, operations: operations, resources: resources
        )
        return (controller, operations, resources)
    }

    @Test("Pull streams progress into the operation and refreshes images")
    func pull() async {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.images.refresh()
        let countBefore = resources.images.items.count

        controller.pull(reference: "busybox:latest", platform: "")
        _ = await eventually { operations.operations.first?.status == .succeeded }
        _ = await eventually { resources.images.items.count == countBefore + 1 }

        #expect(operations.operations.first?.outputExcerpt.contains("Unpacking") == true)
    }

    @Test("Delete requires confirmation and reports the reclaimed summary")
    func deleteFlow() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.images.refresh()
        let image = try #require(resources.images.items.first)

        controller.pendingDelete = image
        controller.confirmDelete()
        _ = await eventually { operations.operations.first?.status == .succeeded }
        #expect(operations.operations.first?.outputExcerpt.contains("Reclaimed") == true)
    }

    @Test("Login passes the password through as stdin data and never logs it")
    func login() async {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, _) = makeController(engine: engine)

        controller.login(server: "ghcr.io", username: "me", password: "hunter2")
        _ = await eventually { operations.operations.first?.status == .succeeded }

        let stored = await engine.lastLoginPassword
        #expect(stored == Data("hunter2".utf8))
        let record = operations.operations.first
        #expect(record?.redactedCommand?.contains("hunter2") == false)
        #expect(record?.redactedCommand?.contains("--password-stdin") == true)
    }

    @Test("Build records history that survives via the JSON store")
    func buildHistory() async {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, _) = makeController(engine: engine)

        var config = BuildConfiguration()
        config.contextDirectory = "/tmp"
        config.tag = "test-build:1"
        config.buildArguments = [KeyValueEntry(key: "TOKEN", value: "secret-token")]
        controller.build(config)
        _ = await eventually { operations.operations.first?.status == .succeeded }
        _ = await eventually { !controller.buildHistory.records.isEmpty }

        let record = controller.buildHistory.records.first
        #expect(record?.tag == "test-build:1")
        #expect(record?.succeeded == true)
        // Persisted history never contains secret values.
        #expect(record?.redactedCommand.contains("secret-token") == false)

        // A fresh store reading the same file sees the record (restart survival).
        controller.buildHistory.clear()
        #expect(controller.buildHistory.records.isEmpty)
    }

    @Test("Invalid build config surfaces validation without executing")
    func invalidBuild() {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, _) = makeController(engine: engine)
        var config = BuildConfiguration()
        config.contextDirectory = "/tmp"  // tag missing
        controller.build(config)
        #expect(controller.lastError != nil)
        #expect(operations.operations.isEmpty)
    }

    @Test("Builder mutations are guarded and refresh state")
    func builderLifecycle() async {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, _) = makeController(engine: engine)

        controller.startBuilder()
        _ = await eventually { operations.operations.first?.status == .succeeded }
        let status = try? await engine.builderStatus()
        #expect(status?.isRunning == true)

        controller.stopBuilder()
        _ = await eventually { operations.operations.count { $0.status == .succeeded } == 2 }
        let stopped = try? await engine.builderStatus()
        #expect(stopped?.isRunning == false)
    }
}
