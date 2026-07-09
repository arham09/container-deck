import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("Phase 4 volume engine")
struct Phase4EngineTests {
    private func makeEngine(
        _ results: [Result<CommandResult, ContainerEngineError>]
    ) -> (AppleContainerCLIEngine, ScriptedCommandRunner) {
        let runner = ScriptedCommandRunner(results: results)
        let engine = AppleContainerCLIEngine(runner: runner) {
            URL(fileURLWithPath: "/usr/local/bin/container")
        }
        return (engine, runner)
    }

    @Test("Volume commands send verified arguments")
    func volumeArguments() async throws {
        let (engine, runner) = makeEngine([
            .success(makeResult(stdout: "data")),
            .success(makeResult(stdout: "data")),
            .success(makeResult(stdout: "Reclaimed Zero KB in disk space")),
        ])
        try await engine.createVolume(
            name: "data", size: "10G", labels: [KeyValueEntry(key: "team", value: "core")]
        )
        try await engine.deleteVolume(name: "data")
        let summary = try await engine.pruneVolumes()

        let requests = runner.recordedRequests.map(\.arguments)
        #expect(requests[0] == ["volume", "create", "-s", "10G", "--label", "team=core", "data"])
        #expect(requests[1] == ["volume", "delete", "data"])
        #expect(requests[2] == ["volume", "prune"])
        #expect(summary.contains("Reclaimed"))
    }

    @Test("Invalid volume input is rejected before spawning")
    func validation() async throws {
        let (engine, runner) = makeEngine([])
        await #expect(throws: ContainerEngineError.self) {
            try await engine.createVolume(name: "bad name", size: nil, labels: [])
        }
        await #expect(throws: ContainerEngineError.self) {
            try await engine.createVolume(name: "ok", size: "lots", labels: [])
        }
        #expect(runner.recordedRequests.isEmpty)
    }

    @Test("Network mutations are capability-gated, never guessed")
    func networksGated() async throws {
        let (engine, _) = makeEngine([])
        await #expect(throws: ContainerEngineError.self) {
            try await engine.createNetwork(name: "backend")
        }
        await #expect(throws: ContainerEngineError.self) {
            try await engine.deleteNetwork(name: "backend")
        }
    }
}

@MainActor
@Suite("VolumeActionsController")
struct VolumeActionsControllerTests {
    @Test("Create, delete, and prune flow through operations and refresh")
    func fullFlow() async throws {
        let engine = MockContainerEngine(running: true)
        let operations = OperationStore()
        let resources = ResourceCenter(engine: engine)
        let controller = VolumeActionsController(
            engine: engine, operations: operations, resources: resources
        )
        await resources.volumes.refresh()
        let countBefore = resources.volumes.items.count

        controller.create(name: "new-vol", size: "1G", labels: [])
        _ = await eventually { resources.volumes.items.count == countBefore + 1 }
        #expect(operations.operations.first?.status == .succeeded)

        let created = try #require(resources.volumes.items.first { $0.name == "new-vol" })
        controller.pendingDelete = created
        controller.confirmDelete()
        _ = await eventually { !resources.volumes.items.contains { $0.name == "new-vol" } }

        controller.pendingPrune = true
        controller.confirmPrune()
        _ = await eventually {
            operations.operations.first?.outputExcerpt.contains("Reclaimed") == true
        }
    }

    @Test("Invalid create surfaces the error without executing")
    func invalidCreate() async {
        let engine = MockContainerEngine(running: true)
        let operations = OperationStore()
        let resources = ResourceCenter(engine: engine)
        let controller = VolumeActionsController(
            engine: engine, operations: operations, resources: resources
        )
        controller.create(name: "bad name", size: "", labels: [])
        _ = await eventually { controller.lastError != nil }
        #expect(controller.lastError != nil)
    }
}
