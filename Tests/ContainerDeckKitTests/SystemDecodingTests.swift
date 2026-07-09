import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("System JSON decoding (fixtures captured from CLI 1.0.0)")
struct SystemDecodingTests {
    @Test("Version fixture decodes")
    func versionFixture() throws {
        let version = try SystemVersionMapper.map(data: try fixtureData("system-version"))
        #expect(version.version == "1.0.0")
        #expect(version.commit == "ee848e3ebfd7c73b04dd419683be54fb450b8779")
        #expect(version.buildType == "release")
        #expect(version.components.count == 1)
    }

    @Test("Version with unknown fields and extra components still decodes")
    func versionUnknownFields() throws {
        let version = try SystemVersionMapper.map(data: try fixtureData("system-version-unknown-fields"))
        #expect(version.version == "1.0.0")
        #expect(version.components.count == 2)
    }

    @Test("Empty version array is unexpectedOutput")
    func versionEmptyArray() throws {
        #expect(throws: ContainerEngineError.self) {
            _ = try SystemVersionMapper.map(data: Data("[]".utf8))
        }
    }

    @Test("Garbage version output is decodingFailed")
    func versionGarbage() throws {
        #expect(throws: ContainerEngineError.self) {
            _ = try SystemVersionMapper.map(data: Data("not json".utf8))
        }
    }

    @Test("Stopped status fixture maps to stopped with reported string")
    func statusStopped() throws {
        let status = try SystemStatusMapper.map(data: try fixtureData("system-status-stopped"))
        #expect(!status.isRunning)
        #expect(status.runtime == .stopped(reportedStatus: "unregistered"))
        // Empty strings in the CLI output become nil in the domain model.
        #expect(status.apiServerVersion == nil)
        #expect(status.appRoot == nil)
    }

    @Test("Running status fixture maps to running with populated fields")
    func statusRunning() throws {
        let status = try SystemStatusMapper.map(data: try fixtureData("system-status-running"))
        #expect(status.isRunning)
        #expect(status.apiServerVersion?.contains("1.0.0") == true)
        #expect(status.installRoot == "/usr/local/")
        #expect(!status.rawJSON.isEmpty)
    }

    @Test("Unknown extra fields never break status decoding")
    func statusUnknownFields() throws {
        let status = try SystemStatusMapper.map(data: try fixtureData("system-status-unknown-fields"))
        #expect(status.isRunning)
    }

    @Test("Missing optional fields never break status decoding")
    func statusMissingFields() throws {
        let status = try SystemStatusMapper.map(data: try fixtureData("system-status-missing-fields"))
        #expect(status.isRunning)
        #expect(status.apiServerVersion == nil)
    }

    @Test("A future unrecognized status string maps to stopped, preserved verbatim")
    func statusUnrecognizedValue() throws {
        let status = try SystemStatusMapper.map(data: Data(#"{"status":"draining"}"#.utf8))
        #expect(!status.isRunning)
        #expect(status.runtime == .stopped(reportedStatus: "draining"))
    }

    @Test("Garbage status output is decodingFailed")
    func statusGarbage() throws {
        #expect(throws: ContainerEngineError.self) {
            _ = try SystemStatusMapper.map(data: Data("apiserver is not running".utf8))
        }
    }
}
