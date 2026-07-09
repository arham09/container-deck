import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("AppleContainerCLIEngine Phase 1 reads")
struct Phase1EngineTests {
    private func makeEngine(
        _ results: [Result<CommandResult, ContainerEngineError>]
    ) -> (AppleContainerCLIEngine, ScriptedCommandRunner) {
        let runner = ScriptedCommandRunner(results: results)
        let engine = AppleContainerCLIEngine(runner: runner) {
            URL(fileURLWithPath: "/usr/local/bin/container")
        }
        return (engine, runner)
    }

    private var serviceDownResult: CommandResult {
        makeResult(
            exitCode: 1,
            stderr: """
            Error: interrupted: "XPC connection error: Connection invalid"
            Ensure container system service has been started with `container system start`.
            """
        )
    }

    @Test("List commands send the verified arguments")
    func verifiedArguments() async throws {
        let listFixture = String(decoding: try fixtureData("container-list"), as: UTF8.self)
        let (engine, runner) = makeEngine([
            .success(makeResult(stdout: listFixture)),
            .success(makeResult(stdout: "[]")),
            .success(makeResult(stdout: "[]")),
            .success(makeResult(stdout: "[]")),
            .success(makeResult(stdout: "[]")),
            .success(makeResult(stdout: "[]")),
            .success(makeResult(stdout: String(decoding: try fixtureData("system-df"), as: UTF8.self))),
        ])
        _ = try await engine.listContainers(all: true)
        _ = try await engine.listImages()
        _ = try await engine.listVolumes()
        _ = try await engine.listMachines()
        _ = try await engine.listRegistries()
        _ = try await engine.builderStatus()
        _ = try await engine.diskUsage()

        let requests = runner.recordedRequests.map(\.arguments)
        #expect(requests[0] == ["list", "--all", "--format", "json"])
        #expect(requests[1] == ["image", "list", "--verbose", "--format", "json"])
        #expect(requests[2] == ["volume", "list", "--format", "json"])
        #expect(requests[3] == ["machine", "list", "--format", "json"])
        #expect(requests[4] == ["registry", "list", "--format", "json"])
        #expect(requests[5] == ["builder", "status", "--format", "json"])
        #expect(requests[6] == ["system", "df", "--format", "json"])
    }

    @Test("listContainers without all omits the flag")
    func runningOnlyArguments() async throws {
        let (engine, runner) = makeEngine([.success(makeResult(stdout: "[]"))])
        _ = try await engine.listContainers(all: false)
        #expect(runner.recordedRequests.first?.arguments == ["list", "--format", "json"])
    }

    @Test("The verified stopped-system error text maps to serviceNotRunning")
    func serviceNotRunningMapping() async throws {
        let (engine, _) = makeEngine([.success(serviceDownResult)])
        await #expect(throws: ContainerEngineError.serviceNotRunning) {
            _ = try await engine.listContainers(all: true)
        }
    }

    @Test("A missing network plugin maps to featureUnavailable")
    func networkPluginMissing() async throws {
        let (engine, _) = makeEngine([
            .success(makeResult(
                exitCode: 1,
                stdout: "Error: Plugin 'container-network' not found.\n..."
            ))
        ])
        do {
            _ = try await engine.listNetworks()
            Issue.record("expected featureUnavailable")
        } catch let error as ContainerEngineError {
            guard case .featureUnavailable(let reason) = error else {
                Issue.record("expected featureUnavailable, got \(error)")
                return
            }
            #expect(reason.contains("macOS 26"))
        }
    }

    @Test("Non-empty stats output is reported as unverified, never guessed")
    func statsUnverifiedSchema() async throws {
        let (engine, _) = makeEngine([
            .success(makeResult(stdout: #"[{"mystery":"row"}]"#))
        ])
        do {
            _ = try await engine.containerStatistics()
            Issue.record("expected featureUnavailable")
        } catch let error as ContainerEngineError {
            guard case .featureUnavailable = error else {
                Issue.record("expected featureUnavailable, got \(error)")
                return
            }
        }
    }

    @Test("Empty stats output returns an empty result")
    func statsEmpty() async throws {
        let (engine, _) = makeEngine([.success(makeResult(stdout: "[]"))])
        let statistics = try await engine.containerStatistics()
        #expect(statistics.isEmpty)
    }

    @Test("inspectContainer validates the ID before spawning anything")
    func inspectValidation() async throws {
        let (engine, runner) = makeEngine([])
        await #expect(throws: ContainerEngineError.self) {
            _ = try await engine.inspectContainer(id: "bad;id")
        }
        #expect(runner.recordedRequests.isEmpty)
    }
}

@MainActor
@Suite("ResourceStore")
struct ResourceStoreTests {
    @Test("Success loads items")
    func success() async {
        let store = ResourceStore<ContainerSummary> { MockData.containers }
        await store.refresh()
        #expect(store.phase == .loaded)
        #expect(store.items.count == MockData.containers.count)
        #expect(!store.isStale)
    }

    @Test("Stopped system with no data shows needsSystem")
    func needsSystem() async {
        let store = ResourceStore<ContainerSummary> {
            throw ContainerEngineError.serviceNotRunning
        }
        await store.refresh()
        #expect(store.phase == .needsSystem)
    }

    @Test("Stopped system keeps loaded data and marks it stale")
    func staleOnStop() async {
        let flag = FailToggle()
        let store = ResourceStore<ContainerSummary> {
            if flag.shouldFail { throw ContainerEngineError.serviceNotRunning }
            return MockData.containers
        }
        await store.refresh()
        #expect(store.phase == .loaded)
        flag.shouldFail = true
        await store.refresh()
        #expect(store.phase == .loaded)
        #expect(store.isStale)
        #expect(store.items.count == MockData.containers.count)
    }

    @Test("Capability-gated features surface the reason")
    func unavailable() async {
        let store = ResourceStore<NetworkSummary> {
            throw ContainerEngineError.featureUnavailable("plugin missing")
        }
        await store.refresh()
        #expect(store.phase == .unavailable("plugin missing"))
    }

    @Test("A failed refresh never erases loaded data")
    func failureKeepsData() async {
        let flag = FailToggle()
        let store = ResourceStore<ContainerSummary> {
            if flag.shouldFail {
                throw ContainerEngineError.commandFailed(
                    executable: "container", arguments: [], exitCode: 1, stderr: "boom"
                )
            }
            return MockData.containers
        }
        await store.refresh()
        flag.shouldFail = true
        await store.refresh()
        #expect(store.phase == .loaded)
        #expect(!store.items.isEmpty)
    }
}

/// Mutable failure toggle usable from Sendable closures.
final class FailToggle: @unchecked Sendable {
    var shouldFail = false
}
