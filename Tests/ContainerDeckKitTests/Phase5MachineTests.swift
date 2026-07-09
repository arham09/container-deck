import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("Phase 5 machine engine")
struct Phase5EngineTests {
    private func makeEngine(
        _ results: [Result<CommandResult, ContainerEngineError>]
    ) -> (AppleContainerCLIEngine, ScriptedCommandRunner) {
        let runner = ScriptedCommandRunner(results: results)
        let engine = AppleContainerCLIEngine(runner: runner) {
            URL(fileURLWithPath: "/usr/local/bin/container")
        }
        return (engine, runner)
    }

    @Test("Machine create streams with all verified flags")
    func createArguments() async throws {
        let (engine, runner) = makeEngine([])
        runner.scriptStream([.stdout("dev\n"), .completed(exitCode: 0)])
        var config = MachineConfiguration()
        config.image = "ubuntu:24.04"
        config.name = "dev"
        config.cpus = "4"
        config.memory = "8G"
        config.homeMount = .ro
        config.setAsDefault = true
        config.createWithoutBooting = true
        _ = try await engine.createMachine(config)
        #expect(runner.recordedRequests.first?.arguments == [
            "machine", "create", "--progress", "plain",
            "--name", "dev", "--cpus", "4", "--memory", "8G",
            "--home-mount", "ro", "--set-default", "--no-boot",
            "ubuntu:24.04",
        ])
    }

    @Test("Machine lifecycle commands send verified arguments")
    func lifecycleArguments() async throws {
        let (engine, runner) = makeEngine([
            .success(makeResult()), .success(makeResult()),
            .success(makeResult()), .success(makeResult()),
            .success(makeResult(stdout: "Linux dev 6.6")),
        ])
        try await engine.stopMachine(name: "dev")
        try await engine.deleteMachine(name: "dev")
        try await engine.setMachine(name: "dev", settings: ["cpus=8", "home-mount=ro"])
        try await engine.setDefaultMachine(name: "dev")
        let output = try await engine.runMachineCommand(name: "dev", command: ["uname", "-a"])

        let requests = runner.recordedRequests.map(\.arguments)
        #expect(requests[0] == ["machine", "stop", "dev"])
        #expect(requests[1] == ["machine", "delete", "dev"])
        #expect(requests[2] == ["machine", "set", "--name", "dev", "cpus=8", "home-mount=ro"])
        #expect(requests[3] == ["machine", "set-default", "dev"])
        #expect(requests[4] == ["machine", "run", "--name", "dev", "uname", "-a"])
        #expect(output.contains("Linux"))
    }

    @Test("Machine logs send verified arguments")
    func logsArguments() async throws {
        let (engine, runner) = makeEngine([])
        runner.scriptStream([.stdout("log\n"), .completed(exitCode: 0)])
        _ = try await engine.machineLogs(name: "dev", tail: 100, follow: true, boot: false)
        #expect(runner.recordedRequests.first?.arguments
            == ["machine", "logs", "--follow", "-n", "100", "dev"])
    }

    @Test("Unknown settings keys are rejected before spawning")
    func settingsValidation() async throws {
        let (engine, runner) = makeEngine([])
        await #expect(throws: ContainerEngineError.self) {
            try await engine.setMachine(name: "dev", settings: ["nested-virt=on"])
        }
        #expect(runner.recordedRequests.isEmpty)
    }
}

@MainActor
@Suite("MachineActionsController")
struct MachineActionsControllerTests {
    private func makeController(
        engine: MockContainerEngine
    ) -> (MachineActionsController, OperationStore, ResourceCenter) {
        let operations = OperationStore()
        let resources = ResourceCenter(engine: engine)
        let controller = MachineActionsController(
            engine: engine, operations: operations, resources: resources
        )
        return (controller, operations, resources)
    }

    @Test("Create streams, then the machine appears")
    func create() async {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.machines.refresh()
        let before = resources.machines.items.count

        var config = MachineConfiguration()
        config.image = "alpine:3.22"
        config.name = "new-machine"
        controller.create(config)
        _ = await eventually { resources.machines.items.count == before + 1 }
        #expect(operations.operations.first?.status == .succeeded)
    }

    @Test("Settings changes mark pending restart; restart clears it")
    func pendingRestart() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, _, resources) = makeController(engine: engine)
        await resources.machines.refresh()
        let machine = try #require(resources.machines.items.first)

        controller.applySettings(machine, settings: ["cpus=8"])
        _ = await eventually { controller.pendingRestart.contains(machine.name) }
        #expect(controller.pendingRestart.contains(machine.name))

        controller.restart(machine)
        _ = await eventually { !controller.pendingRestart.contains(machine.name) }
        #expect(!controller.pendingRestart.contains(machine.name))
    }

    @Test("Set default moves the star to exactly one machine")
    func setDefault() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, _, resources) = makeController(engine: engine)
        await resources.machines.refresh()
        let nonDefault = try #require(resources.machines.items.first { !$0.isDefault })

        controller.setDefault(nonDefault)
        _ = await eventually {
            resources.machines.items.first { $0.name == nonDefault.name }?.isDefault == true
        }
        #expect(resources.machines.items.count { $0.isDefault } == 1)
    }

    @Test("One-shot command output lands in the operation record")
    func runCommand() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, operations, resources) = makeController(engine: engine)
        await resources.machines.refresh()
        let machine = try #require(resources.machines.items.first)

        controller.runCommand(machine, command: "uname -a")
        _ = await eventually { operations.operations.first?.status == .succeeded }
        #expect(operations.operations.first?.outputExcerpt.contains("uname -a") == true)
    }

    @Test("Delete requires confirmation and removes the machine")
    func delete() async throws {
        let engine = MockContainerEngine(running: true)
        let (controller, _, resources) = makeController(engine: engine)
        await resources.machines.refresh()
        let machine = try #require(resources.machines.items.first)

        controller.pendingDelete = machine
        controller.confirmDelete()
        _ = await eventually { !resources.machines.items.contains { $0.name == machine.name } }
        #expect(!resources.machines.items.contains { $0.name == machine.name })
    }
}
