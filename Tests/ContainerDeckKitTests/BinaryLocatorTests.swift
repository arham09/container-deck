import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("ContainerBinaryLocator")
struct BinaryLocatorTests {
    /// Creates a fake `container` executable that answers the version probe.
    private func makeFakeBinary(
        in directory: URL,
        version: String = "9.9.9",
        exitCode: Int = 0
    ) throws -> URL {
        let script = """
        #!/bin/sh
        echo '[{"appName":"container","version":"\(version)"}]'
        exit \(exitCode)
        """
        let url = directory.appendingPathComponent("container")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("containerdeck-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Finds a valid binary via PATH")
    func findsViaPath() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeFakeBinary(in: directory)

        let locator = ContainerBinaryLocator(
            runner: CommandRunner(),
            searchPath: directory.path,
            knownLocations: []
        )
        let location = try await locator.locate(userConfiguredPath: nil, persistedPath: nil)
        #expect(location.source == .environmentPath)
        #expect(location.version.version == "9.9.9")
    }

    @Test("Finds a valid binary via known locations")
    func findsViaKnownLocation() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = try makeFakeBinary(in: directory)

        let locator = ContainerBinaryLocator(
            runner: CommandRunner(),
            searchPath: nil,
            knownLocations: [binary.path]
        )
        let location = try await locator.locate(userConfiguredPath: nil, persistedPath: nil)
        #expect(location.source == .knownLocation)
    }

    @Test("User-configured path outranks PATH")
    func userConfiguredWins() async throws {
        let pathDirectory = try makeTempDirectory()
        let configuredDirectory = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: pathDirectory)
            try? FileManager.default.removeItem(at: configuredDirectory)
        }
        _ = try makeFakeBinary(in: pathDirectory, version: "1.1.1")
        let configured = try makeFakeBinary(in: configuredDirectory, version: "2.2.2")

        let locator = ContainerBinaryLocator(
            runner: CommandRunner(),
            searchPath: pathDirectory.path,
            knownLocations: []
        )
        let location = try await locator.locate(
            userConfiguredPath: configured.path,
            persistedPath: nil
        )
        #expect(location.source == .userConfigured)
        #expect(location.version.version == "2.2.2")
    }

    @Test("Missing binary throws binaryNotFound")
    func missingBinary() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let locator = ContainerBinaryLocator(
            runner: CommandRunner(),
            searchPath: directory.path,
            knownLocations: []
        )
        await #expect(throws: ContainerEngineError.binaryNotFound) {
            _ = try await locator.locate(userConfiguredPath: nil, persistedPath: nil)
        }
    }

    @Test("A binary that fails the version probe is rejected")
    func invalidBinary() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeFakeBinary(in: directory, exitCode: 1)

        let locator = ContainerBinaryLocator(
            runner: CommandRunner(),
            searchPath: directory.path,
            knownLocations: []
        )
        await #expect(throws: ContainerEngineError.binaryNotFound) {
            _ = try await locator.locate(userConfiguredPath: nil, persistedPath: nil)
        }
    }

    @Test("Manual selection validates before adopting")
    func manualSelection() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = try makeFakeBinary(in: directory)

        let locator = ContainerBinaryLocator(
            runner: CommandRunner(),
            searchPath: nil,
            knownLocations: []
        )
        let location = try await locator.adopt(manualSelection: binary)
        #expect(location.source == .manualSelection)

        let bogus = directory.appendingPathComponent("not-a-binary")
        try Data("plain".utf8).write(to: bogus)
        await #expect(throws: ContainerEngineError.self) {
            _ = try await locator.adopt(manualSelection: bogus)
        }
    }
}
