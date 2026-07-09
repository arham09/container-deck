import Foundation
import Testing
@testable import ContainerDeckKit

/// Read-only integration against the actually installed Apple Container CLI.
/// Skipped (never faked) when the binary is absent — spec §5.
@Suite("Real CLI integration (read-only)")
struct RealCLIIntegrationTests {
    static let binaryPath = "/usr/local/bin/container"
    static var binaryInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    @Test("Installed CLI answers the version probe", .enabled(if: binaryInstalled))
    func realVersion() async throws {
        let runner = CommandRunner()
        let engine = AppleContainerCLIEngine(runner: runner) {
            URL(fileURLWithPath: Self.binaryPath)
        }
        let version = try await engine.systemVersion()
        #expect(!version.version.isEmpty)
    }

    @Test("Installed CLI answers the status probe in either state", .enabled(if: binaryInstalled))
    func realStatus() async throws {
        let runner = CommandRunner()
        let engine = AppleContainerCLIEngine(runner: runner) {
            URL(fileURLWithPath: Self.binaryPath)
        }
        // Must decode regardless of running/stopped (status exits 1 when stopped).
        _ = try await engine.systemStatus()
    }

    @Test("Binary discovery finds the installed CLI", .enabled(if: binaryInstalled))
    func realDiscovery() async throws {
        let locator = ContainerBinaryLocator(runner: CommandRunner())
        let location = try await locator.locate(userConfiguredPath: nil, persistedPath: nil)
        #expect(FileManager.default.isExecutableFile(atPath: location.url.path))
    }

    @Test("Resource reads decode in either system state", .enabled(if: binaryInstalled))
    func realResourceReads() async throws {
        let engine = AppleContainerCLIEngine(runner: CommandRunner()) {
            URL(fileURLWithPath: Self.binaryPath)
        }
        // Running system → lists decode; stopped system → the verified
        // serviceNotRunning mapping. Anything else is a real failure.
        func check<T>(_ body: () async throws -> T) async throws {
            do {
                _ = try await body()
            } catch ContainerEngineError.serviceNotRunning {
                // acceptable: system is stopped
            } catch ContainerEngineError.featureUnavailable {
                // acceptable: capability-gated (e.g. networks plugin)
            }
        }
        try await check { try await engine.listContainers(all: true) }
        try await check { try await engine.listImages() }
        try await check { try await engine.listVolumes() }
        try await check { try await engine.listMachines() }
        try await check { try await engine.listRegistries() }
        try await check { try await engine.builderStatus() }
        try await check { try await engine.diskUsage() }
        try await check { try await engine.containerStatistics() }
    }
}
